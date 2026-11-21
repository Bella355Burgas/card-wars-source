"""Runs tools/train_balance.gd in many processes at once.

  python tools/train_balance_run.py OUT_DIR TAG [key=value ...]

The key=value pairs go to the script as they are (runs, seed, diff, policy, trains, level, immortal).
`procs` (default 18) is the number of processes, `root=` another copy of the project to play (a frozen state to compare with). Writes OUT_DIR/TAG_<shard>.jsonl; read with
tools/train_balance_report.py. OUT_DIR should be outside the repository.
"""
import os
import subprocess
import sys
import time

GODOT = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"


def main() -> None:
    out, tag = sys.argv[1], sys.argv[2]
    args = [a for a in sys.argv[3:] if not a.startswith(("procs=", "root="))]
    procs = int(next((a.split("=")[1] for a in sys.argv[3:] if a.startswith("procs=")), "18"))
    os.makedirs(out, exist_ok=True)
    root = next((a.split("=", 1)[1] for a in sys.argv[3:] if a.startswith("root=")),
                os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    t0 = time.time()
    running = []
    for shard in range(procs):
        cmd = [GODOT, "--headless", "--path", root, "-s", "tools/train_balance.gd", "--",
               "out=" + out.replace("\\", "/"), "tag=" + tag, "shard=%d" % shard, "shards=%d" % procs] + args
        running.append(subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    for p in running:
        p.wait()
    print("%s: %d processes, %.0f s" % (tag, procs, time.time() - t0), flush=True)


if __name__ == "__main__":
    main()
