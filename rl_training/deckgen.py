"""Random Card Wars loadouts for self-play: the 14 ready decks, ready decks with some
cards swapped (like the decks players build) and a few fully random legal decks.

Rules are the ones in scripts/core/card_db.gd (deck_errors): at least 40 cards,
each card at most 3 copies, exactly 4 lanes of land types (rainbow is not a land).
A random deck is also playable: a card needs as many lands of its own type in
play as its cost, so the generator only picks cards the lanes can pay for.
"""
import random
from urllib.parse import quote

from cw_data import NON_RAINBOW_LANDS, LANE_COUNT, CardTable

DECK_MIN = 40
DECK_MAX_COPIES = 3
PRESET_CHANCE = 0.7          # chance that a loadout is one of the 14 ready decks
MUTATED_CHANCE = 0.2         # chance of a ready deck with MUTATE_MIN..MAX cards swapped;
                             # the rest are fully random decks
MUTATE_MIN, MUTATE_MAX = 5, 15
OWN_HERO_CHANCE = 0.5        # chance that a ready (or swapped) deck plays its own hero card

_table = None


def table():
    global _table
    if _table is None:
        _table = CardTable()
    return _table


def deck_errors(lands, deck):
    """Mirror of CardDB.deck_errors; an empty list means the deck is legal."""
    errors = []
    if len(lands) != LANE_COUNT:
        errors.append("lanes")
    for t in lands:
        if t not in NON_RAINBOW_LANDS:
            errors.append(f"land {t}")
    total = 0
    defs = table().def_by_id
    for cid, copies in deck.items():
        if cid not in defs:
            errors.append(f"unknown card {cid}")
            continue
        if copies < 1 or copies > DECK_MAX_COPIES:
            errors.append(f"copies {cid}")
        land = defs[cid]["land"]
        if defs[cid]["cost"] == 0 and land != "rainbow" and land not in lands:
            errors.append(f"cost 0 needs {land} {cid}")
        total += copies
    if total < DECK_MIN:
        errors.append(f"size {total}")
    return errors


def custom_code(name, lands, deck):
    """Pick code of an own deck, same format as CardDB.custom_code."""
    entries = ",".join(f"{cid}={deck[cid]}" for cid in sorted(deck))
    return f"custom:{quote(name, safe='')}:{','.join(lands)}:{entries}"


def _lane_counts(rng, k):
    """Split 4 lanes over k land types, every type at least once."""
    cuts = sorted(rng.sample(range(1, LANE_COUNT), k - 1))
    bounds = [0] + cuts + [LANE_COUNT]
    return [bounds[i + 1] - bounds[i] for i in range(k)]


def _payable(lanes):
    """Cards by kind that the lanes can pay for: as many lands of the card's type as its cost."""
    cap = {tp: lanes.count(tp) for tp in set(lanes)}
    pool = {"creature": [], "building": [], "spell": []}
    for c in table().defs:
        land = c["land"]
        if land == "rainbow":
            ok = c["cost"] <= LANE_COUNT
        else:
            ok = land in cap and c["cost"] <= cap[land]
        if ok:
            pool[c["kind"]].append(c["id"])
    return pool


def random_deck(rng, name):
    """A legal, playable random deck: (lanes, deck) with exactly 40 cards."""
    for _ in range(200):
        k = rng.choices([1, 2, 3, 4], weights=[2, 5, 2, 1])[0]
        types = rng.sample(NON_RAINBOW_LANDS, k)
        counts = _lane_counts(rng, k)
        lanes = [tp for tp, n in zip(types, counts) for _ in range(n)]
        rng.shuffle(lanes)

        n_building = rng.randint(3, 6)
        n_spell = rng.randint(6, 11)
        want = {"creature": DECK_MIN - n_building - n_spell, "building": n_building, "spell": n_spell}
        pool = _payable(lanes)

        deck = {}
        ok = True
        for kind, n in want.items():
            if not pool[kind]:
                ok = False
                break
            added = 0
            tries = 0
            while added < n and tries < 1000:
                tries += 1
                cid = rng.choice(pool[kind])
                if deck.get(cid, 0) < DECK_MAX_COPIES:
                    deck[cid] = deck.get(cid, 0) + 1
                    added += 1
            if added < n:
                ok = False
                break
        if ok and not deck_errors(lanes, deck):
            return lanes, deck
    raise RuntimeError("could not build a random deck")


def mutated_deck(rng):
    """A ready deck with some cards swapped for others of the same kind its lanes can pay
    for: (hero deck id, lanes, deck), or None when the result breaks the deck rules."""
    t = table()
    hero = rng.choice(t.hero_order)
    lanes = list(t.heroes[hero]["lands"])
    deck = dict(t.heroes[hero]["deck"])
    pool = _payable(lanes)
    for _ in range(rng.randint(MUTATE_MIN, MUTATE_MAX)):
        copies = [cid for cid, n in deck.items() for _ in range(n)]
        out = rng.choice(copies)
        kind = t.def_by_id[out]["kind"]
        choices = [cid for cid in pool[kind] if cid != out and deck.get(cid, 0) < DECK_MAX_COPIES]
        if not choices:
            continue
        new = rng.choice(choices)
        deck[out] -= 1
        if deck[out] == 0:
            del deck[out]
        deck[new] = deck.get(new, 0) + 1
    if deck_errors(lanes, deck):
        return None
    return hero, lanes, deck


def deck_pick(rng, deck):
    """A ready deck (given by id) with its own hero card, or another one (preset_pick)."""
    if deck not in table().hero_order:
        raise SystemExit(f"{deck} is not a ready deck; choose one of: {', '.join(table().hero_order)}")
    card = deck if rng.random() < OWN_HERO_CHANCE else rng.choice(table().hero_card_order)
    return deck if card == deck else f"{deck}@{card}"


def preset_pick(rng):
    """One of the 14 ready decks, sometimes with another deck's hero card."""
    return deck_pick(rng, rng.choice(table().hero_order))


def loadout(rng, serial):
    """A pick string for one seat: a ready, swapped or random deck, with a hero card."""
    t = table()
    r = rng.random()
    if r < PRESET_CHANCE:
        return preset_pick(rng), "preset"
    if r < PRESET_CHANCE + MUTATED_CHANCE:
        for _ in range(20):
            made = mutated_deck(rng)
            if made is not None:
                hero, lanes, deck = made
                card = hero if rng.random() < OWN_HERO_CHANCE else rng.choice(t.hero_card_order)
                return f"{custom_code(f'Mut{serial}', lanes, deck)}@{card}", "mutated"
    lanes, deck = random_deck(rng, f"Random{serial}")
    card = rng.choice(t.hero_card_order)
    return f"{custom_code(f'Random{serial}', lanes, deck)}@{card}", "random"


def game_spec(rng, serial, seed, bot="none", bot_seat=-1, log=False, presets=False,
              deck="", deck_seat=-1):
    """Everything the worker needs to start one game. presets: both seats play a
    ready deck with its own hero card (the games a player meets in the menu).
    deck: a ready deck id that the seat deck_seat plays (-1: a random seat), with its
    own hero card or another one; the other seat plays a random loadout (or a ready
    deck when presets is set). Those games train and measure a network for that deck."""
    if deck:
        seat = deck_seat if deck_seat >= 0 else rng.randint(0, 1)
        heroes = [None, None]
        heroes[seat] = deck_pick(rng, deck)
        heroes[1 - seat] = preset_pick(rng) if presets else loadout(rng, serial * 2 + 1)[0]
    elif presets:
        heroes = [rng.choice(table().hero_order), rng.choice(table().hero_order)]
    else:
        heroes = [loadout(rng, serial * 2)[0], loadout(rng, serial * 2 + 1)[0]]
    spec = {"heroes": heroes, "first": rng.randint(0, 1), "seed": seed,
            "bot": bot, "bot_seat": bot_seat, "log": log}
    if deck:
        spec["deck_seat"] = seat
    return spec


def describe_pick(pick):
    """Readable name of a pick for the text logs."""
    t = table()
    deck_part, _, card = pick.partition("@")
    card = card or deck_part
    hero_name = t.hero_cards[card]["name"] if card in t.hero_cards else card
    if deck_part.startswith("custom:"):
        body = deck_part[len("custom:"):]
        name, lanes, entries = body.split(":")
        names = []
        for entry in entries.split(","):
            cid, n = entry.split("=")
            names.append(f"{t.def_by_id[cid]['name']} x{n}")
        return (f"своя колода «{name}» (земли: {lanes}; герой-карта: {hero_name})\n    "
                + "; ".join(names))
    return f"колода «{deck_part}» (герой-карта: {hero_name})"
