' vtfont.bas -- the GRAM half of the character set, and the one routine that
' turns an ASCII byte into a Foreground/Background-mode BACKTAB word.
'
' In FG/BG mode (MODE 1) the STIC gives every cell its own foreground (8
' colours) and background (16 colours), which is what makes ANSI colour
' possible at all -- but it pays for that with the card number field, which
' drops to six bits. Only GROM cards 0-63 and GRAM cards 0-63 are reachable
' (jzIntv stic.c, stic_draw_fgbg: gr_idx = card & $9F8). GROM card N is ASCII
' N+32, so GROM alone covers ASCII 32-95: symbols, digits and UPPERCASE.
' Lowercase lives in GROM cards 64-94, which FG/BG mode cannot see.
'
' So lowercase moves into GRAM. The glyphs below are not hand-drawn: they are
' GROM cards 64-94 read straight out of jzIntv rom/grom.bin, so a lowercase
' letter on screen is pixel-identical to the one the console would have drawn
' itself, and nothing has to be redesigned to match.
'
'   GRAM 0-30   ASCII 96-126  -- backtick, a-z, { | } ~
'   GRAM 31-42  reserved for DEC special graphics (box drawing)
'   GRAM 43     solid block -- the terminal cursor MOB and the grid edit cursor
'   GRAM 44-63  spare
'
' GROM card 95 is a solid block already, but it is card 95: out of reach in
' FG/BG mode. Hence GRAM 43.

    ' The FG/BG mode BACKTAB word:
    '
    '   bit  13   12   11   10    9   8..3         2..0
    '        bg2  bg3  GRAM bg1  bg0  card 0-63    fg 0-7
    '
    ' The background nibble is scattered across four non-adjacent bits, so it
    ' is cheaper to keep it pre-scattered in a table than to reassemble it per
    ' cell. Index by background colour 0-15; the result ORs straight into the
    ' word. (IntyBASIC's manual documents this bit order incorrectly; the
    ' table below follows the STIC.)
bg_scatter:
    DATA $0000, $0200, $0400, $0600, $2000, $2200, $2400, $2600
    DATA $1000, $1200, $1400, $1600, $3000, $3200, $3400, $3600

    ' cell_word's arguments and result. DIMmed here, ahead of the procedure
    ' below: IntyBASIC auto-declares a variable at first use, so a DIM in the
    ' including file -- which lands after this include -- is a redefinition.
    DIM cw_c, cw_fg
    DIM #cw_w, #cw_bgw

    CONST GRAM_BLOCK  = 43      ' solid block
    CONST GRAM_DEC0   = 31      ' first DEC special-graphics card
    CONST CARD_GRAM   = 2048    ' word bit 11: card comes from GRAM

' ---------------------------------------------------------------------------
' cell_word: ASCII cw_c (32-126) + colour -> #cw_w, a FG/BG BACKTAB word.
'
' cw_fg   foreground, STIC colour 0-7
' #cw_bgw background, ALREADY scattered (bg_scatter(colour))
'
' The background arrives pre-scattered rather than as a colour index because
' every caller holds one attribute across many characters -- a whole SGR run,
' or an entire grid repaint -- so the table lookup happens once per attribute
' change instead of once per glyph.
'
' No lookup table maps ASCII to a card: the two ranges are contiguous, so it
' is one compare and a multiply. A table would cost 95 words of ROM to save
' nothing.
' ---------------------------------------------------------------------------
cell_word: PROCEDURE
    IF cw_c < 96 THEN
        #cw_w = (cw_c - 32) * 8                 ' GROM card 0-63
    ELSE
        #cw_w = (cw_c - 96) * 8 + CARD_GRAM     ' GRAM card 0-30
    END IF
    #cw_w = #cw_w + cw_fg + #cw_bgw
END

' ---------------------------------------------------------------------------
' font_load: push the GRAM cards up before anything can display them.
'
' IntyBASIC queues a DEFINE for the next frame's interrupt to execute, and the
' manual puts the ceiling at "approximately 18 cards" per frame, so 31 glyphs
' plus the block need three passes with a WAIT between them. This runs once,
' at boot, before the first CLS.
' ---------------------------------------------------------------------------
font_load: PROCEDURE
    DEFINE 0, 16, glyph_lower
    WAIT
    DEFINE 16, 15, glyph_lower2
    WAIT
    DEFINE GRAM_BLOCK, 1, glyph_block
    WAIT
END

glyph_lower:
    ' GRAM 0  -- ASCII 96, backtick
    BITMAP "....X..."
    BITMAP ".....X.."
    BITMAP "......X."
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    ' GRAM 1  -- ASCII 97, lowercase a
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXX.."
    BITMAP "....XX.."
    BITMAP ".XXXXX.."
    BITMAP ".XX.XX.."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 2  -- ASCII 98, lowercase b
    BITMAP ".XXX...."
    BITMAP "..XX...."
    BITMAP "..XXXXX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XXXXX."
    BITMAP "........"
    ' GRAM 3  -- ASCII 99, lowercase c
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".XX..XX."
    BITMAP ".XX....."
    BITMAP ".XX....."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 4  -- ASCII 100, lowercase d
    BITMAP "....XXX."
    BITMAP "....XX.."
    BITMAP ".XXXXX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XXXXX.."
    BITMAP "........"
    ' GRAM 5  -- ASCII 101, lowercase e
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".XX..XX."
    BITMAP ".XXXXXX."
    BITMAP ".XX....."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 6  -- ASCII 102, lowercase f
    BITMAP "........"
    BITMAP "..XXXXX."
    BITMAP "..XX...."
    BITMAP ".XXXXX.."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "........"
    ' GRAM 7  -- ASCII 103, lowercase g
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XXXXX.."
    BITMAP "....XX.."
    BITMAP ".XXXXX.."
    ' GRAM 8  -- ASCII 104, lowercase h
    BITMAP ".XX....."
    BITMAP ".XX....."
    BITMAP ".XXXXX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XXX."
    BITMAP "........"
    ' GRAM 9  -- ASCII 105, lowercase i
    BITMAP "...XX..."
    BITMAP "........"
    BITMAP "..XXX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 10 -- ASCII 106, lowercase j
    BITMAP ".....XX."
    BITMAP "........"
    BITMAP ".....XX."
    BITMAP ".....XX."
    BITMAP ".....XX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XXXXX."
    ' GRAM 11 -- ASCII 107, lowercase k
    BITMAP ".XX....."
    BITMAP ".XX....."
    BITMAP ".XX..XX."
    BITMAP ".XX.XX.."
    BITMAP ".XXXX..."
    BITMAP ".XX..XX."
    BITMAP ".XX..XX."
    BITMAP "........"
    ' GRAM 12 -- ASCII 108, lowercase l
    BITMAP "..XXX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 13 -- ASCII 109, lowercase m
    BITMAP "........"
    BITMAP "........"
    BITMAP "XXXXXXX."
    BITMAP "XX.X.XX."
    BITMAP "XX.X.XX."
    BITMAP "XX.X.XX."
    BITMAP "XX.X.XX."
    BITMAP "........"
    ' GRAM 14 -- ASCII 110, lowercase n
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "........"
    ' GRAM 15 -- ASCII 111, lowercase o
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".XX..XX."
    BITMAP ".XX..XX."
    BITMAP ".XX..XX."
    BITMAP ".XXXXXX."
    BITMAP "........"

glyph_lower2:
    ' GRAM 16 -- ASCII 112, lowercase p
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XXXXX."
    BITMAP "..XX...."
    BITMAP "..XX...."
    ' GRAM 17 -- ASCII 113, lowercase q
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XXXXX.."
    BITMAP "....XX.."
    BITMAP "....XXX."
    ' GRAM 18 -- ASCII 114, lowercase r
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP "..XX.XX."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "........"
    ' GRAM 19 -- ASCII 115, lowercase s
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".XX....."
    BITMAP ".XXXXXX."
    BITMAP ".....XX."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 20 -- ASCII 116, lowercase t
    BITMAP "........"
    BITMAP "..XX...."
    BITMAP ".XXXXXX."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "..XXXXX."
    BITMAP "........"
    ' GRAM 21 -- ASCII 117, lowercase u
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 22 -- ASCII 118, lowercase v
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XX..XX."
    BITMAP ".XX..XX."
    BITMAP ".XX..XX."
    BITMAP "..XXXX.."
    BITMAP "...XX..."
    BITMAP "........"
    ' GRAM 23 -- ASCII 119, lowercase w
    BITMAP "........"
    BITMAP "........"
    BITMAP "XX.X.XX."
    BITMAP "XX.X.XX."
    BITMAP "XX.X.XX."
    BITMAP "XXXXXXX."
    BITMAP ".XX.XX.."
    BITMAP "........"
    ' GRAM 24 -- ASCII 120, lowercase x
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XX..XX."
    BITMAP "..XXXX.."
    BITMAP "...XX..."
    BITMAP "..XXXX.."
    BITMAP ".XX..XX."
    BITMAP "........"
    ' GRAM 25 -- ASCII 121, lowercase y
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XXXXX."
    BITMAP ".....XX."
    BITMAP "..XXXXX."
    ' GRAM 26 -- ASCII 122, lowercase z
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".....XX."
    BITMAP "...XX..."
    BITMAP ".XX....."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 27 -- ASCII 123, left brace
    BITMAP "....XXX."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "..XX...."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....XXX."
    BITMAP "........"
    ' GRAM 28 -- ASCII 124, pipe
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    ' GRAM 29 -- ASCII 125, right brace
    BITMAP ".XXX...."
    BITMAP "...X...."
    BITMAP "...X...."
    BITMAP "....XX.."
    BITMAP "...X...."
    BITMAP "...X...."
    BITMAP ".XXX...."
    BITMAP "........"
    ' GRAM 30 -- ASCII 126, tilde
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXX..."
    BITMAP "...XXXX."
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"

glyph_block:
    ' GRAM 43 -- solid block
    BITMAP "XXXXXXXX"
    BITMAP "XXXXXXXX"
    BITMAP "XXXXXXXX"
    BITMAP "XXXXXXXX"
    BITMAP "XXXXXXXX"
    BITMAP "XXXXXXXX"
    BITMAP "XXXXXXXX"
    BITMAP "XXXXXXXX"
