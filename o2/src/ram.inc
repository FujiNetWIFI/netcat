; ram.inc -- where everything lives.
;
; Internal RAM (64 bytes):
;   $00-$07  register bank 0: the main program
;   $08-$17  the stack, 8 levels: the interrupts take 1 (tools/checkstack.py)
;   $18-$1F  register bank 1: the interrupts' own. r3 = the next line's Y,
;            r4 = its control byte (colour), r5 = its pointer bias (-Y/4),
;            r6 = P1 saved, r7 = A saved; r0-r2 scratch
;   $20-$3C  below
;   $3D-$3F  the BIOS's

FRAMES  equ 020h                ; vblanks
QUIET   equ 021h                ; frames whose last line has been drawn
HEAD    equ 022h                ; the buffer row at the top of the screen
BROW    equ 023h                ; the interrupts': the next band's buffer row
PANM    equ 024h                ; the window's left column / 2 (main writes)
PANV    equ 025h                ; ... this frame's (vblank copies PANM)
SPRY    equ 026h                ; the cursor, sprite 0: Y, X, attribute
SPRX    equ 027h
SPRA    equ 028h
SCOL    equ 029h                ; the colour register
CURPG   equ 02Ah                ; the page mapped at $800

; External RAM (128 bytes, $00-$7F, MOVX with P1_MAIN):
; the terminal (term.inc)
CX      equ 000h                ; the cursor: column 0-80 (80: a wrap pending)
CY      equ 001h                ; screen row 0..ROWS-1
PAN     equ 002h                ; the window's left column (even, 0..PANMAX)
FOLLOW  equ 003h                ; 1: the window follows the cursor
ESC     equ 004h                ; the escape swallower's state (term.inc)
ESCN    equ 005h                ; bytes swallowed in this sequence
BLINK   equ 006h                ; the cursor's blink clock
; the keyboard and the stick (input.inc)
SHIFT   equ 009h                ; the prefix waiting: 1 x (shift), 2 divide (control)
KLAST   equ 00Ah                ; BIOS readkey's memory (its r7)
JOY     equ 00Bh                ; the stick now: J_* bits
JOYP    equ 00Ch                ; last frame's
JOYEV   equ 00Dh                ; pressed since last frame
REP     equ 00Eh                ; auto-repeat countdown
; the network (net.inc)
NSTATE  equ 010h                ; NS_*
NSEQ    equ 011h                ; the sequence number posted
NWAIT   equ 012h                ; frames left for the transaction
NWAITX  equ 013h                ; ... times this many more (OPEN)
RXLEN   equ 014h                ; the READ's bytes
RXPOS   equ 015h                ; ... how many are on the screen
NERR    equ 016h                ; why the connection ended
KQN     equ 017h                ; keys waiting
KQ      equ 018h                ; KQ_MAX: their bytes
KQS     equ KQ+KQ_MAX           ; how many the WRITE out is sending
DRN     equ KQS+1               ; bytes the drain may still put up this frame
SPTR    equ DRN+1               ; t_str's place in its string
STRB    equ 080h-STRB_LEN       ; a string from page 1 (p1.inc)
