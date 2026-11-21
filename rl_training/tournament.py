"""Round robin between networks of a run: to pick the one for the game and to
measure the AI difficulty levels.

    python tournament.py runs/<name>                       # snapshots from 500k on, best.pt, latest.pt
    python tournament.py runs/<name> --from 0 --pairs 200  # every snapshot
    python tournament.py runs/<name> --entry "50k t1=snapshots/snap_000050005.pt@1" \\
        --entry "1M=latest.pt" --entry "heuristic=bot:heuristic" --out levels.json

An --entry is "label=checkpoint" (relative to the run folder), "label=checkpoint@T"
(it samples its moves at temperature T instead of taking the best one, like a
level of the game) or "label=bot:heuristic" / "label=bot:random" (the workers'
bots; two bots never meet). With entries the snapshots are not added.

Every pair plays the same --pairs games twice, with the seats swapped: the same
decks, hero cards, first player and engine seed, so neither side is luckier
with its deck. Half the games are on random loadouts (as in training), half on
the ready decks with their own hero cards (the games a player meets in the
menu). Networks without @T play greedily, as the game's AI does.

--deck X rates the networks as players of the ready deck X: in every base game one
seat plays X (the seat alternates from game to game, so each network plays X as often
as the other seat) and the other seat plays an ordinary deck. Compare a deck network
with the general network on X: python tournament.py runs/<name> --deck X --entry ...

The ratings are fitted to all results at once (Bradley-Terry, a draw is half a
win) on the run's Elo scale: the first network with a row in log.csv keeps its
Elo from there. The ranking is printed and saved to runs/<name>/<--out>.
"""
import argparse
import csv
import glob
import json
import math
import os
import random
import sys
import time

import numpy as np
import torch

import deckgen
from cw_pool import WorkerPool
from policy import CardWarsPolicy
from train_selfplay import Collector, frozen_copy

SEED = 2 * 10**9      # other games than the training evaluation (EVAL_SEED)
ELO = 400.0 / math.log(10.0)


class Sampled(torch.nn.Module):
    """A network that samples its moves at a temperature. The collector takes the
    best option; the best of logits / T plus Gumbel noise is a draw from softmax(logits / T)."""

    def __init__(self, model, temperature, seed):
        super().__init__()
        self.model = model
        self.temperature = temperature
        self.gen = torch.Generator().manual_seed(seed)

    def forward(self, **batch):
        logits, values = self.model(**batch)
        u = torch.rand(logits.shape, generator=self.gen).clamp_(1e-9, 1.0 - 1e-9)
        return logits / self.temperature - torch.log(-torch.log(u)), values


def snapshot_entries(run_dir, start):
    """The snapshots from `start` games on, then best.pt and latest.pt, each network once."""
    found = {}
    for path in sorted(glob.glob(os.path.join(run_dir, "snapshots", "snap_*.pt"))):
        games = int(os.path.basename(path)[5:-3])
        if games >= start:
            found[games] = path
    for name in ("best.pt", "latest.pt"):
        path = os.path.join(run_dir, name)
        if os.path.exists(path):
            games = torch.load(path, weights_only=False, map_location="cpu")["games"]
            found.setdefault(games, path)
    return [{"name": f"{games // 1000}k", "path": found[games], "temp": 0.0, "bot": None}
            for games in sorted(found)]


def parse_entry(run_dir, text):
    name, sep, src = text.partition("=")
    if not sep or not name or not src:
        raise SystemExit(f"bad --entry {text!r}: expected label=checkpoint[@T] or label=bot:<kind>")
    if src.startswith("bot:"):
        return {"name": name, "path": None, "temp": 0.0, "bot": src[4:]}
    path, _, temp = src.partition("@")
    return {"name": name, "path": os.path.join(run_dir, path), "temp": float(temp) if temp else 0.0, "bot": None}


def training_elo(run_dir, games):
    """The Elo log.csv gave the network at its evaluation (None if there is no such row)."""
    path = os.path.join(run_dir, "log.csv")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if int(row["games"]) == games and row["elo"] != "":
                return float(row["elo"])
    return None


def fit(n, results, ref):
    """Bradley-Terry ratings (natural units) from (i, j, points of i) per game; ratings[ref] = 0.
    Returns the ratings and their standard errors."""
    points = np.zeros((n, n))
    games = np.zeros((n, n))
    for i, j, s in results:
        points[i, j] += s
        points[j, i] += 1.0 - s
        games[i, j] += 1
        games[j, i] += 1
    r = np.zeros(n)
    free = [k for k in range(n) if k != ref]
    for _ in range(100):
        p = 1.0 / (1.0 + np.exp(r[None, :] - r[:, None]))      # p[i, j]: chance that i beats j
        grad = (points - games * p).sum(axis=1)
        w = games * p * (1.0 - p)
        hess = w - np.diag(w.sum(axis=1))
        step = np.linalg.solve(hess[np.ix_(free, free)], grad[free])
        r[free] -= step
        if np.abs(step).max() < 1e-10:
            break
    se = np.zeros(n)
    se[free] = np.sqrt(np.diag(np.linalg.inv(-hess[np.ix_(free, free)])))
    return r, se


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description="Round robin between networks of a run")
    parser.add_argument("run_dir")
    parser.add_argument("--from", dest="start", type=int, default=500_000,
                        help="earliest snapshot (games) in the tournament")
    parser.add_argument("--entry", action="append", default=[],
                        help="label=checkpoint[@T] or label=bot:<kind>; replaces the snapshots")
    parser.add_argument("--pairs", type=int, default=300,
                        help="games per pair, each played twice with the seats swapped")
    parser.add_argument("--out", default="tournament.json", help="result file in the run folder")
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--slots", type=int, default=16)
    parser.add_argument("--torch-threads", type=int, default=4)
    parser.add_argument("--deck", default="", help="rate the networks on this ready deck (see the docstring)")
    args = parser.parse_args()
    torch.set_num_threads(args.torch_threads)

    table = deckgen.table()
    if args.deck and args.deck not in table.hero_order:
        raise SystemExit(f"--deck {args.deck}: not a ready deck; choose one of: " + ", ".join(table.hero_order))
    entries = [parse_entry(args.run_dir, e) for e in args.entry] or snapshot_entries(args.run_dir, args.start)
    if len(entries) < 2:
        raise SystemExit("fewer than two players to compare")
    names = [e["name"] for e in entries]
    if len(set(names)) != len(names):
        raise SystemExit("labels must differ")
    models = {}
    info = []
    for k, e in enumerate(entries):
        x = {"name": e["name"], "path": None, "temperature": e["temp"], "bot": e["bot"], "games": None,
             "train_elo": None}
        if e["bot"] is None:
            ckpt = torch.load(e["path"], weights_only=False, map_location="cpu")
            if ckpt["table"] != table.signature:
                raise SystemExit(f"{e['path']} was made for another card set")
            model = frozen_copy(CardWarsPolicy.from_checkpoint(ckpt, table.static))
            models[e["name"]] = Sampled(model, e["temp"], seed=k + 1) if e["temp"] > 0 else model
            x.update({"path": os.path.relpath(e["path"], args.run_dir).replace("\\", "/"), "games": ckpt["games"]})
            if e["temp"] == 0:
                x["train_elo"] = training_elo(args.run_dir, ckpt["games"])
        info.append(x)

    # The same base games for every pair; each pair plays them in a row (few networks per batch).
    base = []
    for k in range(args.pairs):
        seed = SEED + k
        kind = "preset" if k % 2 else "random"
        spec = deckgen.game_spec(random.Random(seed), serial=k, seed=seed, presets=kind == "preset",
                                 deck=args.deck, deck_seat=k % 2)
        spec["kind"] = kind
        spec["agent_seat"] = 0
        base.append(spec)
    n = len(names)
    pairs = [(a, b) for a in range(n) for b in range(a + 1, n) if entries[a]["bot"] is None or entries[b]["bot"] is None]
    specs = []
    for a, b in pairs:
        for spec in base:
            for first, second in ((a, b), (b, a)):
                seats = [first, second]
                bot_seat = next((s for s in (0, 1) if entries[seats[s]]["bot"]), -1)
                # A bot's seat is played inside the worker; the network named for it is never asked.
                net = [names[x] for x in seats if entries[x]["bot"] is None]
                spec_k = {**spec, "seat_models": [names[x] if entries[x]["bot"] is None else net[0] for x in seats],
                          "pair": (first, second)}
                if bot_seat >= 0:
                    spec_k["bot"] = entries[seats[bot_seat]]["bot"]
                    spec_k["bot_seat"] = bot_seat
                specs.append(spec_k)
    total = len(specs)
    print(f"{n} players: {', '.join(names)}" + (f"; playing the deck {args.deck}" if args.deck else ""))
    print(f"{len(pairs)} pairs x {2 * args.pairs} games = {total} games", flush=True)

    pool = WorkerPool(args.workers, args.slots, os.path.join(args.run_dir, "tournament_workers"), base_port=25600)
    queue = iter(specs)
    col = Collector(pool, range(pool.n_workers), table, lambda: next(queue, None), record=False)
    t_start = last_print = time.time()
    try:
        while col.busy():
            col.send_next(models, greedy=True)
            col.receive()
            if time.time() - last_print > 60:
                last_print = time.time()
                done = col.games_finished
                rate = done / max(1e-9, last_print - t_start)
                print(f"  {done}/{total} games, {rate:.0f}/s, ~{(total - done) / max(rate, 1e-9) / 60:.0f} min left",
                      flush=True)
    finally:
        pool.close()
    minutes = (time.time() - t_start) / 60

    results = []
    stats = {}                               # (a, b) with a < b -> [a wins, draws, b wins]
    for r in col.results:
        first, second = r["spec"]["pair"]
        s = 0.5 if r["draw"] else (1.0 if r["win"] else 0.0)    # points of the seat-0 player
        results.append((first, second, s))
        a, b = min(first, second), max(first, second)
        row = stats.setdefault((a, b), [0, 0, 0])
        if r["draw"]:
            row[1] += 1
        else:
            row[0 if r["win"] == (first == a) else 2] += 1
    ref = next((k for k in range(n) if info[k]["train_elo"] is not None), 0)
    ref_elo = info[ref]["train_elo"] or 0.0
    r, se = fit(n, results, ref)
    for k in range(n):
        played = [(s if i == k else 1.0 - s) for i, j, s in results if k in (i, j)]
        info[k].update({"elo": round(ref_elo + r[k] * ELO, 1), "se": round(se[k] * ELO, 1),
                        "score": round(float(np.mean(played)), 4) if played else None, "n": len(played)})

    order = sorted(range(n), key=lambda k: -info[k]["elo"])
    width = max(8, max(len(x) for x in names) + 1)
    print(f"\n{col.games_finished} games in {minutes:.1f} min, {len(col.errors)} errors")
    print(f"Elo on the run's scale ({names[ref]} = {ref_elo:.0f}, its Elo in log.csv); ± is 95%")
    print(f"{'#':>2}  {'player':<{width}} {'Elo':>7} {'±':>5}  {'score':>6}  {'log.csv':>7}  source")
    for place, k in enumerate(order, 1):
        x = info[k]
        train = f"{x['train_elo']:.0f}" if x["train_elo"] is not None else "-"
        source = f"bot {x['bot']}" if x["bot"] else x["path"] + (f" @{x['temperature']:g}" if x["temperature"] else "")
        print(f"{place:>2}  {x['name']:<{width}} {x['elo']:7.1f} {1.96 * x['se']:5.1f}  {x['score'] * 100:5.1f}%  "
              f"{train:>7}  {source}")
    print("\nscore of the row against the column, %:")
    print(" " * width + "".join(f"{names[k]:>{width}}" for k in order))
    for i in order:
        cells = []
        for j in order:
            a, b = min(i, j), max(i, j)
            if i == j or (a, b) not in stats:
                cells.append(f"{'':>{width}}")
                continue
            w, d, l = stats[(a, b)]
            if i != a:
                w, l = l, w
            cells.append(f"{(w + 0.5 * d) / max(1, w + d + l) * 100:{width}.1f}")
        print(f"{names[i]:<{width}}" + "".join(cells))
    best = info[order[0]]
    if best["path"]:
        print(f"\nstrongest: {best['name']} -> python export_model.py "
              f"{os.path.normpath(os.path.join(args.run_dir, best['path']))}")

    out = os.path.join(args.run_dir, args.out)
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"deck": args.deck, "pairs_games": 2 * args.pairs, "minutes": round(minutes, 1), "errors": len(col.errors),
                   "ranking": [info[k] for k in order],
                   "pairs": [{"a": names[a], "b": names[b], "a_wins": w, "draws": d, "b_wins": l}
                             for (a, b), (w, d, l) in sorted(stats.items())]},
                  f, ensure_ascii=False, indent=2)
    print(f"saved {out}")


if __name__ == "__main__":
    main()
