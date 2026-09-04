"""echosrv.py -- the local target for `make echotest`.

Sends a banner long enough to scroll the 13-row pane several times over, then
a handful of escape and control sequences that must NOT reach the screen, then
echoes whatever it is sent back line by line. Between them those cover the
three things no remote host can be relied on to exercise on demand: the
scroll, the terminal's control handling, and NET_WRITE.

    python3 emu/echosrv.py &
    ENDPOINT=N:TCP://127.0.0.1:4242/ ./build.sh
    make echotest

Expected on screen, once the banner has scrolled past line 40:

    CSI ok          the \\x1b[1;32m ... \\x1b[0m wrapper was swallowed
    charset ok      the \\x1b(B selector was swallowed
    tab:    X       the tab advanced to column 8
    bs:AC           the B was backspaced over and replaced

and, after the composer sends ABC, `you said [ABC]`.
"""

import socket, threading, time

def log(*a):
    print("%.2f" % time.time(), *a, flush=True)

def serve(c):
    log("CONNECT")
    c.sendall(b"netcat scroll test\r\n")
    for i in range(1, 41):
        c.sendall(("line %02d abcdefghijklmnopqrstuvwxyz\r\n" % i).encode())
    # control and escape handling: none of the escapes should reach the screen
    c.sendall(b"\x1b[1;32mCSI ok\x1b[0m\r\n")
    c.sendall(b"\x1b(Bcharset ok\r\n")
    c.sendall(b"tab:\tX\r\n")
    c.sendall(b"bs:AB\bC\r\n")
    c.sendall(b"echo> ")
    buf = b""
    try:
        while True:
            d = c.recv(64)
            if not d:
                break
            log("RAW", repr(d))
            buf += d
            while b"\n" in buf:
                ln, buf = buf.split(b"\n", 1)
                log("LINE", repr(ln))
                c.sendall(b"you said [" + ln.strip() + b"]\r\necho> ")
    except OSError as e:
        log("ERR", e)
    log("CLOSE")
    c.close()

s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 4242))
s.listen(5)
log("echosrv on 4242")
while True:
    c, _ = s.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
