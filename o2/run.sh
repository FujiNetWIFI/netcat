#!/usr/bin/env bash
# run.sh -- netcat in MAME's Odyssey 2 with the FujiNet cart, in a window,
# against a live fujinet-pc.
#
#   ./run.sh                          build/nc.bin (built if missing)
#   ./run.sh path/to/image.bin        another image (more MAME options after it)
#   ENDPOINT=N:TCP://host:port/ ./run.sh   rebuild for that host first
#
# Needs ~/Workspace/mame (MAME_DIR) with the O2 FujiNet cart device grafted in
# (fujinet-firmware PR #2177, pico/o2/emu/apply-mame.sh: protocol 2, the
# APPBANK pages) and a fujinet-pc BoIP listener on FUJINET_TCP (default
# 127.0.0.1:9995).
#
# MAME's keys: letters, digits, Space, Enter (ENT), Backspace (CLR); Y and N
# are YES and NO; the console's ? is the / key, its * and / the keypad's.
# The arrow keys are the stick, Left Ctrl its button, F1 the console's RESET.
#
# MAME runs from its own tree, so every path here is absolute.
set -euo pipefail
cd "$(dirname "$0")"
HERE="$PWD"

MAME_DIR="${MAME_DIR:-$HOME/Workspace/mame}"
export FUJINET_TCP="${FUJINET_TCP:-127.0.0.1:9995}"
IMAGE="${1:-$HERE/build/nc.bin}"
[ "${IMAGE#/}" = "$IMAGE" ] && IMAGE="$HERE/$IMAGE"

if [ -n "${ENDPOINT:-}" ] || [ ! -f build/nc.bin ]; then
    ./build.sh
fi
[ -f "$IMAGE" ] || { echo "run.sh: no $IMAGE" >&2; exit 1; }
[ -x "$MAME_DIR/mame" ] || { echo "run.sh: no MAME at $MAME_DIR" >&2; exit 1; }

mkdir -p "$HERE/build/snap" "$HERE/build/cfg"
cd "$MAME_DIR"
exec ./mame odyssey2 -cartslot fujinet -cart "$IMAGE" \
    -snapshot_directory "$HERE/build/snap" -cfg_directory "$HERE/build/cfg" \
    -window -nomax "${@:2}"
