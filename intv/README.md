# netcat for Intellivision (IntyBASIC)

A line-mode network terminal for the Mattel Intellivision with a FujiNet
cartridge. Type any `N:` devicespec on the on-screen keyboard (the same
character grid FujiNet CONFIG uses for WiFi SSIDs), connect, and everything
the far end sends scrolls across rows 0–9 of the screen, with a blue block
cursor blinking where the next byte will land; the action button opens the
keyboard again to compose a line to send. The URL buffer holds
256 bytes, displayed in a three-row window that scrolls once a long URL
outgrows it. The prefilled default is tcpbin.com's echo service (port
4242), so pressing `OK` untouched gives a self-test needing no server of
your own.

With an **ECS keyboard** attached the port stops being line-mode: you type
on real keys and each keystroke goes straight out the wire, the way a dumb
terminal should behave. The ECS is detected at boot and is entirely
optional — the same ROM falls back to the hand controller and the on-screen
grid when there isn't one, so there is only one binary to build.

This is the worked example from Appendix D of the *FujiNet Programmer's
Guide for Intellivision* (`fujinet-manuals` repo, `intv/fujinet-programmers-guide/`;
wiki edition: *FujiNet Programming Guide for the Intellivision* on the
fujinet-firmware wiki).

## Controls

On the keyboard (URL screen and line composer):

| Control | Action |
|---|---|
| disc | move the cursor around the grid / down to `SPC DEL OK ESC` |
| action button | type the highlighted character / press the highlighted button |
| keypad `0` / `CLEAR` / `ENTER` | space / backspace / accept (same as `OK`) |
| ECS keyboard | types directly; `RTN` accepts, `ESC` cancels, `←` (or `CTL`+`H`) backspaces |

`OK` on the URL screen dials; `ESC` there restores the default URL. `OK`
on the composer sends the line plus CR LF; `ESC` cancels. In the terminal:

| Control | Action |
|---|---|
| action button | open the composer |
| keypad `CLEAR` | hang up and return to the URL screen |
| ECS keyboard | sends as you type — no composer needed |

With a keyboard, `RTN` sends CR LF, the four arrow keys send ANSI cursor
sequences (`ESC [ A`/`B`/`C`/`D`), `ESC` sends 27, and `CTL`+key sends the
usual control codes (`CTL`+`C` = 3, `CTL`+`M` = a bare CR, and so on). Keys
are scanned every video frame and queued, so nothing is dropped while the
main loop is blocked on a FujiNet mailbox round trip; everything typed
during one pass is coalesced into a single write.

## Building

Needs [IntyBASIC](https://github.com/nanochess/IntyBASIC) v1.4.2 and
jzintv's `as1600`:

```sh
make            # -> netcat.bin (+ .cfg) and netcat.rom
```

Unlike the C ports in `src/`, this port is IntyBASIC and builds standalone —
it is not part of the root mekkogx build.

## Running

`./run.sh` (or `make run`) launches the ROM in the FujiNet-patched jzIntv
against a fujinet-firmware instance over BoIP (default `localhost:9995`;
override with `FUJINET_TARGET=host:port`). The ECS is emulated by default;
**press `F7` in jzIntv to point the host keyboard at the ECS matrix** (it
boots mapped to the hand controllers, and without `F7` the keyboard looks
dead). `ECS=0 ./run.sh` tests the controller-only fallback. On real hardware, copy
`netcat.rom` onto the cartridge SD, or serve it from a TNFS host and boot
it through CONFIG.

There is no need to edit anything to change targets — type the devicespec
at the URL screen (e.g. `N:TELNET://TELEHACK.COM:23/`). To change the
*prefilled default*, edit the `lit_spec` DATA bytes in `netcat.bas` and
adjust `LEN_SPEC` to match.

## Files

- `netcat.bas` — the terminal: URL entry, a wrap-around receive pane with
  a repaintable shadow, the blinking MOB cursor, the line composer, and the
  OPEN → STATUS/READ/WRITE → CLOSE loop.
- `kbd.bas` — the on-screen character-grid keyboard and edge-detected
  input poller, ported from `fujinet-config/intv` (`input.bas`), with the
  value display widened to a three-row scrolling window for long URLs.
- `fujinet.bas` — the reusable FujiNet mailbox library from the
  programmer's guide (transaction primitives, N: helpers including
  `net_write`, AppKeys, `fn_putnum`).
- `ecskbd.bas` — ECS detection, the per-frame keyboard scan, and the ring
  buffer the terminal and the grid drain. It does not declare the frame hook
  itself: IntyBASIC allows only one `ON FRAME GOSUB` per program, and
  `netcat.bas`'s `frame_tick` owns it and drives both the scan and the cursor.
- `ecskbd.asm` — the ECS keyboard matrix scanner, vendored from jzIntv's
  SDK-1600 examples (`examples/ecs_kbd/scan_kbd.asm`, Joe Zbiciak, released
  to the public domain under CC0 1.0), renamed for `USR` and made stateless.
