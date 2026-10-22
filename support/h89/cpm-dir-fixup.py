#!/usr/bin/env python3
"""
Mark the zeroed directory entries in an hz89 CP/M disk image as erased.

appmake's cpm_write_file gives a file of exactly 16 blocks a second, empty
directory entry -- all zeros -- which DIR lists as a nameless file. ERA marks
an entry erased with E5 in its first byte only: Heath's CP/M 2.2.04 ends its
directory search at an entry that is all E5 (never used), so a fully blanked
entry would hide every file after it. The directory is the first 8 logical
sectors after the 3 boot tracks (10 x 256-byte sectors a track), in the
image's skewed order.

From fujinet-go-h89-desktop's tools/disks/make-fujinet-disks.sh.

    cpm-dir-fixup.py DISK.h8d
"""
import sys

SKEW = [0, 4, 8, 2, 6, 1, 5, 9, 3, 7]

with open(sys.argv[1], 'r+b') as f:
    for ls in range(8):
        off = (3 * 10 + SKEW[ls]) * 256
        f.seek(off)
        sec = bytearray(f.read(256))
        for e in range(0, 256, 32):
            if not any(sec[e:e + 32]):
                sec[e] = 0xE5
        f.seek(off)
        f.write(sec)
