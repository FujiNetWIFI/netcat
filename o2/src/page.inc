; page.inc -- the two ends every page carries.
;
; PAGE_HEAD at $800: the page's dispatcher. A = an entry number; the table
; that follows holds the low bytes of its entry stubs, all within $800-$8FF
; because JMPP stays in its page. Page 0's entry 0 is the boot.
;
; PAGE_TAIL: mb_get at $F00, the read stub for the mailbox page -- MOVP reads
; the page the PC is in, and $F00-$F1F is each page's own -- and on page 0 the
; FUJI claim and the APPBANK header (fuji_mailbox.h), both under the mailbox
; at run time.

; FCALL: a call into the fixed half or the BIOS. AS puts SEL MB0 in front of
; it and nothing behind; RET does not restore MB, so this does
; (tools/checkmb.py).
FCALL   macro target
    call target
    sel mb1
    endm

PAGE_HEAD macro {GLOBALSYMBOLS}
    org 800h
pg_disp:
    add a,#pg_tab&0FFh
    jmpp @a
pg_tab:
    endm

PAGE_TAIL macro {GLOBALSYMBOLS}
    org 0F00h
mb_get:                         ; A = offset in page $F00 -> the byte there
    movp a,@a
    ret
    if PAGE=0
    org 0F2Ch
    db "FUJI"
    org O2_APP_HDR
    db "APPB",O2_APP_VERSION,NPAGES
    endif
    endm
