"""Foreground local preview. Standard library only; no build/install/audio hooks."""
import argparse
import fcntl
import functools
import http.client
import http.server
import json
import os
from pathlib import Path
import socket
import signal
import threading
import time
import sys
import uuid

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "tool/dev_launch.json"
HEALTH = "/__phonopticon/health"


def probe(host, port):
    connection = http.client.HTTPConnection(host, port, timeout=1)
    try:
        connection.request("GET", HEALTH)
        response = connection.getresponse()
        if response.status != 200:
            return None
        return json.loads(response.read(16384))
    except (OSError, ValueError, http.client.HTTPException):
        return None
    finally:
        connection.close()


def identity_matches(live, state, root):
    return bool(live and state and live.get("project") == "phonopticon"
                and live.get("workspace") == str(root)
                and live.get("run_id") == state.get("run_id")
                and live.get("pid") == state.get("pid"))


class PreviewHandler(http.server.SimpleHTTPRequestHandler):
    def safe_path(self):
        base = Path(self.directory)
        target = Path(self.translate_path(self.path))
        try:
            relative = target.relative_to(base)
        except ValueError:
            return False
        current = base
        for component in relative.parts:
            current = current / component
            # lstat/is_symlink inspects the link itself, never its target.
            if current.is_symlink():
                return False
        return True

    def do_GET(self):
        if self.path == HEALTH:
            payload = json.dumps(self.server.identity).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if not self.safe_path():
            self.send_error(403, "Symlinks and paths outside the preview are not served")
            return
        super().do_GET()

    def do_HEAD(self):
        if not self.safe_path():
            self.send_error(403, "Symlinks and paths outside the preview are not served")
            return
        super().do_HEAD()


class PreviewServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def read_state(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def run_server(root, state_dir, port, host="127.0.0.1"):
    if host != "127.0.0.1":
        raise ValueError("Only loopback binding is supported")
    web = root / "build/web"
    if (root / "build").is_symlink() or web.is_symlink():
        print("FAILED dependency: build/web must not be a symlink", flush=True)
        return 2
    for dependency in (web / "index.html", web / "main.dart.js"):
        if dependency.is_symlink() or not dependency.is_file():
            print("FAILED dependency: {}. Build explicitly using README commands; no automatic build.".format(dependency), flush=True)
            return 2
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    state_path = state_dir / "run.json"
    with (state_dir / "launch.lock").open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            live = probe(host, port)
            if identity_matches(live, read_state(state_path), root):
                print("ALREADY RUNNING: verified Phonopticon at http://{}:{}/; reuse its existing foreground iTerm pane. No duplicate started.".format(host, port), flush=True)
                return 0
            print("BUSY: another launcher owns the lock but readiness/identity is not verified. No restart or kill attempted.", flush=True)
            return 3
        handler = functools.partial(PreviewHandler, directory=str(web))
        try:
            server = PreviewServer((host, port), handler)
        except OSError as error:
            print("PORT CONFLICT: {}:{}: {}. Existing listener preserved; no alternate port selected.".format(host, port, error), flush=True)
            return 4
        server.identity = {"project": "phonopticon", "workspace": str(root),
                           "pid": os.getpid(), "run_id": str(uuid.uuid4()),
                           "host": socket.gethostname(), "port": server.server_port}
        state_path.write_text(json.dumps(server.identity, indent=2) + "\n")
        print("STARTING: Phonopticon / local / {} / web preview\nWorkspace: {}\nURL: http://{}:{}/\nLogs: this pane. Ctrl-C stops only this server.".format(socket.gethostname(), root, host, server.server_port), flush=True)
        def report_ready():
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                if identity_matches(probe(host, server.server_port), server.identity, root):
                    print("READY: verified Phonopticon http://{}:{}/".format(host, server.server_port), flush=True)
                    return
                time.sleep(0.05)
            print("FAILED readiness: no matching HTTP health response; inspect this pane.", flush=True)
        threading.Thread(target=report_ready, daemon=True).start()
        try:
            server.serve_forever(poll_interval=0.1)
        except KeyboardInterrupt:
            print("\nStop requested: closing owned foreground server.", flush=True)
        finally:
            server.server_close()
            # Retain metadata for diagnosis; stale PID/run.json is never proof of life.
            print("STOPPED: Phonopticon web preview; host={}; restart via the project iTerm profile.".format(socket.gethostname()), flush=True)
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["serve", "status"])
    args = parser.parse_args()
    config = json.loads(MANIFEST.read_text())
    if config["workspace"] != str(ROOT):
        parser.error("Manifest checkout differs from runtime checkout; update explicitly.")
    process = config["processes"][0]
    host, port = process["bind"], process["host_port"]
    state_dir = Path(config["state_directory"])
    registry = read_state(Path(config["port_registry"]))
    expected = {"project": config["project"], "mode": "local", "bind": host, "port": port, "transport": "tcp/http"}
    if not registry or expected not in registry.get("allocations", []):
        print("FAILED: missing/mismatched port reservation; install the project launch configuration explicitly.")
        return 2
    if args.action == "status":
        if identity_matches(probe(host, port), read_state(state_dir / "run.json"), ROOT):
            print("READY: verified Phonopticon at http://{}:{}/".format(host, port))
            return 0
        print("NOT READY: no verified owned listener at http://{}:{}/; no process changed.".format(host, port))
        return 1
    return run_server(ROOT, state_dir, port, host)


if __name__ == "__main__":
    os.umask(0o077)
    signal.signal(signal.SIGINT, signal.default_int_handler)
    sys.exit(main())
