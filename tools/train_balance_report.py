"""Tables from the runs of tools/train_balance.gd (markdown to stdout).

  python tools/train_balance_report.py DIR TAG [TAG ...] [--title TEXT] [--sections a,b,c]

TAG is a prefix of the files DIR/TAG_<shard>.jsonl (the runs of one setting). The sections:
surv, deaths, hp, fights, fatigue, heals, ohko, items, econ, growth, choices. Standard errors are
binomial (mean +- se); item effects are differences of the win rate against the fights of the same
kind, train and part of the train without the item (Mantel-Haenszel weights).
"""
import glob
import json
import math
import os
import sys
from collections import defaultdict

HEAL_NAMES = {
    "game.gd:_lifesteal": "вампиризм", "game.gd:_start_turn": "регенерация и колокол", "game.gd:_wagon_turn_start": "вагон (пикник, кубик)",
    "game.gd:_item_spell": "заклинание (чайник)", "game.gd:_item_died": "медальон (смерть существа)",
}


def load(d, tag):
    runs = []
    for fn in sorted(glob.glob("%s/%s_*.jsonl" % (d, tag))):
        for line in open(fn, encoding="utf8"):
            if line.strip():
                runs.append(json.loads(line))
    return runs


def mean(xs):
    xs = list(xs)
    return sum(xs) / len(xs) if xs else float("nan")


def se(xs):
    xs = list(xs)
    if len(xs) < 2:
        return float("nan")
    m = mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1) / len(xs))


def pct(x):
    return "%.0f%%" % (100 * x) if x == x else "-"


def ms(xs, f="%.1f"):
    xs = list(xs)
    if not xs:
        return "-"
    return (f + "±" + f) % (mean(xs), se(xs))


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(x) for x in r) + " |")
    return "\n".join(out)


def fights_of(runs):
    for r in runs:
        for f in r["fights"]:
            f["_run"] = r
            yield f


def heal_name(tag):
    k = tag.rsplit(":", 1)[0]
    return HEAL_NAMES.get(k, k.replace(".gd", ""))


def win_turns(f):
    """Own turns the winner had when the fight ended (turn 1 belongs to `first`)."""
    t = f["turns"]
    w = 0 if f["won"] else 1
    t_first = (t + 1) // 2
    return t_first if w == f["first"] else t // 2


def sec_surv(runs, title):
    mortal = [r for r in runs if not r["immortal"]]
    if not mortal:
        return ""
    n = len(mortal)
    out = ["### Выживание: %s (забегов %d)" % (title, n), ""]
    ps = [r["passed"] for r in mortal]
    cap = max(r["passed"] for r in mortal if r["died"] is None) if any(r["died"] is None for r in mortal) else 0
    out.append("Пройдено вагонов: среднее %s, медиана %d, дошли до лимита (без смерти) %s." % (
        ms(ps), sorted(ps)[n // 2], pct(sum(1 for r in mortal if r["died"] is None) / n)))
    rows = []
    for k in [1, 2, 3, 4, 5, 6, 8, 10, 11, 13, 15, 20, 21, 25, 30, 31, 40]:
        reached = [1 if r["passed"] >= k or r["died"] is None and r["passed"] >= k else 0 for r in mortal]
        p = mean(reached)
        rows.append(("пройден вагон %d" % k, pct(p), "±%.1f%%" % (100 * math.sqrt(max(p * (1 - p), 1e-9) / n))))
    out.append(table(["точка", "доля", "se"], rows))
    out.append("")
    out.append("Смерть по номеру вагона (условно: умер на вагоне k | дошёл до k):")
    rows = []
    for k in range(0, 31):
        reach = [r for r in mortal if r["passed"] >= k]
        died = [r for r in reach if r["died"] and r["passed"] == k]
        if len(reach) >= 10:
            rows.append((k + 1, len(reach), len(died), pct(len(died) / len(reach))))
    out.append(table(["вагон", "дошли", "умерли", "риск"], rows))
    return "\n".join(out)


def sec_deaths(runs, title):
    mortal = [r for r in runs if not r["immortal"] and r["died"]]
    if not mortal:
        return ""
    out = ["### Смерти: %s (%d)" % (title, len(mortal)), ""]
    for key in ["kind", "enemy", "rule", "cause", "tr"]:
        c = defaultdict(int)
        for r in mortal:
            c[str(r["died"][key]) or "-"] += 1
        out.append("%s: %s" % (key, ", ".join("%s %s" % (k, pct(v / len(mortal))) for k, v in sorted(c.items(), key=lambda x: -x[1])[:14])))
        out.append("")
    return "\n".join(out)


def sec_hp(runs, title):
    by = defaultdict(list)
    low = defaultdict(list)
    mhp = defaultdict(list)
    for r in runs:
        for s in r["snaps"]:
            by[s["p"]].append(s["hp"])
            mhp[s["p"]].append(s["mhp"])
            low[s["p"]].append(1 if s["hp"] < 0.4 * s["mhp"] else 0)
    out = ["### HP героя на входе в вагон: %s" % title, ""]
    rows = []
    for k in sorted(by):
        if len(by[k]) >= 15 and (k < 12 or k % 5 == 0):
            rows.append((k + 1, len(by[k]), ms(by[k]), ms(mhp[k]), pct(mean(low[k]))))
    out.append(table(["вагон", "n", "HP", "макс. HP", "HP<40%"], rows))
    return "\n".join(out)


def sec_fights(runs, title):
    fs = list(fights_of(runs))
    out = ["### Бои по поездам и видам: %s" % title, ""]
    rows = []
    for tr in range(1, 8):
        for kind in ["fight", "elite", "double", "boss"]:
            g = [f for f in fs if f["tr"] == tr and f["kind"] == kind]
            if len(g) < 15:
                continue
            w = [1 if f["won"] else 0 for f in g]
            lost = [f["hp0"] - f["hp_left"] for f in g if f["won"]]
            rows.append((tr, kind, len(g), "%s±%.0f" % (pct(mean(w)), 100 * se(w)), ms([f["turns"] for f in g]), ms(lost), mean(f["ehp"] for f in g).__round__(1)))
    out.append(table(["поезд", "вид", "боёв", "победы", "ходов (оба)", "HP потеряно в победах", "HP врага"], rows))
    return "\n".join(out)


def sec_fatigue(runs, title):
    fs = list(fights_of(runs))
    out = ["### Усталость и колоды: %s" % title, ""]
    rows = []
    for tr in range(1, 8):
        g = [f for f in fs if f["tr"] == tr]
        if len(g) < 20:
            continue
        lost = [f for f in g if not f["won"]]
        rows.append((tr, len(g), pct(mean(1 if f["draw_fails"][0] > 0 else 0 for f in g)), pct(mean(1 if f["draw_fails"][1] > 0 else 0 for f in g)),
                     "%.2f" % mean(f["dmg"][0].get("fatigue", 0) for f in g), "%.2f" % mean(f["dmg"][1].get("fatigue", 0) for f in g),
                     pct(mean(1 if f["last"][1] == "fatigue" and f["won"] else 0 for f in g)),
                     pct(mean(1 if f["cause"] == "fatigue" else 0 for f in lost)) if lost else "-",
                     "%.1f" % mean(f["deck"] for f in g)))
    out.append(table(["поезд", "боёв", "у героя пустая колода", "у врага пустая колода", "урон усталости герою", "врагу", "бои, добитые усталостью врага", "поражения от усталости (доля поражений)", "карт в колоде героя"], rows))
    out.append("")
    ps = [f["turns"] for f in fs]
    out.append("Длина боя (оба игрока): среднее %s, 90-й процентиль %d, макс %d; боёв >=40 ходов %s, застрявших %s." % (
        ms(ps), sorted(ps)[int(0.9 * len(ps))], max(ps), pct(mean(1 if t >= 40 else 0 for t in ps)), pct(mean(1 if f["cause"] == "stuck" else 0 for f in fs))))
    return "\n".join(out)


def sec_heals(runs, title):
    fs = list(fights_of(runs))
    out = ["### Лечение: %s" % title, ""]
    for side, nm in [(0, "герой"), (1, "враг")]:
        tot = defaultdict(float)
        for f in fs:
            for k, v in f["heals"][side].items():
                tot[heal_name(k)] += v
        rows = [(k, "%.2f" % (v / len(fs))) for k, v in sorted(tot.items(), key=lambda x: -x[1])[:12]]
        out.append("Лечение за бой, %s (среднее по %d боям, всего %.2f):" % (nm, len(fs), sum(tot.values()) / len(fs)))
        out.append(table(["источник", "HP за бой"], rows))
        out.append("")
    # outside the fights
    win_heal = defaultdict(list)
    for f in fs:
        if f["won"] and "hp_after" in f:
            win_heal[f["kind"]].append(f["hp_after"] - f["hp_left"])
    out.append("Лечение после победы (HP, учитывая максимум): " + ", ".join("%s %s" % (k, ms(v, "%.1f")) for k, v in win_heal.items()))
    rest = [e for r in runs for e in r["ev"] if e["t"] == "rest"]
    if rest:
        heals = [min(e["heal"], e["mhp"] - e["hp0"]) for e in rest if e["choice"] == "heal"]
        out.append("")
        out.append("Отдых: %d, лечат %s, средний эффективный хил %s, улучшение %s, убрать %s, земля %s." % (
            len(rest), pct(len(heals) / len(rest)), ms(heals), pct(mean(1 if e["choice"] == "upgrade" else 0 for e in rest)),
            pct(mean(1 if e["choice"] == "remove" else 0 for e in rest)), pct(mean(1 if e["choice"] == "land" else 0 for e in rest))))
    # walls
    out.append("")
    zero = [f for f in fs if sum(f["dmg"][1].values()) == 0]
    net = [f for f in fs if sum(f["heals"][1].values()) >= sum(f["dmg"][1].values()) > 0]
    big = [f for f in fs if sum(f["heals"][1].values()) >= 6]
    out.append("Бои, где враг не получил урона: %s; где вылечил не меньше, чем получил: %s; где враг вылечил >=6 HP: %s." % (
        pct(len(zero) / len(fs)), pct(len(net) / len(fs)), pct(len(big) / len(fs))))
    out.append("Из них проиграно: без урона %s, враг вылечил >= получил %s, >=6 HP хила %s." % (
        pct(mean(0 if f["won"] else 1 for f in zero)) if zero else "-", pct(mean(0 if f["won"] else 1 for f in net)) if net else "-",
        pct(mean(0 if f["won"] else 1 for f in big)) if big else "-"))
    out.append("")
    out.append("Враг лечится (по источникам, бои, где враг вылечил >=6): " + ", ".join(
        "%s %d" % (k, v) for k, v in sorted(defaultdict(int, {heal_name(k): sum(1 for f in big for kk in f["heals"][1] if heal_name(kk) == k) for k in
                                                                {heal_name(kk) for f in big for kk in f["heals"][1]}}).items(), key=lambda x: -x[1])[:8]))
    # enemy-heal vs enemy deck / rule
    byenemy = defaultdict(list)
    byrule = defaultdict(list)
    for f in fs:
        byenemy[f["enemy"]].append(sum(f["heals"][1].values()))
        byrule[f["rule"] or "-"].append(sum(f["heals"][1].values()))
    out.append("")
    out.append("Хил врага за бой по колодам: " + ", ".join("%s %.1f" % (k, mean(v)) for k, v in sorted(byenemy.items(), key=lambda x: -mean(x[1]))[:8]))
    out.append("")
    out.append("Хил врага за бой по правилам вагона: " + ", ".join("%s %.1f (n=%d)" % (k, mean(v), len(v)) for k, v in sorted(byrule.items(), key=lambda x: -mean(x[1]))[:8] if len(v) >= 8))
    byrule_h = defaultdict(list)
    for f in fs:
        byrule_h[f["rule"] or "-"].append(sum(f["heals"][0].values()))
    out.append("")
    out.append("Хил героя за бой по правилам вагона: " + ", ".join("%s %.1f" % (k, mean(v)) for k, v in sorted(byrule_h.items(), key=lambda x: -mean(x[1]))[:6] if len(v) >= 8))
    return "\n".join(out)


def sec_ohko(runs, title):
    fs = list(fights_of(runs))
    out = ["### Темп и ваншоты: %s" % title, ""]
    rows = []
    for tr in range(1, 8):
        g = [f for f in fs if f["tr"] == tr]
        if len(g) < 20:
            continue
        wins = [f for f in g if f["won"]]
        losses = [f for f in g if not f["won"]]
        quick_w = mean(1 if f["won"] and win_turns(f) <= 2 else 0 for f in g)
        quick_l = mean(1 if (not f["won"]) and win_turns(f) <= 2 else 0 for f in g)
        pdmg = [sum(f["dmg"][1].values()) for f in g]
        edmg = [sum(f["dmg"][0].values()) for f in g]
        pt = [max((f["turns"] + (1 if f["first"] == 0 else 0)) // 2, 1) for f in g]
        hit_p = [f["hits"][1][2] for f in g if f["hits"][1][0] > 0]
        hit_e = [f["hits"][0][2] for f in g if f["hits"][0][0] > 0]
        pk = [f for f in g if "peak" in f]
        one_h = pct(mean(1 if f["peak"][1] >= f["ehp"] else 0 for f in pk)) if pk else "-"
        one_e = pct(mean(1 if f["peak"][0] >= f["hp0"] else 0 for f in pk)) if pk else "-"
        burst_h = "%.1f" % mean(f["peak"][1] for f in pk) if pk else "-"
        burst_e = "%.1f" % mean(f["peak"][0] for f in pk) if pk else "-"
        rows.append((tr, len(g), pct(quick_w), pct(quick_l), "%.1f" % mean(f["ehp"] for f in g), "%.1f" % mean(pdmg), "%.1f" % mean(a / b for a, b in zip(pdmg, pt)),
                     "%.1f" % mean(edmg), "%.1f" % mean(hit_p), "%.1f" % mean(hit_e), "%.1f" % mean(f["mhp"] for f in g), burst_h, one_h, burst_e, one_e))
    out.append(table(["поезд", "боёв", "герой выиграл за <=2 своих хода", "враг выиграл за <=2 своих хода", "HP врага", "урон героя по врагу за бой", "за ход героя", "урон врага по герою за бой", "макс. удар героя по лицу", "макс. удар врага по лицу", "макс. HP героя", "лучший ход героя, урон", "ваншот врага за один ход", "лучший ход врага, урон", "ваншот героя за один ход"], rows))
    return "\n".join(out)


def mh(strata):
    """Mantel-Haenszel style effect: sum of weighted differences. strata: list of (with: [x], without: [x])."""
    num = 0.0
    den = 0.0
    var = 0.0
    for a, b in strata:
        if len(a) < 1 or len(b) < 1:
            continue
        w = len(a) * len(b) / (len(a) + len(b))
        d = mean(a) - mean(b)
        num += w * d
        den += w
        va = sum((x - mean(a)) ** 2 for x in a) / max(len(a) - 1, 1)
        vb = sum((x - mean(b)) ** 2 for x in b) / max(len(b) - 1, 1)
        var += w * w * (va / len(a) + vb / len(b))
    if den == 0:
        return float("nan"), float("nan")
    return num / den, math.sqrt(var) / den


def effects(fs, member, outcome):
    """For every key member(f) gives: stratum-adjusted difference of outcome(f), se, n with."""
    keys = defaultdict(int)
    strata = defaultdict(list)
    for f in fs:
        strata[(f["kind"], f["tr"], f["p"] // 3)].append(f)
    res = {}
    allkeys = set()
    for f in fs:
        allkeys.update(member(f))
    for key in allkeys:
        parts = []
        nw = 0
        for g in strata.values():
            a = [outcome(f) for f in g if key in member(f)]
            b = [outcome(f) for f in g if key not in member(f)]
            nw += len(a)
            parts.append((a, b))
        d, s = mh(parts)
        res[key] = (d, s, nw)
    return res


def sec_items(runs, title):
    fs = list(fights_of(runs))
    out = ["### Влияние на следующие бои: %s (боёв %d)" % (title, len(fs)), ""]
    out.append("Разность доли побед (с предметом против без, в тех же вид+поезд+вагон//3), п.п.; вторая колонка: разность потерянных HP героя в бою, % макс. HP (минус = лучше).")
    out.append("")
    for nm, member in [("предметы", lambda f: f["items"]), ("наборы", lambda f: ["набор:" + s for s in f["sets"]]),
                       ("проклятия", lambda f: f["curses"]), ("перки (уровень статов)", lambda f: [k for k, v in f["perks"].items() if v]),
                       ("прочее", lambda f: (["тёмная дверь"] if f["dark"] else []) + (["двойной"] if f["double"] else []))]:
        win = effects(fs, member, lambda f: 1.0 if f["won"] else 0.0)
        loss = effects(fs, member, lambda f: (f["hp0"] - f["hp_left"]) / max(f["mhp"], 1))
        turns = effects(fs, member, lambda f: float(f["turns"]))
        rows = []
        for k, (d, s, n) in win.items():
            if n >= 40:
                rows.append((k, n, 100 * d, 100 * s, 100 * loss[k][0], turns[k][0]))
        rows.sort(key=lambda r: (r[4] + 0.0) + 0.5 * (-r[2]))
        out.append("**%s** (n боёв с ним >= 40; сверху сильнее)" % nm)
        sel = rows[:12] + [None] + rows[-12:] if len(rows) > 26 and not os.environ.get("FULL") else rows
        out.append(table(["что", "боёв с ним", "Δ побед п.п.", "se", "Δ потерь HP, п.п. макс.", "Δ ходов боя"],
                         [("…", "", "", "", "", "") if r is None else (r[0], r[1], "%+.1f" % r[2], "%.1f" % r[3], "%+.1f" % r[4], "%+.1f" % r[5]) for r in sel]))
        out.append("")
    return "\n".join(out)


def sec_econ(runs, title):
    out = ["### Монеты: %s" % title, ""]
    by = defaultdict(lambda: defaultdict(float))
    cnt = defaultdict(int)
    for r in runs:
        seen = set()
        for p, what, amt in r["eco"]:
            by[p // 5][what] += amt
        for s in r["snaps"]:
            if s["p"] // 5 not in seen:
                seen.add(s["p"] // 5)
                cnt[s["p"] // 5] += 1
    cats = ["fight", "event", "shop_item", "shop_card", "shop_upgrade", "shop_uncurse"]
    rows = []
    for b in sorted(by):
        if cnt[b] >= 20:
            rows.append(("%d-%d" % (b * 5 + 1, b * 5 + 5),) + tuple("%.1f" % (by[b][c] / cnt[b]) for c in cats) + ("%.1f" % mean(s["coins"] for r in runs for s in r["snaps"] if s["p"] // 5 == b),))
    out.append("Монет за забег на пятёрку вагонов (+ доход, − трата), на забег, который дошёл до пятёрки:")
    out.append(table(["вагоны"] + cats + ["монет в кошельке на входе"], rows))
    return "\n".join(out)


def sec_growth(runs, title):
    fs = list(fights_of(runs))
    out = ["### Рост героя по поездам: %s" % title, ""]
    rows = []
    for tr in range(1, 8):
        g = [f for f in fs if f["tr"] == tr]
        if len(g) < 20:
            continue
        def st(k):
            return mean(f["fstats"].get(k, 0) for f in g)
        rows.append((tr, len(g), "%.0f" % mean(f["mhp"] for f in g), "%.0f" % st("crit"), "%.0f" % st("crit_dmg"), "%.0f" % st("lifesteal"), "%.1f" % st("armor"), "%.1f" % st("regen"),
                     "%.1f" % st("atk"), "%.1f" % st("actions"), "%.1f" % mean(len(f["items"]) for f in g), "%.0f" % mean(f["deck"] for f in g), "%.1f" % mean(f["ehp"] for f in g),
                     pct(mean(1 if f["won"] else 0 for f in g))))
    out.append(table(["поезд", "боёв", "макс. HP", "крит%", "сила крита", "вампиризм%", "броня", "реген", "сила существ", "действия", "предметов", "карт", "HP врага", "победы"], rows))
    return "\n".join(out)


def sec_choices(runs, title):
    out = ["### Выбор и события: %s" % title, ""]
    perks = defaultdict(int)
    for r in runs:
        for e in r["ev"]:
            if e["t"] == "perk":
                perks[e["key"]] += 1
    out.append("Перки взято: " + ", ".join("%s %d" % (k, v) for k, v in sorted(perks.items(), key=lambda x: -x[1])))
    ev = defaultdict(lambda: [0, 0.0, 0.0, 0])
    for r in runs:
        for e in r["ev"]:
            if e["t"] == "event":
                k = (e["id"], e.get("label", "уйти"))
                ev[k][0] += 1
                if e["opt"] >= 0:
                    ev[k][1] += e["hp1"] - e["hp"]
                    ev[k][2] += e["mhp1"] - e["mhp"]
    rows = [(k[0], k[1], v[0], "%+.1f" % (v[1] / v[0]), "%+.1f" % (v[2] / v[0])) for k, v in sorted(ev.items())]
    out.append("")
    out.append(table(["событие", "вариант", "раз", "сдвиг HP", "сдвиг макс. HP"], rows))
    return "\n".join(out)


def sec_bench(runs, title):
    """Bench lines (mode=bench) are not runs: `runs` is the list of fight lines."""
    by = defaultdict(dict)
    for f in runs:
        by[f["what"]][f["j"]] = f
    base = by.get("none:", {})
    out = ["### Стенд: по одной вещи на стандартном герое (%s), боёв на вещь %d" % (title, len(base)), ""]
    rows = []
    for what, fs in by.items():
        if what == "none:":
            continue
        dw, dl, dt, dh = [], [], [], []
        for j, f in fs.items():
            b = base.get(j)
            if b is None:
                continue
            dw.append((1 if f["won"] else 0) - (1 if b["won"] else 0))
            dl.append(100 * (f["hp_lost"] / max(f["mhp"], 1) - b["hp_lost"] / max(b["mhp"], 1)))
            dt.append(f["turns"] - b["turns"])
            dh.append(sum(f["heals"][1].values()) - sum(b["heals"][1].values()))
        if dw:
            rows.append((what, len(dw), 100 * mean(dw), 100 * se(dw), mean(dl), mean(dt), mean(dh)))
    rows.sort(key=lambda r: -r[2])
    wins = mean(1 if f["won"] else 0 for f in base.values())
    out.append("Без вещи: побед %s, потерь HP %.1f%% макс., ходов %.1f." % (pct(wins), mean(100 * f["hp_lost"] / f["mhp"] for f in base.values()), mean(f["turns"] for f in base.values())))
    out.append("")
    out.append(table(["вещь", "боёв", "Δ побед п.п.", "se", "Δ потерь HP п.п. макс.", "Δ ходов", "Δ хила врага"],
                     [(r[0], r[1], "%+.1f" % r[2], "%.1f" % r[3], "%+.1f" % r[4], "%+.1f" % r[5], "%+.1f" % r[6]) for r in rows]))
    return "\n".join(out)


def sec_enemy(runs, title):
    fs = list(fights_of(runs))
    out = ["### Что делает врага сильнее: %s (боёв %d)" % (title, len(fs)), "",
           "Δ побед героя (п.п.) и Δ потерь HP (п.п. макс.) против боёв того же вида, поезда и части поезда без этого. Минус = враг сильнее.", ""]
    for nm, member in [("статы врага", lambda f: ["стат:" + k for k in f["estats"]]), ("правило вагона", lambda f: ["вагон:" + f["rule"]] if f["rule"] else []),
                       ("колода врага", lambda f: ["колода:" + f["enemy"]]), ("ИИ врага", lambda f: ["ИИ:" + f["lv"]])]:
        win = effects(fs, member, lambda f: 1.0 if f["won"] else 0.0)
        loss = effects(fs, member, lambda f: (f["hp0"] - f["hp_left"]) / max(f["mhp"], 1))
        rows = sorted(((k, n, 100 * d, 100 * s, 100 * loss[k][0]) for k, (d, s, n) in win.items() if n >= 40), key=lambda r: r[2])
        out.append("**%s**" % nm)
        out.append(table(["что", "боёв", "Δ побед", "se", "Δ потерь HP"], [(r[0], r[1], "%+.1f" % r[2], "%.1f" % r[3], "%+.1f" % r[4]) for r in rows]))
        out.append("")
    return "\n".join(out)


SECTIONS = {"enemy": sec_enemy, "surv": sec_surv, "deaths": sec_deaths, "hp": sec_hp, "fights": sec_fights, "fatigue": sec_fatigue, "heals": sec_heals,
            "ohko": sec_ohko, "items": sec_items, "econ": sec_econ, "growth": sec_growth, "choices": sec_choices}


def main():
    args = sys.argv[1:]
    secs = list(SECTIONS)
    title = None
    if "--sections" in args:
        i = args.index("--sections")
        secs = args[i + 1].split(",")
        del args[i:i + 2]
    if "--title" in args:
        i = args.index("--title")
        title = args[i + 1]
        del args[i:i + 2]
    d = args[0]
    runs = []
    for tag in args[1:]:
        runs += load(d, tag)
    title = title or "+".join(args[1:])
    if "bench" in secs:
        print(sec_bench(runs, title))
        return
    print("## %s: %d забегов" % (title, len(runs)))
    print()
    for s in secs:
        text = SECTIONS[s](runs, title)
        if text:
            print(text)
            print()


if __name__ == "__main__":
    main()
