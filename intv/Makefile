# intv/Makefile -- IntyBASIC build for the Intellivision netcat.
#
# Standalone rather than wired into the root Makefile, same as the other
# IntyBASIC FujiNet clients (fujinet-5cardstud/intv et al.): the root build
# (mekkogx) drives cc65/cmoc-family C toolchains for the other platforms,
# and IntyBASIC/as1600 is a different toolchain entirely.
#
# LIBDIR points at lib/, which vendors the IntyBASIC *1.4.2* prologue and
# epilogue. Do not point it at an IntyBASIC checkout: 1.5.x ships an epilogue
# whose `IF intybasic_scroll` / `IF intybasic_col` guards the 1.4.2 compiler
# never emits, which silently moves the 16-bit variable ceiling and changes
# the RAM map out from under the equates in netcat.bas.
#
# Override INTYBASIC/AS1600/LIBDIR on the command line if your tools
# aren't on PATH, e.g.:
#   make INTYBASIC=/path/to/intybasic

INTYBASIC ?= intybasic
AS1600    ?= as1600
LIBDIR    ?= ./lib/

PRODUCT = netcat
SOURCES = netcat.bas fujinet.bas kbd.bas ecskbd.bas ecskbd.asm \
          lib/intybasic_prologue.asm lib/intybasic_epilogue.asm

.PHONY: all clean run guard

all: $(PRODUCT).bin $(PRODUCT).rom guard

$(PRODUCT).asm: $(SOURCES)
	$(INTYBASIC) netcat.bas $(PRODUCT).asm $(LIBDIR)

# .bin + .cfg -- for loading from SD via the cartridge menu.
$(PRODUCT).bin: $(PRODUCT).asm
	$(AS1600) -o $(PRODUCT).bin -l $(PRODUCT).lst $(PRODUCT).asm

# .rom -- Intellicart format, for jzIntv and network boot.
$(PRODUCT).rom: $(PRODUCT).asm
	$(AS1600) -o $(PRODUCT).rom $(PRODUCT).asm

# guard -- the three silent overflows this program can hit. IntyBASIC checks
# none of them: it reports "of 47 available" 16-bit variables from a table that
# does not match the vendored epilogue, and it happily continues ROM past the
# end of a mapped segment.
#
#   _SYSTEM  > $322   16-bit vars have run into _scroll_buffer and the MOB
#                     shadow -- shows up as random sprite/screen corruption.
#   _SCRATCH > $1EF   8-bit vars have run into the PSG at $01F0.
#   $7000/$E000 in the .cfg -- code spilled out of $5000-$6FFF or $D000-$DFFF
#                     into an unmapped segment. Boots, then dies two
#                     instructions later in unprogrammed GROM.
guard: $(PRODUCT).lst $(PRODUCT).cfg
	@awk '/_SYSTEM:[ \t]*EQU/  { n = strtonum($$1); if (n > 803) { printf "GUARD: 16-bit vars overflow -- _SYSTEM=%s (max 0x323)\n", $$1; exit 1 } print "  16-bit vars end at " $$1 " (limit 0x323)" }' $(PRODUCT).lst
	@awk '/_SCRATCH:[ \t]*EQU/ { n = strtonum($$1); if (n > 495) { printf "GUARD: 8-bit vars overflow -- _SCRATCH=%s (max 0x1EF)\n", $$1; exit 1 } print "  8-bit vars end at " $$1 " (limit 0x1EF)" }' $(PRODUCT).lst
	@if grep -qE '= \$$(7000|E000)' $(PRODUCT).cfg; then \
	    echo "GUARD: ROM spilled into an unmapped segment:"; grep -E '= \$$(7000|E000)' $(PRODUCT).cfg; exit 1; fi
	@grep -E '^\$$' $(PRODUCT).cfg | sed 's/^/  rom: /'

$(PRODUCT).cfg: $(PRODUCT).bin
$(PRODUCT).lst: $(PRODUCT).bin

run: $(PRODUCT).rom
	./run.sh

clean:
	rm -f $(PRODUCT).asm $(PRODUCT).bin $(PRODUCT).cfg $(PRODUCT).rom $(PRODUCT).lst
