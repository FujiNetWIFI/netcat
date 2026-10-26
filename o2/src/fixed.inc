; fixed.inc -- the fixed half, $400-$7FF: the display engine and the screen.
;
; The 8244 has 28 character objects; a screen of text is the four quads,
; interleaved into 16 columns, re-pointed for each of ROWS lines by a line
; counter interrupt in the blanked gap under the line before (object
; registers take writes only while the foreground is off). The 8048 holds A11
; at 0 for a whole interrupt routine, so all of it runs below $800, and it
; reads the screen with MOVP -- which reads the page the code is in.
;
; So there are no display tables: the terminal itself is here, ROWS rows of
; 80 columns in cartridge RAM (the main program writes them through the
; mailbox's POKE register), two rows a page beside a copy of the writer, and
; each band draws its line straight out of its row:
;   - a cell holds 4 x glyph. The VDC adds Y/2 to a character's pointer
;     while it draws, so the register wants glyph*8 - Y/2, nine bits; with
;     r5 = -Y/4, `add a,r5 / clr c / rlc a` is exactly that -- the low byte
;     in A, bit 8 in C -- and the control byte is colour<<1 + C.
;   - a row is its even columns, then its odd ones (PLANE bytes each). Quad
;     0 shows window columns 0,2,4,6 and quad 1 8-14, quads 2 and 3 the odd
;     ones between: the sixteen characters, in register order, are
;     E[p..p+7] then O[p..p+7]. The window's position p is the only thing a
;     pan changes.
;   - the rows are a ring: HEAD is the one at the top. A scroll moves HEAD
;     and blanks one row.
;
; Assembled into every page's build; build.sh takes it from page 0's and
; checks the others agree.

CTL_ON  equ vdc_ctrl_fore
CTL_OFF equ 0

; WRITER: draw the line of the row whose even plane starts at A, in this
; page, at Y r3 with bias r5 and control r4. Entered from a band (VDC
; selected, foreground off); leaves through band_out. Clobbers r0-r2, F0.
WRITER  macro wr,wl,wm,{GLOBALSYMBOLS}
wr:
    mov r0,#PANV
    add a,@r0
    mov r1,a                    ; E[p]
    mov a,r3                    ; Y, once a quad (its characters share it)
    mov r0,#vdc_quad0
    movx @r0,a
    mov r0,#vdc_quad1
    movx @r0,a
    mov r0,#vdc_quad2
    movx @r0,a
    mov r0,#vdc_quad3
    movx @r0,a
    mov r0,#vdc_quad0+2         ; the first pointer; each 4 on from the last
    clr f0
    mov r2,#8
wl:
    mov a,r1
    movp a,@a                   ; 4 x glyph
    inc r1
    add a,r5
    clr c
    rlc a                       ; glyph*8 - Y/2: low byte, bit 8 in C
    movx @r0,a
    inc r0
    clr a
    addc a,r4
    movx @r0,a
    inc r0
    inc r0
    inc r0
    djnz r2,wl
    cpl f0
    jf0 wm
    jmp band_out
wm:
    mov a,r1                    ; E[p+8] -> O[p]
    add a,#PLANE-8
    mov r1,a
    mov r2,#8
    jmp wl
    endm

; A blank row
BLANKROW macro
    db PLANE*2 dup (CELL_SP)
    endm

; ===========================================================================
;  page $4: vectors, boot, page switching, the band dispatcher, row 0
; ===========================================================================
    org 400h
    jmp start                   ; $400 reset
    jmp vbl_isr                 ; $402 external IRQ: the VDC's vblank
    jmp tim_isr                 ; $404 counter overflow: a line has ended
    jmp start                   ; $406 (the BIOS's own vblank chain: unused)
    jmp start                   ; $408 (after the BIOS's game select: unused)
    retr                        ; $40A
    nop

; start: a console RESET does not reset the cartridge, so the page mapped
; and the screen survive it; the boot puts back what it needs.
start:                          ; (a reset leaves interrupts off, the counter
    mov a,#P1_MAIN              ; stopped)
    outl p1,a
    clr a
    call sel_page               ; page 0
st_boot:
    jmp 800h                    ; page 0's entry 0 (A = 0): the boot

; sel_page: map page A at $800-$F1F. Main program, P1 = P1_MAIN.
; Clobbers A, r0, r1.
sel_page:
    mov r1,#CURPG
    mov @r1,a
    mov r0,#FN_W_REGSEL
    mov a,#FN_REG_CODEBANK
    movx @r0,a
    inc r0
    mov a,@r1
    movx @r0,a
    ret

; farcall: entry A of page r7, from page 0, which is mapped again after.
; One level: what it runs may not farcall. Results come back in r2-r5 or
; external RAM. Clobbers A, r0, r1, r6.
farcall:
    mov r6,a
    mov a,r7
    call sel_page
    mov a,r6
    call 800h                   ; the page's dispatcher (page.inc)
    sel mb0
    clr a
    jmp sel_page

; tim_isr: a line has ended. The counter is re-armed first, plus what it has
; counted since the overflow, so a band that starts late doesn't make the
; next one late; then the next line is drawn from its row.
tim_isr:
    sel rb1
    mov r7,a
    mov a,t
    add a,#256-PITCH
    mov t,a
    in a,p1
    mov r6,a
    mov a,#P1_VDC
    outl p1,a
    mov r0,#vdc_control
    mov a,#CTL_OFF
    movx @r0,a
band_go:                        ; vbl_isr joins here for line 0
    mov r0,#BROW
    mov a,@r0
    inc @r0
    add a,#rowjt&0FFh
    jmpp @a
rowjt:                          ; HEAD + line -> the row's stub (0..2*ROWS-2)
    db rs0&0FFh, rs1&0FFh, rs2&0FFh, rs3&0FFh, rs4&0FFh, rs5&0FFh, rs6&0FFh
    db rs0&0FFh, rs1&0FFh, rs2&0FFh, rs3&0FFh, rs4&0FFh, rs5&0FFh
rs0:
    mov a,#ROW0&0FFh
    jmp wr4
rs1:
    mov a,#ROW1&0FFh
    jmp wr5
rs2:
    mov a,#ROW2&0FFh
    jmp wr5
rs3:
    mov a,#ROW3&0FFh
    jmp wr6
rs4:
    mov a,#ROW4&0FFh
    jmp wr6
rs5:
    mov a,#ROW5&0FFh
    jmp wr7
rs6:
    mov a,#ROW6&0FFh
    jmp wr7

    WRITER wr4,wr4_l,wr4_m
ROW0:
    BLANKROW
    if $ > 500h
    error "page $4 has run out"
    endif

; ===========================================================================
;  page $5: rows 1 and 2; the vblank
; ===========================================================================
    org 500h
    WRITER wr5,wr5_l,wr5_m
ROW1:
    BLANKROW
ROW2:
    BLANKROW

; vbl_isr: once a frame, in the blank. Arms the first band -- exact anywhere
; in the blank, because the counter counts display lines only (T1 is
; vblank|hblank) -- puts the cursor sprite and the colour, takes this
; frame's top row and window position, and draws line 0.
vbl_isr:
    sel rb1
    mov r7,a
    in a,p1
    mov r6,a
    mov a,#P1_VDC
    outl p1,a
    mov r0,#vdc_status
    movx a,@r0                  ; reading the status drops the IRQ
    mov a,#256-(Y0+14-LEAD)
    mov t,a
    mov r0,#vdc_control
    mov a,#CTL_OFF
    movx @r0,a
    jmp vbl_2
    if $ > 600h
    error "page $5 has run out"
    endif

; ===========================================================================
;  page $6: rows 3 and 4; the band's way out
; ===========================================================================
    org 600h
    WRITER wr6,wr6_l,wr6_m
ROW3:
    BLANKROW
ROW4:
    BLANKROW

; band_out: foreground on, the next line's Y and bias; after the last line,
; no band until the next frame, and QUIET counts the frame done.
band_out:
    ifdef PADN                  ; (a timing test: build.sh PADN=n adds 2+2n cycles)
    if PADN > 0
    mov r2,#PADN
    djnz r2,$
    endif
    endif
    mov r0,#vdc_control
    mov a,#CTL_ON
    movx @r0,a
    mov a,r3
    add a,#PITCH
    mov r3,a
    mov a,r5
    add a,#256-PITCH/4
    mov r5,a
    mov a,r3
    xrl a,#YEND&0FFh
    jnz bo_out
    mov t,a                     ; (A = 0) 256 lines: the vblank re-arms first
    mov r0,#QUIET
    inc @r0
bo_out:
    mov a,r6
    outl p1,a
    mov a,r7
    retr
    if $ > 700h
    error "page $6 has run out"
    endif

; ===========================================================================
;  page $7: rows 5 and 6; the rest of the vblank
; ===========================================================================
    org 700h
    WRITER wr7,wr7_l,wr7_m
ROW5:
    BLANKROW
ROW6:
    BLANKROW

vbl_2:
    mov r0,#FRAMES
    inc @r0
    mov r1,#SPRY                ; the cursor: sprite 0's Y, X, attribute
    mov r0,#vdc_spr0_ctrl
    mov r2,#3
vb_spr:
    mov a,@r1
    movx @r0,a
    inc r0
    inc r1
    djnz r2,vb_spr
    mov a,@r1                   ; SCOL
    mov r0,#vdc_color
    movx @r0,a
    mov r0,#PANM
    mov a,@r0
    inc r0
    mov @r0,a                   ; PANV
    mov r0,#HEAD
    mov a,@r0
    mov r0,#BROW
    mov @r0,a
    mov r3,#Y0
    mov r5,#(256-Y0/4)&0FFh
    mov r4,#TXT_COL<<1
    jmp band_go
    if $ > 800h
    error "page $7 has run out"
    endif

; The rows, by number, for the main program's POKEs (offsets from $400)
RB_0    equ ROW0-400h
RB_1    equ ROW1-400h
RB_2    equ ROW2-400h
RB_3    equ ROW3-400h
RB_4    equ ROW4-400h
RB_5    equ ROW5-400h
RB_6    equ ROW6-400h
