#!/bin/sh
# tools/screendump.sh -- run the ROM headless and print what is on the screen.
#
# There is no way to look at a television from a script, but jzIntv's debugger
# can: --script runs a fixed number of cycles and then dumps memory, and BACKTAB
# decodes back into characters and colours. That makes the terminal's rendering
# testable without a human in the loop, which matters for a program whose whole
# job is putting the right glyph in the right cell.
#
#   tools/screendump.sh [cycles]     cycles default ~3.3s of emulated time
#   ECS=1 tools/screendump.sh        with the ECS keyboard attached
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
CYCLES=${1:-3000000}
JZINTV_DIR=${JZINTV_DIR:-$HOME/Workspace/jzintv-20200712-src}
JZINTV=${JZINTV:-$JZINTV_DIR/bin/linux/jzintv}
FUJINET_TARGET=${FUJINET_TARGET:-localhost:9995}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
printf 'r %d\nd\nq\n' "$CYCLES" > "$WORK/script"

ECS_ARGS=""
[ "${ECS:-0}" = "1" ] && ECS_ARGS="-s1 -E $JZINTV_DIR/rom/ecs.bin"

# The debugger writes dump.mem into the current directory, so run there.
( cd "$WORK" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    timeout 120 "$JZINTV" -q -d --script=script \
      -e "$JZINTV_DIR/rom/exec.bin" -g "$JZINTV_DIR/rom/grom.bin" \
      --fujinet="$FUJINET_TARGET" $ECS_ARGS \
      "$ROOT/netcat.rom" >log 2>&1 ) || true

[ -f "$WORK/dump.mem" ] || { echo "no dump.mem -- jzIntv output:"; cat "$WORK/log"; exit 1; }
python3 tools/decode_backtab.py "$WORK/dump.mem"
