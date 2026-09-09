' vt.bas -- the 80x25 screen the terminal actually keeps, and the control
' characters that move around it.
'
' The Intellivision shows 20x12 cards. A terminal that tells the far end it is
' 20 columns wide gets a usable but strange screen: ssh, vi and anything
' curses-shaped assume 80. So the screen the program maintains is 80x25, held
' in cartridge RAM, and BACKTAB shows a 20x12 window onto it (vtview.bas).
'
' TBUF is 25 rows of 80 cells and each cell is two consecutive 8-bit
' locations -- the low then the high byte of a finished Foreground/Background
' BACKTAB word. Storing the composed word rather than a character and an
' attribute means the repaint does no colour arithmetic at all: it reads two
' bytes and recombines them (see VPROW in vtasm.asm). The cost is paid once,
' here, when the character is written.
'
' Rows are reached through rowmap, an indirection table of slot numbers, so
' scrolling never moves the 4000 bytes of buffer: it rotates at most 25 bytes
' and blanks one row. The same mechanism serves a full-screen scroll, a
' DECSTBM region, IL and DL.

    CONST TCOLS  = 80           ' the virtual screen
    CONST TROWS  = 25
    CONST TROWB  = 160          ' bytes per row: 80 cells x 2

    ' Cartridge RAM. PiRTO II maps $8000-$9FFF as RAM unconditionally; the
    ' MEMATTR in fujinet.bas declares $8000-$9BFF of it to jzIntv and must not
    ' be widened (see the comment there -- $9C00 is the mailbox).
    CONST TBUF      = $8000     ' 4000 bytes: $8000-$8F9F
    CONST SC_ROWMAP = $9440     ' 25 bytes: logical row -> slot

    ' Slot base addresses. A DATA table rather than a multiply: this is read on
    ' every row change and on all twelve rows of every repaint.
rowaddr:
    DATA $8000, $80A0, $8140, $81E0, $8280, $8320, $83C0, $8460, $8500
    DATA $85A0, $8640, $86E0, $8780, $8820, $88C0, $8960, $8A00, $8AA0
    DATA $8B40, $8BE0, $8C80, $8D20, $8DC0, $8E60, $8F00

    DIM vt_col, vt_row, vt_pend, vt_slot, vt_i
    DIM sr_top, sr_bot
    DIM blank_lo, blank_hi
    ' an_state, an_n and an_awm belong to vtansi.bas, but vt.bas is included
    ' first and touches them -- vt_putc has to know whether autowrap is on --
    ' so they are declared here. IntyBASIC creates a variable at first use, so
    ' whichever file mentions one first is the one that has to DIM it.
    DIM an_state, an_n, an_awm
    ' The repaint bounds, written here and consumed by vtview.bas.
    DIM vp_full, vp_dtop, vp_dbot
    DIM #vt_base, #vt_cell

    ASM INCLUDE "vtasm.asm"

' ---------------------------------------------------------------------------
' vt_attr: recompute the blank cell after the attribute changes.
'
' Erasing has to write the *current* background, not black -- that is what
' makes a coloured backdrop survive a clear-to-end-of-line. Keeping the blank
' pre-composed means TFILL2 can take it as two plain bytes.
' ---------------------------------------------------------------------------
vt_attr: PROCEDURE
    cw_c = 32 : cw_fg = term_fg : GOSUB cell_word
    blank_lo = #cw_w AND 255
    blank_hi = #cw_w / 256
END

' ---------------------------------------------------------------------------
' vt_locate: recover the cell pointer after the cursor is moved by anything
' other than ordinary printing. #vt_cell walks itself along a row; this is
' what puts it back on a new one.
' ---------------------------------------------------------------------------
vt_locate: PROCEDURE
    #vt_base = rowaddr(PEEK(SC_ROWMAP + vt_row))
    #vt_cell = #vt_base + vt_col * 2
END

' ---------------------------------------------------------------------------
' vt_reset: identity rowmap, whole buffer blanked, cursor home.
'
' The blanking is not optional. jzIntv fills RAM with random bytes at power-on
' (mem.c), so without this the terminal starts as 2000 cells of confetti.
' ---------------------------------------------------------------------------
vt_reset: PROCEDURE
    FOR vt_i = 0 TO TROWS - 1
        POKE (SC_ROWMAP + vt_i), vt_i
    NEXT vt_i
    sr_top = 0
    sr_bot = TROWS - 1
    vt_col = 0
    vt_row = 0
    vt_pend = 0
    an_state = 0
    an_awm = 1
    GOSUB vt_attr
    vt_i = USR TFILL2(TBUF, TCOLS * TROWS, blank_lo, blank_hi)
    GOSUB vt_locate
END

' ---------------------------------------------------------------------------
' vt_scroll_up: roll the scrolling region up one row.
'
' ROTUP hands back the slot that fell off the top, which is exactly the row to
' blank and reuse at the bottom -- so a scroll costs a 25-byte rotate and one
' 80-cell fill, not a 4000-byte move.
' ---------------------------------------------------------------------------
vt_scroll_up: PROCEDURE
    vt_slot = USR ROTUP(SC_ROWMAP + sr_top, sr_bot - sr_top + 1)
    vt_i = USR TFILL2(rowaddr(vt_slot), TCOLS, blank_lo, blank_hi)
    vp_full = 1
END

' ---------------------------------------------------------------------------
' vt_index: line feed. Down one row inside the region, or scroll at the foot
' of it.
' ---------------------------------------------------------------------------
vt_index: PROCEDURE
    vt_pend = 0
    IF vt_row = sr_bot THEN
        GOSUB vt_scroll_up
    ELSE
        IF vt_row < TROWS - 1 THEN vt_row = vt_row + 1
    END IF
    GOSUB vt_locate
END

vt_cr: PROCEDURE
    vt_pend = 0
    vt_col = 0
    #vt_cell = #vt_base
END

vt_bs: PROCEDURE
    vt_pend = 0
    IF vt_col > 0 THEN
        vt_col = vt_col - 1
        #vt_cell = #vt_cell - 2
    END IF
END

' Fixed tab stops every eight columns. HTS/TBC can move them later; nothing
' in a shell session has needed it yet.
vt_tab: PROCEDURE
    vt_pend = 0
    vt_col = (vt_col / 8) * 8 + 8
    IF vt_col > TCOLS - 1 THEN vt_col = TCOLS - 1
    #vt_cell = #vt_base + vt_col * 2
END

' ---------------------------------------------------------------------------
' vt_putc: put one printable character at the cursor.
'
' The wrap is deferred, the way a real terminal does it: printing in the last
' column leaves the cursor *on* that column with a pending flag, and the wrap
' only happens when another character actually arrives. Wrapping eagerly puts
' the cursor on the next line the moment column 79 is written, which makes a
' program that fills a line and then moves the cursor draw one row too low.
' ---------------------------------------------------------------------------
vt_putc: PROCEDURE
    IF vt_pend THEN
        vt_pend = 0
        vt_col = 0
        GOSUB vt_index
    END IF
    cw_c = nc_c : cw_fg = term_fg : GOSUB cell_word
    POKE #vt_cell, #cw_w AND 255
    POKE (#vt_cell + 1), #cw_w / 256
    IF vt_row >= vp_dtop THEN
        IF vt_row <= vp_dbot THEN GOTO vt_pc_moved
    END IF
    IF vt_row < vp_dtop THEN vp_dtop = vt_row
    IF vt_row > vp_dbot THEN vp_dbot = vt_row
vt_pc_moved:
    IF vt_col = TCOLS - 1 THEN
        ' DECAWM. With autowrap off the cursor stays put and each further
        ' character overwrites column 79, which is what a program that turned
        ' it off is relying on.
        IF an_awm THEN vt_pend = 1
    ELSE
        vt_col = vt_col + 1
        #vt_cell = #vt_cell + 2
    END IF
END

' The escape swallower that used to live here, and the vt_feed that called
' it, are gone: vtansi.bas interprets these sequences now rather than eating
' them. an_state is still declared above, because vtansi.bas drives it and
' vt.bas is included first.
