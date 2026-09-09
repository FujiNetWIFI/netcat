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
import re, struct, sys, pathlib

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



# --- extra diagnostics, used by tools/termtest.sh -v -------------------------
def symbols(lst):
    """Pull IntyBASIC variable addresses out of an as1600 listing."""
    # The symbol table prints as two columns of "ADDRESS  name" pairs.
    out = {}
    for line in open(lst, errors="replace"):
        for addr, name in re.findall(r'([0-9A-F]{8})\s+var_([A-Z0-9_]+)\b', line):
            out[name] = int(addr, 16)
    return out

def dump_state(memfile, lst, rows=None):
    mem = pathlib.Path(memfile).read_bytes()
    w = struct.unpack(">%dH" % (len(mem) // 2), mem)
    sym = symbols(lst)
    want = ["VX", "VY", "VP_TRACK", "VP_FULL", "VP_DTOP", "VP_DBOT",
            "VT_COL", "VT_ROW", "VT_PEND", "SR_TOP", "SR_BOT",
            "AN_STATE", "TERM_FG", "BLANK_LO", "BLANK_HI"]
    print("   state:", "  ".join("%s=%d" % (n, w[sym[n]] & 0xFF)
                                 for n in want if n in sym))
    url = ""
    for i in range(256):
        c = w[0x9200 + i] & 0xFF
        if c == 0:
            break
        url += chr(c) if 32 <= c < 127 else "."
    print("   SC_URL: %s" % url)
    rowmap = [w[0x9440 + i] & 0xFF for i in range(25)]
    print("   rowmap:", " ".join("%d" % r for r in rowmap))
    print("   TBUF (logical rows, columns 0-79):")
    for r in (rows if rows is not None else range(25)):
        base = 0x8000 + rowmap[r] * 160
        cells = [(w[base + c*2] & 0xFF) | ((w[base + c*2 + 1] & 0xFF) << 8)
                 for c in range(80)]
        print("   %2d |%s|" % (r, "".join(glyph(c) for c in cells)))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "dump.mem")
    if len(sys.argv) > 2:
        dump_state(sys.argv[1], sys.argv[2])
