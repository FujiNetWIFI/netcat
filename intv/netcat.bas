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

    ' Declarations come before the INCLUDEs, not after: IntyBASIC creates a
    ' variable at its first use, so a name an include mentions is already
    ' declared by the time a later DIM gets to it -- and that DIM is then an
    ' error. Everything shared with vt.bas, vtview.bas and vtfont.bas lives
    ' here, above them.
    ' IntyBASIC allows exactly one of these, so both per-frame jobs -- the ECS
    ' keyboard scan and the cursor blink -- hang off frame_tick.
    ON FRAME GOSUB frame_tick

    ' How much to pull out of the mailbox in one pass. The RX window holds
    ' 512, but every byte has to walk the parser, so a full window would be
    ' most of a fifth of a second of work with the keyboard ignored throughout.
    CONST TERM_READ  = 256

    ' How many consecutive unhappy STATUS polls to tolerate before declaring
    ' the connection dead. It cannot be zero. OPEN returns as soon as the
    ' request is accepted, not when the far end is reachable, so the first
    ' STATUS after it routinely reports "not connected" -- for TCP that is a
    ' race measured in milliseconds, but SSH has a TCP connect, a protocol
    ' handshake and an authentication to get through first. Treating that
    ' first answer as fatal hung up on every ssh session before it started.
    '
    ' Patient while dialling, brisk once the session is up: waiting four
    ' minutes to notice a shell that has exited is not patience.
    CONST TERM_GRACE = 240
    CONST TERM_DROP  = 16

    CONST STATUS_ROW = 220      ' row 11, used only by the screens that
                                ' are not the terminal -- the terminal itself
                                ' now owns all twelve rows.

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
    ' $9400-$943F is the ECS key ring (ecskbd.bas) and $9440 the row map
    ' (vt.bas); the 80x25 buffer has $8000-$8F9F.

' ---------------------------------------------------------------------------
' The window-size query.
'
' NetworkProtocolSSH reads term, cols and rows out of the devicespec query and
' hands them to ssh_channel_request_pty_size(); NetworkProtocolTelnet does the
' same for its terminal type and NAWS. Without them the far end assumes 80x24
' of something called "vanilla" and a curses program draws to the wrong shape.
'
' The type is xterm rather than linux on purpose. Both are 80x25 and both do
' colour, but the linux terminfo's smacs/rmacs are ESC [ 11 m / ESC [ 10 m --
' the IBM alternate character set -- while this terminal implements ESC ( 0,
' which is what xterm advertises. Claim linux and the box drawing never fires.
'
' Only TELNET and SSH get it: NetworkProtocolTCP ignores a query, and a spec
' that brought its own is left alone so ?term=ansi stays available by hand.
lit_query:
    DATA 63,116,101,114,109,61,120,116,101,114,109,38,99,111
    DATA 108,115,61,56,48,38,114,111,119,115,61,50,53
    CONST LEN_QUERY = 27

' The default devicespec: "N:TELNET://BBS.FOZZTEXX.COM/"
lit_spec:
    DATA 78,58,84,69,76,78,69,84,58,47,47,66,66,83
    DATA 46,70,79,90,90,84,69,88,88,46,67,79,77,47
    CONST LEN_SPEC = 28

    DIM nc_i, nc_c, ts_fin
    DIM uq_i, uq_c, uq_len, uq_ok
    DIM nc_up, nc_bad, nc_lim
    DIM #an_a, #an_b
    DIM cur_on, cur_lit, cur_col, cur_row, cur_c
    DIM #cur_attr
    DIM #cur_x, #cur_y

    ' The terminal's current attribute. Only the foreground moves for now;
    ' the background is black until SGR lands. (cell_word's own arguments are
    ' DIMmed in vtfont.bas, which has to declare them ahead of its first use.)
    DIM term_fg

    INCLUDE "fujinet.bas"
    INCLUDE "ecskbd.bas"
    INCLUDE "vtfont.bas"
    INCLUDE "kbd.bas"
    INCLUDE "vt.bas"
    INCLUDE "vtview.bas"

    ' The parser goes in the second ROM segment. $5000-$6FFF is 8K words and
    ' the terminal core had already spent most of it; $D000-$DFFF is the next
    ' window the cartridge maps, and fujinet-config/intv uses the same pair on
    ' this exact hardware. Everything after this ORG -- the parser, this file's
    ' own procedures, main, and the IntyBASIC epilogue -- lands there, so the
    ' "guard" make target watches for a spill into the unmapped $E000.
    ASM ORG $D000
    INCLUDE "vtansi.bas"

    ' ...and the rest into the third. $D000-$DFFF is 4K words and the parser
    ' fills it; without this the compiler silently continues into $E000, which
    ' is not mapped -- the cart boots and then runs off into unprogrammed GROM
    ' two instructions later. That is what the "guard" make target checks for,
    ' and it is how this ORG came to be here.
    ASM ORG $F000


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
    GOSUB ov_tick
END

' ---------------------------------------------------------------------------
' The terminal's blinking block cursor, MOB 0.
'
' A MOB rather than a BACKTAB cell because the cursor sits exactly where the
' next received byte will be drawn: as a character cell it would have to be
' erased before every write and repainted after, and it would have to be kept
' out of the buffer so a repaint did not make it permanent. A sprite floats
' over all of that, and the receive path stays untouched.
'
' Where it goes is decided by vp_cursor, in the main loop. The interrupt used
' to work that out itself, but recovering a row and column costs two divisions
' and IntyBASIC compiles division into a subtract loop -- not something to run
' inside a frame hook. All that is left here is the blink.
'
' cur_show / cur_hide bracket the terminal. Hiding matters -- a MOB left
' enabled keeps drawing over whatever screen comes next.
' ---------------------------------------------------------------------------
cur_show: PROCEDURE
    cur_on = 1
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

    ' The MOB registers are shadowed in RAM and blitted by the ISR every frame,
    ' so a single write persists -- only touch them when the phase flips.
    IF (FRAME AND CUR_BLINK) = 0 THEN
        IF cur_lit <> 1 THEN
            cur_lit = 1
            SPRITE CUR_MOB, #cur_x, #cur_y, #cur_attr
        END IF
    ELSE
        IF cur_lit <> 0 THEN
            cur_lit = 0
            SPRITE CUR_MOB, 0, 0, 0
        END IF
    END IF
END

' ---------------------------------------------------------------------------
' term_keypad: the keypad in the terminal.
'
' Sixty columns of horizontal travel is a long way to walk a disc, so 1-4 jump
' the window to a column band and ENTER recentres it on the cursor. These keys
' were decoded but unused before.
' ---------------------------------------------------------------------------
term_keypad: PROCEDURE
    IF in_key >= 1 THEN
        IF in_key <= 4 THEN
            vp_i = in_key - 1
            GOSUB vp_band
            RETURN
        END IF
    END IF
    IF in_key = KEYPAD_ENTER THEN
        vp_track = 1
        BORDER BORDER_FOLLOW
        GOSUB vp_follow
        vp_full = 1
        GOSUB ov_show
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
    #fn_txlen = 0

    ' Answers to DSR and DA first: a program that asked one is blocked until
    ' it arrives, and it rides out with whatever was typed rather than costing
    ' a mailbox round trip of its own.
    IF an_rlen THEN
        FOR ts_fin = 0 TO an_rlen - 1
            POKE (FN_TX + ts_fin), PEEK(SC_REPLY + ts_fin) AND 255
        NEXT ts_fin
        #fn_txlen = an_rlen
        an_rlen = 0
    END IF

    IF ecs_present = 0 THEN
        IF #fn_txlen = 0 THEN RETURN
        fn_len = #fn_txlen
        GOSUB net_write
        RETURN
    END IF
    GOSUB ecs_getkey
    DO WHILE ecs_k <> ECS_NONE
        IF ecs_k = ECS_ENTER THEN
            ' A bare CR. This used to send CR LF, which is right for a
            ' line-oriented socket and wrong for a terminal: over a pty the LF
            ' is a second newline, so every RETURN left a blank line behind.
            ' The TELNET handler in the firmware adds what NVT needs.
            POKE (FN_TX + #fn_txlen), 13
            #fn_txlen = #fn_txlen + 1
        ELSEIF ecs_k >= ECS_LEFT AND ecs_k <= ECS_DOWN THEN
            ts_fin = 68                     ' LEFT
            IF ecs_k = ECS_RIGHT THEN ts_fin = 67
            IF ecs_k = ECS_UP THEN ts_fin = 65
            IF ecs_k = ECS_DOWN THEN ts_fin = 66
            POKE (FN_TX + #fn_txlen), 27
            ' DECCKM: with application cursor keys set, the arrows are
            ' ESC O A and not ESC [ A. readline and vi both turn it on, and
            ' both stop understanding the arrows if it is ignored.
            IF an_ckm THEN
                POKE (FN_TX + #fn_txlen + 1), 79
            ELSE
                POKE (FN_TX + #fn_txlen + 1), 91
            END IF
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
' url_wantsz: append the window-size query to SC_URL, in place.
'
' Runs after the URL screen and before the OPEN. Three ways to decline: the
' spec already has a query, the scheme is not one that reads it, or there is
' not room -- FN_TX is 256 bytes and the whole devicespec has to fit in it
' alongside the query, so a spec near the buffer ceiling is left as typed.
' ---------------------------------------------------------------------------
url_wantsz: PROCEDURE
    #fn_src = SC_URL : ls_max = 255 : GOSUB fn_strlen
    uq_len = fn_len
    IF uq_len + LEN_QUERY > 250 THEN RETURN

    uq_ok = 0
    FOR uq_i = 0 TO uq_len - 1
        uq_c = PEEK(SC_URL + uq_i) AND 255
        IF uq_c = 63 THEN RETURN            ' "?" -- the caller knows better
    NEXT uq_i

    ' Scheme test on the two letters after "N:", which is enough to tell
    ' TELNET and SSH apart from TCP, UDP, HTTP and the rest.
    uq_c = PEEK(SC_URL + 2) AND 255
    IF uq_c = 84 THEN uq_ok = 1             ' T(ELNET)
    IF uq_c = 116 THEN uq_ok = 1
    IF uq_c = 83 THEN uq_ok = 1             ' S(SH)
    IF uq_c = 115 THEN uq_ok = 1
    IF uq_ok = 0 THEN RETURN
    uq_c = PEEK(SC_URL + 3) AND 255
    IF uq_c = 67 THEN RETURN                ' "SC..." is not SSH
    IF uq_c = 99 THEN RETURN

    FOR uq_i = 0 TO LEN_QUERY - 1
        POKE (SC_URL + uq_len + uq_i), PEEK(VARPTR lit_query(0) + uq_i) AND 255
    NEXT uq_i
    POKE (SC_URL + uq_len + LEN_QUERY), 0
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
    GOSUB vp_dirty_all
    GOSUB vp_paint
    GOSUB vp_cursor
    GOSUB ecs_flush
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

    ' Open the accepted devicespec: read-write, no translation (we are the
    ' terminal, so nothing else should be rewriting the stream).
    GOSUB url_wantsz
    CLS
    PRINT AT 0 COLOR COL_NORMAL, "DIALING..."

    ' Close first. The unit may still be open from a previous session: this
    ' program does not get to run its own shutdown when the console is reset
    ' or the emulator is killed, and the FujiNet keeps the unit either way --
    ' the same persistence that makes fn_transact derive its sequence number
    ' from the cartridge's ACKSEQ rather than a local counter. A CLOSE with
    ' nothing open is harmless; an OPEN onto a stale unit never connects.
    GOSUB net_close

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
    PRINT AT 0 COLOR COL_NORMAL, "CONNECTING..."
    GOSUB an_sgr_reset
    GOSUB vt_reset
    GOSUB vp_reset
    an_awm = 1
    an_ckm = 0
    an_rlen = 0
    nc_up = 0
    nc_bad = 0
    GOSUB ecs_flush

term_loop:
    WAIT

    ' Keys go out before the round trip as well as after it. A pass costs at
    ' least one blocking mailbox transaction, so a key typed during the last
    ' one would otherwise wait a whole extra pass for its echo.
    GOSUB term_send_keys

    ' --- receive: anything waiting? read a chunk and feed it to the terminal
    GOSUB net_status
    IF fn_ok THEN
        nc_bad = 0
    ELSE
        nc_bad = nc_bad + 1
    END IF

    ' Take the "CONNECTING..." notice down on either a healthy link or bytes
    ' to show. Both, because a connection that has already closed can still
    ' have a screenful waiting: an unhappy STATUS is not a reason to throw
    ' away what the far end managed to say before it went.
    IF nc_up = 0 THEN
        IF fn_ok THEN GOTO nc_isup
        IF #net_avail = 0 THEN GOTO nc_notup
nc_isup:
        nc_up = 1
        CLS
        GOSUB vp_dirty_all
        GOSUB cur_show
nc_notup:
    END IF

    ' Give up slowly while dialling and quickly once the session has been up.
    nc_lim = TERM_GRACE
    IF nc_up THEN nc_lim = TERM_DROP
    IF nc_bad >= nc_lim THEN
        IF #net_avail = 0 THEN
            PRINT AT STATUS_ROW COLOR COL_ERROR, "CONNECTION LOST     "
            GOSUB cur_hide
lost_wait:
            WAIT
            GOSUB in_poll
            IF in_btn = 0 THEN GOTO lost_wait
            GOSUB net_close        ' free the unit regardless
            GOTO dial
        END IF
    END IF

    IF #net_avail > 0 THEN
        #net_readlen = #net_avail
        IF #net_readlen > TERM_READ THEN #net_readlen = TERM_READ
        GOSUB net_read
        IF fn_ok THEN
            FOR nc_i = 0 TO #net_gotlen - 1
                nc_c = PEEK(FN_RX + nc_i) AND 255
                GOSUB an_feed
            NEXT nc_i
        END IF
    END IF

    ' --- input: ECS keys go straight out the wire (one write for the whole
    ' pass); the controller drives the window and opens the composer ---
    GOSUB term_send_keys
    GOSUB in_poll
    IF in_key = KEYPAD_CLEAR THEN
        GOSUB net_close
        GOTO dial
    END IF
    IF in_btop THEN GOSUB vp_toggle
    IF in_blow THEN GOSUB compose_line
    GOSUB vp_pan
    IF in_key <> KEYPAD_NONE THEN GOSUB term_keypad

    ' --- and only now put it on the screen. Painting once per pass rather
    ' than once per character is what makes a 20x12 window onto an 80x25
    ' buffer affordable: a chunk of 256 bytes costs one repaint, not 256.
    IF nc_up THEN
        GOSUB vp_follow
        GOSUB vp_paint
        GOSUB vp_cursor
    END IF
    GOTO term_loop

halt:
    WAIT
    GOTO halt
