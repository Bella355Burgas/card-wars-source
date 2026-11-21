class_name AIEncoder
extends RefCounted
## Encodes Card Wars game state, card features, and action masks for RL agents (PPO).

const CardDB = preload("res://scripts/core/card_db.gd")

const NUM_ACTIONS := 64
const STATE_DIM := 181
const MAX_HAND_SLOTS := 8

static var _card_id_to_int: Dictionary = {}
static var _int_to_card_id: Dictionary = {}
static var _initialized := false


static func init() -> void:
	if _initialized:
		return
	CardDB.ensure_loaded()
	_card_id_to_int.clear()
	_int_to_card_id.clear()

	# Deterministic card ID mapping:
	# First assign Finn and Jake deck cards (45 unique cards), then any remaining cards.
	var hero_cards := []
	var h_finn := CardDB.hero("finn")
	var h_jake := CardDB.hero("jake")
	for cid in h_finn["deck"].keys():
		if not hero_cards.has(cid):
			hero_cards.append(cid)
	for cid in h_jake["deck"].keys():
		if not hero_cards.has(cid):
			hero_cards.append(cid)
	hero_cards.sort()

	var idx := 1
	for cid: String in hero_cards:
		_card_id_to_int[cid] = idx
		_int_to_card_id[idx] = cid
		idx += 1

	for cid: String in CardDB._defs.keys():
		if not _card_id_to_int.has(cid):
			_card_id_to_int[cid] = idx
			_int_to_card_id[idx] = cid
			idx += 1

	_initialized = true


static func card_to_int(card_id: String) -> int:
	init()
	return _card_id_to_int.get(card_id, 0)


static func int_to_card(idx: int) -> String:
	init()
	return _int_to_card_id.get(idx, "")


static func get_card_features(card_id: String) -> PackedFloat32Array:
	init()
	var arr := PackedFloat32Array()
	arr.resize(10)
	if card_id == "" or not CardDB.has_def(card_id):
		return arr

	var d: Dictionary = CardDB.get_def(card_id)
	arr[0] = float(d.get("cost", 0)) / 3.0
	var kind: String = d.get("kind", "")
	arr[1] = 1.0 if kind == "creature" else (0.5 if kind == "building" else 0.0)
	arr[2] = float(d.get("atk", 0)) / 15.0
	arr[3] = float(d.get("def", 0)) / 20.0
	arr[4] = 1.0 if d.get("floop", false) else 0.0
	arr[5] = 1.0 if int(d.get("activated", 0)) > 0 else 0.0
	var land: String = d.get("land", "")
	arr[6] = 1.0 if land == "plain" else 0.0
	arr[7] = 1.0 if land == "corn" else 0.0
	arr[8] = 1.0 if land == "rainbow" else 0.0
	arr[9] = 1.0 if (land != "plain" and land != "corn" and land != "rainbow") else 0.0
	return arr


static func encode_state(game, p: int) -> PackedFloat32Array:
	init()
	var vec := PackedFloat32Array()
	vec.resize(STATE_DIM)
	var o: int = game.opp(p)
	var ps = game.players[p]
	var opp_ps = game.players[o]

	var idx := 0

	# 1. Player & Opponent general stats (13 values)
	vec[idx] = float(ps.hp) / 25.0; idx += 1
	vec[idx] = float(opp_ps.hp) / 25.0; idx += 1
	vec[idx] = float(ps.actions) / 2.0; idx += 1
	vec[idx] = float(opp_ps.actions) / 2.0; idx += 1
	vec[idx] = float(game.turn_number) / 30.0; idx += 1
	vec[idx] = 1.0 if game.phase == "attack" else 0.0; idx += 1
	vec[idx] = 1.0 if game.first_player == p else 0.0; idx += 1
	vec[idx] = float(ps.deck.size()) / 40.0; idx += 1
	vec[idx] = float(opp_ps.deck.size()) / 40.0; idx += 1
	vec[idx] = float(ps.discard.size()) / 40.0; idx += 1
	vec[idx] = float(opp_ps.discard.size()) / 40.0; idx += 1
	vec[idx] = float(ps.hand.size()) / 10.0; idx += 1
	vec[idx] = float(opp_ps.hand.size()) / 10.0; idx += 1

	# 2. Lands (16 values: 4 lanes * 2 for p, 4 lanes * 2 for o)
	for lane in 4:
		var l: Dictionary = ps.lands[lane]
		var ltype: String = l.get("type", "")
		var code := 0.33 if ltype == "plain" else (0.66 if ltype == "corn" else 1.0)
		vec[idx] = code; idx += 1
		vec[idx] = 1.0 if l.get("flipped", false) else 0.0; idx += 1
	for lane in 4:
		var l: Dictionary = opp_ps.lands[lane]
		var ltype: String = l.get("type", "")
		var code := 0.33 if ltype == "plain" else (0.66 if ltype == "corn" else 1.0)
		vec[idx] = code; idx += 1
		vec[idx] = 1.0 if l.get("flipped", false) else 0.0; idx += 1

	# 3. Board: player p lanes (44 values: 4 lanes * 11 features)
	for lane in 4:
		var c = ps.creatures[lane]
		if c != null:
			vec[idx] = 1.0; idx += 1
			vec[idx] = float(card_to_int(c.id)) / 80.0; idx += 1
			vec[idx] = float(game.atk_of(p, lane)) / 15.0; idx += 1
			vec[idx] = float(game.def_of(p, lane)) / 20.0; idx += 1
			vec[idx] = float(c.damage) / 20.0; idx += 1
			vec[idx] = 1.0 if c.exhausted else 0.0; idx += 1
			vec[idx] = 1.0 if c.flooped else 0.0; idx += 1
			vec[idx] = 1.0 if game.can_attack(p, lane) else 0.0; idx += 1
		else:
			idx += 8

		var b = ps.buildings[lane]
		if b != null:
			vec[idx] = 1.0; idx += 1
			vec[idx] = float(card_to_int(b.id)) / 80.0; idx += 1
			vec[idx] = 1.0 if b.flooped else 0.0; idx += 1
		else:
			idx += 3

	# 4. Board: opponent lanes (44 values: 4 lanes * 11 features)
	for lane in 4:
		var c = opp_ps.creatures[lane]
		if c != null:
			vec[idx] = 1.0; idx += 1
			vec[idx] = float(card_to_int(c.id)) / 80.0; idx += 1
			vec[idx] = float(game.atk_of(o, lane)) / 15.0; idx += 1
			vec[idx] = float(game.def_of(o, lane)) / 20.0; idx += 1
			vec[idx] = float(c.damage) / 20.0; idx += 1
			vec[idx] = 1.0 if c.exhausted else 0.0; idx += 1
			vec[idx] = 1.0 if c.flooped else 0.0; idx += 1
			vec[idx] = 1.0 if game.protected_by_cool_dog(o, lane) else 0.0; idx += 1
		else:
			idx += 8

		var b = opp_ps.buildings[lane]
		if b != null:
			vec[idx] = 1.0; idx += 1
			vec[idx] = float(card_to_int(b.id)) / 80.0; idx += 1
			vec[idx] = 1.0 if b.flooped else 0.0; idx += 1
		else:
			idx += 3

	# 5. Hand: up to 8 slots * 8 features = 64 values
	var hand_size: int = ps.hand.size()
	for slot in MAX_HAND_SLOTS:
		if slot < hand_size:
			var c = ps.hand[slot]
			var d: Dictionary = c.def()
			vec[idx] = 1.0; idx += 1
			vec[idx] = float(card_to_int(c.id)) / 80.0; idx += 1
			vec[idx] = float(d.get("cost", 0)) / 3.0; idx += 1
			var kind: String = d.get("kind", "")
			vec[idx] = 1.0 if kind == "creature" else (0.5 if kind == "building" else 0.0); idx += 1
			vec[idx] = float(d.get("atk", 0)) / 15.0; idx += 1
			vec[idx] = float(d.get("def", 0)) / 20.0; idx += 1
			vec[idx] = 1.0 if d.get("floop", false) else 0.0; idx += 1
			vec[idx] = 1.0 if game.can_play(p, c.uid) else 0.0; idx += 1
		else:
			idx += 8

	return vec


static func get_action_mask(game, p: int) -> Array:
	var mask := []
	mask.resize(NUM_ACTIONS)
	mask.fill(false)

	if p != game.turn_player or (game.phase != "main" and game.phase != "attack"):
		mask[58] = true # end_turn fallback
		return mask

	var hand: Array = game.players[p].hand
	var hand_count: int = hand.size()

	# 0..31: play creature/building to lane (slot 0..7, lane 0..3)
	for slot in min(hand_count, MAX_HAND_SLOTS):
		var c = hand[slot]
		if c.kind() != "spell" and c.kind() != "teamwork":
			for lane in 4:
				if game.can_play(p, c.uid, lane):
					mask[slot * 4 + lane] = true

	# 32..39: play spell
	for slot in min(hand_count, MAX_HAND_SLOTS):
		var c = hand[slot]
		if c.kind() == "spell" or c.kind() == "teamwork":
			if game.can_play(p, c.uid, -1):
				mask[32 + slot] = true

	# 40..43: floop creature
	for lane in 4:
		if game.can_floop(p, "creature", lane):
			mask[40 + lane] = true

	# 44..47: floop building
	for lane in 4:
		if game.can_floop(p, "building", lane):
			mask[44 + lane] = true

	# 48..51: activate creature
	for lane in 4:
		if game.can_activate(p, "creature", lane):
			mask[48 + lane] = true

	# 52..55: attack lane
	if game.phase == "attack":
		for lane in 4:
			if game.can_attack(p, lane):
				mask[52 + lane] = true

	# 56: draw for action
	if game.can_draw_for_action(p):
		mask[56] = true

	# 57: begin attack
	if game.phase == "main" and not game.attackers_left(p).is_empty():
		mask[57] = true

	# 58: end turn (always valid in main or attack)
	mask[58] = true

	return mask


static func action_to_command(game, p: int, action_idx: int) -> Dictionary:
	var hand: Array = game.players[p].hand
	if action_idx >= 0 and action_idx < 32:
		var slot := action_idx / 4
		var lane := action_idx % 4
		if slot < hand.size():
			return {"cmd": "play", "uid": hand[slot].uid, "lane": lane}
	elif action_idx >= 32 and action_idx < 40:
		var slot := action_idx - 32
		if slot < hand.size():
			return {"cmd": "play", "uid": hand[slot].uid, "lane": -1}
	elif action_idx >= 40 and action_idx < 44:
		return {"cmd": "floop", "kind": "creature", "lane": action_idx - 40}
	elif action_idx >= 44 and action_idx < 48:
		return {"cmd": "floop", "kind": "building", "lane": action_idx - 44}
	elif action_idx >= 48 and action_idx < 52:
		return {"cmd": "activate", "kind": "creature", "lane": action_idx - 48}
	elif action_idx >= 52 and action_idx < 56:
		return {"cmd": "attack", "lane": action_idx - 52}
	elif action_idx == 56:
		return {"cmd": "draw"}
	elif action_idx == 57:
		return {"cmd": "begin_attack"}
	elif action_idx == 58:
		return {"cmd": "end_turn"}
	return {"cmd": "end_turn"}
