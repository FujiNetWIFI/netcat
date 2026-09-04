#!/usr/bin/env python3
"""checksize.py -- per-module ROM budget table from the zmac listing.

texas.asm brackets every module with an MB_* fence label; this reads their
addresses out of the listing's symbol table, prints the size of each span,
and fails the build if MB_END is over the 0x1B00 ROM top. build.sh already
rejects an oversized image -- this exists so growth is visible per module
long before that, the way o2's checkers keep its bank layout honest.

Usage: checksize.py build/texas.lst
"""

import re
import sys

ORG = 0x2000            # cart window base; ROM offset = address - ORG
ROM_TOP = 0x1B00
WARN_SPARE = 200        # grumble (but pass) when headroom drops below this


def read_symbols(path: str) -> dict[str, int]:
    """MB_* fence labels from the zmac symbol table, name -> address."""
    syms = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    # zmac's symbol table lowercases names and lists them as "name value",
    # several pairs per line, a trailing + marking multiple references
    # (e.g. "mb_data         2045+"). Labels carry no "=" (EQUs do).
    for name, val in re.findall(
            r"\b(mb_[a-z0-9_]+)\s+=?\s*([0-9a-f]{1,5})\+?", text):
        syms[name.upper()] = int(val, 16)
    return syms


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    syms = read_symbols(sys.argv[1])
    if "MB_END" not in syms or len(syms) < 2:
        print("checksize: no MB_* fence labels found in the listing",
              file=sys.stderr)
        return 1

    fences = sorted(syms.items(), key=lambda kv: kv[1])
    print("checksize: module budget")
    for (name, addr), (_, nxt) in zip(fences, fences[1:]):
        print(f"  {name[3:]:<10} {nxt - addr:5} bytes")
    used = syms["MB_END"] - ORG
    spare = ROM_TOP - used
    print(f"  {'total':<10} {used:5} of {ROM_TOP} ({spare} spare)")
    if spare < 0:
        print(f"checksize: {-spare} bytes over the ROM top", file=sys.stderr)
        return 1
    if spare < WARN_SPARE:
        print(f"checksize: headroom under {WARN_SPARE} bytes", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
