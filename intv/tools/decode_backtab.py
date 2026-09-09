#!/usr/bin/env python3
"""Decode BACKTAB out of a jzIntv 'd' memory dump into the screen it shows.

jzIntv's debugger writes dump.mem as a big-endian 16-bit image of memory as the
CPU sees it, so BACKTAB is the 240 words at $0200. Foreground/Background mode
packs a cell as

    bit  13   12   11   10    9   8..3        2..0
         bg2  bg3  GRAM bg1  bg0  card 0-63   fg 0-7

GROM card N is ASCII N+32, covering 32..95. GRAM cards 0..30 are ASCII 96..126
(vtfont.bas), and GRAM 43 is the solid block used for cursors.
"""
import struct, sys, pathlib

STIC = ["black", "blue", "red", "tan", "dkgreen", "green", "yellow", "white",
        "grey", "cyan", "orange", "brown", "pink", "ltblue", "yelgrn", "purple"]

def glyph(w):
    card, gram = (w >> 3) & 0x3F, (w >> 11) & 1
    if gram:
        if card < 31:
            return chr(96 + card)
        return "█" if card == 43 else "?"
    return chr(32 + card)

def colours(w):
    return w & 7, ((w >> 9) & 0x3) | ((w >> 13) & 0x1) << 2 | ((w >> 12) & 0x1) << 3

def main(path):
    mem = pathlib.Path(path).read_bytes()
    words = struct.unpack(">%dH" % (len(mem) // 2), mem)
    bt = words[0x200:0x2F0]
    print("      +" + "-" * 20 + "+")
    for r in range(12):
        print("   %2d |%s|" % (r, "".join(glyph(w) for w in bt[r*20:(r+1)*20])))
    print("      +" + "-" * 20 + "+")
    seen = {}
    for w in bt:
        seen[colours(w)] = seen.get(colours(w), 0) + 1
    print("   colours (fg on bg, cells):")
    for (fg, bg), n in sorted(seen.items(), key=lambda kv: -kv[1]):
        print("     %-8s on %-8s  %3d" % (STIC[fg], STIC[bg], n))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "dump.mem")
