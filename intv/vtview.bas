' vtview.bas -- the 20x12 window onto the 80x25 screen.
'
' Everything the far end sends lands in TBUF (vt.bas). This file decides which
' 20x12 corner of it BACKTAB is showing, and puts it there.
'
' Two modes, toggled with the top action button:
'
'   FOLLOW (default) the window snaps so the cursor is always visible. This is
'                    what makes the terminal usable without thinking about it:
'                    output appears where you are looking.
'   FREE             the window stays where the disc left it while data keeps
'                    landing in the buffer behind you -- for reading back a
'                    wide line, or watching one column of a table scroll.
'
' The border colour carries the mode, because a screen this small cannot
' afford a status line: blue while following, black when free.

    CONST VCOLS = 20            ' the window
    CONST VROWS = 12
    CONST VXMAX = TCOLS - VCOLS ' 60
    CONST VYMAX = TROWS - VROWS ' 13
    CONST BACKTAB0 = $0200

    CONST BORDER_FOLLOW = CS_BLUE
    CONST BORDER_FREE   = CS_BLACK

    ' vp_full / vp_dtop / vp_dbot are DIMmed in vt.bas, which writes them
    ' from vt_putc and vt_scroll_up and is included first.
    DIM vx, vy, vp_track, vp_i, vp_slot, vp_d
    DIM cur_vis
    DIM ov_frames, ov_p, ov_i

    CONST OV_ROW    = 220       ' BACKTAB row 11
    CONST OV_FRAMES = 90        ' about a second and a half

' ---------------------------------------------------------------------------
' vp_reset: window home, following, everything dirty.
' ---------------------------------------------------------------------------
vp_reset: PROCEDURE
    vx = 0
    vy = 0
    vp_track = 1
    GOSUB vp_dirty_all
    BORDER BORDER_FOLLOW
END

' vp_dirty_all / vp_dirty_none: the repaint bounds. Tracking a min and max
' logical row rather than a per-row bitmap costs two bytes and over-paints a
' little; a scroll dirties everything anyway, which is the common case.
vp_dirty_all: PROCEDURE
    vp_full = 1
    vp_dtop = 0
    vp_dbot = TROWS - 1
END

vp_dirty_none: PROCEDURE
    vp_full = 0
    vp_dtop = TROWS
    vp_dbot = 0
END

' ---------------------------------------------------------------------------
' vp_follow: bring the cursor back into view.
'
' Only ever moves the window by the minimum needed, so a cursor walking along
' a long line drags the window one column at a time instead of jumping.
' ---------------------------------------------------------------------------
vp_follow: PROCEDURE
    IF vp_track = 0 THEN RETURN
    IF vt_col < vx THEN vx = vt_col : vp_full = 1
    IF vt_col > vx + VCOLS - 1 THEN vx = vt_col - (VCOLS - 1) : vp_full = 1
    IF vt_row < vy THEN vy = vt_row : vp_full = 1
    IF vt_row > vy + VROWS - 1 THEN vy = vt_row - (VROWS - 1) : vp_full = 1
END

' ---------------------------------------------------------------------------
' vp_paint: put the window on the screen.
'
' Twelve calls into VPROW, which is the only reason this is affordable: 37
' cycles a cell, ~9300 for the lot, about two thirds of one NTSC frame. The
' same job in IntyBASIC took nearly four frames.
'
' A row is skipped when it is outside the dirty range, so steady output that
' touches one line repaints one line.
' ---------------------------------------------------------------------------
vp_paint: PROCEDURE
    FOR vp_i = 0 TO VROWS - 1
        ' The status overlay borrows the bottom row while it is up.
        IF ov_frames THEN
            IF vp_i = VROWS - 1 THEN GOTO vp_skip
        END IF
        IF vp_full = 0 THEN
            IF vy + vp_i < vp_dtop THEN GOTO vp_skip
            IF vy + vp_i > vp_dbot THEN GOTO vp_skip
        END IF
        vp_slot = PEEK(SC_ROWMAP + vy + vp_i)
        vp_d = USR VPROW(rowaddr(vp_slot) + vx * 2, BACKTAB0 + vp_i * 20)
vp_skip:
    NEXT vp_i
    GOSUB vp_dirty_none
END

' ---------------------------------------------------------------------------
' vp_cursor: place the cursor MOB for this frame.
'
' Computed here, in the main loop, and not in the interrupt: recovering a row
' and column needs a division, and IntyBASIC compiles division into a subtract
' loop. The frame hook is left with nothing to do but flip the blink.
'
' Out of view the MOB parks on the nearest edge and turns red, so FREE mode
' still says which way the cursor went.
' ---------------------------------------------------------------------------
vp_cursor: PROCEDURE
    cur_col = vt_col - vx
    cur_row = vt_row - vy
    cur_vis = 1
    IF cur_col < 0 THEN cur_col = 0 : cur_vis = 0
    IF cur_col > VCOLS - 1 THEN cur_col = VCOLS - 1 : cur_vis = 0
    IF cur_row < 0 THEN cur_row = 0 : cur_vis = 0
    IF cur_row > VROWS - 1 THEN cur_row = VROWS - 1 : cur_vis = 0
    #cur_x = SPR_VISIBLE + CUR_MOB_X0 + cur_col * 8
    #cur_y = SPR_ZOOMY2 + CUR_MOB_Y0 + cur_row * 8
    cur_col = CS_BLUE
    IF cur_vis = 0 THEN cur_col = CS_RED
    cur_attr = (256 + GRAM_BLOCK) * 8 + cur_col
    cur_lit = 2                         ' force the blink to re-issue
END

' ---------------------------------------------------------------------------
' ov_show / ov_tick: the status line, which is only there when it is useful.
'
' Twelve rows is not enough to spend one on a permanent status bar, and most
' of the time there is nothing to say -- the border colour already carries the
' follow/free state. So the position and mode appear on the bottom row for a
' second and a half after the window is moved, and then that row goes back to
' being terminal. vp_paint leaves it alone while the overlay is up.
'
' The countdown runs in the frame interrupt but the repaint does not: ov_tick
' only raises the dirty flag, and the main loop puts the row back.
' ---------------------------------------------------------------------------
ov_show: PROCEDURE
    #cw_bgw = bg_scatter(CS_BLACK)
    PRINT AT OV_ROW COLOR COL_DIM, "C   R               "
    ov_p = OV_ROW + 1 : ov_i = vx : GOSUB ov_num2
    ov_p = OV_ROW + 5 : ov_i = vy : GOSUB ov_num2
    IF vp_track THEN
        PRINT AT OV_ROW + 8 COLOR COL_HILIGHT, "FOLLOW"
    ELSE
        PRINT AT OV_ROW + 8 COLOR COL_HILIGHT, "FREE"
    END IF
    GOSUB an_apply              ' put the terminal's own attribute back
    ov_frames = OV_FRAMES
END

ov_num2: PROCEDURE
    cw_fg = COL_DIM
    cw_c = 48 + ov_i / 10 : GOSUB cell_word : #BACKTAB(ov_p) = #cw_w
    cw_c = 48 + ov_i % 10 : GOSUB cell_word : #BACKTAB(ov_p + 1) = #cw_w
END

ov_tick: PROCEDURE
    IF ov_frames = 0 THEN RETURN
    ov_frames = ov_frames - 1
    IF ov_frames = 0 THEN vp_full = 1
END

' ---------------------------------------------------------------------------
' vp_pan: move the window by hand. Any pan drops out of FOLLOW -- reaching for
' the disc is the same as saying "stop moving on me".
' ---------------------------------------------------------------------------
vp_pan: PROCEDURE
    IF in_disc = 0 THEN RETURN
    IF vp_track THEN GOSUB vp_untrack
    IF in_disc = DISC_LEFT THEN
        IF vx > 0 THEN vx = vx - 1
    END IF
    IF in_disc = DISC_RIGHT THEN
        IF vx < VXMAX THEN vx = vx + 1
    END IF
    IF in_disc = DISC_UP THEN
        IF vy > 0 THEN vy = vy - 1
    END IF
    IF in_disc = DISC_DOWN THEN
        IF vy < VYMAX THEN vy = vy + 1
    END IF
    vp_full = 1
    GOSUB ov_show
END

vp_untrack: PROCEDURE
    vp_track = 0
    BORDER BORDER_FREE
END

' vp_toggle: the top action button. Re-arming snaps straight back to the
' cursor rather than waiting for the next byte to arrive.
vp_toggle: PROCEDURE
    IF vp_track THEN
        GOSUB vp_untrack
    ELSE
        vp_track = 1
        BORDER BORDER_FOLLOW
        GOSUB vp_follow
    END IF
    GOSUB ov_show
END

' vp_home: keypad 1-4 jump the window to a column band, ENTER recentres on the
' cursor. Sixty columns of travel is a long way on a disc.
vp_band: PROCEDURE
    GOSUB vp_untrack
    vx = vp_i * VCOLS
    IF vx > VXMAX THEN vx = VXMAX
    vp_full = 1
    GOSUB ov_show
END
