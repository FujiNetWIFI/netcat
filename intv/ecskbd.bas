' ecskbd.bas -- ECS keyboard support: a per-frame matrix scan feeding a small
' ring buffer that the rest of the program drains at its own pace.
'
' The ECS (Entertainment Computer System) is the Intellivision's keyboard
' add-on. It is optional here and detected at boot: with one attached you type
' on real keys, without one everything falls back to the hand controller and
' the on-screen grid in kbd.bas, from the same ROM. Nothing in this file knows
' about the network -- it hands out ASCII, and netcat.bas decides what that
' means on the wire.
'
' WHY THE FRAME INTERRUPT.  term_loop samples input exactly once per pass, and
' every pass does a *blocking* mailbox round trip (net_status, plus net_read
' when bytes are waiting); fn_transact will sit on WAIT for up to 900 frames.
' So the loop's own sampling rate is nowhere near 60 Hz, and a key pressed and
' released inside one transaction would simply never be seen. Scanning from
' scanning from the frame interrupt instead means the matrix is read every
' video frame no matter what the main loop is blocked on, and keys queue up
' until it comes back. IntyBASIC allows only ONE "ON FRAME GOSUB" per program,
' so this file does not declare it: the host program must call ecs_tick once
' per frame from its own hook. netcat.bas does that in frame_tick.
'
' RING BUFFER SAFETY.  ecs_tick runs in the interrupt, everything else runs in
' the main program, so this is a single-producer / single-consumer queue: the
' producer only ever writes ecs_qt, the consumer only ever writes ecs_qh, and
' an 8-bit variable is written with one MVO, which cannot be interrupted
' half-done. That is the whole reason no interrupt masking appears here. For
' the same reason ecs_tick works in ecs_raw and ecs_getkey works in ecs_k --
' one shared scratch variable would be clobbered mid-read by the interrupt.
'
' The scanner itself is ecskbd.asm (Joe Zbiciak's, CC0); see its header.

    ' The scanner's return values. Everything else it returns is either a
    ' printable ASCII character or a control code from CTL+key.
    CONST ECS_NONE  = 255
    CONST ECS_LEFT  = $1C
    CONST ECS_RIGHT = $1D
    CONST ECS_UP    = $1E
    CONST ECS_DOWN  = $1F
    CONST ECS_ENTER = $0A       ' RTN (and CTL+J, which is the same thing)
    CONST ECS_ESC   = 27

    ' 16 entries is far more than a human can outrun a 60 Hz scan with, and a
    ' power of two so the wrap is an AND rather than a compare.
    CONST ECS_QLEN  = 16
    ' 64 entries, not 16. A mailbox transaction can WAIT up to 900 frames, and
    ' the scan keeps running in the frame interrupt throughout -- so the ring
    ' has to hold everything typed across a stall, not just a couple of keys.
    ' Sixteen silently dropped the rest.
    CONST ECS_QMASK = 63
    CONST SC_ECSQ   = $9400     ' $9400-$943F; the row map follows at $9440

    DIM ecs_present             ' set once at boot; 0 disables everything here
    DIM ecs_raw, ecs_plast      ' interrupt side only
    DIM ecs_qt, ecs_qh, ecs_n   ' qt written by the interrupt, qh by the main
    DIM ecs_k                   ' main side only: the key ecs_getkey popped

' ---------------------------------------------------------------------------
' ecs_init: call once, early. ECS.AVAILABLE is IntyBASIC's own boot-time probe
' (it writes $55/$AA to ECS RAM at $4040/$4041 and reads them back), so it
' costs nothing here. Note that merely *reading* ECS.AVAILABLE does not make
' the compiler think we use the ECS -- CONT3/CONT4/SOUND 5-9 would, and that
' would mark the ROM as REQUIRING an ECS, which is exactly what we don't want.
' ---------------------------------------------------------------------------
ecs_init: PROCEDURE
    ecs_present = ECS.AVAILABLE
    ecs_qh = 0
    ecs_qt = 0
    ecs_plast = ECS_NONE
END

' ---------------------------------------------------------------------------
' ecs_tick: the per-frame scan. Runs in the video interrupt (see frame_tick in
' netcat.bas), so it stays short
' -- overrunning a frame here accumulates interrupts and overflows the stack.
'
' The frame hook can fire before ecs_init has run; every variable is zero at boot, so
' ecs_present = 0 and we return before touching the PSG (which the IntyBASIC
' prologue has not configured yet at that point either).
'
' The "same key as last frame" test is the debounce: a held key is reported
' once, on the frame it goes down, and not again until it changes. That is the
' rule the upstream scanner enforced with its own state byte; it lives here
' instead. A full queue drops the key rather than overwriting an unread one.
' ---------------------------------------------------------------------------
ecs_tick: PROCEDURE
    IF ecs_present = 0 THEN RETURN
    ecs_raw = USR ECSKEY
    IF ecs_raw = ecs_plast THEN RETURN
    ecs_plast = ecs_raw
    IF ecs_raw = ECS_NONE THEN RETURN
    ecs_n = (ecs_qt + 1) AND ECS_QMASK
    IF ecs_n = ecs_qh THEN RETURN
    POKE (SC_ECSQ + ecs_qt), ecs_raw
    ecs_qt = ecs_n
END

' ---------------------------------------------------------------------------
' ecs_getkey: pop one key into ecs_k, or ECS_NONE when the queue is empty.
' ---------------------------------------------------------------------------
ecs_getkey: PROCEDURE
    ecs_k = ECS_NONE
    IF ecs_qh = ecs_qt THEN RETURN
    ecs_k = PEEK(SC_ECSQ + ecs_qh) AND 255
    ecs_qh = (ecs_qh + 1) AND ECS_QMASK
END

' ---------------------------------------------------------------------------
' ecs_flush: throw away anything queued. Called when changing screens, so keys
' typed at a screen that wasn't listening don't spray into the next one.
' ---------------------------------------------------------------------------
ecs_flush: PROCEDURE
    ecs_qh = ecs_qt
END

    ' Mark the ROM as ECS-ENHANCED, not ECS-REQUIRED: jzIntv (and flash carts)
    ' will bring the ECS up automatically when this ROM is loaded, but the ROM
    ' still runs, controller-only, when there is no ECS and no ecs.bin.
    ASM CFGVAR "ecs_compat" = 2

    ASM INCLUDE "ecskbd.asm"
