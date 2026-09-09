' netcat.bas -- a line-mode network terminal in IntyBASIC. Type any N:
' devicespec on the on-screen keyboard (the same character grid FujiNet
' CONFIG uses for WiFi SSIDs), connect, and everything the far end sends
' scrolls up rows 0-9 of the screen. The action button opens the keyboard
' again to compose a line; OK sends it (plus CR LF). The default URL is
' tcpbin.com's echo service, so an untouched OK at the URL screen gives a
' self-test needing no server of your own.
'
' URL screen:  disc + action button  pick characters on the grid
'              OK (or keypad ENTER)  connect
'              ESC                   restore the default URL
'              keypad 0 / CLEAR      space / backspace
'              The URL buffer holds 256 bytes; rows 0-2 are a 60-character
'              window that scrolls once a long URL outgrows them.
'
' Terminal:    action button         open the keyboard to compose a line
'                                    (OK sends + CR LF, ESC cancels)
'              keypad CLEAR          hang up, back to the URL screen
'
' With an ECS keyboard attached (detected at boot, see ecskbd.bas) the
' terminal stops being line-mode: keys are sent as you type, RTN sends CR LF,
' the arrows send ANSI cursor sequences and CTL+key sends control codes. The
' keyboard also types directly into the character grid on both the URL screen
' and the composer, so the disc never has to walk. Without an ECS none of that
' exists and the program behaves exactly as described above.
'
' A blue block cursor blinks at the terminal's write position, drawn with a
' MOB (hardware sprite) rather than a BACKTAB cell so it costs the receive
' path nothing and never has to be erased out of the character shadow.
'
' While the keyboard is open the connection is not polled; incoming bytes
' simply wait on the FujiNet and are drained when the terminal returns.
'
' Build:  intybasic netcat.bas netcat.asm && as1600 -o netcat netcat.asm
    GOTO main

    INCLUDE "fujinet.bas"
    INCLUDE "ecskbd.bas"
    INCLUDE "vtfont.bas"
    INCLUDE "kbd.bas"

    ' IntyBASIC allows exactly one of these, so both per-frame jobs -- the ECS
    ' keyboard scan and the cursor blink -- hang off frame_tick.
    ON FRAME GOSUB frame_tick

    CONST TERM_CELLS = 200      ' rows 0-9 are the terminal
    CONST STATUS_ROW = 220      ' row 11: status + key hints

    ' MOB (sprite) register bits, and the pixel offset from background card
    ' (0,0) to MOB coordinates. Both axes are offset by 8 -- MOB (8,8) is the
    ' top-left card. That was measured against the emulator for the FujiNet
    ' CONFIG port (see its constants.bas); don't try to infer it from the
    ' IntyBASIC manual's X 0-168 / Y 0-95 ranges, which imply an asymmetry
    ' that isn't there.
    CONST SPR_VISIBLE = $0200   ' X reg bit 9
    CONST SPR_ZOOMY2  = $0100   ' Y reg bit 8: scale 01 = one card-pixel tall
    CONST CUR_MOB_X0  = 8
    CONST CUR_MOB_Y0  = 8
    CONST CUR_MOB     = 0       ' nothing else in this program uses a MOB
    CONST CUR_BLINK   = 16      ' frames lit, then dark: a ~0.53 s cycle

    ' Scratch RAM, ours, above fujinet.bas's buffers (which end at $917F).
    CONST SC_URL  = $9200       ' devicespec, 256 bytes (255 chars + NUL)
    CONST SC_LINE = $9300       ' composed line, 253 bytes (252 + NUL)
    CONST SC_TERM = $9400       ' 200-byte shadow of the terminal cells

' The default devicespec (24 bytes): "N:TCP://TCPBIN.COM:4242/"
lit_spec:
    DATA 78,58,84,67,80,58,47,47,84,67,80,66,73,78
    DATA 46,67,79,77,58,52,50,52,50,47
    CONST LEN_SPEC = 24

    DIM term_pos, nc_i, nc_c, nc_cr, nc_row, tc_i, ts_fin
    DIM cur_on, cur_last, cur_lit
    DIM #cur_x, #cur_y

    ' The terminal's current attribute. Only the foreground moves for now;
    ' the background is black until SGR lands. (cell_word's own arguments are
    ' DIMmed in vtfont.bas, which has to declare them ahead of its first use.)
    DIM term_fg

' ---------------------------------------------------------------------------
' term_clear_row: blank the terminal row term_pos sits in, screen and
' shadow both -- called on entering a fresh row so wrapped-around output
' never interleaves with a stale line. Uses its own loop variable (tc_i):
' it's called from term_putc/term_newline while those run inside the
' receive loop's "FOR nc_i = 0 TO #net_gotlen - 1" in main -- reusing nc_i
' here would clobber that outer loop's counter on every line break.
' ---------------------------------------------------------------------------
term_clear_row: PROCEDURE
    nc_row = (term_pos / 20) * 20
    cw_c = 32 : cw_fg = term_fg : GOSUB cell_word
    FOR tc_i = 0 TO 19
        #BACKTAB(nc_row + tc_i) = #cw_w
        POKE (SC_TERM + nc_row + tc_i), 32
    NEXT tc_i
END

' ---------------------------------------------------------------------------
' term_putc: draw ASCII nc_c at the terminal cursor, handling CR/LF and
' wrap-around, mirroring every cell into SC_TERM so the display can be
' repainted after the keyboard has been over it. GROM cards 0-94 cover
' ASCII 32-126 directly.
' ---------------------------------------------------------------------------
term_putc: PROCEDURE
    IF nc_c = 13 THEN nc_cr = 1 : GOSUB term_newline : RETURN
    IF nc_c = 10 THEN
        ' collapse the LF of a CR LF pair; a bare LF is a newline
        IF nc_cr = 0 THEN GOSUB term_newline
        nc_cr = 0
        RETURN
    END IF
    nc_cr = 0
    IF nc_c < 32 OR nc_c > 126 THEN RETURN
    cw_c = nc_c : cw_fg = term_fg : GOSUB cell_word
    #BACKTAB(term_pos) = #cw_w
    POKE (SC_TERM + term_pos), nc_c
    term_pos = term_pos + 1
    IF term_pos >= TERM_CELLS THEN term_pos = 0
    IF (term_pos % 20) = 0 THEN GOSUB term_clear_row
END

term_newline: PROCEDURE
    term_pos = (term_pos / 20) * 20 + 20
    IF term_pos >= TERM_CELLS THEN term_pos = 0
    GOSUB term_clear_row
END

' ---------------------------------------------------------------------------
' term_init / term_repaint: reset the pane, or redraw all 200 cells from
' the shadow after the keyboard borrowed the screen.
' ---------------------------------------------------------------------------
term_init: PROCEDURE
    term_pos = 0
    nc_cr = 0
    FOR nc_i = 0 TO TERM_CELLS - 1
        POKE (SC_TERM + nc_i), 32
    NEXT nc_i
END

term_repaint: PROCEDURE
    FOR nc_i = 0 TO TERM_CELLS - 1
        nc_c = PEEK(SC_TERM + nc_i) AND 255
        IF nc_c < 32 OR nc_c > 126 THEN nc_c = 32
        cw_c = nc_c : cw_fg = term_fg : GOSUB cell_word
        #BACKTAB(nc_i) = #cw_w
    NEXT nc_i
END

' ---------------------------------------------------------------------------
' frame_tick: the one ON FRAME hook (IntyBASIC permits a single declaration).
' It runs inside the video interrupt, so everything it calls must be short --
' overrun a frame and the interrupts pile up until the stack overflows. It can
' also fire before main has initialised anything, which is safe because every
' variable is zero at boot and both callees bail on their zeroed enable flag.
' ---------------------------------------------------------------------------
frame_tick: PROCEDURE
    GOSUB ecs_tick
    GOSUB cur_tick
END

' ---------------------------------------------------------------------------
' The terminal's blinking block cursor, MOB 0.
'
' A MOB rather than a BACKTAB cell because the cursor sits exactly where the
' next received byte will be drawn: as a character cell it would have to be
' erased before every term_putc and repainted after, and it would have to be
' kept out of the SC_TERM shadow so term_repaint didn't make it permanent. A
' sprite floats over all of that, and the receive path stays untouched.
'
' cur_show / cur_hide bracket the terminal. Hiding matters -- a MOB left
' enabled keeps drawing over whatever screen comes next.
' ---------------------------------------------------------------------------
cur_show: PROCEDURE
    cur_on = 1
    cur_last = 255              ' impossible term_pos: forces a recompute
    cur_lit = 2                 ' neither lit nor dark: forces a re-issue
END

cur_hide: PROCEDURE
    cur_on = 0
    cur_lit = 0
    SPRITE CUR_MOB, 0, 0, 0
END

' cur_tick: called once per frame from frame_tick.
cur_tick: PROCEDURE
    IF cur_on = 0 THEN RETURN

    ' Recompute the MOB coordinates only when the cursor actually moved. The
    ' / and % below are real division calls, not shifts, and this runs in the
    ' interrupt -- the common frame is "nothing moved" and costs one compare.
    IF term_pos <> cur_last THEN
        cur_last = term_pos
        #cur_x = SPR_VISIBLE + CUR_MOB_X0 + (term_pos % 20) * 8
        #cur_y = SPR_ZOOMY2 + CUR_MOB_Y0 + (term_pos / 20) * 8
        cur_lit = 2
    END IF

    ' The MOB registers are shadowed in RAM and blitted by the ISR every frame,
    ' so a single write persists -- only touch them when the phase flips.
    IF (FRAME AND CUR_BLINK) = 0 THEN
        IF cur_lit <> 1 THEN
            cur_lit = 1
            SPRITE CUR_MOB, #cur_x, #cur_y, (256 + GRAM_BLOCK) * 8 + CS_BLUE
        END IF
    ELSE
        IF cur_lit <> 0 THEN
            cur_lit = 0
            SPRITE CUR_MOB, 0, 0, 0
        END IF
    END IF
END

' ---------------------------------------------------------------------------
' term_hint: the row-11 key legend for the terminal. Two versions, because
' with a keyboard the action button is no longer how you say anything.
' ---------------------------------------------------------------------------
term_hint: PROCEDURE
    IF ecs_present THEN
        PRINT AT STATUS_ROW COLOR COL_DIM, "TYPE - CLR HANGS UP "
    ELSE
        PRINT AT STATUS_ROW COLOR COL_DIM, "BTN TYPE - CLR URL  "
    END IF
END

' ---------------------------------------------------------------------------
' term_send_keys: drain everything the ECS keyboard has queued since the last
' pass and send it as ONE write.
'
' Coalescing is the point. net_write is a full mailbox round trip, so sending
' a transaction per keystroke would peg typing to the round-trip rate; draining
' the whole queue into FN_TX first costs one transaction no matter how many
' keys arrived, and the queue is a ring in ecskbd.bas that the frame interrupt
' has been filling while this loop was blocked in net_status.
'
' Translation: RTN -> CR LF (what compose_line already appends to a line), the
' four arrows -> ANSI CSI, and everything else -- printable ASCII, ESC, and the
' control codes CTL+key produces -- straight through as one byte. The 60-byte
' ceiling leaves room for a 3-byte sequence inside the TX window and simply
' defers the rest to the next pass, one frame later.
' ---------------------------------------------------------------------------
term_send_keys: PROCEDURE
    IF ecs_present = 0 THEN RETURN
    #fn_txlen = 0
    GOSUB ecs_getkey
    DO WHILE ecs_k <> ECS_NONE
        IF ecs_k = ECS_ENTER THEN
            POKE (FN_TX + #fn_txlen), 13
            POKE (FN_TX + #fn_txlen + 1), 10
            #fn_txlen = #fn_txlen + 2
        ELSEIF ecs_k >= ECS_LEFT AND ecs_k <= ECS_DOWN THEN
            ts_fin = 68                     ' LEFT
            IF ecs_k = ECS_RIGHT THEN ts_fin = 67
            IF ecs_k = ECS_UP THEN ts_fin = 65
            IF ecs_k = ECS_DOWN THEN ts_fin = 66
            POKE (FN_TX + #fn_txlen), 27
            POKE (FN_TX + #fn_txlen + 1), 91
            POKE (FN_TX + #fn_txlen + 2), ts_fin
            #fn_txlen = #fn_txlen + 3
        ELSE
            POKE (FN_TX + #fn_txlen), ecs_k
            #fn_txlen = #fn_txlen + 1
        END IF
        IF #fn_txlen > 60 THEN EXIT DO
        GOSUB ecs_getkey
    LOOP
    IF #fn_txlen > 0 THEN
        fn_len = #fn_txlen
        GOSUB net_write
    END IF
END

' ---------------------------------------------------------------------------
' seed_url: (re)load the default devicespec into SC_URL.
' ---------------------------------------------------------------------------
seed_url: PROCEDURE
    FOR nc_i = 0 TO LEN_SPEC - 1
        POKE (SC_URL + nc_i), PEEK(VARPTR lit_spec(0) + nc_i) AND 255
    NEXT nc_i
    POKE (SC_URL + LEN_SPEC), 0
END

' ---------------------------------------------------------------------------
' url_screen: full-screen URL editor on the character grid. Returns with
' fn_ok = 1 and the accepted devicespec NUL-terminated in SC_URL. ESC
' restores the default and keeps editing (there is nothing to cancel to).
' ---------------------------------------------------------------------------
url_screen: PROCEDURE
    GOSUB cur_hide              ' the grid draws its own cursor
us_again:
    CLS
    IF ecs_present THEN
        PRINT AT STATUS_ROW COLOR COL_DIM, "TYPE URL - RTN DIALS"
    ELSE
        PRINT AT STATUS_ROW COLOR COL_DIM, "TYPE URL - OK DIALS "
    END IF
    #ge_dst = SC_URL
    #g_max = 256
    GOSUB grid_entry
    IF fn_ok = 0 THEN
        GOSUB seed_url
        GOTO us_again
    END IF
    IF g_len = 0 THEN
        GOSUB seed_url
        GOTO us_again
    END IF
END

' ---------------------------------------------------------------------------
' compose_line: the same grid over the terminal screen. On OK, sends the
' line plus CR LF out the open channel. Restores the terminal afterward.
' ---------------------------------------------------------------------------
compose_line: PROCEDURE
    GOSUB cur_hide
    CLS
    IF ecs_present THEN
        PRINT AT STATUS_ROW COLOR COL_DIM, "RTN SENDS - ESC BACK"
    ELSE
        PRINT AT STATUS_ROW COLOR COL_DIM, "OK SENDS - ESC BACK "
    END IF
    GOSUB ecs_flush             ' keys meant for the terminal were already sent
    POKE SC_LINE, 0             ' fresh line every time
    #ge_dst = SC_LINE
    #g_max = 253
    GOSUB grid_entry

    IF fn_ok THEN
        #fn_txlen = 0
        #fn_src = SC_LINE : ls_max = 253 : GOSUB fn_strlen : GOSUB fn_putstr
        POKE (FN_TX + #fn_txlen), 13
        POKE (FN_TX + #fn_txlen + 1), 10
        fn_len = #fn_txlen + 2
        GOSUB net_write
    END IF

    CLS
    GOSUB term_repaint
    GOSUB ecs_flush
    GOSUB term_hint
    GOSUB cur_show
END

main:
    ' Foreground/Background mode, for the whole program and for good: it is the
    ' only STIC mode with a per-cell background, and every screen here now
    ' composes its cards through cell_word, which speaks it. The cost is that
    ' cards are limited to GROM 0-63 and GRAM 0-63, which is why vtfont.bas
    ' exists -- and why every PRINT string in this program is UPPERCASE.
    MODE 1 : WAIT
    term_fg = COL_NORMAL
    #cw_bgw = bg_scatter(CS_BLACK)
    GOSUB font_load
    GOSUB ecs_init
    CLS
    PRINT AT 0 COLOR COL_NORMAL, "FUJINET NETCAT"
    PRINT AT 40, "CONNECTING TO FUJINET"
    GOSUB fn_wait_mailbox
    IF fn_ok = 0 THEN
        PRINT AT 40, "NO CARTRIDGE MAILBOX "
        GOTO halt
    END IF
    GOSUB seed_url

dial:
    GOSUB url_screen

    ' Open the accepted devicespec: read-write, no translation (we handle
    ' CR LF ourselves).
    CLS
    PRINT AT 0 COLOR COL_NORMAL, "DIALING..."
    #fn_txlen = 0
    #fn_src = SC_URL : ls_max = 255 : GOSUB fn_strlen : GOSUB fn_putstr
    mb_dev = NET_DEVICEID
    mb_cmd = NETCMD_OPEN
    mb_nparam = 2
    pm_i = 0 : pm_size = 1 : #pm_val = OPEN_MODE_RW : GOSUB fn_param
    pm_i = 1 : pm_size = 1 : #pm_val = OPEN_TRANS_NONE : GOSUB fn_param
    GOSUB fn_transact
    IF fn_ok = 0 THEN
        PRINT AT 40 COLOR COL_ERROR, "CONNECT FAILED"
        PRINT AT 60 COLOR COL_DIM, "PRESS BUTTON TO EDIT"
con_wait:
        WAIT
        GOSUB in_poll
        IF in_btn = 0 THEN GOTO con_wait
        GOTO dial                  ' SC_URL still holds the typo -- fix it
    END IF

    CLS
    GOSUB term_init
    GOSUB term_clear_row
    GOSUB ecs_flush
    GOSUB term_hint
    GOSUB cur_show

term_loop:
    WAIT

    ' --- receive: anything waiting? read up to 64 bytes and print it ---
    GOSUB net_status
    IF fn_ok = 0 THEN
        PRINT AT STATUS_ROW COLOR COL_ERROR, "CONNECTION LOST     "
        GOSUB cur_hide
lost_wait:
        WAIT
        GOSUB in_poll
        IF in_btn = 0 THEN GOTO lost_wait
        GOSUB net_close            ' free the unit regardless
        GOTO dial
    END IF
    IF #net_avail > 0 THEN
        #net_readlen = #net_avail
        IF #net_readlen > 64 THEN #net_readlen = 64
        GOSUB net_read
        IF fn_ok THEN
            FOR nc_i = 0 TO #net_gotlen - 1
                nc_c = PEEK(FN_RX + nc_i) AND 255
                GOSUB term_putc
            NEXT nc_i
        END IF
    END IF

    ' --- input: ECS keys go straight out the wire (one write for the whole
    ' pass); the controller still opens the composer and hangs up ---
    GOSUB term_send_keys
    GOSUB in_poll
    IF in_btn THEN GOSUB compose_line
    IF in_key = KEYPAD_CLEAR THEN
        GOSUB net_close
        GOTO dial
    END IF
    GOTO term_loop

halt:
    WAIT
    GOTO halt
