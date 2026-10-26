; equ.inc -- constants: the console, the cartridge, the screen.

; ---- P1 (all active low but COPY and LUM) ----
; Main code runs with external RAM and the cartridge on the bus; the interrupts
; switch to the VDC and put P1 back. COPY low always, or the cart's write
; strobe is gated off. The bank bits stay high: APPBANK pages are picked
; through the mailbox, not by P10/P11.
P1_MAIN equ 0AFh                ; XRAM + cart selected, VDC parked
P1_VDC  equ 0B7h                ; VDC selected
P1_JOY  equ 0BBh                ; keyboard scanner (joystick) selected

; ---- the mailbox (fuji_mailbox.h, protocol 2) ----
FN_W_REGSEL     equ 0E0h
FN_W_REGDATA    equ 0E1h
FN_W_DATA       equ 0E2h
FN_W_SEQ        equ 0E3h
FN_REG_DEVICE   equ 000h
FN_REG_CMD      equ 001h
FN_REG_NPARAM   equ 002h
FN_REG_DATA_RST equ 005h
FN_REG_CODEBANK equ 008h
FN_REG_POKE_LO  equ 00Ah
FN_REG_POKE_HI  equ 00Bh
FN_REG_POKE     equ 00Ch
FN_REG_RXWIN    equ 00Dh
FN_R_ACKSEQ     equ 0F20h
FN_R_ERR        equ 0F22h
FN_R_REPLY_CMD  equ 0F23h
FN_R_RXLEN_LO   equ 0F24h
FN_R_RXLEN_HI   equ 0F25h
FN_R_MAGIC0     equ 0F29h
FN_R_MAGIC1     equ 0F2Ah
FN_R_PROTO_VER  equ 0F2Bh
FN_R_DATA       equ 0F30h       ; the read window: 208 bytes from RXWIN*16
FN_PROTO_VER    equ 2
O2_APP_HDR      equ 0F30h
O2_APP_VERSION  equ 1

FC_ACK          equ 006h
NET_DEVICEID    equ 071h
NC_OPEN         equ 04Fh
NC_CLOSE        equ 043h
NC_READ         equ 052h
NC_STATUS       equ 053h
NC_WRITE        equ 057h
NM_RW           equ 00Ch        ; open mode: read/write
RD_MAX          equ 208         ; a READ fits the window: no RXWIN moves

; ---- the VDC's character generator (o2doc appendix C) ----
G_SPACE equ 12

; Character colours (control byte bits 1-3), as MAME's i8244 draws them
C_WHITE equ 7
TXT_COL equ C_WHITE

; The colour register ($A3): bits 5/4/3 are the background's R/G/B
BG_FOLLOW equ 008h              ; dark blue: the window follows the cursor
BG_FREE   equ 010h              ; dark green: the stick has moved it

; ---- the screen ----
; ROWS text lines of 16 characters, a window onto an 80-column terminal.
; A line at Y covers Y..Y+13; the band interrupt after it re-points the
; quads for the next line in the blanked 18 lines that follow. Y has to be a
; multiple of 4 (fixed.inc: the pointer arithmetic).
ROWS    equ 7
PITCH   equ 32
Y0      equ 16                  ; MAME hides characters above Y=14 (NTSC)
LEAD    equ 1                   ; lines a band starts before its line ends
X0      equ 16                  ; the window's left edge
COLS    equ 80                  ; the terminal
WCOLS   equ 16                  ; the window
PANMAX  equ COLS-WCOLS          ; the window's leftmost column, at most
PLANE   equ COLS/2              ; a row: even columns, then odd ones
CELL_SP equ 4*G_SPACE           ; a blank cell (cells hold 4 x glyph)
YEND    equ Y0+ROWS*PITCH       ; Y past the last line: the frame's bands are done

; ---- the stick (input.inc): JOY / JOYEV bits ----
J_UP    equ 01h
J_DOWN  equ 02h
J_LEFT  equ 04h
J_RIGHT equ 08h
J_FIRE  equ 10h

; ---- the network (net.inc): NSTATE; from NS_STAT on, a transaction is out ----
NS_IDLE  equ 0                  ; connected: a STATUS or a WRITE next
NS_DRAIN equ 1                  ; a READ's bytes going to the screen
NS_DEAD  equ 2                  ; not connected: fire dials
NS_STAT  equ 3                  ; a STATUS out
NS_READ  equ 4                  ; a READ out
NS_WRITE equ 5                  ; a WRITE out
NS_CLOSE equ 6                  ; the CLOSE before an OPEN out
NS_OPEN  equ 7                  ; an OPEN out
DRAIN_N  equ 24                 ; bytes to the screen a frame
NTMOUT   equ 250                ; frames a transaction may take (OPEN: x4)
KQ_MAX   equ 8                  ; keys waiting to be sent

; ---- page 1 (p1.inc): its farcall entries, and the strings by number ----
PG_ONE   equ 1
E_KEY    equ 0                  ; r5 = key code, r4 = its prefix -> r5 = its byte
E_STR    equ 1                  ; r5 = S_* -> STRB, NUL-terminated
E_SPEC   equ 2                  ; the spec into the TX stream, NUL and all
S_HELLO  equ 0
S_DIAL   equ 1
S_CONN   equ 2
S_FAIL   equ 3
S_NOANS  equ 4
S_LOST   equ 5
S_FIRE   equ 6
S_CRLF   equ 7
S_SPEC   equ 8                  ; the spec (t_spec stops at its query)
STRB_LEN equ 48
