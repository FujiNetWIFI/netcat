#!/usr/bin/env python3
"""mkfont.py -- 4x6 font -> assets/font.inc (zmac, 1bpp), 96 glyphs.

Extends the card-game ports' generator (fujinet-5cardstud/astrocade/tools)
from 64 glyphs to 96 so netcat can show a BBS in mixed case. The first 64
(20H-5FH) come from the same Lynx BMPs and stay byte-identical to the
family's committed font; 60H-7FH are new.

The Lynx set has 68 glyph BMPs but the 64-glyph table used only 63 of them,
and the five left over are exactly the punctuation the upper range needs:
backtick, the curly brackets, the bar and the tilde. So the only genuinely
new art is a-z, hand-drawn below -- the BMPs named a.bmp..z.bmp are the
CAPITALS (the 64-glyph table maps 0x41+c to chr(0x61+c)).

Lowercase geometry, within the 4x6 cell (column 3 is always blank, it is the
inter-character gap, and row 0 is the inter-line gap for capitals):
  x-height       rows 2-5
  ascenders      rows 0-5   (b d f h k l t -- taller than caps, as in type)
  dots           row 0      (i j)
  descenders     body rows 2-4, tail row 5   (g j p q y)

Ink is the HIGH nibble, bit 7 leftmost: one magic-expander write per row
(the expander takes the high nibble on the first write after the MAGIC
register is set -- see gfx.inc).

The Lynx art lives outside this repo, so point LYNX= at it:
    LYNX=~/Workspace/fujinet-5cardstud/src/lynx/4x6 tools/mkfont.py
The output is committed; rerun only after art changes (make assets).
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LYNX = os.environ.get(
    "LYNX",
    os.path.expanduser("~/Workspace/fujinet-5cardstud/src/lynx/4x6"))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "font.inc"))

W, H = 4, 6
FIRST, LAST = 0x20, 0x7F

# 20H-5FH: src/lynx/4x6font.s's table (0x26 reuses plus.spr for ampersand
# there). 60H and 7BH-7EH are the BMPs that table never used.
NAMES = {
    0x20: "space", 0x21: "exclam", 0x22: "quotation", 0x23: "hash",
    0x24: "dollar", 0x25: "percent", 0x26: "plus", 0x27: "apostr",
    0x28: "left-rbrack", 0x29: "right-rbrack", 0x2A: "asterisk",
    0x2B: "plus", 0x2C: "comma", 0x2D: "hypen", 0x2E: "period",
    0x2F: "forwardslash",
    0x3A: "colon", 0x3B: "semicolon", 0x3C: "left-abrack", 0x3D: "equal",
    0x3E: "right-abrack", 0x3F: "question", 0x40: "at",
    0x5B: "left-sbrack", 0x5C: "backslash", 0x5D: "right-sbrack",
    0x5E: "carat", 0x5F: "underscore",
    0x60: "backtick",
    0x7B: "left-cbrack", 0x7C: "bar", 0x7D: "right-cbrack", 0x7E: "tilde",
}
for d in range(10):
    NAMES[0x30 + d] = chr(0x30 + d)
for c in range(26):
    NAMES[0x41 + c] = chr(0x61 + c)

# 61H-7AH, hand-drawn. Six rows of four columns, top row first.
ART = {
    "a": ["....", "....", "##..", ".##.", "#.#.", ".##."],
    "b": ["#...", "#...", "#...", "##..", "#.#.", "##.."],
    "c": ["....", "....", ".##.", "#...", "#...", ".##."],
    "d": ["..#.", "..#.", "..#.", ".##.", "#.#.", ".##."],
    "e": ["....", "....", ".##.", "#.#.", "##..", ".##."],
    "f": [".##.", ".#..", "###.", ".#..", ".#..", ".#.."],
    "g": ["....", "....", ".##.", "#.#.", ".##.", "##.."],
    "h": ["#...", "#...", "#...", "##..", "#.#.", "#.#."],
    "i": [".#..", "....", ".#..", ".#..", ".#..", ".#.."],
    "j": ["..#.", "....", "..#.", "..#.", "..#.", "##.."],
    "k": ["#...", "#...", "#.#.", "##..", "##..", "#.#."],
    "l": ["##..", ".#..", ".#..", ".#..", ".#..", ".##."],
    "m": ["....", "....", "#.#.", "###.", "#.#.", "#.#."],
    "n": ["....", "....", "##..", "#.#.", "#.#.", "#.#."],
    "o": ["....", "....", ".#..", "#.#.", "#.#.", ".#.."],
    "p": ["....", "....", "##..", "#.#.", "##..", "#..."],
    "q": ["....", "....", ".##.", "#.#.", ".##.", "..#."],
    "r": ["....", "....", "##..", "#.#.", "#...", "#..."],
    "s": ["....", "....", ".##.", "#...", "..#.", "##.."],
    "t": [".#..", ".#..", "###.", ".#..", ".#..", ".##."],
    "u": ["....", "....", "#.#.", "#.#.", "#.#.", ".##."],
    "v": ["....", "....", "#.#.", "#.#.", "#.#.", ".#.."],
    "w": ["....", "....", "#.#.", "#.#.", "###.", "#.#."],
    "x": ["....", "....", "#.#.", ".#..", ".#..", "#.#."],
    "y": ["....", "....", "#.#.", "#.#.", ".##.", "##.."],
    "z": ["....", "....", "###.", "..#.", ".#..", "###."],
}


def read_bmp_4x6(path: str) -> list[list[int]]:
    """Rows top-down of 0/1 ink flags from a 4x6 Windows BMP.

    The set is 4bpp except tilde.bmp, which someone saved as 24bpp; both are
    black ink on a white ground, so ink is just "this pixel is dark".
    """
    with open(path, "rb") as f:
        data = f.read()
    if data[:2] != b"BM":
        raise SystemExit(f"mkfont: {path}: not a BMP")
    offset = int.from_bytes(data[10:14], "little")
    w = int.from_bytes(data[18:22], "little")
    h = int.from_bytes(data[22:26], "little", signed=True)
    bpp = int.from_bytes(data[28:30], "little")
    if (w, h) != (W, H) or bpp not in (4, 24):
        raise SystemExit(f"mkfont: {path}: {w}x{h}x{bpp}, want {W}x{H}x4|24")
    stride = ((w * bpp + 31) // 32) * 4
    rows = []
    for y in range(h):                    # BMP rows are bottom-up
        base = offset + (h - 1 - y) * stride
        row = []
        for x in range(w):
            if bpp == 4:
                byte = data[base + x // 2]
                nib = byte >> 4 if x % 2 == 0 else byte & 0x0F
                ink = nib == 0
            else:
                b, g, r = data[base + x * 3:base + x * 3 + 3]
                ink = (r + g + b) < 3 * 128
            row.append(1 if ink else 0)
        rows.append(row)
    return rows


def rows_for(cp: int) -> list[list[int]]:
    """Ink rows for a codepoint: hand-drawn art, a BMP, or blank."""
    ch = chr(cp)
    if ch in ART:
        art = ART[ch]
        if len(art) != H or any(len(r) != W for r in art):
            raise SystemExit(f"mkfont: {ch!r}: art must be {H} rows of {W}")
        return [[1 if c == "#" else 0 for c in r] for r in art]
    name = NAMES.get(cp)
    if name is None:
        if cp == 0x7F:                    # DEL: nothing to draw
            return [[0] * W for _ in range(H)]
        raise SystemExit(f"mkfont: no source mapped for {cp:#04x}")
    return read_bmp_4x6(os.path.join(LYNX, f"{name}.bmp"))


def main() -> int:
    if not os.path.isdir(LYNX):
        raise SystemExit(f"mkfont: no Lynx art at {LYNX}; set LYNX=")
    lines = [
        "; font.inc -- 4x6 font, 1bpp, GENERATED by tools/mkfont.py -- do not",
        "; edit; rerun `make assets`.",
        ";",
        "; 96 glyphs, codepoints 20H-7FH, 6 bytes each, top row first. 20H-5FH",
        "; are byte-identical to the card-game ports' font (same Lynx BMPs);",
        "; 61H-7AH are hand-drawn lowercase, so a BBS reads in mixed case.",
        "; Ink is the HIGH nibble, bit 7 leftmost: one magic-expander write",
        "; per row (the expander takes the high nibble first after a MAGIC",
        "; register write -- see gfx.inc).",
        "FONT46:",
    ]
    for cp in range(FIRST, LAST + 1):
        rows = rows_for(cp)
        label = chr(cp) if 0x20 < cp < 0x7F else f"{cp:02X}"
        lines.append(f"; {cp:02X}H '{label}'")
        for row in rows:
            val = 0
            for x, ink in enumerate(row):
                if ink:
                    val |= 0x80 >> x
            art = "".join("#" if ink else "." for ink in row)
            lines.append(f"        DB      {val:03X}H    ; {art}")
    lines.append("")

    # Self-checks: glyph count and total size are structural.
    n_glyphs = LAST - FIRST + 1
    n_bytes = sum(1 for l in lines if l.strip().startswith("DB"))
    assert n_glyphs == 96, n_glyphs
    assert n_bytes == n_glyphs * H, n_bytes

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("\n".join(lines))
    print(f"mkfont: {n_glyphs} glyphs, {n_bytes} bytes -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
