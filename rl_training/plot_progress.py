"""Draws how the agent's strength grew with the number of training games.

    python plot_progress.py runs/<name>

Reads runs/<name>/log.csv (written by train_selfplay.py), saves runs/<name>/progress.png
and prints the game where the agent was strongest.

Strength is the Elo column: the agent of the first evaluation is 0, and every
evaluation adds what the score against the current anchor implies to that
anchor's Elo. It keeps growing after the bots are beaten, so the peak is taken
from it. The shaded band is a 95% interval of one evaluation's Elo against its
anchor; vertical ticks mark the evaluations where the agent became the new anchor.
"""
import csv
import json
import math
import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def num(value):
    return float(value) if value not in ("", None) else None


def elo_band(score, n):
    """Half-width of a 95% interval of the Elo gap a score over n games implies."""
    s = min(max(score, 0.02), 0.98)
    se = math.sqrt(s * (1 - s) / max(n, 1))
    return 1.96 * se * 400 / math.log(10) / (s * (1 - s))


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if len(sys.argv) < 2:
        raise SystemExit("usage: python plot_progress.py runs/<name>")
    run = sys.argv[1]
    with open(os.path.join(run, "log.csv"), encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    with open(os.path.join(run, "config.json"), encoding="utf-8") as f:
        n = 2 * int(json.load(f)["eval_games"])       # anchor + preset games
    if not rows:
        raise SystemExit("log.csv has no evaluations yet")

    games = [int(r["games"]) for r in rows]
    elo = [num(r["elo"]) for r in rows]
    gen = [int(r["anchor_gen"]) for r in rows]
    entropy = [float(r["entropy"]) for r in rows]
    v_loss = [float(r["v_loss"]) for r in rows]
    capped = [num(r.get("capped")) or 0.0 for r in rows]

    def series(key):
        pts = [(g, num(r[key])) for g, r in zip(games, rows) if num(r[key]) is not None]
        return [p[0] for p in pts], [p[1] for p in pts]

    fig, (ax, ax_wr, ax2) = plt.subplots(3, 1, figsize=(10, 11), sharex=True,
                                         gridspec_kw={"height_ratios": [3, 2, 1.3]})
    ax.plot(games, elo, marker="o", ms=3, lw=2.0, color="#d62728", label="Elo агента")
    lo, hi = [], []
    for r, e in zip(rows, elo):
        wa, da, wp, dp = (num(r.get(k)) for k in ("wr_anchor", "draw_anchor", "wr_preset", "draw_preset"))
        if wa is None or wp is None:
            lo.append(e)
            hi.append(e)
            continue
        score = (wa + da / 2 + wp + dp / 2) / 2
        w = elo_band(score, n)
        lo.append(e - w)
        hi.append(e + w)
    ax.fill_between(games, lo, hi, color="#d62728", alpha=0.12)
    for k in range(1, len(rows)):
        if gen[k] > gen[k - 1]:
            ax.axvline(games[k], color="#999999", lw=0.6, ls=":")
    peak = max(range(len(elo)), key=lambda i: elo[i])
    best_g, best_e = games[peak], elo[peak]
    ax.scatter([best_g], [best_e], s=90, color="#2ca02c", zorder=5)
    ax.annotate(f"пик: {best_g:,} игр\nElo {best_e:.0f}", xy=(best_g, best_e), xytext=(12, -38),
                textcoords="offset points", fontsize=10, color="#2ca02c",
                arrowprops=dict(arrowstyle="-", color="#2ca02c"))
    ax.set_ylabel("Elo (агент первой оценки = 0)")
    ax.set_title("Обучение с нуля: сила агента")
    ax.grid(alpha=0.3)
    ax.legend(loc="lower right")

    for key, label, color, lw in (("wr_heur", "против эвристического бота", "#1f77b4", 1.2),
                                  ("wr_rand", "против случайного бота", "#7f7f7f", 1.0),
                                  ("wr_anchor", "против якоря (случайные колоды)", "#d62728", 1.4),
                                  ("wr_preset", "против якоря (готовые колоды)", "#ff7f0e", 1.4)):
        g, v = series(key)
        if v:
            ax_wr.plot(g, [x * 100 for x in v], marker="o", ms=2, lw=lw, color=color, label=label)
    ax_wr.plot(games, [c * 100 for c in capped], lw=1.0, ls="--", color="#8c564b",
               label="партий, оборванных лимитом, %")
    ax_wr.axhline(50, color="grey", lw=0.8, ls=":")
    ax_wr.set_ylim(0, 100)
    ax_wr.set_ylabel("побед агента, %")
    ax_wr.grid(alpha=0.3)
    ax_wr.legend(loc="lower right", fontsize=8)

    ax2.plot(games, entropy, color="#9467bd", lw=1.4, label="энтропия политики")
    ax2.set_ylabel("энтропия")
    ax2b = ax2.twinx()
    ax2b.plot(games, v_loss, color="#8c564b", lw=1.1, alpha=0.8, label="ошибка оценки (value loss)")
    ax2b.set_ylabel("value loss")
    ax2.set_xlabel("сыгранных игр")
    ax2.grid(alpha=0.3)
    handles = ax2.get_lines() + ax2b.get_lines()
    ax2.legend(handles, [h.get_label() for h in handles], loc="upper right", fontsize=9)

    fig.tight_layout()
    out = os.path.join(run, "progress.png")
    fig.savefig(out, dpi=130)

    print(f"peak: game {best_g:,}, Elo {best_e:.0f} (anchor #{gen[peak]})")
    h = num(rows[peak]["wr_heur"])
    if h is not None:
        print(f"  at that game: vs heuristic {h * 100:.1f}%")
    print(f"last: game {games[-1]:,}, Elo {elo[-1]:.0f}, anchors {gen[-1]}")
    print(f"chart: {out}")


if __name__ == "__main__":
    main()
