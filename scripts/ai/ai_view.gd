extends RefCounted
## What an AI seat sees when it decides. One builder for both places a decision
## is made: the self-play worker (scripts/ai/rl_worker.gd), whose views Python
## encodes in rl_training/cw_data.py, and the in-game agent (policy_agent.gd),
## which encodes them the same way. Change a view here and the encoders must
## change with it, and the model must be retrained.
##
## A view is from the deciding seat's side: index 0 of every pair is that seat.
## Decisions come in three modes:
##   MODE_COMMAND  a legal command of the turn (play, floop, attack, ...);
##   MODE_MULLIGAN keep the starting hand or change it;
##   MODE_CHOICE   a card asks for a target, a card or an option.
## Every option is a candidate [code, card id, lane, slot, side, index]:
##   code   CMD_* below;
##   lane   0..3, -1 for none;
##   slot   the board / hand / hero slot the option is about (SLOT_*), -1 for none;
##   side   SIDE_OWN / SIDE_OPP / SIDE_NONE;
##   index  position of an "option" choice (0, 1, 2, 3 = the last one), else IDX_NONE.

const CardDB = preload("res://scripts/core/card_db.gd")

const MODE_COMMAND := 0
const MODE_MULLIGAN := 1
const MODE_CHOICE := 2

const CMD_PLAY_CREATURE := 0
const CMD_PLAY_BUILDING := 1
const CMD_PLAY_SPELL := 2
const CMD_FLOOP_CREATURE := 3
const CMD_FLOOP_BUILDING := 4
const CMD_FLOOP_HERO := 5
const CMD_ACTIVATE_CREATURE := 6
const CMD_ACTIVATE_BUILDING := 7
const CMD_THAW := 8
const CMD_HERO := 9
const CMD_DRAW := 10
const CMD_BEGIN_ATTACK := 11
const CMD_ATTACK := 12
const CMD_END_TURN := 13
const CMD_KEEP := 14
const CMD_MULLIGAN := 15
const CH_CANCEL := 16
const CH_CREATURE := 17
const CH_BUILDING := 18
const CH_HAND := 19
const CH_CARD := 20
const CH_LANE := 21
const CH_LAND := 22
const CH_OPTION := 23

## Choice kinds of the engine, in the order of the one-hot in the encoders.
const CHOICE_KINDS := ["creature", "building", "hand_card", "card", "lane", "land", "option"]

const SLOT_OWN_CREATURE := 0
const SLOT_OWN_BUILDING := 4
const SLOT_OPP_CREATURE := 8
const SLOT_OPP_BUILDING := 12
const SLOT_HAND := 16
const HAND_SLOTS := 10
const SLOT_HERO_OWN := 26
const SLOT_HERO_OPP := 27
const SLOT_SOURCE := 28

const SIDE_OWN := 0
const SIDE_OPP := 1
const SIDE_NONE := 2
const IDX_NONE := 4

const CAND_MAX := 96        # options beyond this are not offered
const POOL_MAX := 60        # cards listed per pile (own deck, own discard, opponent's discard)
const STEM_LEN := 6         # same crude stemmer as rl_training/cw_data.py
const LANES := 4

static var _token_re: RegEx = null


# ---------------------------------------------------------------- views

## The turn's legal commands.
static func command_view(g, p: int, cmds: Array) -> Dictionary:
	var playable := {}
	for c: Dictionary in cmds:
		if c["cmd"] == "play":
			playable[int(c["uid"])] = true
	var v := _base(g, p, MODE_COMMAND, playable)
	var cands := []
	for c: Dictionary in cmds.slice(0, CAND_MAX):
		cands.append(command_cand(g, p, c))
	v["cands"] = cands
	return v


## The position as the command decision of player p sees it, without the options
## (the search scores positions with it: the value head reads the same inputs).
static func state_view(g, p: int) -> Dictionary:
	return _base(g, p, MODE_COMMAND, {})


## Keep (value false) or change (true) the starting hand.
static func mulligan_view(g, p: int) -> Dictionary:
	var v := _base(g, p, MODE_MULLIGAN, {})
	v["cands"] = [[CMD_KEEP, "", -1, -1, SIDE_NONE, IDX_NONE], [CMD_MULLIGAN, "", -1, -1, SIDE_NONE, IDX_NONE]]
	return v


## A choice request of the engine: {"view": ..., "values": [...]}, where values[k]
## is what the chooser returns for candidate k (null = decline an optional choice).
static func choice_view(g, req: Dictionary) -> Dictionary:
	var p := int(req.get("player", g.turn_player))
	var kind := String(req.get("kind", ""))
	var optional: bool = req.get("optional", false)
	var options: Array = req.get("options", [])
	var limit := CAND_MAX - (1 if optional else 0)
	if options.size() > limit:
		options = options.slice(0, limit)
	var v := _base(g, p, MODE_CHOICE, {})
	v["ck"] = CHOICE_KINDS.find(kind)
	v["opt"] = 1 if optional else 0
	v["prompt"] = stems(String(req.get("prompt", "")))
	var cands := []
	var values := []
	for k in options.size():
		cands.append(_option_cand(g, p, kind, options[k], k, options.size()))
		values.append(options[k])
	if optional:
		cands.append([CH_CANCEL, "", -1, -1, SIDE_NONE, IDX_NONE])
		values.append(null)
	v["cands"] = cands
	return {"view": v, "values": values}


# ---------------------------------------------------------------- state

## 2 на 2 and на троих the seat sees the game as one of two players: on its side its own four
## landscapes, on the other side the opponents' spots across them (two of one opponent,
## two of the other), the team's hit points scaled to 25, the next seat's counts, and
## the discard piles of both opponents.
static func _base(g, p: int, mode: int, playable: Dictionary) -> Dictionary:
	var o: int = g.opp(p)
	var ps = g.players[p]
	var os = g.players[o]
	var mine := []
	var theirs := []
	for lane in LANES:
		mine.append([p, lane])
		theirs.append(g.across(p, lane))
	var opp_discard: Array = os.discard
	if g.players.size() > 2:
		opp_discard = []
		for q in g.foes(p):
			opp_discard += g.players[q].discard
	var hand := []
	for c in ps.hand:
		hand.append([c.id, g.cost_of(p, c), 1 if playable.has(c.uid) else 0, 1 if g.land_ok(p, c) else 0])
	var hero_ready := 1 if (mode == MODE_COMMAND and g.can_hero_power(p)) else 0
	var hero_used := 1 if ps.turn.get("hero_used", false) else 0
	return {
		"mode": mode,
		"t": _turn(g),
		"ph": ["setup", "main", "attack"].find(g.phase),
		"first": 1 if g.first_player == p else 0,
		"mine": 1 if g.turn_player == p else 0,
		"hp": [_hp(g, ps.hp), _hp(g, os.hp)],
		"act": [ps.actions, os.actions],
		"deck": [ps.deck.size(), os.deck.size()],
		"disc": [ps.discard.size(), os.discard.size()],
		"hand_n": [ps.hand.size(), os.hand.size()],
		"hero": [ps.hero_card, os.hero_card],
		"hero_dyn": [hero_ready, hero_used],
		"src": g.cmd_source,
		"lands": [_lands(g, mine), _lands(g, theirs)],
		"cr": [_row(g, mine, p, "creature"), _row(g, theirs, p, "creature")],
		"bd": [_row(g, mine, p, "building"), _row(g, theirs, p, "building")],
		"hand": hand,
		# Sorted: the order of the deck is hidden, only what is left in it is known.
		"pools": [_ids(ps.deck, true), _ids(ps.discard, false), _ids(opp_discard, false)],
		"ck": -1,
		"opt": 0,
		"prompt": [],
	}


static func _ids(cards: Array, sort: bool) -> Array:
	var out := []
	for c in cards:
		out.append(c.id)
	if sort:
		out.sort()
	return out.slice(0, POOL_MAX)


## The turn number as in a game for two (2 на 2 the network counts the turns of two
## seats as one round, на троих of three).
static func _turn(g) -> int:
	if g.players.size() == 2:
		return g.turn_number
	return (g.turn_number + 2) / 3 if g.three() else (g.turn_number + 1) / 2


## Hit points as the network knows them: out of 25 (2 на 2 a team has 40).
static func _hp(g, hp: int) -> int:
	return roundi(hp * 25.0 / g.TEAM_HP) if g.teams() else hp


## Landscapes of the spots [side, lane], one entry per lane of the view.
static func _lands(g, spots: Array) -> Array:
	var out := []
	for s: Array in spots:
		var l: Dictionary = g.players[s[0]].lands[s[1]]
		out.append([g.land_type(s[0], s[1]), 1 if l["flipped"] else 0, 1 if l.get("frozen", false) else 0])
	return out


## Creatures or buildings of the spots [side, lane], one entry per lane (null when empty).
## Creature: [id, atk, def, damage, exhausted, flooped, flag, lost abilities], where
## flag is "can attack" for the deciding side and "can be attacked" for the other.
## Building: [id, exhausted, flooped, lost abilities].
## A wagon of «Бесконечный поезд» may hide the other side's cards (id "", no numbers)
## or only their numbers, as it hides them from a player (TrainRules.field_hidden).
static func _row(g, spots: Array, p: int, kind: String) -> Array:
	var out := []
	for s: Array in spots:
		var side: int = s[0]
		var lane: int = s[1]
		var hidden: bool = g.train.field_hidden(p, side)
		var secret: bool = hidden or g.train.numbers_hidden(p, side)
		var c = g.players[side].creatures[lane] if kind == "creature" else g.players[side].buildings[lane]
		if c == null:
			out.append(null)
		elif kind == "creature":
			var flag: bool = g.can_attack(side, lane) if side == p else g.can_be_attacked(side, lane)
			out.append(["" if hidden else c.id, 0 if secret else g.atk_of(side, lane), 0 if secret else g.def_of(side, lane),
				0 if secret else c.damage, 1 if c.exhausted else 0, 1 if c.flooped else 0, 1 if flag else 0,
				1 if c.lost_abilities else 0])
		else:
			out.append(["" if hidden else c.id, 1 if c.exhausted else 0, 1 if c.flooped else 0, 1 if c.lost_abilities else 0])
	return out


# ---------------------------------------------------------------- candidates

static func command_cand(g, p: int, cmd: Dictionary) -> Array:
	match cmd["cmd"]:
		"play":
			var c = g.card(int(cmd["uid"]))
			var code := CMD_PLAY_SPELL
			if c.kind() == "creature":
				code = CMD_PLAY_CREATURE
			elif c.kind() == "building":
				code = CMD_PLAY_BUILDING
			var k: int = g.players[p].hand.find(c)
			return [code, c.id, int(cmd["lane"]), SLOT_HAND + k if k >= 0 and k < HAND_SLOTS else -1, SIDE_OWN, IDX_NONE]
		"floop", "activate":
			var kind: String = cmd["kind"]
			var lane := int(cmd["lane"])
			var creature := kind == "creature"
			var code: int
			if cmd["cmd"] == "floop":
				code = CMD_FLOOP_HERO if cmd.get("hero", false) else (CMD_FLOOP_CREATURE if creature else CMD_FLOOP_BUILDING)
			else:
				code = CMD_ACTIVATE_CREATURE if creature else CMD_ACTIVATE_BUILDING
			var slot := (SLOT_OWN_CREATURE if creature else SLOT_OWN_BUILDING) + lane
			return [code, _id(g.slot(p, kind, lane)), lane, slot, SIDE_OWN, IDX_NONE]
		"thaw":
			return [CMD_THAW, "", int(cmd["lane"]), -1, SIDE_OWN, IDX_NONE]
		"hero":
			return [CMD_HERO, g.players[p].hero_card, -1, SLOT_HERO_OWN, SIDE_OWN, IDX_NONE]
		"draw":
			return [CMD_DRAW, "", -1, -1, SIDE_NONE, IDX_NONE]
		"begin_attack":
			return [CMD_BEGIN_ATTACK, "", -1, -1, SIDE_NONE, IDX_NONE]
		"attack":
			var lane2 := int(cmd["lane"])
			return [CMD_ATTACK, _id(g.slot(p, "creature", lane2)), lane2, SLOT_OWN_CREATURE + lane2, SIDE_OWN, IDX_NONE]
	return [CMD_END_TURN, "", -1, -1, SIDE_NONE, IDX_NONE]


static func _option_cand(g, p: int, kind: String, opt, k: int, n: int) -> Array:
	match kind:
		"creature", "building":
			var side := int(opt["p"])
			var row := "creature" if kind == "creature" else String(opt.get("kind", "building"))
			var at := _view_lane(g, p, side, int(opt["lane"]))
			var base := SLOT_OWN_CREATURE if kind == "creature" else SLOT_OWN_BUILDING
			if side != p:
				base += SLOT_OPP_CREATURE
			return [CH_CREATURE if kind == "creature" else CH_BUILDING, _seen_id(g, p, side, g.slot(side, row, int(opt["lane"]))), at,
				base + at if at >= 0 else -1, _side(g, p, side), IDX_NONE]
		"lane":
			var side2 := int(opt["p"])
			var row2 := String(opt.get("row", "creature"))
			var at2 := _view_lane(g, p, side2, int(opt["lane"]))
			var base2 := SLOT_OWN_CREATURE if row2 == "creature" else SLOT_OWN_BUILDING
			if side2 != p:
				base2 += SLOT_OPP_CREATURE
			return [CH_LANE, _seen_id(g, p, side2, g.slot(side2, row2, int(opt["lane"]))), at2, base2 + at2 if at2 >= 0 else -1,
				_side(g, p, side2), IDX_NONE]
		"land":
			var side3 := int(opt["p"])
			return [CH_LAND, "", _view_lane(g, p, side3, int(opt["lane"])), -1, _side(g, p, side3), IDX_NONE]
		"hand_card", "card":
			var c = g.card(int(opt))
			if c == null:
				return [CH_CARD, "", -1, -1, SIDE_NONE, IDX_NONE]
			var where := _locate(g, p, c)
			return [CH_HAND if kind == "hand_card" else CH_CARD, c.id, where[1], where[0],
				_side(g, p, c.owner), IDX_NONE]
	# "option": only the position is known; the prompt says what the options mean.
	return [CH_OPTION, "", -1, -1, SIDE_NONE, 3 if k == n - 1 else mini(k, 2)]


## [slot, lane] of a card in p's hand or in play (-1 where it has none).
static func _locate(g, p: int, c) -> Array:
	var k: int = g.players[p].hand.find(c)
	if k >= 0:
		return [SLOT_HAND + k if k < HAND_SLOTS else -1, -1]
	for side in g.players.size():
		for lane in LANES:
			var at := _view_lane(g, p, side, lane)
			if at < 0:
				continue
			var base := 0 if side == p else SLOT_OPP_CREATURE
			if g.players[side].creatures[lane] == c:
				return [base + SLOT_OWN_CREATURE + at, at]
			if g.players[side].buildings[lane] == c:
				return [base + SLOT_OWN_BUILDING + at, at]
	return [-1, -1]


## The lane of p's view a spot is on: p's own lane, or the lane of p's it is across
## from; -1 for a spot p's view does not have (2 на 2: the teammate's, and the
## opponents' spots that face the teammate).
static func _view_lane(g, p: int, side: int, lane: int) -> int:
	if side == p:
		return lane
	for l in LANES:
		if g.facing(p, l, side, lane):
			return l
	return -1


## Whose a card or spot is to p: its own team's or the opponents'.
static func _side(g, p: int, side: int) -> int:
	return SIDE_OPP if g.is_foe(p, side) else SIDE_OWN


static func _id(c) -> String:
	return c.id if c != null else ""


## The id of a card in play of `side` as player p sees it.
static func _seen_id(g, p: int, side: int, c) -> String:
	return "" if g.train.field_hidden(p, side) else _id(c)


# ---------------------------------------------------------------- text

## Word stems of a prompt, as rl_training/cw_data.py cuts card texts.
static func stems(text: String) -> Array:
	if _token_re == null:
		_token_re = RegEx.new()
		_token_re.compile("[а-яёa-z]+|[0-9]+")
	var seen := {}
	for m in _token_re.search_all(text.to_lower()):
		seen[m.get_string().substr(0, STEM_LEN)] = true
	var out := seen.keys()
	out.sort()
	return out
