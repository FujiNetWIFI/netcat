;; ======================================================================== ;;
;;  vtasm.asm -- the inner loops of the 80x25 terminal.                     ;;
;;                                                                          ;;
;;  IntyBASIC is fast enough for the terminal's logic and nowhere near fast  ;;
;;  enough for its pixels. The BASIC repaint this replaces cost ~257 cycles  ;;
;;  per cell, so a 20x12 viewport would have taken 3.7 NTSC frames. A frame  ;;
;;  is 14934 cycles and the STIC steals ~1530 of them for its own BACKTAB    ;;
;;  fetches, leaving about 13400 to spend. VPROW brings the same work to 37  ;;
;;  cycles per cell -- a full viewport repaint in ~9300 cycles, two thirds   ;;
;;  of one frame, once per received chunk rather than once per character.    ;;
;;                                                                          ;;
;;  Calling convention is IntyBASIC's USR: arguments in R0-R3, result in R0, ;;
;;  return through R5, R6 untouched -- the same contract ecskbd.asm is       ;;
;;  vendored to. R4-R6 are the CP-1610's auto-incrementing registers and     ;;
;;  R1-R3 are not, so a routine that walks two pointers at once has to push  ;;
;;  R5 to free it as the second one, and return by popping straight into R7. ;;
;;                                                                          ;;
;;  TBUF holds 25 rows of 80 cells, each cell two consecutive 8-bit          ;;
;;  locations: the low then the high byte of a finished Foreground/          ;;
;;  Background BACKTAB word. Interleaving the halves rather than keeping two ;;
;;  separate planes is what lets one pointer read both of them.              ;;
;; ======================================================================== ;;

;; ------------------------------------------------------------------------ ;;
;;  VPROW -- paint one 20-card screen row from one buffer row.              ;;
;;                                                                          ;;
;;      R0  source: rowaddr(slot) + vx*2                                    ;;
;;      R1  destination: $0200 + screenrow*20                               ;;
;;                                                                          ;;
;;  Fully unrolled. At 20 cells a counted loop would spend a fifth of its    ;;
;;  time on the counter.                                                     ;;
;; ------------------------------------------------------------------------ ;;
VPROW       PROC
            PSHR    R5              ; return address out of the way; R5 is
            MOVR    R0,     R4      ; needed as the second auto-inc pointer
            MOVR    R1,     R5
            REPEAT  20
            MVI@    R4,     R0      ; 8   low byte of the word
            MVI@    R4,     R3      ; 8   high byte
            SWAP    R3              ; 6   into bits 8-15
            ADDR    R3,     R0      ; 6
            MVO@    R0,     R5      ; 9   one BACKTAB cell, R5 advances
            ENDR
            PULR    R7              ; return
            ENDP

;; ------------------------------------------------------------------------ ;;
;;  TFILL2 -- fill a run of cells with one two-byte value.                  ;;
;;                                                                          ;;
;;      R0  destination address    R2  low byte                             ;;
;;      R1  cell count             R3  high byte                            ;;
;;                                                                          ;;
;;  Every erase in the terminal goes through here: a cleared row after a     ;;
;;  scroll, ED, EL, ECH, and the whole 2000-cell buffer at boot -- which     ;;
;;  matters, because jzIntv starts RAM full of random bytes.                 ;;
;; ------------------------------------------------------------------------ ;;
TFILL2      PROC
            TSTR    R1
            BEQ     @@out
            MOVR    R0,     R4
@@fill:     MVO@    R2,     R4      ; 9
            MVO@    R3,     R4      ; 9
            DECR    R1              ; 6
            BNEQ    @@fill          ; 9
@@out:      JR      R5
            ENDP

;; ------------------------------------------------------------------------ ;;
;;  ROTUP -- scroll a region up by one row.                                 ;;
;;                                                                          ;;
;;      R0  address of rowmap[top]     R1  row count (bot - top + 1)        ;;
;;      returns R0 = the slot that left the top                             ;;
;;                                                                          ;;
;;  The buffer never moves. rowmap turns a logical row into the slot that    ;;
;;  holds it, so scrolling is a rotate of at most 25 bytes plus one cleared  ;;
;;  row, instead of a 4000-byte memmove -- and the same routine serves the   ;;
;;  full screen, a DECSTBM region, IL and DL. The slot rotated off the top   ;;
;;  comes back as the caller's scratch: it is the row to blank.              ;;
;; ------------------------------------------------------------------------ ;;
ROTUP       PROC
            PSHR    R5
            MOVR    R0,     R4
            MVI@    R4,     R2      ; slot leaving the top
            DECR    R1
            BEQ     @@done          ; a one-row region rotates to itself
            MOVR    R0,     R5      ; write pointer trails the read by one
@@shift:    MVI@    R4,     R3
            MVO@    R3,     R5
            DECR    R1
            BNEQ    @@shift
            MVO@    R2,     R5      ; recycled slot becomes the new bottom
@@done:     MOVR    R2,     R0
            PULR    R7
            ENDP

;; ------------------------------------------------------------------------ ;;
;;  ROTDN -- scroll a region down by one row (reverse index, SD, IL).       ;;
;;                                                                          ;;
;;      R0  address of rowmap[top]     R1  row count                        ;;
;;      returns R0 = the slot that left the bottom, now at the top          ;;
;;                                                                          ;;
;;  The CP-1610 auto-increments but never auto-decrements through R4/R5, so  ;;
;;  this walks forward carrying the displaced slot rather than copying       ;;
;;  backwards: read a cell, write the carry into it, keep what was read.     ;;
;; ------------------------------------------------------------------------ ;;
ROTDN       PROC
            PSHR    R5
            MOVR    R0,     R4
            ADDR    R1,     R4
            DECR    R4
            MVI@    R4,     R2      ; carry = slot at the bottom
            MOVR    R0,     R4      ; read pointer
            MOVR    R0,     R5      ; write pointer
@@shift:    MVI@    R4,     R3
            MVO@    R2,     R5
            MOVR    R3,     R2
            DECR    R1
            BNEQ    @@shift
            MOVR    R2,     R0
            PULR    R7
            ENDP
