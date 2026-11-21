"""Checks that the game's network (scripts/ai/policy_agent.gd) scores exactly like PyTorch.

    python check_parity.py runs/<name>/best.pt [--games 3]

Exports the checkpoint to a temporary file, lets Godot play a few games with it
(tests/policy_parity.gd: both seats, every decision dumped with its scores) and
scores the same decisions with the PyTorch model.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
import torch

import deckgen
from cw_data import ROOT, encode_state
from cw_pool import GODOT_BIN
from export_model import export
from policy import CardWarsPolicy
from train_selfplay import collate

TOLERANCE = 1e-3


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description="Compare the GDScript policy with the PyTorch one")
    parser.add_argument("checkpoint")
    parser.add_argument("--games", type=int, default=3)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        model_json = os.path.join(tmp, "policy.json")
        dump = os.path.join(tmp, "decisions.jsonl")
        export(args.checkpoint, model_json)
        run = subprocess.run([GODOT_BIN, "--headless", "--path", ROOT, "-s", "res://tests/policy_parity.gd",
                              "--", model_json, dump, str(args.games)],
                             capture_output=True, text=True, encoding="utf-8", errors="replace")
        report = [line for line in (run.stdout + run.stderr).splitlines()
                  if line.startswith(("games=", "unfinished", "SCRIPT ERROR", "ERROR", "   at:"))]
        print("\n".join(report))
        if run.returncode != 0 or not os.path.exists(dump):
            raise SystemExit(f"Godot run failed (exit {run.returncode})")
        with open(dump, encoding="utf-8") as f:
            decisions = [json.loads(line) for line in f]

    table = deckgen.table()
    ckpt = torch.load(args.checkpoint, weights_only=False)
    model = CardWarsPolicy.from_checkpoint(ckpt, table.static)
    model.eval()
    worst = 0.0
    worst_value = 0.0
    argmax_diff = 0
    by_mode = {}
    for d in decisions:
        enc = encode_state(d["s"], table)
        with torch.no_grad():
            logits, values = model(**collate([enc]))
        torch_l = logits[0, :enc[-1]].numpy()
        gd_l = np.array(d["l"], dtype=np.float64)
        if gd_l.shape != torch_l.shape:
            raise SystemExit(f"option count differs: {gd_l.shape} vs {torch_l.shape}")
        diff = float(np.abs(gd_l - torch_l).max())
        worst = max(worst, diff)
        worst_value = max(worst_value, abs(float(d["v"]) - float(values[0])))
        # Equal options (two copies of a card in hand, say) tie; any of them is the same pick.
        if torch_l[int(np.argmax(gd_l))] < torch_l.max() - TOLERANCE:
            argmax_diff += 1
        by_mode[d["s"]["mode"]] = by_mode.get(d["s"]["mode"], 0) + 1
    print(f"decisions: {len(decisions)} (by mode {by_mode}); max |logit diff| {worst:.2e}; "
          f"max |value diff| {worst_value:.2e}; different picks {argmax_diff}")
    if worst > TOLERANCE or worst_value > TOLERANCE or argmax_diff:
        raise SystemExit("MISMATCH: the game would not play like the trained network")
    print("OK: the game plays like the trained network")


if __name__ == "__main__":
    main()
