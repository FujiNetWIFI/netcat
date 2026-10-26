#!/usr/bin/env python3
"""screen.py -- the terminal as text, from o2sim's peeks.

    o2sim.py ... | screen.py [LISTING]

Reads the PEEK lines of a scenario that ends with

    cart 400 1024       the fixed half: the rows
    iram 20 11          FRAMES ... HEAD (ram.inc)
    xram 0 4            CX, CY, PAN, FOLLOW

and prints the ROWS x 80 terminal top to bottom (HEAD's ring undone, each
row's even and odd planes interleaved; trailing blanks trimmed), then the
cursor and the window. LISTING (build/nc_p0.lst) gives the rows' addresses.
"""
import re
import sys

ROM = "0123456789:$ ?LP+WERTUIOQSDFGHJKAZXCVBM.-*%=YN/#"


def rows_from(listing):
    rows = {}
    for line in open(listing, errors="ignore"):
        for m in re.finditer(r"\bROW(\d) :\s+([0-9A-F]+) C", line):
            rows[int(m.group(1))] = int(m.group(2), 16)
    return [rows[k] for k in sorted(rows)]


def main(listing="build/nc_p0.lst"):
    peek = {}
    for line in sys.stdin:
        m = re.match(r"PEEK (\w+) ([0-9A-F]+): (.*)", line.strip())
        if m:
            peek[(m.group(1), int(m.group(2), 16))] = [int(b, 16) for b in m.group(3).split()]
    fixed = peek[("cart", 0x400)]
    iram = peek[("iram", 0x20)]
    cx, cy, pan, follow = peek[("xram", 0)][:4]
    head = iram[0x22 - 0x20]
    bases = rows_from(listing)
    n = len(bases)
    for i in range(n):
        b = bases[(head + i) % n] - 0x400
        cells = fixed[b:b + 80]
        text = ""
        for c in range(80):
            v = cells[c // 2] if c % 2 == 0 else cells[40 + c // 2]
            g = v // 4
            text += ROM[g] if g < len(ROM) and v % 4 == 0 else "~"
        print("|" + text.rstrip())
    print("cursor %d,%d  window %d-%d  %s" % (cx, cy, pan, pan + 15, "follow" if follow else "free"))


if __name__ == "__main__":
    main(*sys.argv[1:2])
