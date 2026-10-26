# netcat for the Odyssey 2

A terminal for the Magnavox Odyssey 2 / Philips Videopac, over the FujiNet O2
cartridge. It is 8048 assembly (Macroassembler AS) and stands alone, like
`intv/` and `astrocade/`: it is not part of the root mekkogx build. At power-on
it dials `N:TELNET://bbs.retrocampus.com/`.

It was built and tested in MAME, with the FujiNet cart device and a real
fujinet-pc, against a local fixture and live against bbs.retrocampus.com. It
has not been tried on hardware: real carts need fujinet-firmware PR #2177
(protocol 2, the APPBANK images).

## The screen: 7 lines of 16, a window onto 80 columns

The 8244 has 28 character objects, with a fixed upper-case font. This port
gets 112 characters on screen out of them:

- **Columns:** each line is the four quads interleaved, 16 columns at 8 px.
- **Lines:** a line-counter interrupt re-points the quads for every line, in
  the 18 blanked lines under the one before. The object registers take writes
  only with the foreground off.
- **Layout:** 7 lines at Y = 16, 48, …, 208.
- **Timing:** measured in MAME, the band has about 2 lines of slack (see
  Testing).

No display tables are needed: the interrupt draws each line straight out of
the terminal's own row in cartridge RAM.

- **Cells:** a cell holds 4 × the glyph, so `add a,r5 / clr c / rlc a` (with
  r5 = -Y/4) turns it into the VDC's pointer, glyph·8 - Y/2, all nine bits.
- **Rows:** a row stores its even columns, then its odd ones. The 16
  characters of a line are then two runs of 8 consecutive bytes.
  - **Panning** is one byte the interrupt adds.
  - **Scrolling** advances the ring's head and blanks one row.

  Neither moves any text.

**The terminal is 80 columns by the 7 visible lines**, 560 bytes. It lives in
the 1K of cartridge RAM the console can write (protocol 2's fixed half), beside
the display code. A taller terminal would not fit there.

**The window follows the cursor** while the background is blue. It jumps to
keep the cursor in view, and back to column 0 on a CR. The stick takes it over
(green); the button gives it back.

## Telling the host its size

A TELNET or SSH spec with no query of its own gets `?cols=80&rows=7` (in
`build.sh`). FujiNet then offers NAWS 80×7, and the terminal type stays
`dumb`. Retrocampus takes the 80 but not the 7: its menus are 24 lines, so the
top of a long one scrolls away. There is no room for scrollback.

## What it understands

- **Controls:**
  - CR, LF, BS and TAB are honoured, and FF clears the screen.
  - Line wrap at 80 is deferred.
  - Escape sequences are swallowed whole: CSI, OSC (to BEL or ST), and ESC
    plus an intermediate plus one more byte.
  - Other control characters, DEL and bytes over $7F are dropped.
- **Lower case** shows as upper case.
- **Missing characters:**
  - The font lacks `! " & ' ( ) ; < > @ [ ] ^ _ { } ~` and lower case.
  - `,` `;` `_` `|` borrow `.` `:` `-` `I`.
  - `*` shows as ×, `%` as ÷, `#` as a block, and `\` as the font's backslash.
  - The rest show as blanks.

## Controls

The console has no shift key, and its YES and NO keys are Y and N. So × and ÷,
the keys a terminal needs least, are one-shot prefixes for the next key. The
cursor turns yellow while × waits and green while ÷ does.

| Keys | Send |
|------|------|
| letters, digits, space, `? . - + =` | themselves, letters in lower case |
| ENT | CR LF |
| CLR | backspace |
| × then letter | upper case |
| × then 1 … 0 | `! @ # $ % ^ & * ( )` |
| × then `. - = + ?` | `, _ : ; "` |
| × then SPACE / CLR / ENT | TAB / DEL / ESC |
| × × | `*` |
| × ÷ | `\` |
| ÷ then letter | control code (÷ C is ^C) |
| ÷ then `? . - = +` | `' > < [ ]` |
| ÷ × | `\|` |
| ÷ ÷ | `/` |

| Stick | Does |
|-------|------|
| left / right | pan 2 columns, repeating while held |
| up / down | pan a window's width (16) |
| button | the window back on the cursor; after a hang-up, dial again |

MAME's keys: the letters, digits, Space, Enter (ENT) and Backspace (CLR). Y
and N are YES and NO. The console's `?` is the `/` key, and its × and ÷ are
the keypad's `*` and `/`. The arrow keys are the stick, Left Ctrl its button,
and F1 the console's RESET.

## Building and running

    ./build.sh                      # build/nc.bin: the fixed 1K + 2 pages of 2K
    ENDPOINT=N:TCP://host:port/ ./build.sh
    ./run.sh                        # MAME, in a window
    make spike                      # the display engine alone, a test pattern

`build.sh` needs `~/asl/asl` and `p2bin` (or `ASL=` / `P2BIN=`). It runs
these checks on every build:

- `checkflags`: a JZ/JNZ that tests a MOV, not the ALU result before it.
- `checkobj` and `checklayout`: code that runs into other code.
- `checkmb`: a cross-bank call that leaves MB set wrong.
- `checkpage`: a MOVP table outside its reader's page.
- `checkstack`: 8 levels, interrupts included.

All come from the M.U.L.E. O2 client except `pagemap.py`, which shows each
page's free bytes.

`run.sh` needs `~/Workspace/mame` (`MAME_DIR`) with the O2 FujiNet cart device
grafted in (fujinet-firmware `pico/o2/emu/apply-mame.sh`, PR #2177), and a
fujinet-pc BoIP listener on `FUJINET_TCP` (default 127.0.0.1:9995).

### The memory map

| Where | What |
|-------|------|
| `$400-$7FF` | the fixed half, cart RAM: vectors, interrupts, a writer copy and two of the 7 rows a page (`src/fixed.inc`) |
| page 0 `$800-$EFF` | the program; one 256-byte page per module (conditional jumps are page-relative) |
| page 1 | the key tables, the messages, the spec, reached by `farcall` |
| `$F00-$F1F` | each page's mailbox reader; `$F20` up is the mailbox |

Console RAM: internal `$20-$2A` is the display's (`src/ram.inc`); external RAM
holds the terminal, keyboard and connection state.

## Testing

    make test                       # tools/termtest.py: every test in test/scen

Each test builds an image that dials `tools/fixture.py`. It then runs MAME
headless through `test/rig.sh`, which starts a private fujinet-pc on BoIP
19975 and never touches the everyday one on 9995. The test checks what the
fixture received, and the terminal as text: `tools/screen.py` rebuilds it from
the cart RAM.

| Test | Checks |
|------|--------|
| `spike` | the engine's test pattern, panned and rolled; no line loses pixels |
| `lines` | ten lines scroll; the window comes back to the cursor |
| `wrap` | a 100-column line wraps at 80; the stick pans to columns 48-63 |
| `esc` | CSI, OSC, UTF-8, DEL, BEL leave nothing; TAB stops |
| `keys` | every prefix, as bytes received |
| `hangup` | the far end hangs up; the button redials |
| `telnet` | `N:TELNET` to the fixture: the NAWS offer, text, keys |
| `heldkey` | a held key (the BIOS debounces it with the vblank held off) disturbs no line |

`test/scen/bbs.scen` is the live run: `test/rig.sh test/scen/bbs.scen
build/bbs` against the default build.

**Slack.** `PADN=n SPIKE=1 ./build.sh` adds 2+2n cycles to every band. In
MAME, with `LEAD = 1` (the band starts a line early), lines start losing their
tops between n = 20 and 25: about 45 cycles, 2 lines. `LEAD = 0` leaves under
1 line, and `LEAD = 2` cuts the bottom line of each row.
