; spike.inc -- page 0 for the engine alone (SPIKE=1 ./build.sh): a test
; pattern in every row, no network. The stick pans (left/right) and rolls the
; ring (up/down), so a run can check the window, the ring and the timing.
; Column c shows: a letter for its ten (A = 0-9, B = 10-19 ...) at c%10 = 0,
; the row's number at c%10 = 1, else c%10.

    PAGE_HEAD
    db sp_boot&0FFh

sp_boot:
    dis i
    dis tcnti
    mov r0,#FRAMES
    mov r2,#CURPG-FRAMES
    clr a
sb_clr:
    mov @r0,a
    inc r0
    djnz r2,sb_clr
    mov r0,#SCOL
    mov @r0,#BG_FOLLOW
    mov r0,#SPRY
    mov @r0,#0F8h               ; no cursor
    call vdc_init
    call fill
    call ints_on
sp_loop:
    call frame_sync
    call joy_poll
    mov r0,#JOY
    movx a,@r0
    jb2 sp_left
    jb3 sp_right
sp_v:
    mov r0,#JOYEV
    movx a,@r0
    jb0 sp_up
    jb1 sp_down
    jmp sp_loop
sp_left:
    mov r0,#PANM
    mov a,@r0
    jz sp_v
    dec a
    mov @r0,a
    jmp sp_v
sp_right:
    mov r0,#PANM
    mov a,@r0
    xrl a,#PANMAX/2
    jz sp_v
    inc @r0
    jmp sp_v
sp_up:
    mov r0,#HEAD
    mov a,@r0
    jnz su_dec
    mov a,#ROWS
su_dec:
    dec a
    mov @r0,a
    jmp sp_loop
sp_down:
    mov r0,#HEAD
    inc @r0
    mov a,@r0
    xrl a,#ROWS
    jnz sp_loop
    mov @r0,a
    jmp sp_loop

; fill: the test pattern in every row. Clobbers A, r0-r7.
fill:
    mov r7,#0
fl_row:
    mov a,r7
    call row_at
    mov r4,#0
    call fl_plane
    mov r4,#1
    call fl_plane
    inc r7
    mov a,r7
    xrl a,#ROWS
    jnz fl_row
    ret
; fl_plane: PLANE cells, units digit from r4 in steps of 2, row r7.
fl_plane:
    mov r5,#0
    mov r3,#PLANE
fp_l:
    mov a,r4
    jnz fp_n1
    mov a,r5
    add a,#dectab&0FFh
    movp a,@a
    jmp fp_put
fp_n1:
    xrl a,#1
    jnz fp_n2
    mov a,r7
    jmp fp_put
fp_n2:
    mov a,r4
fp_put:
    rl a
    rl a
    call poke_b
    mov a,r4
    add a,#2
    mov r4,a
    add a,#256-10
    jnc fp_next
    mov r4,a
    inc r5
fp_next:
    djnz r3,fp_l
    ret
dectab:
    db 32,37,35,26,18,27,28,29  ; A B C D E F G H

    org 900h
    include "screen.inc"
    org 0A00h
    include "input.inc"
    org 0B00h
    include "mail.inc"

    PAGE_TAIL
