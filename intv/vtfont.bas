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
' Two more characters come with it, for a different reason. GROM is laid out
' to ASCII-1963, which put an up arrow at 0x5E and a left arrow at 0x5F, so
' cards 62 and 63 draw those arrows and not the circumflex and underscore
' ASCII-1968 replaced them with. They move into GRAM too, which is why the
' GRAM block below starts at ASCII 94 rather than 96 and GROM is left covering
' 32-93 -- and why cell_word still needs only the one compare.
'
'   GRAM 0-32   ASCII 94-126  -- ^ _ backtick, a-z, { | } ~
'   GRAM 43     solid block -- the terminal cursor MOB and the grid edit cursor
'   GRAM 44-57  DEC special graphics: box drawing, for ESC ( 0
'   GRAM 33-42, 58-63  spare
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
    CONST GRAM_DEC0   = 44      ' first DEC special-graphics card
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
    IF cw_c > 127 THEN
        ' A DEC special-graphics glyph. vtansi.bas translates the ASCII the
        ' far end sends into 128+n when the G0/G1 charset selects line
        ' drawing, because 128+ is unreachable any other way -- the terminal
        ' drops everything above 126 on the floor.
        #cw_w = (cw_c - 128 + GRAM_DEC0) * 8 + CARD_GRAM
    ELSEIF cw_c < 94 THEN
        #cw_w = (cw_c - 32) * 8                 ' GROM card 0-61
    ELSE
        #cw_w = (cw_c - 94) * 8 + CARD_GRAM     ' GRAM card 0-32
    END IF
    #cw_w = #cw_w + cw_fg + #cw_bgw
END

' ---------------------------------------------------------------------------
' font_load: push the GRAM cards up before anything can display them.
'
' IntyBASIC queues a DEFINE for the next frame's interrupt to execute, and the
' manual puts the ceiling at "approximately 18 cards" per frame, so 48 cards
' need five passes with a WAIT between them. This runs once, at boot, before
' the first CLS.
' ---------------------------------------------------------------------------
font_load: PROCEDURE
    DEFINE 0, 2, glyph_ascii68
    WAIT
    DEFINE 2, 16, glyph_lower
    WAIT
    DEFINE 18, 15, glyph_lower2
    WAIT
    DEFINE GRAM_BLOCK, 1, glyph_block
    WAIT
    DEFINE GRAM_DEC0, 14, glyph_dec
    WAIT
END

glyph_ascii68:
    ' GRAM 0  -- ASCII 94, circumflex. Also lifted rather than drawn: it is the
    ' top three rows of GROM card 10, the asterisk, which is already a caret at
    ' the font's own stroke weight.
    BITMAP "...X...."
    BITMAP "..XXX..."
    BITMAP ".XX.XX.."
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    ' GRAM 1  -- ASCII 95, underscore. This one has no GROM ancestor to copy,
    ' so it is drawn: full width on the bottom row, where the font's own
    ' descenders sit, so that a run of underscores is an unbroken rule. That is
    ' the same choice glyph_dec makes for the DEC horizontal.
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "XXXXXXXX"

glyph_lower:
    ' GRAM 2  -- ASCII 96, backtick
    BITMAP "....X..."
    BITMAP ".....X.."
    BITMAP "......X."
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    ' GRAM 3  -- ASCII 97, lowercase a
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXX.."
    BITMAP "....XX.."
    BITMAP ".XXXXX.."
    BITMAP ".XX.XX.."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 4  -- ASCII 98, lowercase b
    BITMAP ".XXX...."
    BITMAP "..XX...."
    BITMAP "..XXXXX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XXXXX."
    BITMAP "........"
    ' GRAM 5  -- ASCII 99, lowercase c
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".XX..XX."
    BITMAP ".XX....."
    BITMAP ".XX....."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 6  -- ASCII 100, lowercase d
    BITMAP "....XXX."
    BITMAP "....XX.."
    BITMAP ".XXXXX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XXXXX.."
    BITMAP "........"
    ' GRAM 7  -- ASCII 101, lowercase e
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".XX..XX."
    BITMAP ".XXXXXX."
    BITMAP ".XX....."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 8  -- ASCII 102, lowercase f
    BITMAP "........"
    BITMAP "..XXXXX."
    BITMAP "..XX...."
    BITMAP ".XXXXX.."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "........"
    ' GRAM 9  -- ASCII 103, lowercase g
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XXXXX.."
    BITMAP "....XX.."
    BITMAP ".XXXXX.."
    ' GRAM 10 -- ASCII 104, lowercase h
    BITMAP ".XX....."
    BITMAP ".XX....."
    BITMAP ".XXXXX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XXX."
    BITMAP "........"
    ' GRAM 11 -- ASCII 105, lowercase i
    BITMAP "...XX..."
    BITMAP "........"
    BITMAP "..XXX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 12 -- ASCII 106, lowercase j
    BITMAP ".....XX."
    BITMAP "........"
    BITMAP ".....XX."
    BITMAP ".....XX."
    BITMAP ".....XX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XXXXX."
    ' GRAM 13 -- ASCII 107, lowercase k
    BITMAP ".XX....."
    BITMAP ".XX....."
    BITMAP ".XX..XX."
    BITMAP ".XX.XX.."
    BITMAP ".XXXX..."
    BITMAP ".XX..XX."
    BITMAP ".XX..XX."
    BITMAP "........"
    ' GRAM 14 -- ASCII 108, lowercase l
    BITMAP "..XXX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 15 -- ASCII 109, lowercase m
    BITMAP "........"
    BITMAP "........"
    BITMAP "XXXXXXX."
    BITMAP "XX.X.XX."
    BITMAP "XX.X.XX."
    BITMAP "XX.X.XX."
    BITMAP "XX.X.XX."
    BITMAP "........"
    ' GRAM 16 -- ASCII 110, lowercase n
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "........"
    ' GRAM 17 -- ASCII 111, lowercase o
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".XX..XX."
    BITMAP ".XX..XX."
    BITMAP ".XX..XX."
    BITMAP ".XXXXXX."
    BITMAP "........"

glyph_lower2:
    ' GRAM 18 -- ASCII 112, lowercase p
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XXXXX."
    BITMAP "..XX...."
    BITMAP "..XX...."
    ' GRAM 19 -- ASCII 113, lowercase q
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XXXXX.."
    BITMAP "....XX.."
    BITMAP "....XXX."
    ' GRAM 20 -- ASCII 114, lowercase r
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP "..XX.XX."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "........"
    ' GRAM 21 -- ASCII 115, lowercase s
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".XX....."
    BITMAP ".XXXXXX."
    BITMAP ".....XX."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 22 -- ASCII 116, lowercase t
    BITMAP "........"
    BITMAP "..XX...."
    BITMAP ".XXXXXX."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "..XX...."
    BITMAP "..XXXXX."
    BITMAP "........"
    ' GRAM 23 -- ASCII 117, lowercase u
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XX.XX.."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 24 -- ASCII 118, lowercase v
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XX..XX."
    BITMAP ".XX..XX."
    BITMAP ".XX..XX."
    BITMAP "..XXXX.."
    BITMAP "...XX..."
    BITMAP "........"
    ' GRAM 25 -- ASCII 119, lowercase w
    BITMAP "........"
    BITMAP "........"
    BITMAP "XX.X.XX."
    BITMAP "XX.X.XX."
    BITMAP "XX.X.XX."
    BITMAP "XXXXXXX."
    BITMAP ".XX.XX.."
    BITMAP "........"
    ' GRAM 26 -- ASCII 120, lowercase x
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XX..XX."
    BITMAP "..XXXX.."
    BITMAP "...XX..."
    BITMAP "..XXXX.."
    BITMAP ".XX..XX."
    BITMAP "........"
    ' GRAM 27 -- ASCII 121, lowercase y
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XX.XX."
    BITMAP "..XXXXX."
    BITMAP ".....XX."
    BITMAP "..XXXXX."
    ' GRAM 28 -- ASCII 122, lowercase z
    BITMAP "........"
    BITMAP "........"
    BITMAP ".XXXXXX."
    BITMAP ".....XX."
    BITMAP "...XX..."
    BITMAP ".XX....."
    BITMAP ".XXXXXX."
    BITMAP "........"
    ' GRAM 29 -- ASCII 123, left brace
    BITMAP "....XXX."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "..XX...."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....XXX."
    BITMAP "........"
    ' GRAM 30 -- ASCII 124, pipe
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "...XX..."
    ' GRAM 31 -- ASCII 125, right brace
    BITMAP ".XXX...."
    BITMAP "...X...."
    BITMAP "...X...."
    BITMAP "....XX.."
    BITMAP "...X...."
    BITMAP "...X...."
    BITMAP ".XXX...."
    BITMAP "........"
    ' GRAM 32 -- ASCII 126, tilde
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

glyph_dec:
    ' GRAM 44 -- DEC graphics '`', diamond
    BITMAP "........"
    BITMAP "........"
    BITMAP "....X..."
    BITMAP "...X.X.."
    BITMAP "..X...X."
    BITMAP "...X.X.."
    BITMAP "....X..."
    BITMAP "........"
    ' GRAM 45 -- DEC graphics 'a', checkerboard
    BITMAP ".X.X.X.X"
    BITMAP "X.X.X.X."
    BITMAP ".X.X.X.X"
    BITMAP "X.X.X.X."
    BITMAP ".X.X.X.X"
    BITMAP "X.X.X.X."
    BITMAP ".X.X.X.X"
    BITMAP "X.X.X.X."
    ' GRAM 46 -- DEC graphics 'j', lower right corner
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "XXXXX..."
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    ' GRAM 47 -- DEC graphics 'k', upper right corner
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "XXXXX..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    ' GRAM 48 -- DEC graphics 'l', upper left corner
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "....XXXX"
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    ' GRAM 49 -- DEC graphics 'm', lower left corner
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....XXXX"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    ' GRAM 50 -- DEC graphics 'n', cross
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "XXXXXXXX"
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    ' GRAM 51 -- DEC graphics 'q', horizontal
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "XXXXXXXX"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    ' GRAM 52 -- DEC graphics 't', left tee
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....XXXX"
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    ' GRAM 53 -- DEC graphics 'u', right tee
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "XXXXX..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    ' GRAM 54 -- DEC graphics 'v', bottom tee
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "XXXXXXXX"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    ' GRAM 55 -- DEC graphics 'w', top tee
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "XXXXXXXX"
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    ' GRAM 56 -- DEC graphics 'x', vertical
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    BITMAP "....X..."
    ' GRAM 57 -- DEC graphics '~', centre dot
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
    BITMAP "...XX..."
    BITMAP "...XX..."
    BITMAP "........"
    BITMAP "........"
    BITMAP "........"
