"""Pool of headless Godot workers (scripts/ai/rl_worker.gd), one TCP connection each.

A call sends one batch to every worker and waits for all replies, so the
workers run their games in parallel while Python does the network inference.
A worker that dies or stops answering raises WorkerDied; restart(w) starts a
fresh process in its place (its games are lost, the caller drops them).
"""
import atexit
import json
import os
import socket
import struct
import subprocess
import time

from cw_data import ROOT

GODOT_BIN = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
WORKER_SCRIPT = "res://scripts/ai/rl_worker.gd"


def high_qos(pid):
    """Opts a process out of Windows power throttling (EcoQoS). Without it Windows 11
    keeps windowless background work on the efficiency cores once somebody uses the
    PC (on a 12700KF: 4 E-cores busy, 8 P-cores idle, training 3-4x slower)."""
    if os.name != "nt":
        return
    import ctypes

    class State(ctypes.Structure):
        _fields_ = [("Version", ctypes.c_ulong), ("ControlMask", ctypes.c_ulong), ("StateMask", ctypes.c_ulong)]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    handle = kernel32.OpenProcess(0x0200, False, pid)          # PROCESS_SET_INFORMATION
    if not handle:
        return
    # ProcessPowerThrottling: execution speed and timer resolution not throttled.
    state = State(1, 0x1 | 0x4, 0)
    kernel32.SetProcessInformation(handle, 4, ctypes.byref(state), ctypes.sizeof(state))
    kernel32.CloseHandle(handle)


class WorkerDied(RuntimeError):
    def __init__(self, w, reason):
        super().__init__(f"worker {w}: {reason}")
        self.w = w


def _frame(obj):
    """4-byte little-endian length, then the JSON body."""
    body = json.dumps(obj).encode("utf-8")
    return struct.pack("<I", len(body)) + body


class WorkerPool:
    def __init__(self, n_workers, slots, log_dir, base_port=25000, godot=GODOT_BIN, timeout=180.0):
        self.n_workers = n_workers
        self.slots = slots
        self.log_dir = log_dir
        self.base_port = base_port
        self.godot = godot
        self.timeout = timeout          # seconds a worker may take for one batch
        self.restarts = [0] * n_workers
        self.socks = [None] * n_workers
        self.files = [None] * n_workers
        self.procs = [None] * n_workers
        os.makedirs(log_dir, exist_ok=True)
        high_qos(os.getpid())
        for w in range(n_workers):
            self._spawn(w)
        for w in range(n_workers):
            self._attach(w)
        atexit.register(self.close)

    def _port(self, w):
        # A restarted worker gets a port of its own, so it never waits for the old one to be freed.
        return self.base_port + w + self.n_workers * self.restarts[w]

    def _spawn(self, w):
        mode = "a" if self.restarts[w] else "w"
        log = open(os.path.join(self.log_dir, f"worker_{w}.log"), mode, encoding="utf-8")
        cmd = [self.godot, "--headless", "--path", ROOT, "-s", WORKER_SCRIPT,
               "--", "--port", str(self._port(w)), "--slots", str(self.slots)]
        self.procs[w] = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
        high_qos(self.procs[w].pid)
        log.close()

    def _attach(self, w):
        sock = self._connect(self._port(w))
        sock.settimeout(self.timeout)
        self.socks[w] = sock
        self.files[w] = sock.makefile("rb")

    def _connect(self, port, timeout=60.0):
        deadline = time.time() + timeout
        while True:
            try:
                sock = socket.create_connection(("127.0.0.1", port), timeout=timeout)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                return sock
            except OSError:
                if time.time() > deadline:
                    raise RuntimeError(f"Godot worker on port {port} did not start")
                time.sleep(0.2)

    def restart(self, w):
        """Replaces worker w with a fresh process (all its games are gone)."""
        try:
            self.socks[w].close()
        except OSError:
            pass
        proc = self.procs[w]
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        self.restarts[w] += 1
        self._spawn(w)
        self._attach(w)

    def send(self, w, items):
        """Starts a batch on worker w. Reply it with recv(w), before the next send(w)."""
        try:
            self.socks[w].sendall(_frame({"slots": items}))
        except OSError as e:
            raise WorkerDied(w, f"send failed: {e}") from e

    def recv(self, w):
        try:
            head = self.files[w].read(4)
            if len(head) < 4:
                raise WorkerDied(w, "closed the connection")
            size = struct.unpack("<I", head)[0]
            body = self.files[w].read(size)
            if len(body) < size:
                raise WorkerDied(w, "closed the connection")
        except OSError as e:          # includes the socket timeout
            raise WorkerDied(w, f"no answer: {e}") from e
        return json.loads(body.decode("utf-8"))["r"]

    def close(self):
        for sock in self.socks:
            if sock is None:
                continue
            try:
                sock.sendall(_frame({"cmd": "close"}))
                sock.close()
            except OSError:
                pass
        self.socks = [None] * self.n_workers
        for proc in self.procs:
            if proc is None:
                continue
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        self.procs = [None] * self.n_workers
