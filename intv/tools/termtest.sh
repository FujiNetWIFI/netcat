#!/bin/sh
# tools/termtest.sh -- dial a URL and print the screen, without a human.
#
# The ROM normally waits at the URL screen for someone to press OK, which a
# script cannot do. So this builds a throwaway copy in a temporary directory
# with two edits -- the devicespec replaced, and the URL screen skipped -- runs
# it headless under jzIntv's debugger, and decodes BACKTAB. The repository
# sources are never touched.
#
#   tools/termtest.sh 'N:TCP://127.0.0.1:2323/' [cycles]
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
URL=${1:?usage: termtest.sh <devicespec> [cycles]}
CYCLES=${2:-6000000}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp *.bas *.asm "$WORK/" 2>/dev/null || true
mkdir -p "$WORK/lib" && cp lib/*.asm "$WORK/lib/"
rm -f "$WORK/netcat.asm"

python3 - "$WORK/netcat.bas" "$URL" <<'PY'
import pathlib, re, sys
path, url = sys.argv[1], sys.argv[2]
p = pathlib.Path(path); s = p.read_text()
i, j = s.index("lit_spec:"), s.index("CONST LEN_SPEC")
s = s[:i] + "lit_spec:\n    DATA " + ",".join(str(ord(c)) for c in url) + "\n    " + s[j:]
s = re.sub(r"CONST LEN_SPEC = \d+", "CONST LEN_SPEC = %d" % len(url), s)
s = s.replace("dial:\n    GOSUB url_screen", "dial:\n    ' url_screen skipped by tools/termtest.sh")
p.write_text(s)
PY

( cd "$WORK" && intybasic netcat.bas netcat.asm ./lib/ >/dev/null 2>&1 \
    && as1600 -o netcat.rom -l netcat.lst netcat.asm >/dev/null 2>&1 ) \
  || { echo "test build failed"; ( cd "$WORK" && intybasic netcat.bas netcat.asm ./lib/ ); exit 1; }

JZINTV_DIR=${JZINTV_DIR:-$HOME/Workspace/jzintv-20200712-src}
printf 'r %d\nd\nq\n' "$CYCLES" > "$WORK/script"
( cd "$WORK" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    timeout 180 "${JZINTV:-$JZINTV_DIR/bin/linux/jzintv}" -q -d --script=script \
      -e "$JZINTV_DIR/rom/exec.bin" -g "$JZINTV_DIR/rom/grom.bin" \
      --fujinet="${FUJINET_TARGET:-localhost:9995}" \
      ${ECS:+-s1 -E "$JZINTV_DIR/rom/ecs.bin"} netcat.rom >log 2>&1 ) || true

[ -f "$WORK/dump.mem" ] || { echo "no dump.mem:"; cat "$WORK/log"; exit 1; }
echo "  url: $URL   cycles: $CYCLES"
python3 "$ROOT/tools/decode_backtab.py" "$WORK/dump.mem" ${VERBOSE:+"$WORK/netcat.lst"}
