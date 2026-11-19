#!/usr/bin/python3
"""Lifecycle checks do not need a browser, certificates, or a network port."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

SUPERVISOR = str(Path(__file__).with_name("test-tls-server.py"))
CHILD = [sys.executable, "-c", "import os,time; print(os.getpid(), flush=True); time.sleep(60)"]


class TLSProcessLifecycleTests(unittest.TestCase):
    def assert_gone(self, pid):
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_stop_reaps_server(self):
        process = subprocess.Popen([sys.executable, SUPERVISOR, str(os.getpid()), "60", *CHILD],
                                   stdout=subprocess.PIPE, text=True)
        try:
            child_pid = int(process.stdout.readline())
            process.terminate()
            process.communicate(timeout=4)
            self.assert_gone(child_pid)
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=4)

    def test_timeout_reaps_server(self):
        process = subprocess.Popen([sys.executable, SUPERVISOR, str(os.getpid()), "0.2", *CHILD],
                                   stdout=subprocess.PIPE, text=True)
        try:
            child_pid = int(process.stdout.readline())
            process.communicate(timeout=4)
            self.assert_gone(child_pid)
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=4)

    def test_parent_interruption_reaps_server(self):
        # Kill the stand-in test runner; the supervisor and its child must
        # close their inherited stdout, then disappear without a teardown.
        launcher = subprocess.Popen([sys.executable, "-c", """
import os, subprocess, sys, time
subprocess.Popen([sys.executable, sys.argv[1], str(os.getpid()), '60', *sys.argv[2:]])
time.sleep(60)
""", SUPERVISOR, *CHILD], stdout=subprocess.PIPE, text=True)
        try:
            child_pid = int(launcher.stdout.readline())
            launcher.terminate()
            launcher.communicate(timeout=4)
            self.assert_gone(child_pid)
        finally:
            if launcher.poll() is None:
                launcher.terminate()
                launcher.communicate(timeout=4)


if __name__ == "__main__":
    unittest.main()
