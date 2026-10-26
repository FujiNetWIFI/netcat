; p0.inc -- page 0: netcat. The boot, the main loop, and everything it runs:
; the screen's set-up ($9), the terminal ($A-$B), the connection ($C), the
; keyboard ($D), the mailbox and the strings ($E). Each block of code has a
; 256-byte page of its own: the 8048's conditional jumps stay in their page.

    PAGE_HEAD
    db boot&0FFh

; boot: a power-on, or a console RESET (the cartridge's RAM -- the screen --
; survives that; the program starts over).
boot:
    dis i
    dis tcnti
    mov r0,#FRAMES              ; internal RAM $20-$2A
    mov r2,#CURPG-FRAMES
    clr a
b_iram:
    mov @r0,a
    inc r0
    djnz r2,b_iram
    mov r0,#0                   ; external RAM
    mov r2,#80h
b_xram:
    movx @r0,a
    inc r0
    djnz r2,b_xram
    mov r0,#SCOL
    mov @r0,#BG_FOLLOW
    mov r0,#SPRY
    mov @r0,#0F8h               ; no cursor yet
    mov r0,#FOLLOW
    mov a,#1
    movx @r0,a
    clr a                       ; the reply window at its start, for good
    mov r7,#FN_REG_RXWIN
    call fn_reg
    call vdc_init
    call t_clear
    call ints_on
    mov a,#S_HELLO
    call t_str
    call net_dial
main_loop:
    call frame_sync             ; the frame's lines are drawn
    call key_poll
    call pan_poll
    call cur_show
    call net_step
    jmp main_loop

; pan_poll: the stick moves the window. Left/right pan it two columns every
; PAN_RATE frames while held, up/down a window's width; any of them leaves
; the cursor behind (the background goes green). The button brings the
; window back to the cursor and keeps it there (blue). Clobbers A, r0-r4.
PAN_RATE equ 2
pan_poll:
    call joy_poll
    mov r0,#JOYEV
    movx a,@r0
    jb4 pp_fire
    mov r2,#256-WCOLS
    jb0 pp_by
    mov r2,#WCOLS
    jb1 pp_by
    mov r0,#JOY
    movx a,@r0
    anl a,#J_LEFT|J_RIGHT
    mov r1,a
    mov r0,#REP
    jz pp_rel                   ; neither: a press steps at once
    movx a,@r0
    jz pp_step
    dec a
    movx @r0,a
    ret
pp_rel:
    movx @r0,a
    ret
pp_step:
    mov a,#PAN_RATE-1
    movx @r0,a
    mov r2,#2
    mov a,r1
    jb3 pp_by
    mov r2,#256-2
; pp_by: the window r2 columns over (signed), kept in 0..PANMAX.
pp_by:
    mov r0,#PAN
    movx a,@r0
    add a,r2
    jb7 pp_lo
    mov r3,a
    add a,#256-PANMAX-1
    mov a,r3
    jnc pp_set
    mov a,#PANMAX
    jmp pp_set
pp_lo:
    clr a
pp_set:
    call pan_set
    clr a
    mov r0,#FOLLOW
    movx @r0,a
    mov r0,#SCOL
    mov @r0,#BG_FREE
    ret
pp_fire:
    mov a,#1
    mov r0,#FOLLOW
    movx @r0,a
    mov r0,#SCOL
    mov @r0,#BG_FOLLOW
    jmp t_follow

; cur_show: the cursor sprite for the next frame -- under the cursor's cell
; when the window shows it, blinking; yellow while x waits for its key,
; green while divide does, else white. Clobbers A, r0, r1.
SPR_WHITE  equ 7<<3
SPR_YELLOW equ 3<<3
SPR_GREEN  equ 2<<3
cur_show:
    mov r1,#FRAMES
    mov a,@r1
    jb4 cs_hide
    mov r0,#CX
    movx a,@r0
    mov r1,a
    xrl a,#COLS
    jnz cs_col
    dec r1                      ; a waiting wrap: on column 79
cs_col:
    mov r0,#PAN
    movx a,@r0
    cpl a
    inc a
    add a,r1                    ; the window's column, signed
    jb7 cs_hide
    mov r1,a
    add a,#256-WCOLS
    jc cs_hide
    mov a,r1
    rl a
    rl a
    rl a
    add a,#X0
    mov r0,#SPRX
    mov @r0,a
    mov r0,#CY
    movx a,@r0
    swap a
    rl a                        ; x PITCH (32)
    add a,#Y0
    mov r0,#SPRY
    mov @r0,a
    mov r1,#SPR_WHITE
    mov r0,#SHIFT
    movx a,@r0
    jz cs_attr
    mov r1,#SPR_YELLOW
    jb0 cs_attr
    mov r1,#SPR_GREEN
cs_attr:
    mov r0,#SPRA
    mov a,r1
    mov @r0,a
    ret
cs_hide:
    mov r0,#SPRY
    mov @r0,#0F8h
    ret

    if $ > 900h
    error "page $8 has run out"
    endif

; ---------------------------------------------------------------------------
    org 900h
    include "screen.inc"
    include "input.inc"
    if $ > 0A00h
    error "page $9 has run out"
    endif

    include "term.inc"
    include "net.inc"
    include "keys.inc"

; ---------------------------------------------------------------------------
    org 0E00h
    include "mail.inc"

; t_str: string A (S_*, page 1's) to the terminal, to its NUL or a '?', on
; a line of its own. Clobbers A, r0-r7.
t_str:
    mov r5,a
    mov r0,#CX
    movx a,@r0
    jz ts_fresh
    call t_cr
    call t_lf
ts_fresh:
    mov r7,#PG_ONE
    mov a,#E_STR
    FCALL farcall
    mov a,#STRB
    mov r0,#SPTR
    movx @r0,a
ts_l:
    mov r0,#SPTR
    movx a,@r0
    mov r1,a
    movx a,@r1
    jz ts_done
    xrl a,#'?'
    jz ts_done
    xrl a,#'?'
    call tputc
    mov r0,#SPTR
    movx a,@r0
    inc a
    movx @r0,a
    jmp ts_l
ts_done:
    ret

; ns_down: say A (S_*), then wait for the button.
ns_down:
    call t_str
    mov a,#S_FIRE
    call t_str
    mov a,#NS_DEAD
    mov r0,#NSTATE
    movx @r0,a
    ret

; net_dial: say so, close the channel, then open it (net.inc ns_close).
; Keys typed while there was no connection are not the new one's.
net_dial:
    clr a
    mov r0,#KQN
    movx @r0,a
    mov a,#S_DIAL
    call t_str
    mov a,#S_SPEC               ; (to its query)
    call t_str
    mov a,#S_CRLF
    call t_str
    call np_close
    mov a,#NS_CLOSE
    jmp ns_go

    if $ > 0F00h
    error "page $E has run out"
    endif

    PAGE_TAIL
