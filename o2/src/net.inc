; net.inc -- the connection: one channel of the network device ($71), one
; transaction out at a time, never waited on. net_step, once a frame, moves
; it along (NSTATE):
;
;   CLOSE -> OPEN -> IDLE <-> STATUS -> READ -> DRAIN (DRAIN_N bytes a frame)
;                      ^---> WRITE (the keys typed)
;
; A connection that ends, or never starts, leaves it DEAD until the button.
; FujiNet does the TELNET negotiation itself; the bytes here are the host's.
; The transactions themselves are ntx.inc's. Clobbers A, r0-r7.

    org 0C00h

; net_step: a state from NS_STAT on has a transaction out, and waits for it.
net_step:
    mov r0,#NSTATE
    movx a,@r0
    mov r7,a
    add a,#256-NS_STAT
    jnc ns_disp
    call fn_done
    jnz ns_tick
ns_disp:
    mov a,r7
    add a,#ns_tab&0FFh
    jmpp @a
ns_tab:
    db ns_idle&0FFh, ns_drain&0FFh, ns_dead&0FFh, ns_stat&0FFh
    db ns_read&0FFh, ns_write&0FFh, ns_close&0FFh, ns_open&0FFh

; ns_idle: the keys typed go first; else, what has come?
ns_idle:
    mov r0,#KQN
    movx a,@r0
    jnz ni_write
    call np_status
    mov a,#NS_STAT
    jmp ns_go
ni_write:
    call np_write
    mov a,#NS_WRITE
; ns_go: NSTATE = A, and the transaction out gets NTMOUT frames.
ns_go:
    mov r0,#NSTATE
    movx @r0,a
    mov r0,#NWAIT
    mov a,#NTMOUT
    movx @r0,a
    inc r0
    clr a
    movx @r0,a                  ; NWAITX
    ret

; ns_tick: the transaction is still out; out of time, the connection is
; taken for lost.
ns_tick:
    mov r0,#NWAIT
    movx a,@r0
    dec a
    movx @r0,a
    jnz nt_wait
    inc r0
    movx a,@r0
    jz nt_out
    dec a
    movx @r0,a
    dec r0
    mov a,#NTMOUT
    movx @r0,a
nt_wait:
    ret
nt_out:
    mov a,#S_NOANS
    jmp ns_down

; ns_stat: bytes waiting -> READ them; none, and the host gone -> lost.
ns_stat:
    call fn_ack
    jnz ns_retry
    clr a
    call rx_get
    mov r4,a                    ; bytes waiting
    mov a,#1
    call rx_get
    mov r5,a
    orl a,r4
    jnz st_some
    mov a,#2
    call rx_get                 ; connected
    jnz ns_retry
    mov a,#S_LOST
    jmp ns_down
st_some:
    mov a,r5
    jnz st_max
    mov a,r4
    add a,#256-RD_MAX
    jnc st_read
st_max:
    mov r4,#RD_MAX
st_read:
    mov a,r4
    call np_read
    mov a,#NS_READ
    jmp ns_go

; ns_read: the bytes are in the reply window; on to the screen.
ns_read:
    call fn_ack
    jnz ns_retry
    mov a,#FN_R_RXLEN_LO&0FFh
    call mb_get
    mov r0,#RXLEN
    movx @r0,a
    inc r0
    clr a
    movx @r0,a                  ; RXPOS
    mov a,#NS_DRAIN
    mov r0,#NSTATE
    movx @r0,a
; ns_drain: up to DRAIN_N of them a frame, so the keys and the stick keep
; up with a busy host.
ns_drain:
    mov r0,#DRN
    mov a,#DRAIN_N
    movx @r0,a
nd_l:
    mov r0,#RXPOS
    movx a,@r0
    mov r1,a
    mov r0,#RXLEN
    movx a,@r0
    xrl a,r1
    jz ns_retry                 ; all up: idle
    mov a,r1
    inc a
    mov r0,#RXPOS
    movx @r0,a
    mov a,r1
    call rx_get
    call tputc
    mov r0,#DRN
    movx a,@r0
    dec a
    movx @r0,a
    jnz nd_l
    ret

; ns_retry: idle -- next frame, ask again.
ns_retry:
    clr a
    mov r0,#NSTATE
    movx @r0,a
    ret

; ns_write: the keys are sent; off the queue with them (more may have come).
ns_write:
    mov r0,#KQS
    movx a,@r0
    mov r2,a                    ; sent
    cpl a
    inc a
    mov r3,a
    mov r0,#KQN
    movx a,@r0
    add a,r3
    movx @r0,a                  ; KQN - sent
    jz ns_retry
    mov r4,a
    mov a,r2
    add a,#KQ
    mov r1,a
    mov r0,#KQ
wr_sh:
    movx a,@r1
    movx @r0,a
    inc r0
    inc r1
    djnz r4,wr_sh
    jmp ns_retry

; ns_close: the channel is closed (or never was); dial.
ns_close:
    call np_open
    mov a,#NS_OPEN
    call ns_go
    mov r0,#NWAITX              ; a connect may take a while
    mov a,#3
    movx @r0,a
    ret

; ns_open: connected, or not.
ns_open:
    call fn_ack
    jnz op_fail
    mov a,#S_CONN
    call t_str
    jmp ns_retry
op_fail:
    mov a,#S_FAIL
    jmp ns_down

; ns_dead: the button dials again.
ns_dead:
    mov r0,#JOYEV
    movx a,@r0
    jb4 nd_dial
    ret
nd_dial:
    jmp net_dial

    if $ > 0D00h
    error "page $C has run out"
    endif
