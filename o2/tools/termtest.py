#!/usr/bin/env python3
"""termtest.py -- run test/scen's scenarios against the fixture and check them.

    termtest.py [NAME...]          all of them, or these (test/scen/NAME.scen)

A scenario is a test when its header says what to check:

    # fixture: ARGS     tools/fixture.py's arguments (files in test/data)
    # endpoint: SPEC    the spec to build for (PORT is the fixture's port);
                        N:TCP://127.0.0.1:PORT/ if not given
    # sent: BYTES       a Python bytes literal the fixture must have received
    # screen: TEXT      a line the terminal must show, as tools/screen.py
                        prints it (the last peeks in the scenario)
    # steady: NAME      the burst NAME_* changes in one band at most (the
                        cursor's blink); tools/rowcheck.py
    # spike             the SPIKE build, no fixture

Each runs through test/rig.sh (a private FujiNet); output in build/test/NAME.
"""
import ast
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = int(os.environ.get("FIX_PORT", "2391"))


def header(path):
    h = {"sent": [], "screen": [], "steady": []}
    for line in open(path):
        m = re.match(r"#\s*(fixture|endpoint|sent|screen|steady|spike)\b:?\s?(.*)$", line.rstrip("\n"))
        if not m:
            continue
        k, v = m.group(1), m.group(2)
        if k in ("sent", "screen", "steady"):
            h[k].append(v)
        else:
            h[k] = v
    return h


def build(endpoint, spike):
    key = "spike" if spike else re.sub(r"[^A-Za-z0-9]+", "_", endpoint)
    out = os.path.join(HERE, "build", "img", key)
    env = dict(os.environ, OUT=out, ENDPOINT=endpoint, SPIKE="1" if spike else "0")
    subprocess.run(["./build.sh"], cwd=HERE, env=env, check=True, stdout=subprocess.DEVNULL)
    return os.path.join(out, "nc.bin")


def run(name):
    scen = os.path.join(HERE, "test", "scen", name + ".scen")
    h = header(scen)
    if not ("fixture" in h or "spike" in h):
        return None
    spike = "spike" in h
    endpoint = h.get("endpoint", "N:TCP://127.0.0.1:PORT/").replace("PORT", str(PORT))
    image = build(endpoint, spike)
    out = os.path.join(HERE, "build", "test", name)
    env = dict(os.environ, FIX_PORT=str(PORT))
    if not spike:
        env["FIXTURE"] = h["fixture"]
    r = subprocess.run(["test/rig.sh", scen, out, "60", image], cwd=HERE, env=env,
                       capture_output=True, text=True)
    fails = []
    peeks = [l for l in r.stdout.splitlines() if l.startswith("PEEK")]
    if h["screen"]:
        if len(peeks) < 3:
            fails.append("no peeks for the screen (rig: %s)" % r.stderr.strip()[-200:])
        else:
            s = subprocess.run([sys.executable, os.path.join(HERE, "tools", "screen.py"),
                                os.path.join(os.path.dirname(image), "nc_p0.lst")],
                               input="\n".join(peeks[-3:]), capture_output=True, text=True).stdout
            open(os.path.join(out, "screen.txt"), "w").write(s)
            lines = [l[1:] if l.startswith("|") else l for l in s.splitlines()]
            for want in h["screen"]:
                if want not in lines:
                    fails.append("screen has no line %r" % want)
    if h["sent"]:
        rx = b""
        if os.path.exists(os.path.join(out, "rx")):
            rx = open(os.path.join(out, "rx"), "rb").read()
        for want in h["sent"]:
            b = ast.literal_eval(want)
            if b not in rx:
                fails.append("sent %r, not %r" % (rx, b))
    for burst in h["steady"]:
        s = subprocess.run([sys.executable, os.path.join(HERE, "tools", "rowcheck.py"), out, burst],
                           capture_output=True, text=True).stdout
        bands = set(re.findall(r"y(\d+):", s))
        if not s or len(bands) > 1:
            fails.append("burst %s: %s" % (burst, s.strip().replace("\n", "; ")[:300]))
    return fails


def main(names):
    if not names:
        names = sorted(os.path.basename(p)[:-5] for p in glob.glob(os.path.join(HERE, "test", "scen", "*.scen")))
    bad = 0
    for n in names:
        f = run(n)
        if f is None:
            continue
        print("%-10s %s" % (n, "ok" if not f else "FAIL"))
        for x in f:
            print("    " + x)
        bad += bool(f)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
