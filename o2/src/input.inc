; input.inc -- the stick, the keyboard, the frame clock. Main program,
; P1 = P1_MAIN.

; joy_poll: the left stick into JOY, what was pressed since last time into
; JOYEV. The keyboard scanner shares P2 with the program address, so only the
; BIOS's own code can read it ($38F getjoystick: R1 = stick; R3 up/down,
; R2 left/right as $FF/$01, F0 the button). The interrupts save and restore
; P1, so the stick's P1 survives them. Clobbers A, r0-r4, F0.
joy_poll:
    mov a,#P1_JOY
    outl p1,a
    mov r1,#0
    FCALL getjoystick
    mov a,#P1_MAIN
    outl p1,a
    clr a
    mov r4,a
    jf0 jp_fire
    jmp jp_v
jp_fire:
    mov r4,#J_FIRE
jp_v:
    mov a,r3
    jz jp_h
    jb7 jp_up
    mov a,r4
    orl a,#J_DOWN
    mov r4,a
    jmp jp_h
jp_up:
    mov a,r4
    orl a,#J_UP
    mov r4,a
jp_h:
    mov a,r2
    jz jp_done
    jb7 jp_left
    mov a,r4
    orl a,#J_RIGHT
    mov r4,a
    jmp jp_done
jp_left:
    mov a,r4
    orl a,#J_LEFT
    mov r4,a
jp_done:
    mov r0,#JOYP                ; JOYEV = JOY & ~JOYP; JOYP = JOY
    movx a,@r0
    cpl a
    anl a,r4
    mov r0,#JOYEV
    movx @r0,a
    mov a,r4
    mov r0,#JOYP
    movx @r0,a
    mov r0,#JOY
    movx @r0,a
    ret

; frame_sync: until the frame's last line is drawn -- the stretch with no
; band due before the next frame's, where the BIOS keyboard scan (which
; holds the vblank off) belongs. Clobbers A, r1, r2.
frame_sync:
    mov r1,#QUIET
    mov a,@r1
    mov r2,a
fs_l:
    mov a,@r1
    xrl a,r2
    jz fs_l
    ret
