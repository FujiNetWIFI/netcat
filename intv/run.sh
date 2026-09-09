#!/bin/sh
# run.sh -- build (if needed) and launch netcat in the FujiNet-patched
# jzIntv, connected to a real fujinet-firmware instance over BoIP.
#
# Override any of these on the command line, e.g.:
#   JZINTV=/path/to/jzintv FUJINET_TARGET=localhost:9995 ./run.sh
#   ./run.sh --fujinet-debug        # extra flags are passed straight to jzintv
#   ECS=0 ./run.sh                  # controller-only, to test the fallback
#
# The ECS keyboard is emulated by default (ECS=1, needs ecs.bin). IMPORTANT:
# jzIntv boots with the host keyboard acting as hand controllers, so nothing
# you type reaches the ECS matrix until you press F7, which switches to keymap
# 2 -- the ECS keyboard. F5 switches back. Without that the keyboard support
# looks broken when it isn't.

set -e

cd "$(dirname "$0")"
SDL_AUDIODRIVER=pulseaudio
JZINTV_DIR=${JZINTV_DIR:-$HOME/Workspace/jzintv-20200712-src}
# The build tree puts the binary under bin/<platform>/; fall back to bin/ for
# installs that flatten it.
if [ -z "${JZINTV:-}" ]; then
    if [ -x "$JZINTV_DIR/bin/linux/jzintv" ]; then
        JZINTV=$JZINTV_DIR/bin/linux/jzintv
    else
        JZINTV=$JZINTV_DIR/bin/jzintv
    fi
fi
EXEC_BIN=${EXEC_BIN:-$JZINTV_DIR/rom/exec.bin}
GROM_BIN=${GROM_BIN:-$JZINTV_DIR/rom/grom.bin}
FUJINET_TARGET=${FUJINET_TARGET:-localhost:9995}
ECS=${ECS:-1}
ECS_BIN=${ECS_BIN:-$JZINTV_DIR/rom/ecs.bin}

if [ ! -x "$JZINTV" ]; then
    echo "jzIntv not found or not executable at: $JZINTV" >&2
    echo "Set JZINTV_DIR or JZINTV to point at your FujiNet-patched jzIntv build." >&2
    exit 1
fi
if [ ! -f "$EXEC_BIN" ] || [ ! -f "$GROM_BIN" ]; then
    echo "Missing EXEC/GROM BIOS images:" >&2
    echo "  EXEC_BIN=$EXEC_BIN" >&2
    echo "  GROM_BIN=$GROM_BIN" >&2
    exit 1
fi

# Rebuild only if the ROM is missing or a source file changed since it was
# last built.
if [ ! -f netcat.rom ] || [ -n "$(find . -maxdepth 1 -name '*.bas' -newer netcat.rom)" ]; then
    echo "Building netcat.rom..."
    make
fi

ECS_ARGS=""
if [ "$ECS" = "1" ]; then
    if [ -f "$ECS_BIN" ]; then
        ECS_ARGS="-s1 -E $ECS_BIN"
        echo "ECS keyboard enabled -- press F7 in jzIntv to type on it."
    else
        echo "ECS ROM not found at $ECS_BIN; running controller-only." >&2
        echo "Set ECS_BIN, or ECS=0 to silence this." >&2
    fi
fi

echo "Launching jzIntv against FujiNet at $FUJINET_TARGET ..."
# shellcheck disable=SC2086  # ECS_ARGS is deliberately word-split
exec "$JZINTV" \
    -z 4 \
    -e "$EXEC_BIN" \
    -g "$GROM_BIN" \
    --fujinet="$FUJINET_TARGET" \
    $ECS_ARGS \
    "$@" \
    netcat.rom
