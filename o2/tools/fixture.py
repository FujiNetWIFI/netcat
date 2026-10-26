#!/usr/bin/env python3
"""fixture.py -- the far end for netcat/nes's headless tests.

Listens on 127.0.0.1:PORT and, for each connection, plays the given files
in order (raw bytes: ANSI escapes and all). With --echo it also sends back
whatever arrives, the way a remote shell's line discipline would. Every byte
received is appended to --log, so a test can check what the terminal sent:
keys, arrow sequences, DSR/DA answers. After --hold seconds it hangs up.

    fixture.py [--port 2323] [--log FILE] [--hold SECS] [--echo] FILE...

A file named "-" is a pause of half a second, for tests that look at the
screen between two parts.
"""

import argparse
import socket
import sys
import threading
import time


def serve(conn, files, log, hold, echo_on):
    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    stop = threading.Event()

    def echo():
        conn.settimeout(0.2)
        while not stop.is_set():
            try:
                b = conn.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                return
            if not b:
                return
            if log:
                with open(log, "ab") as f:
                    f.write(b)
            if not echo_on:
                continue
            try:
                conn.sendall(b)
            except OSError:
                return

    t = threading.Thread(target=echo, daemon=True)
    t.start()
    for name in files:
        if name == "-":
            time.sleep(0.5)
            continue
        with open(name, "rb") as f:
            data = f.read()
        conn.sendall(data)
    time.sleep(hold)
    stop.set()
    conn.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=2323)
    ap.add_argument("--log")
    ap.add_argument("--hold", type=float, default=3600)
    ap.add_argument("--echo", action="store_true")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", a.port))
    s.listen(4)
    print("fixture: listening on %d" % a.port, file=sys.stderr, flush=True)
    while True:
        conn, _ = s.accept()
        threading.Thread(target=serve, args=(conn, a.files, a.log, a.hold, a.echo),
                         daemon=True).start()


if __name__ == "__main__":
    main()
