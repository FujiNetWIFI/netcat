PRODUCT = nc
PLATFORMS += adam
PLATFORMS += apple2
PLATFORMS += atari
PLATFORMS += c64
PLATFORMS += coco
PLATFORMS += h89-cpm
PLATFORMS += h89-hdos
PLATFORMS += msx
#PLATFORMS += rc2014
PLATFORMS += vic20

# You can run 'make <platform>' to build for a specific platform,
# or 'make <platform>/<target>' for a platform-specific target.
# Example shortcuts:
#   make coco        → build for coco
#   make apple2/disk → build the 'disk' target for apple2

# SRC_DIRS may use the literal %PLATFORM% token.
# It expands to the chosen PLATFORM plus any of its combos.
SRC_DIRS = src src/%PLATFORM%

# FUJINET_LIB can be
# - a version number such as 4.7.6
# - a directory which contains the libs for each platform
# - a zip file with an archived fujinet-lib
# - a URL to a git repo
# - empty which will use whatever is the latest
# - undefined, no fujinet-lib will be used
FUJINET_LIB = https://github.com/FozzTexx/fujinet-lib-experimental.git

# The H89's bus is only in fujinet-lib itself, which has no H89 release
# archive yet, so both H89 builds take it from git.
ifneq ($(filter h89-cpm h89-hdos,$(PLATFORM)),)
  FUJINET_LIB = https://github.com/FujiNetWIFI/fujinet-lib.git
endif

# Some platforms don’t use FUJINET_LIB; set this to allow builds to continue
# even if the library isn’t present.
FUJINET_LIB_OPTIONAL = 1

# Define extra dirs ("combos") that expand with a platform.
# Format: platform+=combo1,combo2
PLATFORM_COMBOS = \
  c64+=commodore \
  atarixe+=atari \
  msxrom+=msx \
  msxdos+=msx \
  h89-cpm+=h89 \
  h89-hdos+=h89

# H89: no stdio or file handles, since src/h89/con.c talks to the console
# itself. The command line stays on: the URL can come from it. -m leaves the
# map beside the program.
H89_LDFLAGS = -m \
  -pragma-define:CRT_ENABLE_STDIO=0 \
  -pragma-define:CLIB_FOPEN_MAX=0 \
  -pragma-define:CLIB_OPEN_MAX=0 \
  -pragma-define:CLIB_EXIT_STACK_SIZE=0
LDFLAGS_EXTRA_H89-CPM = $(H89_LDFLAGS)
LDFLAGS_EXTRA_H89-HDOS = $(H89_LDFLAGS)

include hirestxt-mod-lib.mk
include mekkogx/toplevel-rules.mk

# If you need to add extra platform-specific steps, do it below:
#   coco/r2r:: coco/custom-step1
#   coco/r2r:: coco/custom-step2
# or
#   apple2/disk: apple2/custom-step1 apple2/custom-step2

EXTRA_C_DEPS_COCO = .get_hirestxt_lib

# H89: the program on a 100K H17 data disk.
PRODUCT_UPPER = $(shell echo $(PRODUCT) | tr '[:lower:]' '[:upper:]')
H89_APPMAKE ?= z88dk-appmake

# HDOS: appmake +hdos wants the bare program (the .abs less its 8-byte
# header: FF 00, load, length, entry) and the load address. It names the
# image after the input file and the file on it after -o, hence the cd.
h89-hdos/r2r-post::
	tail -c +9 $(EXECUTABLE) > $(R2R_PD)/$(PRODUCT).bin
	cd $(R2R_PD) && $(H89_APPMAKE) +hdos -b $(PRODUCT).bin \
	  --org $$(od -An -tu2 -j2 -N2 $(notdir $(EXECUTABLE)) | tr -d ' ') -o $(PRODUCT_UPPER)
	rm -f $(R2R_PD)/$(PRODUCT).bin
	@echo "$(R2R_PD)/$(PRODUCT).h8d: MOUNT SY1: then SY1:$(PRODUCT_UPPER) [URL]"

# CP/M: the hz89 format (H17, 40 tracks, 3 boot tracks), then mark the empty
# directory entries appmake leaves zeroed as erased (support/h89).
h89-cpm/r2r-post::
	cd $(R2R_PD) && $(H89_APPMAKE) +cpmdisk -f hz89 --container raw --no-com-file \
	  -b $(notdir $(EXECUTABLE)) -o $(PRODUCT).h8d
	python3 -I support/h89/cpm-dir-fixup.py $(R2R_PD)/$(PRODUCT).h8d
	@echo "$(R2R_PD)/$(PRODUCT).h8d: B:$(PRODUCT_UPPER) [URL]"
