; keys.inc -- the keyboard (what each key sends is p1.inc's), and the
; transactions (ntx.inc). Main program, P1 = P1_MAIN.
;
; The console has no shift key, and YES and NO are its Y and N. So two keys
; it seldom needs are prefixes for the next key: x (*) shifts it -- upper
; case, a digit's symbol on a PC, punctuation the keyboard lacks -- and
; the divide key (/) makes it a control code. Each, pressed twice, sends
; itself. Plain keys send lower case; CLR is backspace, ENT CR LF.

K_SHIFT equ 29h                 ; x
K_CTRL  equ 2Ah                 ; divide

    org 0D00h

; key_poll: a key pressed since the last call, onto the queue. The BIOS
; scans the matrix (readkey: A = a new key 0-47, $C0 + key while it is held,
; $FF none). It keeps the last key in bank 0's r7 and comes back in bank 1.
; Call it in the quiet stretch (frame_sync): it holds the vblank off for up
; to ~400 cycles while it debounces. Clobbers A, r0-r7.
key_poll:
    mov r0,#KLAST
    movx a,@r0
    mov r7,a
    FCALL readkey
    sel rb0
    mov r6,a
    mov a,r7
    mov r0,#KLAST
    movx @r0,a
    mov a,r6
    jb7 kp_none
    jb6 kp_none
    mov r5,a                    ; the key
    mov r0,#SHIFT
    movx a,@r0
    mov r4,a                    ; 0 plain, 1 after x, 2 after divide
    jnz kp_look                 ; this key finishes a prefix
    mov a,r5
    xrl a,#K_SHIFT
    jz kp_pre1
    xrl a,#K_SHIFT!K_CTRL
    jnz kp_look
    mov a,#2
    movx @r0,a
    ret
kp_pre1:
    mov a,#1
    movx @r0,a
    ret
kp_look:
    clr a                       ; a prefix lasts one key
    movx @r0,a
    mov r7,#PG_ONE
    mov a,#E_KEY
    FCALL farcall               ; r5 = the key's byte
    mov a,r5
    jz kp_none                  ; nothing for that key
    xrl a,#0Dh
    jnz kp_one
    mov a,#0Dh                  ; CR: CR LF
    call kq_put
    mov a,#0Ah
    jmp kq_put
kp_one:
    mov a,r5
    jmp kq_put
kp_none:
    ret

; kq_put: byte A onto the queue (gone, if the queue is full). Clobbers A,
; r0, r1.
kq_put:
    mov r1,a
    mov r0,#KQN
    movx a,@r0
    xrl a,#KQ_MAX
    jz kq_full
    movx a,@r0
    inc a
    movx @r0,a
    add a,#KQ-1
    mov r0,a
    mov a,r1
    movx @r0,a
kq_full:
    ret

    include "ntx.inc"

    if $ > 0E00h
    error "page $D has run out"
    endif
