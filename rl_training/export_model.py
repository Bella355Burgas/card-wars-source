"""Exports a trained checkpoint for the game: data/ai_policy.json, read by
scripts/ai/policy_agent.gd. Once the file is there, «Игра против ИИ» and
«ИИ против ИИ» play with this network (without it, the game keeps the old one).

    python export_model.py runs/<name>/best.pt
    python export_model.py runs/<name>/best.pt --out some/other/path.json

The card encoder is run here once: the file holds every card's embedding. Choice
prompts are encoded in the game from their words, so the vocabulary and the
encoder's weights for words are exported too. Check the result with
check_parity.py.
"""
import argparse
import json
import os
import sys

import numpy as np
import torch

import deckgen
from cw_data import (ROOT, NUMERIC_DIM, NUM_SLOTS, DYN_DIM, GLOB_DIM, NUM_CODES, POOLS, POOL_MAX,
                     CAND_MAX, LANDS)
from policy import CardWarsPolicy

FORMAT = 1


def _num(x):
    return float(f"{x:.8g}")


def matrix(t):
    """A Linear weight [out, in] (or a bias / vector) as rows, cols and flat row-major data."""
    a = t.detach().cpu().numpy().astype(np.float32)
    if a.ndim == 1:
        a = a[None, :]
    return {"rows": int(a.shape[0]), "cols": int(a.shape[1]), "data": [_num(v) for v in a.ravel()]}


def export(ckpt_path, out_path):
    ckpt = torch.load(ckpt_path, weights_only=False)
    table = deckgen.table()
    if ckpt["table"] != table.signature:
        raise SystemExit(f"checkpoint was made for another card set: {ckpt['table']} (now {table.signature})")
    model = CardWarsPolicy.from_checkpoint(ckpt, table.static)
    model.eval()
    with torch.no_grad():
        emb = model.card_enc(model.static)
    enc1, enc2 = model.card_enc[0], model.card_enc[2]
    data = {
        "format": FORMAT,
        "games": ckpt["games"],
        "elo": ckpt.get("elo"),
        "signature": table.signature,
        "dims": model.dims,
        "const": {"num_slots": NUM_SLOTS, "dyn_dim": DYN_DIM, "glob_dim": GLOB_DIM, "num_codes": NUM_CODES,
                  "pools": POOLS, "pool_max": POOL_MAX, "cand_max": CAND_MAX, "lands": LANDS},
        "ids": [""] + table.ids,                  # row k of emb is the card with this id; row 0 is "no card"
        "vocab": table.vocab,
        "emb": matrix(emb),
        # Prompts have no numeric features: only the word columns of the first layer are needed.
        "enc1_w": matrix(enc1.weight[:, NUMERIC_DIM:]),
        "enc1_b": matrix(enc1.bias),
        "enc2_w": matrix(enc2.weight),
        "enc2_b": matrix(enc2.bias),
        "slot_w": matrix(model.slot_proj.weight),
        "slot_b": matrix(model.slot_proj.bias),
        "state_w": matrix(model.state_fc.weight),
        "state_b": matrix(model.state_fc.bias),
        "state2_w": matrix(model.state_fc2.weight),
        "state2_b": matrix(model.state_fc2.bias),
        "cstate_w": matrix(model.cand_state.weight),
        "cstate_b": matrix(model.cand_state.bias),
        "cfeat_w": matrix(model.cand_feat.weight),
        "cfc_w": matrix(model.cand_fc.weight),
        "cfc_b": matrix(model.cand_fc.bias),
        "cout_w": matrix(model.cand_out.weight),
        "cout_b": matrix(model.cand_out.bias),
        # Value head: the search (scripts/ai/search.gd) scores positions with it.
        "value1_w": matrix(model.value[0].weight),
        "value1_b": matrix(model.value[0].bias),
        "value2_w": matrix(model.value[2].weight),
        "value2_b": matrix(model.value[2].bias),
    }
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(out_path) / 1e6
    elo = f", Elo {ckpt['elo']:.0f}" if ckpt.get("elo") is not None else ""
    print(f"exported {ckpt_path} ({ckpt['games']} games{elo}) -> {out_path} ({size:.1f} MB)")


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description="Export a Card Wars policy checkpoint for the game")
    parser.add_argument("checkpoint")
    parser.add_argument("--out", default=os.path.join(ROOT, "data", "ai_policy.json"))
    args = parser.parse_args()
    export(args.checkpoint, args.out)


if __name__ == "__main__":
    main()
