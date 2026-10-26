; screen.inc -- the main program's side of the display: the VDC set up once,
; the interrupts on, and where each row of the terminal lives for POKE.

; vdc_init: display off, every object cleared, the quads put at their
; columns (only Y changes from line to line), the cursor's shape. Main
; program, interrupts off. Clobbers A, r0, r2.
vdc_init:
    mov a,#P1_VDC
    outl p1,a
    mov r0,#vdc_control
    clr a
    movx @r0,a
    mov r0,#0                   ; $00-$9F: sprites, characters, quads, shapes
    mov r2,#0A0h
vi_clr:
    movx @r0,a
    inc r0
    djnz r2,vi_clr
    mov r0,#vdc_quad0+1
    mov a,#X0                   ; window columns 0,2,4,6
    movx @r0,a
    mov r0,#vdc_quad1+1
    mov a,#X0+64                ; 8,10,12,14
    movx @r0,a
    mov r0,#vdc_quad2+1
    mov a,#X0+8                 ; 1,3,5,7
    movx @r0,a
    mov r0,#vdc_quad3+1
    mov a,#X0+72                ; 9,11,13,15
    movx @r0,a
    mov r0,#vdc_spr0_shape+6    ; the cursor: an underline
    mov a,#0FFh
    movx @r0,a
    inc r0
    movx @r0,a
    mov a,#P1_MAIN
    outl p1,a
    ret

; ints_on: the line counter and the vblank interrupt.
ints_on:
    clr a
    mov t,a
    strt cnt
    en tcnti
    en i
    ret

; row_at: aim POKE at the start of buffer row A (0..ROWS-1); cell_at: at
; byte r3 of it (a row never crosses a page). Clobbers A, r0-r3.
row_at:
    mov r3,#0
cell_at:
    mov r1,a
    add a,#rowhi&0FFh
    movp a,@a
    mov r2,a
    mov a,r1
    add a,#rowlo&0FFh
    movp a,@a
    add a,r3
    jmp poke_at
rowlo:
    db RB_0&0FFh, RB_1&0FFh, RB_2&0FFh, RB_3&0FFh, RB_4&0FFh, RB_5&0FFh, RB_6&0FFh
rowhi:
    db RB_0>>8, RB_1>>8, RB_2>>8, RB_3>>8, RB_4>>8, RB_5>>8, RB_6>>8
