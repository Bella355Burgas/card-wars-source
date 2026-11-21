"""Card Wars data for the self-play agent: card text features and state encoding.

Every card is described by its parameters (cost, kind, land, attack, defence,
flags) and by the words of its ability text. Cards are looked up by these
features, not by an id number, so a card the agent has never seen is still
understood through its text, and a new hero card or deck works without retraining.
"""
import json
import os
import re
from collections import Counter

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CARDS_PATH = os.path.join(ROOT, "data", "cards.json")

LANDS = ["plain", "corn", "cute", "swamp", "sandy", "ice", "dead", "rainbow"]
LAND_NONE = len(LANDS)                      # face-down or unknown land
LAND_INDEX = {name: i for i, name in enumerate(LANDS)}
NON_RAINBOW_LANDS = LANDS[:7]
KINDS = ["creature", "building", "spell"]
LANE_COUNT = 4

# Decision modes, command codes, slots and sides; must match scripts/ai/ai_view.gd.
MODE_COMMAND, MODE_MULLIGAN, MODE_CHOICE = 0, 1, 2
CMD_PLAY_CREATURE, CMD_PLAY_BUILDING, CMD_PLAY_SPELL = 0, 1, 2
CMD_FLOOP_CREATURE, CMD_FLOOP_BUILDING, CMD_FLOOP_HERO = 3, 4, 5
CMD_ACTIVATE_CREATURE, CMD_ACTIVATE_BUILDING, CMD_THAW = 6, 7, 8
CMD_HERO, CMD_DRAW, CMD_BEGIN_ATTACK, CMD_ATTACK, CMD_END_TURN = 9, 10, 11, 12, 13
CMD_KEEP, CMD_MULLIGAN = 14, 15
CH_CANCEL, CH_CREATURE, CH_BUILDING, CH_HAND, CH_CARD, CH_LANE, CH_LAND, CH_OPTION = range(16, 24)
NUM_CODES = 24
CHOICE_KINDS = 7           # creature, building, hand_card, card, lane, land, option
SIDES = 3                  # own, opponent, none
OPTION_IDX = 5             # option position 0, 1, 2, last, none

# The board is a fixed list of slots, so the network sees the same layout every time.
SLOT_OWN_CREATURE = 0      # 0..3
SLOT_OWN_BUILDING = 4      # 4..7
SLOT_OPP_CREATURE = 8      # 8..11
SLOT_OPP_BUILDING = 12     # 12..15
SLOT_HAND = 16             # 16..25, up to 10 cards
HAND_SLOTS = 10
SLOT_HERO_OWN = 26
SLOT_HERO_OPP = 27
SLOT_SOURCE = 28           # the card whose command is running (it asks the choices)
NUM_SLOTS = 29
DYN_DIM = 8                # per-slot dynamic features (stats, flags, present)
CAND_MAX = 96              # a decision never has more options than this
POOLS = 3                  # own deck (what is left in it), own discard, opponent's discard
POOL_MAX = 60
GLOB_DIM = 29 + 2 * LANE_COUNT * (len(LANDS) + 1 + 2)

NUM_FLAGS = ["floop", "activated", "act_cost", "floop_cost", "extra_cost", "act_limit",
             "x_stats", "no_replace", "no_ready", "also", "hero_card"]
NUMERIC_DIM = 1 + len(KINDS) + len(LANDS) + 2 + len(NUM_FLAGS)
TOKEN_RE = re.compile(r"[а-яёa-z]+|\d+")
STEM_LEN = 6                  # crude stemmer: "урона", "уроном" -> "урон"
VOCAB_MIN_DF = 2
VOCAB_MAX = 700


def _tokens(text):
    return {w[:STEM_LEN] for w in TOKEN_RE.findall(text.lower())}


class CardTable:
    """Ids of all cards and hero cards, with their static feature rows."""

    def __init__(self):
        with open(CARDS_PATH, encoding="utf-8") as f:
            data = json.load(f)
        self.defs = data["cards"]
        self.heroes = data["heroes"]
        self.hero_order = data["hero_order"]
        self.hero_cards = data["hero_cards"]
        self.hero_card_order = data.get("hero_card_order", list(self.hero_cards))

        self.ids = [c["id"] for c in self.defs] + list(self.hero_card_order)
        clashes = set(c["id"] for c in self.defs) & set(self.hero_card_order)
        assert not clashes, f"card and hero card ids clash: {clashes}"
        # Index 0 is padding ("no card"); real cards start at 1.
        self.index = {cid: i + 1 for i, cid in enumerate(self.ids)}
        self.num_ids = len(self.ids) + 1

        texts = {}
        for c in self.defs:
            texts[c["id"]] = c.get("text", "")
        for cid in self.hero_card_order:
            hc = self.hero_cards[cid]
            texts[cid] = hc.get("text", "") + " " + hc.get("note", "")
        df = Counter()
        for cid in self.ids:
            df.update(_tokens(texts[cid]))
        vocab = [w for w, n in df.most_common() if n >= VOCAB_MIN_DF][:VOCAB_MAX]
        self.vocab = vocab
        vocab_index = {w: i for i, w in enumerate(vocab)}
        self.vocab_index = vocab_index

        self.static = np.zeros((self.num_ids, NUMERIC_DIM + len(vocab)), dtype=np.float32)
        self.def_by_id = {c["id"]: c for c in self.defs}
        for cid in self.ids:
            row = self.index[cid]
            if cid in self.def_by_id:
                self._numeric(row, self.def_by_id[cid])
            else:
                self.static[row, NUMERIC_DIM - 1] = 1.0   # hero card flag
            for w in _tokens(texts[cid]):
                j = vocab_index.get(w)
                if j is not None:
                    self.static[row, NUMERIC_DIM + j] = 1.0
        # Stored in checkpoints: a model is only valid for the same card set and vocabulary.
        self.signature = f"{len(self.ids)}:{len(vocab)}:{self.static.sum():.1f}"

    def _numeric(self, row, d):
        s = self.static
        s[row, 0] = d["cost"] / 3.0
        s[row, 1 + KINDS.index(d["kind"] if d["kind"] in KINDS else "spell")] = 1.0   # командные карты как заклинания
        s[row, 1 + len(KINDS) + LAND_INDEX.get(d["land"], LAND_NONE - 1)] = 1.0
        base = 1 + len(KINDS) + len(LANDS)
        s[row, base] = d.get("atk", 0) / 15.0
        s[row, base + 1] = d.get("def", 0) / 20.0
        flags = {
            "floop": bool(d.get("floop")),
            "activated": int(d.get("activated", 0)) > 0,
            "act_cost": "act_cost" in d,
            "floop_cost": "floop_cost" in d,
            "extra_cost": "extra_cost" in d,
            "act_limit": "act_limit" in d,
            "x_stats": "x_stats" in d,
            "no_replace": "no_replace" in d,
            "no_ready": "no_ready" in d,
            "also": "also" in d,
        }
        for k, name in enumerate(NUM_FLAGS[:-1]):
            s[row, base + 2 + k] = 1.0 if flags[name] else 0.0

    def prompt_row(self, stems):
        """A choice prompt as a card-feature row (its words only), for the card encoder."""
        row = np.zeros(self.static.shape[1], dtype=np.float32)
        for w in stems:
            j = self.vocab_index.get(w)
            if j is not None:
                row[NUMERIC_DIM + j] = 1.0
        return row

    def land_idx(self, name):
        return LAND_INDEX.get(name, LAND_NONE)

    def card_index(self, cid):
        return self.index.get(cid, 0)


# ---------------------------------------------------------------- encoding

ZERO_DYN = (0.0,) * DYN_DIM
ENC_FIELDS = ("card_ids", "dyn", "glob", "prompt", "pools",
              "cand_code", "cand_card", "cand_lane", "cand_slot", "cand_side", "cand_idx")
CAND_FIELDS = ENC_FIELDS[5:]


def _creature_dyn(row):
    _, atk, df, dmg, exh, floop, flag, lost = row
    return (atk / 15.0, df / 20.0, dmg / 20.0, float(exh), float(floop), float(flag), 1.0, float(lost))


def _building_dyn(row):
    _, exh, floop, lost = row
    return (0.0, 0.0, 0.0, float(exh), float(floop), 0.0, 1.0, float(lost))


def encode_state(state, table):
    """One decision view (scripts/ai/ai_view.gd) -> arrays for the policy.

    Returns a tuple in ENC_FIELDS order plus the number of candidates:
    card_ids [NUM_SLOTS], dyn [NUM_SLOTS, DYN_DIM], glob [GLOB_DIM],
    prompt [feature row], pools [POOLS, POOL_MAX] and the candidate arrays [n].
    scripts/ai/policy_agent.gd encodes the same way.
    """
    card_ids = [0] * NUM_SLOTS
    dyn = [ZERO_DYN] * NUM_SLOTS
    cr_own, cr_opp = state["cr"]
    bd_own, bd_opp = state["bd"]
    index = table.index
    for lane in range(LANE_COUNT):
        for row, slot, enc in ((cr_own[lane], SLOT_OWN_CREATURE, _creature_dyn),
                               (cr_opp[lane], SLOT_OPP_CREATURE, _creature_dyn),
                               (bd_own[lane], SLOT_OWN_BUILDING, _building_dyn),
                               (bd_opp[lane], SLOT_OPP_BUILDING, _building_dyn)):
            if row is not None:
                card_ids[slot + lane] = index.get(row[0], 0)
                dyn[slot + lane] = enc(row)
    for k, (cid, cost, playable, land_ok) in enumerate(state["hand"][:HAND_SLOTS]):
        card_ids[SLOT_HAND + k] = index.get(cid, 0)
        dyn[SLOT_HAND + k] = (cost / 3.0, float(playable), float(land_ok), 0.0, 0.0, 0.0, 1.0, 0.0)
    hero_own, hero_opp = state["hero"]
    ready, used = state["hero_dyn"]
    card_ids[SLOT_HERO_OWN] = index.get(hero_own, 0)
    card_ids[SLOT_HERO_OPP] = index.get(hero_opp, 0)
    dyn[SLOT_HERO_OWN] = (float(ready), float(used), 0.0, 0.0, 0.0, 0.0, 1.0, 0.0)
    dyn[SLOT_HERO_OPP] = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0)
    if state["src"]:
        card_ids[SLOT_SOURCE] = index.get(state["src"], 0)
        dyn[SLOT_SOURCE] = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0)

    hp, act = state["hp"], state["act"]
    glob = [hp[0] / 25.0, hp[1] / 25.0, act[0] / 2.0, act[1] / 2.0, state["t"] / 30.0,
            float(state["first"]), float(state["mine"])]
    phase = [0.0] * 3
    if state["ph"] >= 0:
        phase[state["ph"]] = 1.0
    mode = [0.0] * 3
    mode[state["mode"]] = 1.0
    kind = [0.0] * CHOICE_KINDS
    if state["ck"] >= 0:
        kind[state["ck"]] = 1.0
    glob += phase + mode + kind
    glob.append(float(state["opt"]))
    glob += [state["deck"][0] / 40.0, state["deck"][1] / 40.0,
             state["disc"][0] / 40.0, state["disc"][1] / 40.0,
             state["hand_n"][0] / 10.0, state["hand_n"][1] / 10.0,
             float(ready), float(used)]
    for side in range(2):
        for land, flipped, frozen in state["lands"][side]:
            onehot = [0.0] * (len(LANDS) + 1)
            onehot[table.land_idx(land)] = 1.0
            glob.extend(onehot)
            glob.append(float(flipped))
            glob.append(float(frozen))

    pools = np.zeros((POOLS, POOL_MAX), dtype=np.int32)
    for k, ids in enumerate(state["pools"]):
        for j, cid in enumerate(ids[:POOL_MAX]):
            pools[k, j] = index.get(cid, 0)

    cands = state["cands"][:CAND_MAX]
    n = len(cands)
    code = [0] * n
    card = [0] * n
    lane_ = [0] * n
    slot = [0] * n
    side = [0] * n
    idx = [0] * n
    for k, (c_code, cid, lane, c_slot, c_side, c_idx) in enumerate(cands):
        code[k] = c_code
        card[k] = index.get(cid, 0)
        lane_[k] = lane if lane >= 0 else LANE_COUNT
        slot[k] = c_slot
        side[k] = c_side
        idx[k] = c_idx
    return (np.array(card_ids, dtype=np.int32),
            np.array(dyn, dtype=np.float32),
            np.array(glob, dtype=np.float32),
            table.prompt_row(state["prompt"]),
            pools,
            np.array(code, dtype=np.int32),
            np.array(card, dtype=np.int32),
            np.array(lane_, dtype=np.int32),
            np.array(slot, dtype=np.int32),
            np.array(side, dtype=np.int32),
            np.array(idx, dtype=np.int32),
            n)
