' vtansi.bas -- the ANSI/VT interpreter.
'
' Replaces the swallower in vt.bas. The states are the ones every VT parser
' has: GROUND, just-seen-ESC, collecting CSI parameters, ignoring a CSI that
' has gone wrong, inside an OSC string, and designating a character set.
'
' What is implemented is what a shell session actually uses: cursor motion and
' absolute addressing, erase, insert and delete of lines and characters,
' scrolling regions, save/restore, the mode sets that matter (autowrap, cursor
' visibility, application cursor keys), the two queries that block a program
' until they are answered, and SGR.
'
' The 32-byte ceiling on a CSI is kept from the swallower. A stream that gets
' corrupted mid-sequence would otherwise swallow the rest of the session.

    CONST SC_CSI   = $9460      ' 8 parameters
    CONST SC_SAVE  = $9470      ' DECSC: row, col, fg, bg, bold, rev
    CONST SC_REPLY = $9480      ' answers to DSR and DA, drained by the sender

    CONST AN_GROUND  = 0
    CONST AN_ESC     = 1
    CONST AN_CSI     = 2
    CONST AN_IGNORE  = 3
    CONST AN_OSC     = 4
    CONST AN_CHARSET = 5

    CONST AN_MAXPAR  = 8

' ---------------------------------------------------------------------------
' ANSI colour to STIC colour.
'
' Foreground is the lossy half and there is no way around it: FG/BG mode gives
' three bits, and the eight primaries contain no magenta, no cyan and no grey.
' Nearest-RGB is worse than useless here -- it folds red, yellow and magenta
' all onto Red and leaves black, cyan and bright black all on Dark Green -- so
' these are chosen to keep the hue families apart instead. Cyan goes to Green
' and magenta to Red, which are the two collisions; green (4/5) and yellow
' (3/6) keep a genuine dark/bright pair, so SGR 1 does something visible.
'
' Background has all sixteen colours and is nearly faithful: STIC 15 "Purple"
' really is a magenta and STIC 9 "Cyan" really is a cyan.
'
' Both are plain tables. Retuning is a one-line edit, not a code change.
fgmap:
    DATA 0, 2, 4, 3, 1, 2, 5, 7      ' black red green yellow blue mag cyan white
    DATA 0, 2, 5, 6, 1, 2, 5, 7      ' the bright row
bgmap:
    DATA 0, 2, 4,10, 1,15, 9, 8
    DATA 11,12,14, 6, 1,13, 9, 7

    DIM an_np, an_priv, an_p, an_i, an_j, an_n2
    DIM sg_fg, sg_bg, sg_bold, sg_rev
    DIM sa_f, sa_b, sa_bs
    DIM an_ckm, an_rlen
    DIM ve_row, ve_col, ve_n, ve_slot
    DIM vg_row, vg_col

' ---------------------------------------------------------------------------
' an_apply: turn the SGR state into the two things the writer actually uses --
' a STIC foreground and a pre-scattered STIC background.
'
' Reverse video swaps the ANSI indices and re-maps, rather than swapping the
' STIC values. Swapping the values would take a background out of the sixteen-
' colour map and try to use it as a foreground, where anything above 7 does
' not exist.
'
' The legibility guard at the end is not cosmetic: bright-black on black is a
' real and common combination in prompts, and on this palette it is invisible
' rather than merely dim.
' ---------------------------------------------------------------------------
an_apply: PROCEDURE
    sa_f = sg_fg
    sa_b = sg_bg
    IF sg_rev THEN
        sa_f = sg_bg
        sa_b = sg_fg
    END IF
    IF sg_bold THEN
        IF sa_f < 8 THEN sa_f = sa_f + 8
    END IF
    sa_bs = bgmap(sa_b)
    term_fg = fgmap(sa_f)
    IF term_fg = sa_bs THEN
        term_fg = CS_WHITE
        IF sa_bs = CS_WHITE THEN term_fg = CS_BLACK
        IF sa_bs = 8 THEN term_fg = CS_BLACK
        IF sa_bs = 3 THEN term_fg = CS_BLACK
        IF sa_bs = 6 THEN term_fg = CS_BLACK
    END IF
    #cw_bgw = bg_scatter(sa_bs)
    GOSUB vt_attr
END

an_sgr_reset: PROCEDURE
    sg_fg = 7
    sg_bg = 0
    sg_bold = 0
    sg_rev = 0
    GOSUB an_apply
END

' ---------------------------------------------------------------------------
' an_reply: stage bytes to send back.
'
' DSR and DA are questions, and a program that asks one waits for the answer.
' The bytes go into a small buffer that term_send_keys drains ahead of the
' keyboard, so a query is answered in the same write as whatever was typed.
' ---------------------------------------------------------------------------
an_reply: PROCEDURE
    IF an_rlen >= 24 THEN RETURN
    POKE (SC_REPLY + an_rlen), an_i
    an_rlen = an_rlen + 1
END

' an_reply_num: one decimal number, 1-99, no leading zero.
an_reply_num: PROCEDURE
    IF an_j >= 10 THEN
        an_i = 48 + an_j / 10 : GOSUB an_reply
    END IF
    an_i = 48 + an_j % 10 : GOSUB an_reply
END

' ---------------------------------------------------------------------------
' vt_erase: blank a run of cells inside one logical row.
' ---------------------------------------------------------------------------
vt_erase: PROCEDURE
    IF ve_n = 0 THEN RETURN
    ve_slot = PEEK(SC_ROWMAP + ve_row)
    vt_i = USR TFILL2(rowaddr(ve_slot) + ve_col * 2, ve_n, blank_lo, blank_hi)
    IF ve_row < vp_dtop THEN vp_dtop = ve_row
    IF ve_row > vp_dbot THEN vp_dbot = ve_row
END

' vt_goto: absolute cursor move. Callers clamp downward themselves, because
' IntyBASIC's 8-bit variables are unsigned and "row - n" wraps rather than
' going negative.
vt_goto: PROCEDURE
    IF vg_row > TROWS - 1 THEN vg_row = TROWS - 1
    IF vg_col > TCOLS - 1 THEN vg_col = TCOLS - 1
    vt_row = vg_row
    vt_col = vg_col
    vt_pend = 0
    GOSUB vt_locate
END

' ---------------------------------------------------------------------------
' vt_scroll_dn: the other direction, for reverse index and SD.
' ---------------------------------------------------------------------------
vt_scroll_dn: PROCEDURE
    vt_slot = USR ROTDN(SC_ROWMAP + sr_top, sr_bot - sr_top + 1)
    vt_i = USR TFILL2(rowaddr(vt_slot), TCOLS, blank_lo, blank_hi)
    vp_full = 1
END

' vt_rindex: reverse index -- up one row, scrolling the region if at its top.
vt_rindex: PROCEDURE
    vt_pend = 0
    IF vt_row = sr_top THEN
        GOSUB vt_scroll_dn
    ELSE
        IF vt_row > 0 THEN vt_row = vt_row - 1
    END IF
    GOSUB vt_locate
END

' ---------------------------------------------------------------------------
' an_feed: one received byte, dispatched on the parser state.
' ---------------------------------------------------------------------------
an_feed: PROCEDURE
    IF an_state = AN_GROUND THEN GOSUB an_ground : RETURN
    IF an_state = AN_CSI THEN GOSUB an_csi : RETURN
    IF an_state = AN_ESC THEN GOSUB an_esc : RETURN
    IF an_state = AN_OSC THEN GOSUB an_osc : RETURN
    IF an_state = AN_CHARSET THEN an_state = AN_GROUND : RETURN
    ' AN_IGNORE: run to the final byte and drop the whole sequence
    IF nc_c < 64 THEN RETURN
    IF nc_c > 126 THEN RETURN
    an_state = AN_GROUND
END

' Ordered by frequency: printable text is almost everything a session sends.
an_ground: PROCEDURE
    IF nc_c > 126 THEN RETURN                   ' DEL and 8-bit: drop
    IF nc_c >= 32 THEN GOSUB vt_putc : RETURN
    IF nc_c = 13 THEN GOSUB vt_cr : RETURN
    IF nc_c = 10 THEN GOSUB vt_index : RETURN
    IF nc_c = 8 THEN GOSUB vt_bs : RETURN
    IF nc_c = 9 THEN GOSUB vt_tab : RETURN
    IF nc_c = 27 THEN an_state = AN_ESC : RETURN
    IF nc_c = 11 THEN GOSUB vt_index : RETURN
    IF nc_c = 12 THEN GOSUB vt_index : RETURN
    ' BEL, SO and SI: nothing to do here yet
END

an_esc: PROCEDURE
    an_state = AN_GROUND
    IF nc_c = 91 THEN                           ' [  -- CSI
        an_state = AN_CSI
        an_np = 0
        an_priv = 0
        an_n = 0
        FOR an_i = 0 TO AN_MAXPAR - 1
            POKE (SC_CSI + an_i), 0
        NEXT an_i
        RETURN
    END IF
    IF nc_c = 93 THEN an_state = AN_OSC : an_n = 0 : RETURN   ' ]
    IF nc_c = 40 THEN an_state = AN_CHARSET : RETURN          ' (
    IF nc_c = 41 THEN an_state = AN_CHARSET : RETURN          ' )
    IF nc_c = 35 THEN an_state = AN_CHARSET : RETURN          ' #
    IF nc_c = 68 THEN GOSUB vt_index : RETURN                 ' D  IND
    IF nc_c = 77 THEN GOSUB vt_rindex : RETURN                ' M  RI
    IF nc_c = 69 THEN GOSUB vt_cr : GOSUB vt_index : RETURN   ' E  NEL
    IF nc_c = 55 THEN GOSUB an_decsc : RETURN                 ' 7
    IF nc_c = 56 THEN GOSUB an_decrc : RETURN                 ' 8
    IF nc_c = 99 THEN GOSUB an_ris : RETURN                   ' c  RIS
    ' =, > and the rest: keypad modes and things with no screen effect
END

an_decsc: PROCEDURE
    POKE (SC_SAVE + 0), vt_row
    POKE (SC_SAVE + 1), vt_col
    POKE (SC_SAVE + 2), sg_fg
    POKE (SC_SAVE + 3), sg_bg
    POKE (SC_SAVE + 4), sg_bold
    POKE (SC_SAVE + 5), sg_rev
END

an_decrc: PROCEDURE
    vg_row = PEEK(SC_SAVE + 0) AND 255
    vg_col = PEEK(SC_SAVE + 1) AND 255
    sg_fg = PEEK(SC_SAVE + 2) AND 255
    sg_bg = PEEK(SC_SAVE + 3) AND 255
    sg_bold = PEEK(SC_SAVE + 4) AND 255
    sg_rev = PEEK(SC_SAVE + 5) AND 255
    GOSUB an_apply
    GOSUB vt_goto
END

an_ris: PROCEDURE
    GOSUB an_sgr_reset
    GOSUB vt_reset
    an_awm = 1
    an_ckm = 0
    GOSUB vp_dirty_all
END

' OSC: a window title or similar. Runs to BEL or to the ST that follows ESC.
an_osc: PROCEDURE
    an_n = an_n + 1
    IF an_n >= 64 THEN an_state = AN_GROUND : RETURN
    IF nc_c = 7 THEN an_state = AN_GROUND : RETURN
    IF nc_c = 27 THEN an_state = AN_CHARSET   ' ST: eat the byte after ESC
END

' ---------------------------------------------------------------------------
' an_csi: collect parameters until a final byte in $40-$7E.
' ---------------------------------------------------------------------------
an_csi: PROCEDURE
    an_n = an_n + 1
    IF an_n >= 32 THEN an_state = AN_IGNORE : RETURN

    IF nc_c >= 48 THEN
        IF nc_c <= 57 THEN                              ' 0-9
            IF an_np = 0 THEN an_np = 1
            IF an_np <= AN_MAXPAR THEN
                an_p = PEEK(SC_CSI + an_np - 1) AND 255
                an_p = an_p * 10 + nc_c - 48
                IF an_p > 250 THEN an_p = 250
                POKE (SC_CSI + an_np - 1), an_p
            END IF
            RETURN
        END IF
    END IF
    IF nc_c = 59 THEN                                   ' ;
        IF an_np = 0 THEN an_np = 1
        IF an_np < AN_MAXPAR THEN an_np = an_np + 1
        RETURN
    END IF
    IF nc_c = 63 THEN an_priv = 1 : RETURN              ' ?
    IF nc_c < 64 THEN RETURN                            ' other intermediates
    IF nc_c > 126 THEN RETURN
    an_state = AN_GROUND
    GOSUB an_exec
END

' an_arg: parameter an_i, or 1 when it is absent or zero -- the default for
' every counted CSI.
an_arg: PROCEDURE
    an_p = 0
    IF an_i < an_np THEN an_p = PEEK(SC_CSI + an_i) AND 255
    IF an_p = 0 THEN an_p = 1
END

' an_arg0: parameter an_i, or 0 -- the default for the selective erases.
an_arg0: PROCEDURE
    an_p = 0
    IF an_i < an_np THEN an_p = PEEK(SC_CSI + an_i) AND 255
END

' ---------------------------------------------------------------------------
' an_exec: act on a completed CSI.
'
' One flat dispatcher calling handlers, rather than handlers that chain into
' each other. The return stack is 24 words and fixed -- there is no STACK
' statement in IntyBASIC 1.4.2 -- and the frame interrupt nests three more on
' top of whatever the main loop is doing.
' ---------------------------------------------------------------------------
an_exec: PROCEDURE
    IF an_priv THEN GOSUB an_private : RETURN

    IF nc_c = 109 THEN GOSUB an_sgr : RETURN            ' m
    IF nc_c = 72 THEN GOSUB an_cup : RETURN             ' H  CUP
    IF nc_c = 102 THEN GOSUB an_cup : RETURN            ' f  HVP
    IF nc_c = 75 THEN GOSUB an_el : RETURN              ' K  EL
    IF nc_c = 74 THEN GOSUB an_ed : RETURN              ' J  ED

    IF nc_c = 65 THEN                                   ' A  CUU
        an_i = 0 : GOSUB an_arg
        vg_row = 0
        IF vt_row > an_p THEN vg_row = vt_row - an_p
        IF vg_row < sr_top THEN
            IF vt_row >= sr_top THEN vg_row = sr_top
        END IF
        vg_col = vt_col : GOSUB vt_goto : RETURN
    END IF
    IF nc_c = 66 THEN                                   ' B  CUD
        an_i = 0 : GOSUB an_arg
        vg_row = vt_row + an_p
        IF vg_row > sr_bot THEN
            IF vt_row <= sr_bot THEN vg_row = sr_bot
        END IF
        vg_col = vt_col : GOSUB vt_goto : RETURN
    END IF
    IF nc_c = 67 THEN                                   ' C  CUF
        an_i = 0 : GOSUB an_arg
        vg_col = vt_col + an_p
        vg_row = vt_row : GOSUB vt_goto : RETURN
    END IF
    IF nc_c = 68 THEN                                   ' D  CUB
        an_i = 0 : GOSUB an_arg
        vg_col = 0
        IF vt_col > an_p THEN vg_col = vt_col - an_p
        vg_row = vt_row : GOSUB vt_goto : RETURN
    END IF
    IF nc_c = 71 THEN                                   ' G  CHA
        an_i = 0 : GOSUB an_arg
        vg_col = an_p - 1 : vg_row = vt_row : GOSUB vt_goto : RETURN
    END IF
    IF nc_c = 100 THEN                                  ' d  VPA
        an_i = 0 : GOSUB an_arg
        vg_row = an_p - 1 : vg_col = vt_col : GOSUB vt_goto : RETURN
    END IF
    IF nc_c = 69 THEN                                   ' E  CNL
        an_i = 0 : GOSUB an_arg
        vg_row = vt_row + an_p
        IF vg_row > sr_bot THEN vg_row = sr_bot
        vg_col = 0 : GOSUB vt_goto : RETURN
    END IF
    IF nc_c = 70 THEN                                   ' F  CPL
        an_i = 0 : GOSUB an_arg
        vg_row = 0
        IF vt_row > an_p THEN vg_row = vt_row - an_p
        IF vg_row < sr_top THEN vg_row = sr_top
        vg_col = 0 : GOSUB vt_goto : RETURN
    END IF

    IF nc_c = 76 THEN GOSUB an_il : RETURN              ' L  IL
    IF nc_c = 77 THEN GOSUB an_dl : RETURN              ' M  DL
    IF nc_c = 80 THEN GOSUB an_dch : RETURN             ' P  DCH
    IF nc_c = 64 THEN GOSUB an_ich : RETURN             ' @  ICH
    IF nc_c = 88 THEN GOSUB an_ech : RETURN             ' X  ECH
    IF nc_c = 83 THEN GOSUB an_su : RETURN              ' S  SU
    IF nc_c = 84 THEN GOSUB an_sd : RETURN              ' T  SD
    IF nc_c = 114 THEN GOSUB an_stbm : RETURN           ' r  DECSTBM
    IF nc_c = 115 THEN GOSUB an_decsc : RETURN          ' s
    IF nc_c = 117 THEN GOSUB an_decrc : RETURN          ' u
    IF nc_c = 110 THEN GOSUB an_dsr : RETURN            ' n  DSR
    IF nc_c = 99 THEN GOSUB an_da : RETURN              ' c  DA
    ' Everything else -- including the window-manipulation "t" xterm sends
    ' right after ESC [ ?1049h -- is consumed and ignored, not abandoned.
END

an_cup: PROCEDURE
    an_i = 0 : GOSUB an_arg
    vg_row = an_p - 1
    an_i = 1 : GOSUB an_arg
    vg_col = an_p - 1
    GOSUB vt_goto
END

an_el: PROCEDURE
    an_i = 0 : GOSUB an_arg0
    ve_row = vt_row
    IF an_p = 1 THEN
        ve_col = 0 : ve_n = vt_col + 1
    ELSEIF an_p = 2 THEN
        ve_col = 0 : ve_n = TCOLS
    ELSE
        ve_col = vt_col : ve_n = TCOLS - vt_col
    END IF
    GOSUB vt_erase
END

an_ed: PROCEDURE
    an_i = 0 : GOSUB an_arg0
    an_n2 = an_p
    IF an_n2 = 2 THEN
        FOR an_j = 0 TO TROWS - 1
            ve_row = an_j : ve_col = 0 : ve_n = TCOLS : GOSUB vt_erase
        NEXT an_j
        vp_full = 1
        RETURN
    END IF
    IF an_n2 = 1 THEN
        ve_row = vt_row : ve_col = 0 : ve_n = vt_col + 1 : GOSUB vt_erase
        IF vt_row > 0 THEN
            FOR an_j = 0 TO vt_row - 1
                ve_row = an_j : ve_col = 0 : ve_n = TCOLS : GOSUB vt_erase
            NEXT an_j
        END IF
        vp_full = 1
        RETURN
    END IF
    ve_row = vt_row : ve_col = vt_col : ve_n = TCOLS - vt_col : GOSUB vt_erase
    IF vt_row < TROWS - 1 THEN
        FOR an_j = vt_row + 1 TO TROWS - 1
            ve_row = an_j : ve_col = 0 : ve_n = TCOLS : GOSUB vt_erase
        NEXT an_j
    END IF
    vp_full = 1
END

' IL and DL rotate the rows between the cursor and the foot of the scrolling
' region. Same rowmap trick as a scroll, on a shorter range.
an_il: PROCEDURE
    IF vt_row < sr_top THEN RETURN
    IF vt_row > sr_bot THEN RETURN
    an_i = 0 : GOSUB an_arg
    FOR an_j = 1 TO an_p
        vt_slot = USR ROTDN(SC_ROWMAP + vt_row, sr_bot - vt_row + 1)
        vt_i = USR TFILL2(rowaddr(vt_slot), TCOLS, blank_lo, blank_hi)
    NEXT an_j
    vp_full = 1
    GOSUB vt_locate
END

an_dl: PROCEDURE
    IF vt_row < sr_top THEN RETURN
    IF vt_row > sr_bot THEN RETURN
    an_i = 0 : GOSUB an_arg
    FOR an_j = 1 TO an_p
        vt_slot = USR ROTUP(SC_ROWMAP + vt_row, sr_bot - vt_row + 1)
        vt_i = USR TFILL2(rowaddr(vt_slot), TCOLS, blank_lo, blank_hi)
    NEXT an_j
    vp_full = 1
    GOSUB vt_locate
END

an_su: PROCEDURE
    an_i = 0 : GOSUB an_arg
    FOR an_j = 1 TO an_p
        GOSUB vt_scroll_up
    NEXT an_j
END

an_sd: PROCEDURE
    an_i = 0 : GOSUB an_arg
    FOR an_j = 1 TO an_p
        GOSUB vt_scroll_dn
    NEXT an_j
END

an_ech: PROCEDURE
    an_i = 0 : GOSUB an_arg
    ve_row = vt_row
    ve_col = vt_col
    ve_n = an_p
    IF ve_col + ve_n > TCOLS THEN ve_n = TCOLS - ve_col
    GOSUB vt_erase
END

' DCH and ICH shuffle one row. Eighty cells is small enough to do in BASIC,
' and bash's line editor is the only thing that sends them often.
an_dch: PROCEDURE
    an_i = 0 : GOSUB an_arg
    ve_slot = PEEK(SC_ROWMAP + vt_row)
    #an_a = rowaddr(ve_slot) + vt_col * 2
    #an_b = #an_a + an_p * 2
    FOR an_j = vt_col TO TCOLS - 1
        IF an_j + an_p > TCOLS - 1 THEN
            POKE #an_a, blank_lo
            POKE (#an_a + 1), blank_hi
        ELSE
            POKE #an_a, PEEK(#an_b) AND 255
            POKE (#an_a + 1), PEEK(#an_b + 1) AND 255
        END IF
        #an_a = #an_a + 2
        #an_b = #an_b + 2
    NEXT an_j
    IF vt_row < vp_dtop THEN vp_dtop = vt_row
    IF vt_row > vp_dbot THEN vp_dbot = vt_row
END

an_ich: PROCEDURE
    an_i = 0 : GOSUB an_arg
    ve_slot = PEEK(SC_ROWMAP + vt_row)
    #an_a = rowaddr(ve_slot) + (TCOLS - 1) * 2
    #an_b = #an_a - an_p * 2
    FOR an_j = TCOLS - 1 TO vt_col STEP -1
        IF an_j - an_p < vt_col THEN
            POKE #an_a, blank_lo
            POKE (#an_a + 1), blank_hi
        ELSE
            POKE #an_a, PEEK(#an_b) AND 255
            POKE (#an_a + 1), PEEK(#an_b + 1) AND 255
        END IF
        #an_a = #an_a - 2
        #an_b = #an_b - 2
    NEXT an_j
    IF vt_row < vp_dtop THEN vp_dtop = vt_row
    IF vt_row > vp_dbot THEN vp_dbot = vt_row
END

an_stbm: PROCEDURE
    an_i = 0 : GOSUB an_arg
    sr_top = an_p - 1
    an_i = 1 : GOSUB an_arg0
    IF an_p = 0 THEN an_p = TROWS
    sr_bot = an_p - 1
    IF sr_bot > TROWS - 1 THEN sr_bot = TROWS - 1
    IF sr_top >= sr_bot THEN
        sr_top = 0
        sr_bot = TROWS - 1
    END IF
    vg_row = sr_top : vg_col = 0 : GOSUB vt_goto
END

' DSR 6 is the cursor position report; DSR 5 is "are you there". Both block
' the asking program until answered.
an_dsr: PROCEDURE
    an_i = 0 : GOSUB an_arg0
    IF an_p = 6 THEN
        an_i = 27 : GOSUB an_reply
        an_i = 91 : GOSUB an_reply
        an_j = vt_row + 1 : GOSUB an_reply_num
        an_i = 59 : GOSUB an_reply
        an_j = vt_col + 1 : GOSUB an_reply_num
        an_i = 82 : GOSUB an_reply
        RETURN
    END IF
    IF an_p = 5 THEN
        an_i = 27 : GOSUB an_reply
        an_i = 91 : GOSUB an_reply
        an_i = 48 : GOSUB an_reply
        an_i = 110 : GOSUB an_reply
    END IF
END

' Device attributes: "VT102". Enough for terminfo to stop asking.
an_da: PROCEDURE
    an_i = 27 : GOSUB an_reply
    an_i = 91 : GOSUB an_reply
    an_i = 63 : GOSUB an_reply
    an_i = 54 : GOSUB an_reply
    an_i = 99 : GOSUB an_reply
END

' ---------------------------------------------------------------------------
' an_private: ESC [ ? Ps h / l.
'
' There is no RAM for an alternate screen buffer -- 80x25 already fills what
' the cartridge has -- so 1049 and 47 clear and home instead. That is the
' degradation ncurses copes with best: a full-screen program starts on a clean
' screen and leaves its last frame behind on exit.
' ---------------------------------------------------------------------------
an_private: PROCEDURE
    an_i = 0 : GOSUB an_arg0
    an_n2 = an_p
    IF nc_c = 104 THEN                                  ' h  -- set
        IF an_n2 = 7 THEN an_awm = 1 : RETURN
        IF an_n2 = 25 THEN cur_on = 1 : RETURN
        IF an_n2 = 1 THEN an_ckm = 1 : RETURN
        IF an_n2 = 1049 THEN GOSUB an_altclear : RETURN
        IF an_n2 = 47 THEN GOSUB an_altclear : RETURN
        RETURN
    END IF
    IF nc_c = 108 THEN                                  ' l  -- reset
        IF an_n2 = 7 THEN an_awm = 0 : RETURN
        IF an_n2 = 25 THEN GOSUB cur_hide : RETURN
        IF an_n2 = 1 THEN an_ckm = 0 : RETURN
        IF an_n2 = 1049 THEN GOSUB an_altclear : RETURN
        IF an_n2 = 47 THEN GOSUB an_altclear : RETURN
    END IF
END

an_altclear: PROCEDURE
    FOR an_j = 0 TO TROWS - 1
        ve_row = an_j : ve_col = 0 : ve_n = TCOLS : GOSUB vt_erase
    NEXT an_j
    vg_row = 0 : vg_col = 0 : GOSUB vt_goto
    vp_full = 1
END

' ---------------------------------------------------------------------------
' an_sgr: select graphic rendition.
'
' Underline and blink have no representation on this hardware, so they fold to
' bold -- which at least distinguishes the text, and is what the palette can
' honestly offer. 38;5;n and 48;5;n are folded down to the sixteen: the colour
' cube by its brightest component, the greyscale ramp by its level.
' ---------------------------------------------------------------------------
an_sgr: PROCEDURE
    IF an_np = 0 THEN GOSUB an_sgr_reset : RETURN
    an_i = 0
    WHILE an_i < an_np
        GOSUB an_arg0
        an_n2 = an_p
        IF an_n2 = 0 THEN
            sg_fg = 7 : sg_bg = 0 : sg_bold = 0 : sg_rev = 0
        ELSEIF an_n2 = 1 THEN
            sg_bold = 1
        ELSEIF an_n2 = 4 THEN
            sg_bold = 1
        ELSEIF an_n2 = 5 THEN
            sg_bold = 1
        ELSEIF an_n2 = 7 THEN
            sg_rev = 1
        ELSEIF an_n2 = 2 THEN
            sg_bold = 0
        ELSEIF an_n2 = 22 THEN
            sg_bold = 0
        ELSEIF an_n2 = 24 THEN
            sg_bold = 0
        ELSEIF an_n2 = 25 THEN
            sg_bold = 0
        ELSEIF an_n2 = 27 THEN
            sg_rev = 0
        ELSEIF an_n2 = 39 THEN
            sg_fg = 7
        ELSEIF an_n2 = 49 THEN
            sg_bg = 0
        ELSEIF an_n2 = 38 THEN
            GOSUB an_sgr_ext : sg_fg = an_n2
        ELSEIF an_n2 = 48 THEN
            GOSUB an_sgr_ext : sg_bg = an_n2
        ELSE
            IF an_n2 >= 30 THEN
                IF an_n2 <= 37 THEN sg_fg = an_n2 - 30
            END IF
            IF an_n2 >= 40 THEN
                IF an_n2 <= 47 THEN sg_bg = an_n2 - 40
            END IF
            IF an_n2 >= 90 THEN
                IF an_n2 <= 97 THEN sg_fg = an_n2 - 90 + 8
            END IF
            IF an_n2 >= 100 THEN
                IF an_n2 <= 107 THEN sg_bg = an_n2 - 100 + 8
            END IF
        END IF
        an_i = an_i + 1
    WEND
    GOSUB an_apply
END

' an_sgr_ext: consume the tail of 38/48 and leave a 0-15 colour in an_n2.
'
' Parameters are clamped to 250 as they are parsed, so the 256-colour indices
' above that arrive saturated -- which lands them in the greyscale ramp, where
' saturated means white, which is the right answer anyway.
an_sgr_ext: PROCEDURE
    an_i = an_i + 1
    GOSUB an_arg0
    IF an_p = 2 THEN                            ' 38;2;r;g;b -- direct colour
        an_i = an_i + 3
        an_n2 = 7
        RETURN
    END IF
    an_i = an_i + 1
    GOSUB an_arg0                               ' 38;5;n
    an_n2 = an_p
    IF an_n2 < 16 THEN RETURN
    IF an_n2 >= 232 THEN
        an_n2 = 8
        IF an_p >= 244 THEN an_n2 = 15
        IF an_p < 236 THEN an_n2 = 0
        RETURN
    END IF
    ' The 6x6x6 cube: recover r/g/b in 0-5 and pick the nearest of the eight
    ' primaries by which components are lit, brightening when any is high.
    an_p = an_n2 - 16
    an_j = an_p % 6                             ' blue
    an_n2 = (an_p / 6) % 6                      ' green
    an_p = an_p / 36                            ' red
    sa_f = 0
    IF an_p >= 3 THEN sa_f = sa_f + 1
    IF an_n2 >= 3 THEN sa_f = sa_f + 2
    IF an_j >= 3 THEN sa_f = sa_f + 4
    an_n2 = sa_f
    IF an_p >= 4 THEN an_n2 = sa_f + 8
END
