"""Self-play PPO for Card Wars, trained from scratch on random decks and heroes.

    python train_selfplay.py --games 1000000
    python train_selfplay.py --games 1000000 --resume runs/<name>/latest.pt   # continue a run
    python train_selfplay.py --deck marceline --init runs/<name>/best.pt --games 300000   # one deck

--deck X trains a network for the ready deck X (with its own hero card or another):
in every training game one seat plays X, the other plays a random loadout. --init
starts the new run from a checkpoint of the general network (a fresh optimizer and
game count, its own folder), and that network is the first anchor with Elo 0, so the
first evaluation already shows how much stronger the deck network is on X. With
--deck the evaluation games have X on the agent's seat, and the run folder is
runs/<time>_<X>. --deck-samples own learns only from the seat that plays X (the
default, both, learns from both seats: the general play of the other decks is kept).

Every game is random (deckgen): per seat a ready deck, a ready deck with some
cards swapped, or a random legal deck, with a random hero card. The network
plays both seats in most games; in --pool-frac of them one seat is a past
snapshot of it (only the current network's decisions are learned from), so it
keeps beating the strategies it has left behind. It decides everything a player
decides: the starting hand, the turn's commands and every choice a card asks for.

Every --eval-every games the greedy agent plays fixed games against two bots
(heuristic and random) and against the anchor, an earlier copy of itself, on
random loadouts ("anchor") and on the ready decks with their own hero cards
("preset"). Strength is an Elo scale: the agent's Elo is the anchor's plus what
its score against the anchor implies, and once it scores --promote against the
anchor it becomes the new anchor. best.pt is the highest Elo so far; a snapshot
is kept every --snapshot-every games. Results go to runs/<name>/log.csv, text
logs of a few evaluation games to runs/<name>/eval_logs/, games the workers
could not play to runs/<name>/errors.jsonl; plot_progress.py draws the curve.
export_model.py turns a checkpoint into data/ai_policy.json for the game.

The Godot workers run in two groups that take turns: while one group's games are
being read and encoded, the other group computes its next commands.
"""
import argparse
import copy
import csv
import glob
import json
import math
import os
import random
import sys
import time
from collections import deque

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

import deckgen
from cw_data import ROOT, CAND_FIELDS, encode_state
from cw_pool import WorkerDied, WorkerPool
from policy import DEFAULT_DIMS, CardWarsPolicy

GAMMA = 0.99
LAM = 0.95
CLIP = 0.2
ENT_COEF = 0.01
VF_COEF = 0.5
MAX_GRAD = 0.5
SHAPE = 0.01          # reward per HP point a seat takes from the other seat

EVAL_SEED = 10**9     # the evaluation games are the same at every evaluation
EVAL_KINDS = ("heuristic", "random", "anchor", "preset")
ANCHOR_KINDS = ("anchor", "preset")      # games against the anchor; together they give the Elo

CSV_HEADER = ["games", "decisions", "minutes", "games_per_min", "dec_per_s", "lr",
              "pg_loss", "v_loss", "entropy", "kl", "clip_frac", "train_turns", "capped", "errors",
              "elo", "anchor_elo", "anchor_gen",
              "wr_heur", "draw_heur", "turns_heur", "wr_rand", "draw_rand", "turns_rand",
              "wr_anchor", "draw_anchor", "turns_anchor", "wr_preset", "draw_preset", "turns_preset"]


class Step:
    """One decision of a game, as the policy saw it."""
    __slots__ = ("enc", "action", "logp", "value", "p", "hp_self", "hp_opp")

    def __init__(self, enc, action, logp, value, p, hp_self, hp_opp):
        self.enc = enc
        self.action = action
        self.logp = logp
        self.value = value
        self.p = p
        self.hp_self = hp_self
        self.hp_opp = hp_opp


def collate(encs):
    """Stack encoded decisions into batch tensors; options are padded to the widest decision."""
    n = np.array([e[-1] for e in encs])
    width = max(1, int(n.max()))
    batch = {
        "card_ids": torch.from_numpy(np.stack([e[0] for e in encs])).long(),
        "dyn": torch.from_numpy(np.stack([e[1] for e in encs])),
        "glob": torch.from_numpy(np.stack([e[2] for e in encs])),
        "prompt": torch.from_numpy(np.stack([e[3] for e in encs])),
        "pools": torch.from_numpy(np.stack([e[4] for e in encs])).long(),
    }
    for f, name in enumerate(CAND_FIELDS):
        arr = np.zeros((len(encs), width), dtype=np.int64)
        for row, e in enumerate(encs):
            arr[row, :e[-1]] = e[5 + f]
        batch[name] = torch.from_numpy(arr)
    batch["cand_mask"] = torch.from_numpy(np.arange(width)[None, :] < n[:, None])
    return batch


def gae_samples(traj, winner, final_hp):
    """Advantages and returns per seat. Each seat is its own sequence of decisions:
    the result (+1 / -1) lands on its last decision, and HP changes add a small shaping.
    Only recorded seats (the current network's) have decisions in traj."""
    out = []
    for seat in (0, 1):
        idx = [k for k, st in enumerate(traj) if st.p == seat]
        n = len(idx)
        if n == 0:
            continue
        rewards = np.zeros(n, dtype=np.float32)
        for j, k in enumerate(idx):
            st = traj[k]
            if j + 1 < n:
                nxt = traj[idx[j + 1]]
                hs, ho = nxt.hp_self, nxt.hp_opp
            else:
                hs, ho = final_hp[seat], final_hp[1 - seat]
            rewards[j] = SHAPE * ((st.hp_opp - ho) - (st.hp_self - hs))
        if winner == seat:
            rewards[-1] += 1.0
        elif winner == 1 - seat:
            rewards[-1] -= 1.0
        values = np.array([traj[k].value for k in idx], dtype=np.float32)
        adv = np.zeros(n, dtype=np.float32)
        last = 0.0
        for j in reversed(range(n)):
            next_v = values[j + 1] if j + 1 < n else 0.0
            delta = rewards[j] + GAMMA * next_v - values[j]
            last = delta + GAMMA * LAM * last
            adv[j] = last
        ret = adv + values
        for j, k in enumerate(idx):
            st = traj[k]
            out.append((st.enc, st.action, st.logp, float(adv[j]), float(ret[j])))
    return out


class Collector:
    """Drives a group of workers: turns their decisions into actions and sends the next batch.

    send_next() sends one batch to every worker of the group that has something to do;
    receive() waits for those replies and handles them. Games that end are finished
    here, and their slots get a new game from make_spec(). A game a worker reports
    as broken, or that was on a worker that died, is dropped and logged to `errors`."""

    def __init__(self, pool, workers, table, make_spec, record):
        self.pool = pool
        self.workers = list(workers)            # global worker ids of this group
        self.table = table
        self.make_spec = make_spec              # () -> spec, or None when there is nothing left
        self.record = record
        W, S = len(self.workers), pool.slots
        self.env = [[None] * S for _ in range(W)]
        self.new = [[None] * S for _ in range(W)]
        self.sent = []                          # local workers with a batch in flight
        self.samples = []                       # training: (enc, action, logp, adv, ret) of finished games
        self.results = []                       # evaluation: one dict per finished game
        self.errors = []                        # dropped games: {"msg", "spec"}
        self.games_finished = 0
        self.turns = []
        self.capped = []
        for w in range(W):
            for s in range(S):
                self.new[w][s] = self.make_spec()

    def busy(self):
        if self.sent:
            return True
        if any(x is not None for row in self.new for x in row):
            return True
        return any(e is not None for row in self.env for e in row)

    def send_next(self, models, greedy):
        """models: name -> policy. Each seat of a game names the policy that plays it."""
        W, S = len(self.workers), self.pool.slots
        items = [[] for _ in range(W)]
        ready = [(w, s) for w in range(W) for s in range(S)
                 if self.env[w][s] is not None and self.env[w][s]["state"] is not None]
        if ready:
            encs = [encode_state(self.env[w][s]["state"], self.table) for w, s in ready]
            names = [self.env[w][s]["seat_models"][self.env[w][s]["p"]] for w, s in ready]
            actions_np = np.zeros(len(ready), dtype=np.int64)
            logp_np = np.zeros(len(ready), dtype=np.float32)
            values_np = np.zeros(len(ready), dtype=np.float32)
            for name in set(names):
                ks = [k for k, nm in enumerate(names) if nm == name]
                with torch.no_grad():
                    logits, values = models[name](**collate([encs[k] for k in ks]))
                    dist = torch.distributions.Categorical(logits=logits)
                    actions = logits.argmax(-1) if greedy else dist.sample()
                    logp = dist.log_prob(actions)
                actions_np[ks] = actions.numpy()
                logp_np[ks] = logp.numpy()
                values_np[ks] = values.numpy()
            for k, (w, s) in enumerate(ready):
                env = self.env[w][s]
                st = env["state"]
                learn = env["spec"].get("learn", (0, 1))
                if self.record and names[k] == "agent" and env["p"] in learn:
                    env["traj"].append(Step(encs[k], int(actions_np[k]), float(logp_np[k]),
                                            float(values_np[k]), env["p"], st["hp"][0], st["hp"][1]))
                items[w].append({"i": s, "a": int(actions_np[k])})
                env["state"] = None
        for w in range(W):
            for s in range(S):
                spec = self.new[w][s]
                if spec is not None:
                    self.env[w][s] = {"spec": spec, "traj": [], "state": None, "p": -1,
                                      "seat_models": spec.get("seat_models", ["agent", "agent"])}
                    items[w].append({"i": s, "new": spec})
                    self.new[w][s] = None
        self.sent = []
        for w in range(W):
            if items[w]:
                try:
                    self.pool.send(self.workers[w], items[w])
                    self.sent.append(w)
                except WorkerDied as e:
                    self._lose_worker(w, str(e))
        return bool(self.sent)

    def receive(self):
        """Waits for the batches in flight and handles their replies."""
        for w in self.sent:
            try:
                replies = self.pool.recv(self.workers[w])
            except WorkerDied as e:
                self._lose_worker(w, str(e))
                continue
            for r in replies:
                s = r["i"]
                env = self.env[w][s]
                if r["st"] == "dec":
                    env["state"] = r["s"]
                    env["p"] = r["p"]
                elif r["st"] == "done":
                    self._finish(env, r)
                    self.env[w][s] = None
                    self.new[w][s] = self.make_spec()
                else:
                    self.errors.append({"msg": r.get("msg", "?"), "spec": env["spec"]})
                    self.env[w][s] = None
                    self.new[w][s] = self.make_spec()
        self.sent = []

    def _lose_worker(self, w, msg):
        """Restarts a dead or hung worker; its games are dropped and logged."""
        print(f"!! {msg}; restarting it", flush=True)
        for s in range(self.pool.slots):
            env = self.env[w][s]
            if env is not None:
                self.errors.append({"msg": msg, "spec": env["spec"]})
                self.env[w][s] = None
                self.new[w][s] = self.make_spec()
        self.pool.restart(self.workers[w])

    def _finish(self, env, r):
        self.games_finished += 1
        self.turns.append(r["t"])
        self.capped.append(r.get("cap", 0))
        winner = r["w"]
        if self.record:
            self.samples.extend(gae_samples(env["traj"], winner, r["hp"]))
        else:
            spec = env["spec"]
            agent_seat = spec["agent_seat"]
            self.results.append({"win": winner == agent_seat, "draw": winner == -1,
                                 "turns": r["t"], "agent_seat": agent_seat,
                                 "kind": spec["kind"], "spec": spec, "log": r.get("log")})


def run_sync(col, models, greedy=True):
    """Plays a collector to the end without pipelining (used for evaluation)."""
    while col.busy():
        # A batch that could not be sent (its worker was restarted) goes out on the next round.
        col.send_next(models, greedy)
        col.receive()


def ppo_update(model, opt, samples, args):
    batch = collate([s[0] for s in samples])
    n_cands = batch["cand_mask"].sum(dim=1)
    actions = torch.tensor([s[1] for s in samples], dtype=torch.long)
    old_logp = torch.tensor([s[2] for s in samples], dtype=torch.float32)
    adv = torch.tensor([s[3] for s in samples], dtype=torch.float32)
    ret = torch.tensor([s[4] for s in samples], dtype=torch.float32)
    adv = (adv - adv.mean()) / (adv.std() + 1e-8)
    n = len(samples)
    stats = {"pg": 0.0, "v": 0.0, "ent": 0.0, "kl": 0.0, "clip": 0.0, "steps": 0}
    for _ in range(args.epochs):
        perm = torch.randperm(n)
        for start in range(0, n, args.minibatch):
            idx = perm[start:start + args.minibatch]
            # Trim the padded option list to this minibatch's widest decision.
            width = int(n_cands[idx].max())
            mb = {k: (v[idx][:, :width] if k.startswith("cand_") else v[idx]) for k, v in batch.items()}
            logits, values = model(**mb)
            logp_all = F.log_softmax(logits, dim=-1)
            logp = logp_all.gather(1, actions[idx].unsqueeze(1)).squeeze(1)
            ratio = torch.exp(logp - old_logp[idx])
            a = adv[idx]
            pg = -torch.min(ratio * a, torch.clamp(ratio, 1 - CLIP, 1 + CLIP) * a).mean()
            v_loss = F.mse_loss(values, ret[idx])
            probs = logp_all.exp()
            entropy = -(probs * logp_all).sum(dim=-1).mean()
            loss = pg + VF_COEF * v_loss - ENT_COEF * entropy
            opt.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), MAX_GRAD)
            opt.step()
            with torch.no_grad():
                log_ratio = logp - old_logp[idx]
                stats["kl"] += float(((ratio - 1) - log_ratio).mean())
                stats["clip"] += float(((ratio - 1).abs() > CLIP).float().mean())
            stats["pg"] += float(pg.detach())
            stats["v"] += float(v_loss.detach())
            stats["ent"] += float(entropy.detach())
            stats["steps"] += 1
    k = max(1, stats["steps"])
    return {key: stats[key] / k for key in ("pg", "v", "ent", "kl", "clip")}


def run_evals(models, pool, table, n_games, n_text, text_dir, deck=""):
    """Greedy agent against fixed games, per kind of opponent, all played together.

    heuristic / random: the bot plays one seat, on random loadouts. anchor: the
    anchor plays the other seat, on random loadouts; preset: the same on the
    ready decks with their own hero cards (both need models["anchor"]).
    deck: the agent always plays this ready deck (see the docstring).
    Seats alternate; the games are the same at every evaluation, so the numbers
    are comparable across the run."""
    kinds = [k for k in EVAL_KINDS if k not in ANCHOR_KINDS or "anchor" in models]
    specs = []
    for i in range(n_games):
        for kind in kinds:
            agent_seat = i % 2
            seed = EVAL_SEED + EVAL_KINDS.index(kind) * 10**7 + i
            rng = random.Random(seed)
            if kind in ANCHOR_KINDS:
                spec = deckgen.game_spec(rng, serial=i, seed=seed, bot="none", bot_seat=-1,
                                         log=i < n_text, presets=kind == "preset",
                                         deck=deck, deck_seat=agent_seat)
                spec["seat_models"] = ["agent", "anchor"] if agent_seat == 0 else ["anchor", "agent"]
            else:
                spec = deckgen.game_spec(rng, serial=i, seed=seed, bot=kind, bot_seat=1 - agent_seat,
                                         log=i < n_text, deck=deck, deck_seat=agent_seat)
                spec["seat_models"] = ["agent", "agent"]
            spec["agent_seat"] = agent_seat
            spec["kind"] = kind
            spec["idx"] = i
            specs.append(spec)
    queue = iter(specs)
    col = Collector(pool, range(pool.n_workers), table, lambda: next(queue, None), record=False)
    run_sync(col, models)
    stats = {"errors": col.errors}
    for kind in kinds:
        results = [r for r in col.results if r["kind"] == kind]
        for r in results:
            if r["log"] is None:
                continue
            spec = r["spec"]
            os.makedirs(text_dir, exist_ok=True)
            verdict = "победа агента" if r["win"] else ("ничья" if r["draw"] else "проигрыш агента")
            opponent = "якорь (более ранняя копия агента)" if kind in ANCHOR_KINDS else f"бот «{kind}»"
            with open(os.path.join(text_dir, f"{kind}_{spec['idx']:04d}.txt"), "w", encoding="utf-8") as f:
                f.write(f"Агент против: {opponent}. Агент играет за seat {r['agent_seat']}.\n")
                f.write(f"Результат: {verdict}, ходов: {r['turns']}.\n\n")
                for seat, pick in enumerate(spec["heroes"]):
                    f.write(f"Seat {seat}: {deckgen.describe_pick(pick)}\n")
                f.write("\n")
                f.write(r["log"] + "\n")
        n = max(1, len(results))
        wins = sum(r["win"] for r in results)
        draws = sum(r["draw"] for r in results)
        turns = float(np.mean([r["turns"] for r in results])) if results else 0.0
        stats[kind] = {"wr": wins / n, "draw": draws / n, "turns": turns, "n": len(results),
                       "wins": wins, "draws": draws}
    return stats


def elo_gap(score):
    """Elo difference that a score (wins + draws / 2 per game) against a player implies."""
    s = min(max(score, 0.02), 0.98)
    return 400.0 * math.log10(s / (1.0 - s))


def split_workers(n_workers, n_groups):
    return [list(range(g, n_workers, n_groups)) for g in range(n_groups)]


def frozen_copy(model):
    m = copy.deepcopy(model)
    m.eval()
    for p in m.parameters():
        p.requires_grad_(False)
    return m


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description="Card Wars self-play PPO from scratch")
    parser.add_argument("--games", type=int, default=1_000_000, help="total training games")
    parser.add_argument("--workers", type=int, default=12, help="Godot worker processes")
    parser.add_argument("--slots", type=int, default=16, help="games per worker")
    parser.add_argument("--groups", type=int, default=2, help="worker groups that take turns")
    parser.add_argument("--rollout", type=int, default=16384, help="decisions per PPO update")
    parser.add_argument("--minibatch", type=int, default=512)
    parser.add_argument("--epochs", type=int, default=2)
    parser.add_argument("--lr", type=float, default=3e-4, help="learning rate at the start")
    parser.add_argument("--lr-final", type=float, default=3e-5,
                        help="learning rate at --games (falls linearly)")
    parser.add_argument("--eval-every", type=int, default=10_000, help="games between evaluations")
    parser.add_argument("--eval-games", type=int, default=200, help="evaluation games per opponent")
    parser.add_argument("--eval-text", type=int, default=2, help="text logs per opponent and evaluation")
    parser.add_argument("--promote", type=float, default=0.65,
                        help="score against the anchor that makes the agent the new anchor")
    parser.add_argument("--snapshot-every", type=int, default=50_000,
                        help="games between snapshots (kept in snapshots/ and used as pool opponents)")
    parser.add_argument("--pool-frac", type=float, default=0.2,
                        help="share of training games against a past snapshot")
    parser.add_argument("--pool-size", type=int, default=20, help="latest snapshots used as opponents")
    parser.add_argument("--torch-threads", type=int, default=4,
                        help="PyTorch threads while the workers play (more slow them down)")
    parser.add_argument("--update-threads", type=int, default=12,
                        help="PyTorch threads for the PPO update (the workers wait meanwhile)")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--run-dir", default="",
                        help="default: the resumed checkpoint's folder, or runs/<timestamp>")
    parser.add_argument("--resume", default="", help="checkpoint .pt to continue from (use latest.pt)")
    parser.add_argument("--init", default="", help="checkpoint .pt whose weights start a new run "
                        "(it becomes the first anchor, Elo 0)")
    parser.add_argument("--deck", default="", help="ready deck id this network is trained for "
                        "(see table().hero_order)")
    parser.add_argument("--deck-samples", choices=["both", "own"], default="both",
                        help="learn from both seats (both) or only from the seat that plays --deck (own)")
    args = parser.parse_args()
    if args.resume and args.init:
        raise SystemExit("--resume and --init are different things: pick one")
    if args.deck and args.deck not in deckgen.table().hero_order:
        raise SystemExit(f"--deck {args.deck}: not a ready deck; choose one of: "
                         + ", ".join(deckgen.table().hero_order))

    torch.set_num_threads(args.torch_threads)
    torch.manual_seed(args.seed)
    if args.run_dir:
        run_dir = args.run_dir
    elif args.resume:
        run_dir = os.path.dirname(os.path.abspath(args.resume))
    else:
        stamp = time.strftime("%Y%m%d_%H%M%S") + (f"_{args.deck}" if args.deck else "")
        run_dir = os.path.join(ROOT, "rl_training", "runs", stamp)
    os.makedirs(run_dir, exist_ok=True)
    snap_dir = os.path.join(run_dir, "snapshots")
    os.makedirs(snap_dir, exist_ok=True)
    with open(os.path.join(run_dir, "config.json"), "w", encoding="utf-8") as f:
        json.dump(vars(args), f, ensure_ascii=False, indent=2)

    table = deckgen.table()
    dims = dict(DEFAULT_DIMS)
    model = CardWarsPolicy(table.static, **dims)
    opt = torch.optim.Adam(model.parameters(), lr=args.lr, eps=1e-5)
    run = {"anchor": None, "anchor_elo": 0.0, "anchor_gen": 0, "elo": None, "best_elo": -math.inf,
           "decisions": 0}
    games_before = 0
    if args.resume:
        ckpt = torch.load(args.resume, weights_only=False)
        if ckpt["table"] != table.signature:
            raise SystemExit(f"checkpoint was made for another card set: {ckpt['table']}")
        if ckpt.get("dims") != dims:
            raise SystemExit("checkpoint was made for another network (an older train_selfplay.py)")
        model.load_state_dict(ckpt["model"])
        opt.load_state_dict(ckpt["opt"])
        if ckpt.get("anchor") is not None:
            run["anchor"] = frozen_copy(model)
            run["anchor"].load_state_dict(ckpt["anchor"])
        for key in ("anchor_elo", "anchor_gen", "elo", "best_elo", "decisions"):
            if key in ckpt:
                run[key] = ckpt[key]
        games_before = ckpt["games"]
        print(f"resumed from {args.resume} at {games_before} games")
    if args.init:
        ckpt = torch.load(args.init, weights_only=False)
        if ckpt["table"] != table.signature:
            raise SystemExit(f"checkpoint was made for another card set: {ckpt['table']}")
        if ckpt.get("dims") != dims:
            raise SystemExit("checkpoint was made for another network (an older train_selfplay.py)")
        model.load_state_dict(ckpt["model"])
        # The start network is the first anchor (Elo 0): the evaluations measure against it.
        run["anchor"] = frozen_copy(model)
        print(f"started from {args.init} ({ckpt['games']} games of the general network)")

    # Past snapshots the agent plays against (name -> frozen model); changed only at evaluations.
    pool_models = {}

    def load_snapshot(path):
        snap = torch.load(path, weights_only=False)
        m = CardWarsPolicy(table.static, **snap["dims"])
        m.load_state_dict(snap["model"])
        pool_models[f"snap{snap['games']}"] = frozen_copy(m)
        while len(pool_models) > args.pool_size:
            pool_models.pop(next(iter(pool_models)))

    for path in sorted(glob.glob(os.path.join(snap_dir, "snap_*.pt"))):
        if int(os.path.basename(path)[5:-3]) <= games_before:
            load_snapshot(path)

    csv_path = os.path.join(run_dir, "log.csv")
    new_log = not os.path.exists(csv_path) or os.path.getsize(csv_path) == 0
    log_file = open(csv_path, "a", newline="", encoding="utf-8")
    writer = csv.writer(log_file)
    if new_log:
        writer.writerow(CSV_HEADER)
        log_file.flush()
    errors_path = os.path.join(run_dir, "errors.jsonl")

    n_groups = max(1, min(args.groups, args.workers))
    pool = WorkerPool(args.workers, args.slots, log_dir=os.path.join(run_dir, "workers"))
    groups = split_workers(args.workers, n_groups)
    text_dir = os.path.join(run_dir, "eval_logs")
    train_rng = random.Random(args.seed * 1000003 + games_before)
    # `base` is the finished total when the current collectors were made; `started` counts
    # the games handed out since then (games in flight at an evaluation are dropped).
    state = {"base": games_before, "started": 0, "serial": games_before}

    def make_spec():
        if state["started"] >= args.games - state["base"]:
            return None
        state["started"] += 1
        state["serial"] += 1
        seed = train_rng.randrange(1, 2**31 - 1)
        spec = deckgen.game_spec(train_rng, state["serial"], seed=seed, deck=args.deck)
        if args.deck and args.deck_samples == "own":
            spec["learn"] = [spec["deck_seat"]]
        if pool_models and train_rng.random() < args.pool_frac:
            name = train_rng.choice(list(pool_models))
            spec["seat_models"] = ["agent", name] if train_rng.random() < 0.5 else [name, "agent"]
        return spec

    def new_collectors():
        state["started"] = 0
        return [Collector(pool, g, table, make_spec, record=True) for g in groups]

    print(f"run dir: {run_dir}")
    print(f"training games {games_before} -> {args.games}; {args.workers} workers x {args.slots} slots "
          f"in {n_groups} groups; {len(pool_models)} pool snapshots")
    t_start = time.time()
    decisions_start = run["decisions"]
    next_eval = (games_before // args.eval_every + 1) * args.eval_every
    next_snapshot = (games_before // args.snapshot_every + 1) * args.snapshot_every
    last = {"pg": 0.0, "v": 0.0, "ent": 0.0, "kl": 0.0, "clip": 0.0, "lr": args.lr}
    carry = []
    recent_turns = deque(maxlen=2000)
    recent_capped = deque(maxlen=2000)
    errors_total = 0
    cols = new_collectors()

    def finished_total():
        return state["base"] + sum(c.games_finished for c in cols)

    def train_models():
        return {"agent": model, **pool_models}

    def eval_models():
        models = {"agent": model}
        if run["anchor"] is not None:
            models["anchor"] = run["anchor"]
        return models

    def log_errors(errors, games_now):
        nonlocal errors_total
        if not errors:
            return
        errors_total += len(errors)
        with open(errors_path, "a", encoding="utf-8") as f:
            for e in errors:
                f.write(json.dumps({"games": games_now, **e}, ensure_ascii=False) + "\n")

    def write_row(games_now, stats):
        elapsed = time.time() - t_start
        turns = float(np.mean(recent_turns)) if recent_turns else 0.0
        capped = float(np.mean(recent_capped)) if recent_capped else 0.0
        gpm = (games_now - games_before) / max(elapsed / 60.0, 1e-9)
        dps = (run["decisions"] - decisions_start) / max(elapsed, 1e-9)
        row = [games_now, run["decisions"], round(elapsed / 60, 2), round(gpm, 1), round(dps),
               f"{last['lr']:.2e}", round(last["pg"], 5), round(last["v"], 5), round(last["ent"], 4),
               round(last["kl"], 5), round(last["clip"], 4), round(turns, 2), round(capped, 4), errors_total,
               round(run["elo"], 1), round(run["anchor_elo"], 1), run["anchor_gen"]]
        for kind in EVAL_KINDS:
            k = stats.get(kind)
            row += [round(k["wr"], 4), round(k["draw"], 4), round(k["turns"], 2)] if k else ["", "", ""]
        writer.writerow(row)
        log_file.flush()
        return elapsed

    def save(games_now, path):
        torch.save({"model": model.state_dict(), "opt": opt.state_dict(), "games": games_now,
                    "table": table.signature, "args": vars(args), "dims": dims,
                    "anchor": run["anchor"].state_dict() if run["anchor"] is not None else None,
                    "anchor_elo": run["anchor_elo"], "anchor_gen": run["anchor_gen"], "elo": run["elo"],
                    "best_elo": run["best_elo"], "decisions": run["decisions"]}, path)

    def describe(stats):
        parts = [f"Elo {run['elo']:7.1f} (anchor #{run['anchor_gen']} {run['anchor_elo']:.0f})",
                 f"heuristic {stats['heuristic']['wr']*100:5.1f}%",
                 f"random {stats['random']['wr']*100:5.1f}%"]
        for kind in ANCHOR_KINDS:
            if kind in stats:
                parts.append(f"{kind} {stats[kind]['wr']*100:5.1f}%")
        return " | ".join(parts)

    def evaluate(games_now, n_text):
        """Plays the evaluation, moves the Elo and the anchor, writes the row and checkpoints."""
        eval_start = time.time()
        stats = run_evals(eval_models(), pool, table, args.eval_games, n_text, text_dir, deck=args.deck)
        log_errors(stats["errors"], games_now)
        if run["anchor"] is None:
            # The first evaluation sets the scale: this agent is Elo 0 and the first anchor.
            run["elo"] = 0.0
            run["anchor"] = frozen_copy(model)
        else:
            games = sum(stats[k]["n"] for k in ANCHOR_KINDS)
            points = sum(stats[k]["wins"] + 0.5 * stats[k]["draws"] for k in ANCHOR_KINDS)
            score = points / max(1, games)
            run["elo"] = run["anchor_elo"] + elo_gap(score)
            if score >= args.promote:
                run["anchor"] = frozen_copy(model)
                run["anchor_elo"] = run["elo"]
                run["anchor_gen"] += 1
        elapsed = write_row(games_now, stats)
        improved = run["elo"] > run["best_elo"]
        if improved:
            run["best_elo"] = run["elo"]     # before saving latest.pt: a resumed run must know it
        save(games_now, os.path.join(run_dir, "latest.pt"))
        if improved:
            save(games_now, os.path.join(run_dir, "best.pt"))
        print(f"[{games_now:>8} games] {describe(stats)} | capped {np.mean(recent_capped or [0])*100:4.1f}% "
              f"errors {errors_total} | pg {last['pg']:+.4f} v {last['v']:.4f} ent {last['ent']:.3f} "
              f"lr {last['lr']:.1e} | {elapsed/60:6.1f} min (eval {time.time()-eval_start:4.1f}s)", flush=True)
        return stats

    def take(c):
        """Collects what a collector has finished: samples for PPO, turn counts for the log."""
        carry.extend(c.samples)
        c.samples = []
        recent_turns.extend(c.turns)
        c.turns = []
        recent_capped.extend(c.capped)
        c.capped = []
        log_errors(c.errors, finished_total())
        c.errors = []

    def maybe_update(force=False):
        nonlocal carry
        if carry and (len(carry) >= args.rollout or force):
            lr = args.lr + (args.lr_final - args.lr) * min(1.0, finished_total() / max(1, args.games))
            for group in opt.param_groups:
                group["lr"] = lr
            torch.set_num_threads(args.update_threads)
            last.update(ppo_update(model, opt, carry, args))
            torch.set_num_threads(args.torch_threads)
            last["lr"] = lr
            run["decisions"] += len(carry)
            carry = []

    for c in cols:
        c.send_next(train_models(), greedy=False)

    while True:
        games_now = finished_total()
        if games_now >= next_eval and games_now < args.games:
            # The evaluation needs the workers: finish what is in flight, keep the finished games.
            for c in cols:
                c.receive()
                take(c)
            maybe_update()
            games_now = finished_total()
            evaluate(games_now, args.eval_text)
            if games_now >= next_snapshot:
                path = os.path.join(snap_dir, f"snap_{games_now:09d}.pt")
                torch.save({"model": model.state_dict(), "dims": dims, "games": games_now,
                            "table": table.signature}, path)
                load_snapshot(path)
                next_snapshot = (games_now // args.snapshot_every + 1) * args.snapshot_every
            next_eval = (games_now // args.eval_every + 1) * args.eval_every
            state["base"] = games_now
            cols = new_collectors()
            for c in cols:
                c.send_next(train_models(), greedy=False)
            continue

        # One turn of the pipeline: read one group's replies, learn, send its next batch.
        for c in cols:
            c.receive()
            take(c)
            maybe_update()
            c.send_next(train_models(), greedy=False)
        if finished_total() >= args.games and not any(c.busy() for c in cols):
            break
    for c in cols:
        take(c)
    maybe_update(force=True)

    games_now = finished_total()
    stats = evaluate(games_now, 0)
    log_file.close()
    pool.close()
    print(f"done: {games_now} games; final: {describe(stats)}; best Elo {run['best_elo']:.1f}")
    print(f"log: {csv_path}")
    print(f"for the game: python export_model.py {os.path.join(run_dir, 'best.pt')}")


if __name__ == "__main__":
    main()
