"""Bounded loopback-only tests. Own temp files/children only; no Flutter or installs."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest

MODULE = Path(__file__).with_name("dev_server.py")
spec = importlib.util.spec_from_file_location("preview", MODULE)
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)
ENTRY = "import sys,signal; from pathlib import Path; sys.path.insert(0,sys.argv[1]); import dev_server; signal.signal(signal.SIGINT,signal.default_int_handler); sys.exit(dev_server.run_server(Path(sys.argv[2]),Path(sys.argv[3]),int(sys.argv[4])))"


class LaunchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="phonopticon-launch-test-")
        self.root = Path(self.temp.name) / "checkout with spaces"
        self.web = self.root / "build/web"
        self.web.mkdir(parents=True)
        (self.web / "index.html").write_text("fixture preview")
        (self.web / "main.dart.js").write_text("// fixture")
        self.state = Path(self.temp.name) / "state"
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.send_signal(signal.SIGINT)
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()  # Only the exact subprocess created by this test.
                    child.wait(timeout=3)
            if child.stdout is not None:
                child.stdout.close()
        self.temp.cleanup()

    def start(self, port=0, state=None):
        child = subprocess.Popen([sys.executable, "-B", "-c", ENTRY, str(MODULE.parent),
                                  str(self.root), str(state or self.state), str(port)],
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, start_new_session=True)
        self.children.append(child)
        return child

    def ready(self):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            state = preview.read_state(self.state / "run.json")
            if state and preview.identity_matches(preview.probe("127.0.0.1", state["port"]), state, self.root):
                return state
            time.sleep(0.03)
        self.fail("Owned test server did not become ready")

    def test_start_duplicate_stop_and_stale_metadata(self):
        child = self.start()
        state = self.ready()
        duplicate = self.start(state["port"])
        output, _ = duplicate.communicate(timeout=3)
        self.assertEqual(duplicate.returncode, 0)
        self.assertIn("ALREADY RUNNING", output)
        self.assertIsNone(child.poll())
        child.send_signal(signal.SIGINT)
        output, _ = child.communicate(timeout=3)
        self.assertEqual(child.returncode, 0)
        self.assertIn("READY:", output)
        self.assertIn("STOPPED:", output)
        self.assertIsNone(preview.probe("127.0.0.1", state["port"]))
        self.assertTrue((self.state / "run.json").exists())
        self.assertFalse(preview.identity_matches(None, state, self.root))

    def test_occupied_port_preserved(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            port = listener.getsockname()[1]
            child = self.start(port)
            output, _ = child.communicate(timeout=3)
            self.assertEqual(child.returncode, 4)
            self.assertIn("PORT CONFLICT", output)
            self.assertEqual(listener.getsockname()[1], port)

    def test_missing_dependency(self):
        (self.web / "main.dart.js").unlink()  # Test-owned fixture only.
        child = self.start()
        output, _ = child.communicate(timeout=3)
        self.assertEqual(child.returncode, 2)
        self.assertIn("FAILED dependency", output)

    def test_identity_mismatch_not_reused(self):
        self.assertFalse(preview.identity_matches({"project": "other"}, {"pid": os.getpid()}, self.root))

    def test_served_symlink_cannot_escape(self):
        outside = Path(self.temp.name) / "outside.txt"
        outside.write_text("not served")
        (self.web / "escape.txt").symlink_to(outside)
        self.start()
        state = self.ready()
        connection = preview.http.client.HTTPConnection("127.0.0.1", state["port"], timeout=1)
        connection.request("GET", "/escape.txt")
        self.assertEqual(connection.getresponse().status, 403)
        connection.close()


if __name__ == "__main__":
    os.umask(0o077)
    unittest.main()
