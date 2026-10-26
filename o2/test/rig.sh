#!/usr/bin/env bash
# rig.sh -- a private FujiNet (and far end) for a live run, then a scenario.
#
#   test/rig.sh SCENARIO OUTDIR [SECS [IMAGE]]
#
# Starts a private copy of fujinet-pc-rs232 with its BoIP listener on BOIP
# (19975) and, when FIXTURE is set, tools/fixture.py on FIX_PORT (2391) with
# FIXTURE as its arguments (files relative to test/; its log in OUTDIR/rx).
# Then runs tools/o2sim.py on SCENARIO against it, throttled: the network is
# wall time. Kills only what it started; never the everyday fujinet-pc on
# 9995.
#
# The image has to dial the fixture: ENDPOINT=N:TCP://127.0.0.1:2391/
# ./build.sh. With no FIXTURE it dials whatever it was built for.
set -euo pipefail
cd "$(dirname "$0")/.."
HERE=$(pwd)
SCEN=$1
OUT=$(realpath -m "$2")
SECS=${3:-60}
BOIP=${BOIP:-19975}
FIX_PORT=${FIX_PORT:-2391}
FNPC_DIST=${FNPC_DIST:-$HOME/Workspace/fujinet-pc-rs232/build/dist}
RIG="$HERE/build/rig$BOIP"

pids=()
cleanup() {
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
}
trap cleanup EXIT

mkdir -p "$OUT"
if [ -n "${FIXTURE:-}" ]; then
    rm -f "$OUT/rx"
    # shellcheck disable=SC2086
    ( cd test && exec python3 ../tools/fixture.py --port "$FIX_PORT" --log "$OUT/rx" $FIXTURE ) \
        > "$OUT/fixture.log" 2>&1 &
    pids+=($!)
fi

# the last run's FujiNet may not have let go of the port yet
for _ in $(seq 40); do
    ss -ltn | grep -q ":$BOIP " || break
    sleep 0.25
done
if ss -ltn | grep -q ":$BOIP "; then echo "rig: BoIP port $BOIP is taken" >&2; exit 1; fi

rm -rf "$RIG"; mkdir -p "$RIG"
# the binary by link, the rest copied: its config is ours to change
ln -s "$FNPC_DIST/fujinet" "$RIG/fujinet"
cp -a "$FNPC_DIST/data" "$FNPC_DIST/fnconfig.ini" "$RIG"/
mkdir -p "$RIG/SD"
python3 - "$RIG/fnconfig.ini" "$BOIP" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
s = re.sub(r"(\[BOIP\][^\[]*?\bport=)\d*", r"\g<1>" + sys.argv[2], s, flags=re.S)
s = re.sub(r"(\[BOIP\][^\[]*?\benabled=)\d*", r"\g<1>1", s, flags=re.S)
open(sys.argv[1], "w").write(s)
PY
( cd "$RIG" && exec ./fujinet -u http://127.0.0.1:$((BOIP - 10000)) -c fnconfig.ini -s SD ) \
    > "$OUT/fn.log" 2>&1 &
pids+=($!)
for _ in $(seq 20); do
    ss -ltn | grep -q ":$BOIP " && break
    sleep 0.25
done
if ! ss -ltn | grep -q ":$BOIP "; then echo "rig: no BoIP listener on $BOIP" >&2; exit 1; fi

O2SIM_FUJINET="127.0.0.1:$BOIP" O2SIM_SECONDS=$SECS \
    python3 tools/o2sim.py "$SCEN" "$OUT" "${@:4}"
