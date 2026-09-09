;* ======================================================================== *;
;*  The routines and data in this file (scan_kbd.asm) are dedicated to the  *;
;*  public domain via the Creative Commons CC0 v1.0 license by its author,  *;
;*  Joseph Zbiciak.                                                         *;
;*                                                                          *;
;*          https://creativecommons.org/publicdomain/zero/1.0/              *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  ecskbd.asm -- ECS keyboard matrix scanner, called from IntyBASIC.       ;;
;;                                                                          ;;
;;  Vendored from jzIntv's SDK-1600 examples (examples/ecs_kbd/scan_kbd.asm ;;
;;  in the jzintv source tree), which is CC0 -- the header above is Joe      ;;
;;  Zbiciak's and stays verbatim.  Two changes from upstream, both forced    ;;
;;  by living inside an IntyBASIC program rather than an SDK-1600 one:       ;;
;;                                                                          ;;
;;    1. Renamed SCAN_KBD -> ECSKEY, because IntyBASIC uppercases the name   ;;
;;       given to USR and this is reached as "ecs_k = USR ECSKEY".  The      ;;
;;       register contract already matched exactly: argument-free, result    ;;
;;       in R0, returns via R5, clobbers R0-R4, leaves R6 alone.             ;;
;;                                                                          ;;
;;    2. Made it STATELESS.  Upstream keeps one byte, ECS_KEY_LAST, and      ;;
;;       reports a key only when it differs from the previous call, so a     ;;
;;       held key does not machine-gun.  That byte was allocated with        ;;
;;       cart.mac's BYTEVAR macro, which this project does not vendor, and   ;;
;;       guessing at a free cell inside the scratchpad pool IntyBASIC        ;;
;;       manages would be asking for a silent corruption.  So the "only      ;;
;;       report a change" rule moved up into ecskbd.bas, where it is one     ;;
;;       comparison against ecs_plast -- exactly what in_poll in kbd.bas     ;;
;;       already does with in_pkey for the keypad.  ECSKEY now answers       ;;
;;       "what is held down right now", or KEY.NONE.                         ;;
;;                                                                          ;;
;;  Everything else is upstream's, including the reason it is worth having:  ;;
;;  this does a TRANSPOSED scan compared to the ECS ROM's own scanner        ;;
;;  (drive $FF, read $FE), which is what lets it resolve SHIFT correctly,    ;;
;;  and it does one extra probe to pick out CTL.  It makes no attempt to     ;;
;;  handle two keys at once beyond that.                                     ;;
;;                                                                          ;;
;;  $00F8 is PSG register 8: bit 6 is the direction of port $00FE, bit 7     ;;
;;  the direction of port $00FF.  We flip bit 7 on entry and put both back   ;;
;;  to "input" before returning, so the low bits IntyBASIC's prologue wrote  ;;
;;  there ($038, the sound mixer) survive.  Nothing else in netcat touches   ;;
;;  the ECS PSG, and this runs inside the frame ISR, so no other code can    ;;
;;  observe the port mid-scan.                                               ;;
;; ======================================================================== ;;

KEY.LEFT    EQU     $1C     ; \   Can't be generated otherwise, so perfect
KEY.RIGHT   EQU     $1D     ;  |_ candidates.  Could alternately send 8 for
KEY.UP      EQU     $1E     ;  |  left... not sure...
KEY.DOWN    EQU     $1F     ; /
KEY.ENTER   EQU     $A      ; Newline
KEY.ESC     EQU     27
KEY.NONE    EQU     $FF

KBD_DECODE  PROC
@@no_mods   DECLE   KEY.NONE, "ljgda"                       ; col 7
            DECLE   KEY.ENTER, "oute", KEY.NONE             ; col 6
            DECLE   "08642", KEY.RIGHT                      ; col 5
            DECLE   KEY.ESC, "97531"                        ; col 4
            DECLE   "piyrwq"                                ; col 3
            DECLE   ";khfs", KEY.UP                         ; col 2
            DECLE   ".mbcz", KEY.DOWN                       ; col 1
            DECLE   KEY.LEFT, ",nvx "                       ; col 0

@@shifted   DECLE   KEY.NONE, "LJGDA"                       ; col 7
            DECLE   KEY.ENTER, "OUTE", KEY.NONE             ; col 6
            DECLE   ")*-$\"/"                               ; col 5
            DECLE   KEY.ESC, "(/+#="                        ; col 4
            DECLE   "PIYRWQ"                                ; col 3
            DECLE   ":KHFS^"                                ; col 2
            DECLE   ">MBCZ?"                                ; col 1
            DECLE   "%<NVX "                                ; col 0

@@control   DECLE   KEY.NONE, $C, $A, $7, $4, $1            ; col 7
            DECLE   KEY.ENTER, $F, $15, $14, $5, KEY.NONE   ; col 6
            DECLE   "}~_!'", KEY.RIGHT                      ; col 5
            DECLE   KEY.ESC, "{&@`~"                        ; col 4
            DECLE   $10, $9, $19, $12, $17, $11             ; col 3
            DECLE   "|", $B, $8, $6, $13, KEY.UP            ; col 2
            DECLE   "]", $D, $2, $3, $1A, KEY.DOWN          ; col 1
            DECLE   KEY.LEFT, "[", $0E, $16, $18, $20       ; col 0
            ENDP

ECSKEY      PROC

            ;; ------------------------------------------------------------ ;;
            ;;  Try to find CTRL and SHIFT first.                           ;;
            ;;  Shift takes priority over control.                          ;;
            ;; ------------------------------------------------------------ ;;
            MVII    #KBD_DECODE.no_mods, R3 ; neither shift nor ctrl

            MVI     $F8,        R0
            ANDI    #$3F,       R0
            XORI    #$80,       R0          ; transpose scan mode
            MVO     R0,         $F8

            MVII    #$7F,       R1          ; \_ drive column 7 to 0
            MVO     R1,         $FF         ; /
            MVI     $FE,        R2          ; \
            ANDI    #$40,       R2          ;  > look for a 0 in row 6
            BEQ     @@have_shift            ; /

            MVII    #$BF,       R1          ; \_ drive column 6 to 0
            MVO     R1,         $FF         ; /
            MVI     $FE,        R2          ; \
            ANDI    #$20,       R2          ;  > look for a 0 in row 5
            BNEQ    @@done_shift_ctrl       ; /

            MVII    #KBD_DECODE.control, R3
            B       @@done_shift_ctrl

@@have_shift:
            MVII    #KBD_DECODE.shifted, R3

@@done_shift_ctrl:

            ;; ------------------------------------------------------------ ;;
            ;;  Start at col 7 and work our way to col 0.                   ;;
            ;; ------------------------------------------------------------ ;;
            CLRR    R2              ; col pointer
            MVII    #$FF7F, R1

@@col:      MVO     R1,     $FF
            MVI     $FE,    R0
            XORI    #$FF,   R0
            BNEQ    @@maybe_key

@@cont_col: ADDI    #6,     R2
            SLR     R1
            CMPI    #$FF,   R1
            BNEQ    @@col

            MVII    #KEY.NONE,  R0
            B       @@done

            ;; ------------------------------------------------------------ ;;
            ;;  Looks like a key is pressed.  Let's decode it.              ;;
            ;; ------------------------------------------------------------ ;;
@@maybe_key:
            MOVR    R2,     R4
            SARC    R0,     2
            BC      @@got_key       ; row 0
            BOV     @@got_key1      ; row 1
            ADDI    #2,     R4
            SARC    R0,     2
            BC      @@got_key       ; row 2
            BOV     @@got_key1      ; row 3
            ADDI    #2,     R4
            SARC    R0,     2
            BC      @@got_key       ; row 4
            BNOV    @@cont_col      ; row 5
@@got_key1: INCR    R4
@@got_key:

            ADDR    R3,     R4      ; add modifier offset
            MVI@    R4,     R0

            CMPI    #KEY.NONE, R0   ; if invalid, keep scanning
            BEQ     @@cont_col

            ;; ------------------------------------------------------------ ;;
            ;;  Put both I/O ports back to "input" and hand R0 to the       ;;
            ;;  caller.  Upstream compared against ECS_KEY_LAST here; see   ;;
            ;;  the header for why that moved to ecskbd.bas.                ;;
            ;; ------------------------------------------------------------ ;;
@@done:     MVI     $F8,        R1  ; \
            ANDI    #$3F,       R1  ;  > set both I/O ports to "input"
            MVO     R1,         $F8 ; /
            JR      R5
            ENDP
