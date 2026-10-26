; mail.inc -- the cartridge mailbox (fuji_mailbox.h), never waiting; and
; POKE, the way into the fixed half's cartridge RAM.
;
; A transaction is: fn_begin (device, command, parameter count; the TX stream
; rewound), the parameters and payload through FN_W_DATA, then fn_post, which
; writes the sequence number that launches it. fn_done says when the cart has
; echoed it. Main program, P1 = P1_MAIN (the register file and external RAM
; both answer MOVX). Rules carried from the family's other carts:
;   - the sequence number is the cart's ACKSEQ + 1, never a counter of ours:
;     a console RESET restarts this program, not the cartridge;
;   - nothing else writes the register file while a transaction is out --
;     POKE included: the screen is drawn only between transactions;
;   - the reply is the cart's reply buffer, read through the window (RXWIN):
;     the next transaction replaces it.

; fn_reg: register r7 = A. Clobbers r0, r6.
fn_reg:
    mov r6,a
    mov r0,#FN_W_REGSEL
    mov a,r7
    movx @r0,a
    inc r0
    mov a,r6
    movx @r0,a
    ret

; fn_begin: device r2, command r3, r4 parameters to follow. Clobbers A, r0,
; r6, r7.
fn_begin:
    mov a,r2
    mov r7,#FN_REG_DEVICE
    call fn_reg
    mov a,r3
    mov r7,#FN_REG_CMD
    call fn_reg
    mov a,r4
    mov r7,#FN_REG_NPARAM
    call fn_reg
    mov r7,#FN_REG_DATA_RST
    jmp fn_reg

; fn_tx: A into the TX stream. Clobbers r0.
fn_tx:
    mov r0,#FN_W_DATA
    movx @r0,a
    ret

; fn_par1: a one-byte parameter, A. Clobbers r0, r6.
fn_par1:
    mov r6,a
    mov a,#1
    call fn_tx
    mov a,r6
    jmp fn_tx

; fn_post: launch it -- SEQ = the cart's ACKSEQ + 1 (0 is never used), kept
; in NSEQ. Clobbers A, r0.
fn_post:
    mov a,#FN_R_ACKSEQ&0FFh
    call mb_get
    inc a
    jnz fp_ok
    inc a
fp_ok:
    mov r0,#NSEQ
    movx @r0,a
    mov r0,#FN_W_SEQ
    movx @r0,a
    ret

; fn_done: A = 0 once the cart has echoed NSEQ. Clobbers A, r0, r6.
fn_done:
    mov a,#FN_R_ACKSEQ&0FFh
    call mb_get
    mov r6,a
    mov r0,#NSEQ
    movx a,@r0
    xrl a,r6
    ret

; fn_ack: A = 0 if the transaction worked and was ACKed. Clobbers A.
fn_ack:
    mov a,#FN_R_ERR&0FFh
    call mb_get
    jnz fa_bad
    mov a,#FN_R_REPLY_CMD&0FFh
    call mb_get
    xrl a,#FC_ACK
fa_bad:
    ret

; rx_get: A = reply byte A (0-207: the window stays at 0).
rx_get:
    add a,#FN_R_DATA&0FFh
    jmp mb_get

; poke_at: aim POKE at offset r2:A of the fixed half (r2 = 0-3: $400-$7FF).
; Leaves the register file selecting POKE, so each poke_b after it is one
; MOVX. Clobbers A, r0, r1.
poke_at:
    mov r1,a
    mov r0,#FN_W_REGSEL
    mov a,#FN_REG_POKE_LO
    movx @r0,a
    inc r0
    mov a,r1
    movx @r0,a
    dec r0
    mov a,#FN_REG_POKE_HI
    movx @r0,a
    inc r0
    mov a,r2
    movx @r0,a
    dec r0
    mov a,#FN_REG_POKE
    movx @r0,a
    ret

; poke_b: store A at the POKE pointer and advance it. Clobbers r0.
poke_b:
    mov r0,#FN_W_REGDATA
    movx @r0,a
    ret
