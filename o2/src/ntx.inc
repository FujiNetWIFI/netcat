; ntx.inc -- the network device's transactions: each posted, never waited
; for (net.inc waits). Clobbers A, r0-r7.

np_begin:
    mov r2,#NET_DEVICEID
    jmp fn_begin
np_close:
    mov r3,#NC_CLOSE
    mov r4,#0
    call np_begin
    jmp fn_post
np_status:
    mov r3,#NC_STATUS
    mov r4,#2
    call np_begin
    clr a
    call fn_par1
    clr a
    call fn_par1
    jmp fn_post
; np_read: READ A bytes.
np_read:
    mov r5,a
    mov r3,#NC_READ
    mov r4,#2
    call np_begin
    mov a,#2                    ; a two-byte parameter: the length
    call fn_tx
    mov a,r5
    call fn_tx
    clr a
    call fn_tx
    clr a
    call fn_par1
    jmp fn_post
; np_write: WRITE the queue; KQS = how much of it.
np_write:
    mov r0,#KQN
    movx a,@r0
    mov r5,a
    mov r0,#KQS
    movx @r0,a
    mov r3,#NC_WRITE
    mov r4,#1
    call np_begin
    mov a,#2                    ; the length, as a two-byte parameter
    call fn_tx
    mov a,r5
    call fn_tx
    clr a
    call fn_tx
    mov r1,#KQ
npw_l:
    movx a,@r1
    call fn_tx
    inc r1
    djnz r5,npw_l
    jmp fn_post
; np_open: OPEN the spec (page 1 holds it), read and write, no translation.
np_open:
    mov r3,#NC_OPEN
    mov r4,#2
    call np_begin
    mov a,#NM_RW
    call fn_par1
    clr a
    call fn_par1
    mov r7,#PG_ONE
    mov a,#E_SPEC
    FCALL farcall
    jmp fn_post
