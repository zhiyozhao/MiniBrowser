#!/usr/bin/python3
"""Own the TLS child even if the Swift test process crashes or is interrupted."""
import os
import signal
import subprocess
import sys
import time


def supervise(parent_pid, lifetime, command):
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    child = subprocess.Popen(command, start_new_session=True)
    deadline = time.monotonic() + lifetime
    try:
        while child.poll() is None and not stopping:
            if os.getppid() != parent_pid or time.monotonic() >= deadline:
                break
            time.sleep(0.1)
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
        child.wait()


if __name__ == "__main__":
    if sys.argv[1] == "serve":
        import http.server
        import ssl

        server = http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])),
                                                 http.server.SimpleHTTPRequestHandler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(sys.argv[3], sys.argv[4])
        server.socket = context.wrap_socket(server.socket, server_side=True)
        try:
            server.serve_forever()
        finally:
            server.server_close()
    else:
        supervise(int(sys.argv[1]), float(sys.argv[2]), sys.argv[3:])
