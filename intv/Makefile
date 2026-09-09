# intv/Makefile -- IntyBASIC build for the Intellivision netcat.
#
# Standalone rather than wired into the root Makefile, same as the other
# IntyBASIC FujiNet clients (fujinet-5cardstud/intv et al.): the root build
# (mekkogx) drives cc65/cmoc-family C toolchains for the other platforms,
# and IntyBASIC/as1600 is a different toolchain entirely.
#
# Override INTYBASIC/AS1600/LIBDIR on the command line if your tools
# aren't on PATH, e.g.:
#   make INTYBASIC=/path/to/intybasic LIBDIR=/path/to/IntyBASIC/intybasic

INTYBASIC ?= intybasic
AS1600    ?= as1600
LIBDIR    ?= $(HOME)/Workspace/IntyBASIC/intybasic/

PRODUCT = netcat
SOURCES = netcat.bas fujinet.bas kbd.bas ecskbd.bas ecskbd.asm

.PHONY: all clean run

all: $(PRODUCT).bin $(PRODUCT).rom

$(PRODUCT).asm: $(SOURCES)
	$(INTYBASIC) netcat.bas $(PRODUCT).asm $(LIBDIR)

# .bin + .cfg -- for loading from SD via the cartridge menu.
$(PRODUCT).bin: $(PRODUCT).asm
	$(AS1600) -o $(PRODUCT).bin -l $(PRODUCT).lst $(PRODUCT).asm

# .rom -- Intellicart format, for jzIntv and network boot.
$(PRODUCT).rom: $(PRODUCT).asm
	$(AS1600) -o $(PRODUCT).rom $(PRODUCT).asm

run: $(PRODUCT).rom
	./run.sh

clean:
	rm -f $(PRODUCT).asm $(PRODUCT).bin $(PRODUCT).cfg $(PRODUCT).rom $(PRODUCT).lst
