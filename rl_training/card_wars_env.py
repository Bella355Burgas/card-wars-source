import socket
import json
import subprocess
import time
import os
import numpy as np
import gymnasium as gym
from gymnasium import spaces

GODOT_BIN = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class CardWarsEnv(gym.Env):
    """
    Gymnasium environment for Card Wars Godot game.
    Supports Action Masking for MaskablePPO.
    """
    metadata = {"render_modes": ["human"]}

    def __init__(self, port: int = 9999, bot_type: str = "random", auto_launch: bool = True):
        super().__init__()
        self.port = port
        self.bot_type = bot_type  # "random", "heuristic", or "none"
        self.auto_launch = auto_launch

        self.observation_space = spaces.Box(
            low=-1.0, high=2.0, shape=(181,), dtype=np.float32
        )
        self.action_space = spaces.Discrete(64)

        self._proc = None
        self._sock = None
        self._reader = None
        self._writer = None

        self._current_mask = np.ones(64, dtype=bool)
        self._episode_steps = 0
        self._max_episode_steps = 80

        self._connect_or_launch()

    def _connect_or_launch(self):
        try:
            self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self._sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self._sock.connect(("127.0.0.1", self.port))
        except (ConnectionRefusedError, OSError):
            if self.auto_launch:
                print(f"[CardWarsEnv] Launching Godot headless bridge on port {self.port}...")
                cmd = [
                    GODOT_BIN,
                    "--headless",
                    "--path", PROJECT_DIR,
                    "-s", "res://scripts/ai/rl_bridge.gd",
                    "--", "--port", str(self.port)
                ]
                self._proc = subprocess.Popen(
                    cmd,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                connected = False
                for attempt in range(40):
                    time.sleep(0.2)
                    try:
                        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                        self._sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                        self._sock.connect(("127.0.0.1", self.port))
                        connected = True
                        break
                    except (ConnectionRefusedError, OSError):
                        try:
                            self._sock.close()
                        except Exception:
                            pass
                if not connected:
                    raise RuntimeError(f"Could not connect to Godot on port {self.port}")

        self._recv_buf = ""

    def _send_cmd(self, cmd_dict: dict) -> dict:
        line = json.dumps(cmd_dict) + "\n"
        self._sock.sendall(line.encode("utf-8"))
        while "\n" not in self._recv_buf:
            data = self._sock.recv(4096)
            if not data:
                raise RuntimeError("Connection to Godot lost.")
            self._recv_buf += data.decode("utf-8")
        pos = self._recv_buf.find("\n")
        resp_line = self._recv_buf[:pos]
        self._recv_buf = self._recv_buf[pos + 1:]
        return json.loads(resp_line)

    def action_masks(self) -> np.ndarray:
        return self._current_mask

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)
        self._episode_steps = 0
        swap = False
        if seed is None:
            seed = int(np.random.randint(0, 1000000))
            swap = bool(np.random.rand() < 0.5)

        msg = {
            "cmd": "reset",
            "seed": seed,
            "swap_heroes": swap,
            "bot": self.bot_type,
            "agent_player": 0
        }
        res = self._send_cmd(msg)
        obs = np.array(res["obs"], dtype=np.float32)
        self._current_mask = np.array(res["action_mask"], dtype=bool)

        info = res.get("info", {})
        info["action_mask"] = self._current_mask
        return obs, info

    def step(self, action: int):
        self._episode_steps += 1
        msg = {
            "cmd": "step",
            "action": int(action),
            "bot": self.bot_type
        }
        res = self._send_cmd(msg)
        obs = np.array(res["obs"], dtype=np.float32)
        self._current_mask = np.array(res["action_mask"], dtype=bool)
        reward = float(res.get("reward", 0.0))
        terminated = bool(res.get("done", False))
        truncated = self._episode_steps >= self._max_episode_steps

        info = res.get("info", {})
        info["action_mask"] = self._current_mask
        info["winner"] = res.get("winner", -1)

        return obs, reward, terminated, truncated, info

    def close(self):
        try:
            if self._writer:
                self._send_cmd({"cmd": "close"})
        except Exception:
            pass
        if self._sock:
            self._sock.close()
        if self._proc:
            self._proc.terminate()
            self._proc.wait(timeout=2)
