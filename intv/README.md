# netcat for Intellivision (IntyBASIC)

An ANSI colour terminal for the Mattel Intellivision with a FujiNet
cartridge. Type any `N:` devicespec on the on-screen keyboard, connect, and
you get a real terminal: an **80×25 screen** kept in cartridge RAM, with
per-cell colour, scrolling regions, line drawing and cursor addressing —
shown through the console's 20×12 card window as a viewport that follows the
cursor.

The prefilled default is tcpbin.com's echo service (port 4242), so pressing
`OK` untouched gives a self-test needing no server of your own.

With an **ECS keyboard** attached you type on real keys and each keystroke
goes straight out the wire. The ECS is detected at boot and is entirely
optional — the same ROM falls back to the hand controller and an on-screen
character grid when there isn't one, so there is only one binary to build.

## The 80-column problem

The Intellivision shows 20×12 cards. A terminal that tells the far end it is
20 columns wide is technically honest and practically useless: `ssh`, `vi` and
everything curses-shaped assume 80. So the screen this program *keeps* is
80×25, in the 4000 bytes at `$8000` that the FujiNet cartridge maps as RAM,
and the console shows a movable window onto it.

By default the window **follows the cursor**, so output appears where you are
looking and you never think about it. The **top action button** turns that off:
the disc then pans freely while data keeps landing in the buffer behind you —
for reading back a wide line, or watching one column of a table scroll. The
border colour says which mode is on, blue for following and black for free,
and the position appears on the bottom row for a second and a half whenever
the window moves.

## Colour

Per-cell background needs the STIC's Foreground/Background mode, which the
whole program runs in. That mode gives every cell its own foreground and
background but cuts the card number to six bits, so only GROM cards 0–63 —
symbols, digits and UPPERCASE — plus 64 GRAM cards are reachable. Lowercase
therefore lives in GRAM, and the glyphs are GROM cards 64–94 copied out of the
console's own ROM, so a lowercase letter is pixel-identical to the one the
Intellivision would have drawn itself.

Foreground has eight colours and the STIC primaries contain no magenta, no
cyan and no grey, so sixteen ANSI colours fold into eight. The table keeps the
hue families apart rather than taking the nearest RGB match (which would put
red, yellow and magenta all on Red); the two collisions are cyan, which goes
to Green, and magenta, which goes to Red. Green and yellow keep real
dark/bright pairs, so bold does something visible. Background has all sixteen
and is close to faithful — the STIC's "Purple" really is a magenta and its
"Cyan" really is a cyan. Both maps are `DATA` tables at the top of
`vtansi.bas`; retuning them is a one-line edit.

## What it understands

Cursor motion and absolute addressing (`CUU CUD CUF CUB CNL CPL CHA CUP VPA`),
erase (`ED EL ECH`), insert and delete (`IL DL ICH DCH`), scrolling (`SU SD`)
and scrolling regions (`DECSTBM`), save/restore (`DECSC DECRC`), autowrap
(`DECAWM`, with correct deferred wrap at column 80), cursor visibility
(`DECTCEM`), application cursor keys (`DECCKM`), DEC special graphics
(`ESC ( 0`, `SO`/`SI`), string sequences (`OSC` `DCS` `SOS` `PM` `APC`,
swallowed to their terminator however long they run), and `SGR` including
`38;5;n`/`48;5;n` folded down to the sixteen. `DSR` and `DA` are answered,
because a program that asks blocks until they are.

Underline and blink fold to bold — the hardware has neither. There is no
alternate screen buffer, because 80×25 already fills the RAM the cartridge
has, so `?1049` and `?47` clear and home instead.

## Controls

In the terminal:

| Control | Action |
|---|---|
| disc | pan the window (and drop out of follow mode) |
| top action button | toggle follow-the-cursor |
| lower action button | open the line composer (no ECS keyboard needed) |
| keypad `1`–`4` | jump the window to column band 0/20/40/60 |
| keypad `ENTER` | re-centre on the cursor and resume following |
| keypad `CLEAR` | hang up and return to the URL screen |
| ECS keyboard | sends as you type — no composer needed |

With a keyboard, `RTN` sends CR, the arrows send cursor sequences (`ESC [ A`,
or `ESC O A` once an application turns on `DECCKM`), `ESC` sends 27, and
`CTL`+key sends the control codes — `CTL`+`C` = 3, `CTL`+`I` = Tab, and so on.
The ECS `CTL` table doubles as the symbol table, so `CTL`+digit gives
`{ } ~ _ ! ' & @ \` | [ ]`. **`\` is not reachable on any ECS table.** Keys are
scanned every video frame into a 64-entry ring, so nothing is dropped while
the main loop is blocked on a FujiNet mailbox round trip, and everything typed
during one pass is coalesced into a single write.

On the keyboard screens (URL entry and the line composer):

| Control | Action |
|---|---|
| disc | move around the grid / down to `SPC DEL OK ESC` |
| action button | type the highlighted character |
| keypad `0` / `CLEAR` / `ENTER` | space / backspace / accept |
| ECS keyboard | types directly; `RTN` accepts, `ESC` cancels, `←` backspaces |

## Terminal type and window size

A `TELNET` or `SSH` devicespec that carries no query of its own gets
`?term=xterm&cols=80&rows=25` appended, which is how the far end learns to
size its pty to the screen this program actually keeps —
`NetworkProtocolSSH::open()` passes them to `ssh_channel_request_pty_size()`
and the TELNET handler uses them for its terminal type and NAWS. A spec that
brought its own query is left alone, so `?term=ansi` stays available by hand.

`xterm` rather than `linux` on purpose: both are 80×25 colour terminals, but
the `linux` terminfo drives alternate character sets with `ESC [ 11 m` while
this terminal implements `ESC ( 0`, so claiming `linux` would leave the box
drawing permanently unreachable.

## Building

Needs [IntyBASIC](https://github.com/nanochess/IntyBASIC) v1.4.2 and jzintv's
`as1600`:

```sh
make            # -> netcat.bin (+ .cfg) and netcat.rom
```

`lib/` vendors the IntyBASIC **1.4.2** prologue and epilogue, and `LIBDIR`
points there. Do not point it at an IntyBASIC checkout: 1.5.x ships an
epilogue that wraps `_scroll_buffer` in `IF intybasic_scroll`, a symbol the
1.4.2 compiler never emits, which silently moves the 16-bit variable ceiling
and the MOB shadow with it.

`make` also runs a `guard` target, because this program is close to three
limits that nothing else checks:

- 16-bit variables past `$322` run into `_scroll_buffer` and the MOB shadow.
  IntyBASIC reports "of 47 available" from a table that does not match the
  vendored epilogue; the real ceiling is twelve.
- 8-bit variables past `$1EF` run into the PSG.
- ROM past `$6FFF` or `$DFFF` is silently continued into an unmapped segment,
  producing a cart that boots and then dies two instructions later in
  unprogrammed GROM.

The ROM occupies three segments — `$5000`, `$D000` and `$F000` — the same map
`fujinet-config/intv` uses on this cartridge.

## Running

`./run.sh` (or `make run`) launches the ROM in the FujiNet-patched jzIntv
against a fujinet-firmware instance over BoIP (default `localhost:9995`;
override with `FUJINET_TARGET=host:port`). The ECS is emulated by default;
**press `F7` in jzIntv to point the host keyboard at the ECS matrix** (it boots
mapped to the hand controllers, and without `F7` the keyboard looks dead).
`ECS=0 ./run.sh` tests the controller-only fallback. On real hardware, copy
`netcat.rom` onto the cartridge SD, or serve it from a TNFS host and boot it
through CONFIG.

There is no need to edit anything to change targets — type the devicespec at
the URL screen (e.g. `N:SSH://user@host/`). To change the *prefilled default*,
edit the `lit_spec` DATA bytes in `netcat.bas` and adjust `LEN_SPEC`.

## Testing without a television

A terminal is mostly rendering, and rendering is hard to check by eye and easy
to check mechanically. `tools/` runs the ROM headless under jzIntv's debugger,
dumps memory, and decodes BACKTAB back into characters and colours:

```sh
tools/screendump.sh                              # whatever is on screen now
tools/termtest.sh 'N:TCP://127.0.0.1:2323/'      # dial, then dump
VERBOSE=1 tools/termtest.sh 'N:TELNET://host/'   # + variables, rowmap, buffer
```

`termtest.sh` builds a throwaway copy with the devicespec replaced and the URL
screen skipped, so it never touches the repository sources. Point it at a
local `socat TCP-LISTEN:2323,reuseaddr,fork EXEC:...` emitting whatever needs
checking. Everything claimed above was confirmed this way.

## Files

- `netcat.bas` — dial, the main loop, the cursor MOB, key sending, and the
  window-size query.
- `vt.bas` — the 80×25 screen: cells, cursor, control characters, scrolling
  through the `rowmap` indirection table.
- `vtview.bas` — the 20×12 window: following, panning, painting, the status
  overlay.
- `vtansi.bas` — the ANSI/VT interpreter and the ANSI→STIC colour maps.
- `vtfont.bas` — GRAM: lowercase lifted from GROM, the solid block, DEC line
  drawing, and the one routine that turns ASCII into a BACKTAB word.
- `vtasm.asm` — the inner loops: paint a row, fill a run, rotate the row map.
  IntyBASIC repaints at ~257 cycles a cell, which is 3.7 frames for one
  viewport; `VPROW` does it in 37.
- `fujinet.bas` — the FujiNet mailbox library from the programmer's guide.
- `kbd.bas` — the on-screen character grid and the controller poller.
- `ecskbd.bas` / `ecskbd.asm` — ECS detection, the per-frame scan, and the ring
  the terminal drains. `ecskbd.asm` is vendored from jzIntv's SDK-1600
  examples (Joe Zbiciak, CC0).
- `lib/` — the vendored IntyBASIC 1.4.2 prologue and epilogue.

This began as the worked example from Appendix D of the *FujiNet Programmer's
Guide for Intellivision* (`fujinet-manuals` repo,
`intv/fujinet-programmers-guide/`), which describes the line-mode terminal this
grew out of.
