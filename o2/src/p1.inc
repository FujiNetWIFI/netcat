; p1.inc -- page 1: what page 0 has no room for and needs only now and then,
; reached by farcall (fixed.inc): what each key sends, the messages, and the
; spec dialled. Nothing here may call into page 0 (it is not mapped while
; this runs): results come back in r5 or external RAM.

    PAGE_HEAD
    db p1_key&0FFh, e_str&0FFh, e_spec&0FFh   ; E_KEY, E_STR, E_SPEC

e_str:
    jmp p1_str
e_spec:
    jmp p1_spec

; p1_key: r5 = a key's code (0-47; row x 8 + column), r4 = its prefix (0
; none, 1 x, 2 divide) -> r5 = the byte it sends, 0 for none.
p1_key:
    mov a,r4
    rl a
    add a,r4
    rl a
    rl a
    rl a
    rl a                        ; x 48: the prefix's table
    add a,r5
    add a,#knorm&0FFh
    movp a,@a
    mov r5,a
    ret

; Plain: lower case (Y and N are YES and NO), CLR backspace, ENT CR (keys.inc
; adds the LF). x and divide never get here plain.
knorm:
    db "0123456789", 0, 0, " ?lp"
    db "+wertuio"
    db "qsdfghjk"
    db "azxcvbm."
    db "-", 0, 0, "=yn", 08h, 0Dh
; After x: upper case, a PC's shifted digits, the punctuation the keyboard
; lacks; x x is *, x divide \, SPACE TAB, CLR DEL, ENT ESC.
kshift:
    db ")!@#$%^&*(", 0, 0, 09h, 22h, "LP"
    db ";WERTUIO"
    db "QSDFGHJK"
    db "AZXCVBM,"
    db "_*", 5Ch, ":YN", 7Fh, 1Bh
; After divide: control letters; divide divide is /, divide x |, ? ',
; . > - < = [ + ].
kctrl:
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 27h, 0Ch, 10h
    db "]", 17h, 05h, 12h, 14h, 15h, 09h, 0Fh
    db 11h, 13h, 04h, 06h, 07h, 08h, 0Ah, 0Bh
    db 01h, 1Ah, 18h, 03h, 16h, 02h, 0Dh, ">"
    db "<|/[", 19h, 0Eh, 0, 0

    if $ > 900h
    error "page 1's page $8 has run out"
    endif

; ---------------------------------------------------------------------------
    org 900h

; p1_str: string r5 (S_*) into STRB, NUL-terminated, STRB_LEN-1 bytes at
; most. Clobbers A, r0-r2.
p1_str:
    mov a,r5
    add a,#stab&0FFh
    movp a,@a
    mov r1,a
    mov r0,#STRB
    mov r2,#STRB_LEN-1
ps_l:
    mov a,r1
    movp a,@a
    movx @r0,a
    jz ps_done
    inc r0
    inc r1
    djnz r2,ps_l
    clr a
    movx @r0,a
ps_done:
    ret

; p1_spec: the spec into the TX stream, through its NUL. Clobbers A, r0, r1.
p1_spec:
    mov r1,#u_spec&0FFh
    mov r0,#FN_W_DATA
psp_l:
    mov a,r1
    movp a,@a
    movx @r0,a
    inc r1
    jnz psp_l
    ret

stab:                           ; by S_*
    db s_hello&0FFh, s_dial&0FFh, s_conn&0FFh, s_fail&0FFh
    db s_noans&0FFh, s_lost&0FFh, s_fire&0FFh, s_crlf&0FFh, u_spec&0FFh
s_hello:
    db "FUJINET NETCAT",0Dh,0Ah,0
s_dial:
    db "DIALING",0Dh,0Ah,0
s_conn:
    db "CONNECTED.",0Dh,0Ah,0
s_fail:
    db "NO CONNECTION.",0Dh,0Ah,0
s_noans:
    db "NO ANSWER.",0Dh,0Ah,0
s_lost:
    db "DISCONNECTED.",0Dh,0Ah,0
s_fire:
    db "FIRE REDIALS.",0Dh,0Ah
s_crlf:
    db 0                        ; nothing: t_str's fresh line is the point
    include "endpoint.inc"

    if $ > 0A00h
    error "page 1's page $9 has run out"
    endif

    PAGE_TAIL
