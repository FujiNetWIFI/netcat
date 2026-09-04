# netcat for the Bally Astrocade

A standalone Z80 assembly terminal client, in the mold of the other Astrocade
FujiNet ports (`fujinet-config`, `fujinet-battleship`, `fujinet-texasHoldEm`,
`fujinet-5cardstud`, `fujinet-fujitzee`): the shared C core cannot fit this
machine, so the client is written to it. It talks to the FujiNet Astrocade
cartridge — the RP2040 mailbox cart from `fujinet-firmware/pico/astrocade` —
and is not part of the root mekkogx build, exactly as `netcat/intv/` is not.

Built and tested in MAME through a real fujinet-pc BoIP listener, against both
a live BBS and a local server.

Three things here are new to this family of ports:

* **It holds a connection open.** Every other Astrocade client is a one-shot
  HTTP GET, so this is the first to implement `N:` WRITE (`net.inc`), and the
  first whose CLOSE is not deferred to the start of the next request.
* **The pane scrolls.** The others redraw opaquely out of the reply window
  every poll, so nothing ever had to move.
* **The font has lowercase.** The family's 4x6 font is 64 glyphs of
  uppercase; a BBS is mixed case, so it is extended to 96 (`tools/mkfont.py`).

## Building and running

    ./build.sh                # build/nc.bin, exactly 8192 bytes
    ./run.sh                  # MAME with the fujinet cart device
    make smoke                # headless: dial the default and snapshot

Environment:

  * `ENDPOINT=` — the devicespec the dial screen starts with, default
    `N:TELNET://BBS.FOZZTEXX.COM/`. Regenerated into `build/endpoint.inc` on
    every build, so it can be changed without editing source.
  * `ZMAC=` — assembler override. Otherwise zmac is taken from `PATH`, then
    `~/Workspace/zmac-1.3/zmac`, then `$FUJI_PICO/tools/zmac/zmac`.
  * `FUJI_PICO=` — the cartridge bring-up tree, only consulted as the last
    place to look for zmac.

The port is self-contained the way the game ports are: `tools/checkrom.py` is
vendored here and `fujilib.inc` / `HVGLIB.H` / `state.inc` live in the port, so
a build needs no particular branch of the firmware tree checked out. Those are
copies of the bring-up's `testrom/` files — keep them in step.

`run.sh` expects the MAME tree with the fujinet cart device grafted in
(`pico/astrocade/emu/apply.sh`) at `MAME_DIR` (default `~/Workspace/mame`) and
a fujinet-pc BoIP listener at `FUJINET_TCP` (default 127.0.0.1:9995). At the
on-screen menu, keypad **1** starts netcat.

## The cartridge budget

The cart serves an 8K window; the mailbox owns 1B00H up, so code and data end
at 1AFFH — 6,912 bytes, enforced by `checkrom.py` and itemised by
`tools/checksize.py` on every build (the `MB_*` labels in `nc.asm` are its
module fences). It currently uses about 3.2K. `build.sh` stamps the `FUJI`
claim signature at 1CFCH, so when this image is booted over the network the
cart keeps the mailbox alive for it.

RAM is screen RAM, full stop. `LINES = 84` shows 14 rows of 4x6 text and
leaves 4D20H up — 736 bytes — to the program; the card games' `LINES = 90`
would have left 496, which the terminal's shadow does not fit in. Interrupts
stay off for the program's whole life (fujilib's contract: with I = 0, refresh
strays land in OS ROM and never hit the hotspots).

## The screen

40 columns by 14 rows, over the family's byte-aligned 4x6 renderer:

```
rows 0-12   the terminal pane, scrolling
row  13     the status line
rows 9-13   the grid keyboard, when it is open
```

**Scrolling** is an `LDIR` — there is no display-base or scroll register on
this hardware, and the BIOS `SCROLL` call is itself a software copy. Moving
the pane up one row is 2,880 bytes, about 34 ms at 1.789 MHz, and it happens
once per line feed at the bottom. The TV-typewriter fallback (re-home and
clear forward) turned out not to be needed.

**The shadow.** The grid keyboard opens over the bottom of the pane, so the
four terminal rows it covers are mirrored into a 160-byte character shadow
that `TSCROL` shifts in step with the screen. A shadow of the whole pane would
be 520 bytes and would not fit.

**The cursor** is the bottom scanline of its cell, written directly. It sits
where the next character will land, which in normal flow is blank.

**Escape sequences** are swallowed rather than printed: a CSI runs to its final
byte, `ESC ( B` and friends eat one more, and a runaway sequence is abandoned
after 32 bytes. CR, LF, BS and TAB are honoured; DEL and 8-bit CP437 art are
dropped rather than drawn as the wrong glyph.

## Telling the BBS how big we are

`NetworkProtocolTELNET::open()` reads `?term=`, `?cols=` and `?rows=` off the
devicespec query and offers TELNET NAWS only when a window size was given, and
its default terminal type is already `dumb`. So when the devicespec begins
`N:TELNET://` and carries no query of its own, `NOPEN` appends
`?cols=40&rows=13`. That one string is the difference between a BBS wrapping
to this screen and wrapping at 80 columns into ragged halves. A spec that
brought its own query is left alone, so `?term=ansi` stays available.

## Controls

There is no keyboard on this machine, so keys send their character the instant
they are pressed — a BBS menu is one keypress — and the trigger opens a grid
keyboard for anything else.

    0-9 . / - + x %        send that character (x sends *)
    =                      send CR LF
    CE                     send backspace
    MR / MS / CH           send ESC / Ctrl-C / space
    stick                  send the cursor keys (ESC [ A/B/C/D)
    trigger                open the composer
    C                      hang up, back to the dial screen

In the composer and on the dial screen, the stick and trigger pick characters
off the grid, the keypad types directly, `CE` deletes, `=` sends (or connects),
and `C` cancels — on the dial screen `C` restores the compiled-in default.
Only the stick auto-repeats.

## Testing

`make smoke` runs MAME headless against the compiled-in default and snapshots
early and late into `build/astrocde/`. `FUJINET_DEBUG=1` (the default here)
logs every mailbox transaction.

For the paths a remote host cannot be relied on to exercise on demand — the
scroll, the terminal's control handling, and NET_WRITE — there is a local
server:

    python3 emu/echosrv.py &
    ENDPOINT=N:TCP://127.0.0.1:4242/ ./build.sh
    make echotest

It sends 40 lines (several pane-fulls), then escape and control sequences that
must not reach the screen, then echoes what it is sent. `emu/compose.lua`
drives the grid keyboard to type `ABC` and send it; the server logs the line it
received and the screen should come back showing `you said [ABC]` with the
covered rows restored from the shadow.

`make resettest` soft-resets the console mid-session; the transaction log must
show the sequence numbers continuing across the reset, which is what proves the
client derives SEQ from the cart's persisted ACKSEQ rather than a local counter
(a console RESET restarts this program but not the cart).

One note if you write your own MAME harness: `manager.machine.time.seconds` is
an attotime's **integer** seconds field, so a fractional threshold compared
against it does not fire until the next whole second. That silently turns a
150 ms tap into a one-second hold, long enough to auto-repeat. The scripts here
schedule in frames.
