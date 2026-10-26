; term.inc -- the terminal: a dumb teletype, 80 columns by ROWS, in the
; fixed half's rows (fixed.inc). Main program, P1 = P1_MAIN; everything
; here clobbers A and r0-r7 unless it says otherwise.
;
; CR, LF, BS, TAB and FF move the cursor; a character past column 79 waits
; there (CX = 80) and wraps when the next one comes. Escape sequences are
; swallowed whole: ESC [ to its final byte, ESC ] to BEL or ESC \, ESC and
; an intermediate plus one byte, ESC and anything else. Other control
; characters, DEL and bytes over $7F are dropped.

ES_NONE equ 0
ES_ESC  equ 1                   ; ESC seen
ES_CSI  equ 2                   ; in ESC [ ..., to a byte $40-$7E
ES_ONE  equ 3                   ; one more byte (ESC ( B and the like)
ES_OSC  equ 4                   ; in ESC ] ..., to BEL or ESC
ES_MAX  equ 40                  ; a sequence this long was never one

; ---------------------------------------------------------------------------
    org 0A00h

; tputc: byte A to the terminal.
tputc:
    mov r7,a
    mov r0,#ESC
    movx a,@r0
    jnz tp_esc
    mov a,r7
    jb7 tp_drop                 ; $80-$FF
    add a,#256-20h
    jnc tp_ctl
    mov a,r7
    xrl a,#7Fh
    jz tp_drop                  ; DEL
    mov a,r7
    add a,#(charmap-20h)&0FFh
    movp a,@a
    jmp t_put
tp_drop:
    ret
tp_ctl:
    mov a,r7
    xrl a,#0Dh
    jz tp_cr
    xrl a,#0Dh!0Ah
    jz tp_lf
    xrl a,#0Ah!08h
    jz tp_bs
    xrl a,#08h!09h
    jz tp_tab
    xrl a,#09h!1Bh
    jz tp_escape
    xrl a,#1Bh!0Ch
    jz tp_ff
    ret
tp_cr:
    jmp t_cr
tp_lf:
    jmp t_lf
tp_bs:
    jmp t_bs
tp_tab:
    jmp t_tab
tp_ff:
    jmp t_clear
tp_escape:
    mov a,#ES_ESC
    jmp tp_state

; In a sequence: r7 the byte, A the state.
tp_esc:
    mov r6,a
    mov r0,#ESCN                ; a runaway sequence ends anyway
    movx a,@r0
    inc a
    movx @r0,a
    add a,#256-ES_MAX
    jc tp_end
    mov a,r6
    xrl a,#ES_ESC
    jz tp_e1
    xrl a,#ES_ESC!ES_CSI
    jz tp_csi
    xrl a,#ES_CSI!ES_ONE
    jz tp_end
    ; ES_OSC: to BEL, or to ESC (the ESC \ that ends it goes as ES_ESC + one)
    mov a,r7
    xrl a,#07h
    jz tp_end
    xrl a,#07h!1Bh
    jnz tp_keep
    jmp tp_escape
tp_e1:                          ; the byte after ESC
    mov a,r7
    xrl a,#'['
    jz tp_tocsi
    xrl a,#'['!']'
    jz tp_toosc
    mov a,r7                    ; $20-$2F: an intermediate, one byte to come
    add a,#256-20h
    jnc tp_end
    add a,#256-10h
    jc tp_end
    mov a,#ES_ONE
    jmp tp_state
tp_tocsi:
    mov a,#ES_CSI
    jmp tp_state
tp_toosc:
    mov a,#ES_OSC
    jmp tp_state
tp_csi:                         ; parameters until a final byte $40-$7E
    mov a,r7
    add a,#256-40h
    jnc tp_keep
tp_end:
    clr a
tp_state:
    mov r0,#ESC
    movx @r0,a
    mov r0,#ESCN
    clr a
    movx @r0,a
tp_keep:
    ret

    include "charmap.inc"
    if $ > 0B00h
    error "page $A has run out"
    endif

; ---------------------------------------------------------------------------
    org 0B00h

; t_put: cell A (4 x glyph) at the cursor, and the cursor on.
t_put:
    mov r5,a
    mov r0,#CX
    movx a,@r0
    xrl a,#COLS
    jnz tpu_at
    call t_cr                   ; the wrap that was waiting
    call t_lf
tpu_at:
    call cur_poke
    mov a,r5
    call poke_b
    mov r0,#CX
    movx a,@r0
    inc a
    movx @r0,a
    jmp t_follow

; cur_poke: aim POKE at the cursor's cell. Clobbers A, r0-r3.
cur_poke:
    mov r0,#CX
    movx a,@r0
    clr c
    rrc a                       ; column / 2, odd columns in C
    jnc cp_even
    add a,#PLANE
cp_even:
    mov r3,a
    call cur_row
    jmp cell_at

; cur_row: A = the buffer row under the cursor. Clobbers r0, r1.
cur_row:
    mov r0,#CY
    movx a,@r0
; buf_row: A = the buffer row on screen row A. Clobbers r0, r1.
buf_row:
    mov r0,#HEAD
    add a,@r0
    mov r1,a
    add a,#256-ROWS
    jc br_wrap
    mov a,r1
br_wrap:
    ret

; t_cr: column 0.
t_cr:
    clr a
    mov r0,#CX
    movx @r0,a
    jmp t_follow

; t_lf: down a row; at the bottom, the screen scrolls.
t_lf:
    mov r0,#CY
    movx a,@r0
    inc a
    mov r1,a
    xrl a,#ROWS
    jz tl_scroll
    mov a,r1
    movx @r0,a
    jmp t_follow
tl_scroll:
    mov r0,#HEAD                ; the top row comes round as the bottom one
    mov a,@r0
    mov r7,a
    inc a
    mov r1,a
    xrl a,#ROWS
    jz tl_head
    mov a,r1
tl_head:
    mov @r0,a
    mov a,r7
    call clear_row
    jmp t_follow

; t_bs: back a column (from a waiting wrap, to 79).
t_bs:
    mov r0,#CX
    movx a,@r0
    jz tb_done
    dec a
    movx @r0,a
tb_done:
    jmp t_follow

; t_tab: on to the next multiple of 8, 79 at most.
t_tab:
    mov r0,#CX
    movx a,@r0
    add a,#8
    anl a,#0F8h
    mov r1,a
    add a,#256-COLS
    jnc tt_set
    mov r1,#COLS-1
tt_set:
    mov a,r1
    movx @r0,a
    jmp t_follow

; t_clear: every row blank, the cursor home.
t_clear:
    mov r7,#ROWS-1
tcl_l:
    mov a,r7
    call clear_row
    mov a,r7
    dec r7
    jnz tcl_l
    clr a
    mov r0,#CX
    movx @r0,a
    inc r0
    movx @r0,a                  ; CY
    jmp t_follow

; clear_row: buffer row A blank. Clobbers A, r0-r3.
clear_row:
    call row_at
    mov r0,#FN_W_REGDATA        ; poke_b, COLS times
    mov r3,#COLS
    mov a,#CELL_SP
clr_l:
    movx @r0,a
    djnz r3,clr_l
    ret

; t_follow: with FOLLOW on, the window comes to the cursor -- back to it,
; or on to have it 8 columns in.
t_follow:
    mov r0,#FOLLOW
    movx a,@r0
    jz tf_done
    mov r0,#CX
    movx a,@r0
    mov r1,a
    xrl a,#COLS
    jnz tf_c
    dec r1                      ; a waiting wrap: column 79
tf_c:
    mov r0,#PAN
    movx a,@r0
    cpl a
    inc a
    add a,r1                    ; column - PAN, signed (both are under 128)
    jb7 tf_move                 ; left of the window
    add a,#256-WCOLS
    jnc tf_done                 ; in it
tf_move:
    mov a,r1
    add a,#256-8
    jc tf_pos
    clr a
tf_pos:
    anl a,#0FEh
    mov r1,a
    add a,#256-PANMAX-1
    jnc tf_set
    mov r1,#PANMAX
tf_set:
    mov a,r1
    jmp pan_set
tf_done:
    ret

; pan_set: the window at column A (even, 0..PANMAX). Clobbers A, r0.
pan_set:
    mov r0,#PAN
    movx @r0,a
    clr c
    rrc a
    mov r0,#PANM
    mov @r0,a
    ret

    if $ > 0C00h
    error "page $B has run out"
    endif
