# netcat for the Bally Astrocade. Standalone, outside mekkogx, in the
# battleship/fujitzee mold: the build is build.sh (zmac + the layout checks),
# this file is the convenience wrapper.

SRCS := nc.asm HVGLIB.H fujinet.inc fujilib.inc $(wildcard *.inc) \
        assets/font.inc

all: build/nc.bin

build/nc.bin: $(SRCS) build.sh tools/checkrom.py tools/checksize.py
	./build.sh

run: build/nc.bin
	./run.sh

# Regenerate the font from the Lynx 4x6 art plus this port's hand-drawn
# lowercase. The output is committed; only art changes need this.
LYNX ?= $(HOME)/Workspace/fujinet-5cardstud/src/lynx/4x6
assets:
	LYNX=$(LYNX) python3 tools/mkfont.py

MAME_DIR ?= $(HOME)/Workspace/mame

# Headless end-to-end test: launch, accept the default devicespec, let the
# BBS banner arrive and scroll, then snapshot. Needs a running fujinet-pc
# (BoIP on 127.0.0.1:9995) and a reachable endpoint.
smoke: build/nc.bin
	rm -rf build/astrocde
	FUJINET_DEBUG=$${FUJINET_DEBUG:-1} $(MAME_DIR)/mame astrocde \
	    -rompath $(MAME_DIR)/roms \
	    -cartslot fujinet -cart $(CURDIR)/build/nc.bin \
	    -autoboot_script emu/smoke.lua -video none -sound none \
	    -seconds_to_run 60 -snapshot_directory $(CURDIR)/build
	@ls build/astrocde/

# The write path and the terminal's control handling, against a local server
# rather than whatever a BBS happens to send. Start emu/echosrv.py first and
# build with ENDPOINT=N:TCP://127.0.0.1:4242/ -- see that file's docstring.
echotest: build/nc.bin
	rm -rf build/astrocde
	FUJINET_DEBUG=$${FUJINET_DEBUG:-1} $(MAME_DIR)/mame astrocde \
	    -rompath $(MAME_DIR)/roms \
	    -cartslot fujinet -cart $(CURDIR)/build/nc.bin \
	    -autoboot_script emu/compose.lua -video none -sound none \
	    -seconds_to_run 32 -snapshot_directory $(CURDIR)/build
	@ls build/astrocde/

# Console RESET must not restart the mailbox sequence numbering.
resettest: build/nc.bin
	FUJINET_DEBUG=1 $(MAME_DIR)/mame astrocde \
	    -rompath $(MAME_DIR)/roms \
	    -cartslot fujinet -cart $(CURDIR)/build/nc.bin \
	    -autoboot_script emu/resettest.lua -video none -sound none \
	    -seconds_to_run 40

clean:
	rm -rf build

.PHONY: all run smoke echotest resettest clean assets
