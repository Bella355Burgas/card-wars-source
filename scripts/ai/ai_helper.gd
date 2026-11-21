extends RefCounted
## Rules of thumb for the AI seats on top of the PPO agent. The network only
## picks commands; this picks sensible targets when a card asks for a choice
## and uses the hero card abilities, which the network was never trained on.

## Prompt words that mean "this hurts the chosen card".
const HARM := ["урон", "уничтож", "сброс", "сбрось", "замороз", "лёд", "поверни", "переверн", "верни",
	"под контроль", "−", "атакуй"]


# ---------------------------------------------------------------- choices

static func choose(game, req: Dictionary):
	var options: Array = req.get("options", [])
	if options.is_empty():
		return null
	var p: int = int(req.get("player", game.turn_player))
	var planned = _from_plan(game, options)
	if planned != null:
		return planned
	var plain := obvious(game, req)
	if not plain.is_empty():
		return plain[0]
	var prompt := String(req.get("prompt", "")).to_lower()
	var optional: bool = req.get("optional", false)
	match String(req.get("kind", "")):
		"creature", "building":
			return _pick_target(game, p, options, prompt, optional)
		"hand_card":
			return _pick_hand(game, p, options, prompt, optional)
		"card":
			return _pick_card(game, p, options, prompt, optional)
		"lane":
			return _pick_lane(game, p, options, req)
		"land":
			return _pick_land(game, p, options, prompt)
		"option":
			return options[1] if options.size() > 1 and String(options[0]) == "Ничего" else options[0]
	return options[0]


## Choices where the right answer is plain and the network, which has not seen
## these cards, went wrong: heal yourself, put attack tokens on your own creature.
## [answer] or [] to leave the choice to the network.
static func obvious(game, req: Dictionary) -> Array:
	var options: Array = req.get("options", [])
	if options.is_empty():
		return []
	var p: int = int(req.get("player", game.turn_player))
	var prompt := String(req.get("prompt", "")).to_lower()
	match String(req.get("kind", "")):
		"option":
			if prompt.begins_with("начало хода") or prompt.begins_with("фиалис: показать"):
				return [options[0]]
			if _is_heal(prompt):
				var pick = _heal_option(game, p, options)
				if pick != null:
					return [pick]
		"creature":
			# Король вампиров: the damage goes to the foe's best creature, the heal stays when there is none.
			if prompt.begins_with("король вампиров"):
				return [_pick_target(game, p, options, prompt, true)]
			if _is_heal(prompt):
				return [_pick_target(game, p, options, prompt, req.get("optional", false))]
			if prompt.contains("жетон") and prompt.contains("атак") \
					and options.any(func(o): return not game.is_foe(p, int(o["p"]))):
				return [_pick_target(game, p, options, prompt, req.get("optional", false))]
	return []


## A harmful "option" choice without the "Игрок: имя" lines of p's own side:
## the network only sees option positions and could hit itself.
static func without_own_players(game, req: Dictionary) -> Dictionary:
	if String(req.get("kind", "")) != "option" or not _is_harm(String(req.get("prompt", "")).to_lower()):
		return req
	var p: int = int(req.get("player", game.turn_player))
	var foe_names := []
	var own_names := []
	for s in game.sides():
		(foe_names if game.is_foe(p, s) else own_names).append("Игрок: " + game.players[s].name)
	var options: Array = req.get("options", [])
	var keep: Array = options.filter(func(o): return not own_names.has(String(o)) or foe_names.has(String(o)))
	if keep.is_empty() or keep.size() == options.size():
		return req
	var out := req.duplicate()
	out["options"] = keep
	return out


## Whom to heal among players (by name or «Игрок: имя») and «Существо»: never a foe. A hurt player of
## p's side, else a hurt creature of p's, else p's own player (nothing is wasted on the foe). null: no
## player of p's side among the options.
static func _heal_option(game, p: int, options: Array):
	var own := []
	for s in game.sides():
		if game.is_foe(p, s):
			continue
		for o in options:
			if String(o) == game.players[s].name or String(o) == "Игрок: " + game.players[s].name:
				own.append([o, s])
	if own.is_empty():
		return null
	own.sort_custom(func(a, b): return game.players[a[1]].hp - game.players[a[1]].max_hp < game.players[b[1]].hp - game.players[b[1]].max_hp)
	var hurt: bool = game.players[own[0][1]].hp < game.players[own[0][1]].max_hp
	if not hurt and options.has("Существо") \
			and not game.creature_opts(p, [p], func(x, _s, _l): return x.damage > 0).is_empty():
		return "Существо"
	return own[0][0]


## Prompt words of a heal («снять 2 урона», «восстанови», «кого лечить»), not a heal-or-damage choice.
static func _is_heal(prompt: String) -> bool:
	if prompt.contains("нанес"):
		return false
	if (prompt.contains("снять") or prompt.contains("сними")) and prompt.contains("урон"):
		return true
	return prompt.contains("восстанов") or prompt.contains("вылеч") or prompt.contains("лечи")


static func _is_harm(prompt: String) -> bool:
	if _is_heal(prompt):
		return false
	for w: String in HARM:
		if prompt.contains(w):
			return true
	return false


## The damage a prompt talks about ("нанеси 2 урона" → 2), 0 if none.
static func _amount(prompt: String) -> int:
	var i := prompt.find("урон")
	if i < 0:
		return 0
	var digits := ""
	for k in range(i - 1, maxi(i - 6, -1), -1):
		var ch := prompt[k]
		if ch >= "0" and ch <= "9":
			digits = ch + digits
		elif digits != "":
			break
	return int(digits) if digits != "" else 1


static func _best(arr: Array, score: Callable):
	var best = null
	var best_s := -INF
	for o in arr:
		var s: float = score.call(o)
		if best == null or s > best_s:
			best = o
			best_s = s
	return best


static func _value(game, o: Dictionary) -> float:
	var kind: String = o.get("kind", "creature")
	var c = game.slot(int(o["p"]), kind, int(o["lane"]))
	if c == null:
		return 0.0
	if kind != "creature":
		return 2.0 * c.def()["cost"] + 1.0
	return float(game.atk_of(int(o["p"]), int(o["lane"])) * 2 + game.hp_of(int(o["p"]), int(o["lane"]))) \
		+ 2.0 * c.def()["cost"]


static func _pick_target(game, p: int, options: Array, prompt: String, optional: bool):
	var harm := _is_harm(prompt)
	var own := options.filter(func(o): return not game.is_foe(p, int(o["p"])))
	var enemy := options.filter(func(o): return game.is_foe(p, int(o["p"])))
	if harm and not enemy.is_empty():
		var amount := _amount(prompt)
		return _best(enemy, func(o):
			var s := _value(game, o)
			if amount > 0 and o.get("kind", "creature") == "creature" and game.hp_of(int(o["p"]), int(o["lane"])) <= amount:
				s += 100.0
			return s)
	if not harm and not own.is_empty():
		var heal := _is_heal(prompt)
		return _best(own, func(o):
			var c = game.slot(int(o["p"]), o.get("kind", "creature"), int(o["lane"]))
			var s := _value(game, o)
			if heal and c != null:
				s += 10.0 * c.damage
			if c != null and not c.exhausted:
				s += 5.0
			return s)
	# Only the "wrong" side is offered.
	if optional:
		return null
	if harm:
		return _best(own, func(o): return -_value(game, o))
	# A heal that must go to a foe (Дуэт): one with no damage gains nothing from it.
	return _best(enemy, func(o):
		var c = game.slot(int(o["p"]), o.get("kind", "creature"), int(o["lane"]))
		return -_value(game, o) - (100.0 * c.damage if c != null else 0.0))


## How much p wants to keep a card.
static func _keep(game, p: int, uid) -> float:
	var c = game.card(int(uid))
	var d: Dictionary = c.def()
	var v := float(d["cost"]) + 1.0
	if d["kind"] == "creature":
		v += 0.5
	if not game.land_ok(c.owner, c):
		v -= 3.0
	return v


static func _pick_hand(game, p: int, options: Array, prompt: String, optional: bool):
	if prompt.contains("станет") and prompt.contains("радужн"):
		# Синюшный чудила: make the card we can't play yet Rainbow.
		return _best(options, func(u): return (0.0 if game.land_ok(p, game.card(int(u))) else 10.0) + game.card(int(u)).def()["cost"])
	if prompt.contains("радужная"):
		# Хорёк-скрипач: a Rainbow discard gives an action.
		return _best(options, func(u): return (10.0 if game.play_land(game.card(int(u))) == "rainbow" else 0.0) - _keep(game, p, u))
	var worst = _best(options, func(u): return -_keep(game, p, u))
	if optional and _keep(game, p, worst) > 2.0:
		return null
	return worst


static func _pick_card(game, p: int, options: Array, prompt: String, optional: bool):
	var owner: int = game.card(int(options[0])).owner
	if game.is_foe(p, owner):
		return _best(options, func(u): return _keep(game, owner, u))
	if optional and prompt.contains("сброс"):
		# Рикардио: throw the top card away only if it is weak.
		return options[0] if options.size() == 1 and _keep(game, p, options[0]) < 2.0 else null
	return _best(options, func(u): return _keep(game, p, u))


static func _pick_lane(game, p: int, options: Array, req := {}):
	var hurts: bool = req.get("hurts_controller", false)
	return _best(options, func(opt):
		var side: int = int(opt["p"])
		var lane: int = int(opt["lane"])
		if hurts:
			# A pop-trooper with a drawback is best handed to the opponent.
			if side != p:
				return 10.0 if game.players[p].creatures[lane] == null else 0.0
			return -5.0
		if side != p:
			return 0.0
		var s := 0.0
		if opt.get("row", "creature") == "creature":
			var a: Array = game.across(p, lane)
			var foe = game.players[a[0]].creatures[a[1]]
			s += 10.0 if foe == null else -float(game.atk_of(a[0], a[1]))
			if game.players[p].creatures[lane] != null:
				s -= 20.0
		else:
			s += 5.0 if game.players[p].creatures[lane] != null else 0.0
		return s)


static func _pick_land(game, p: int, options: Array, prompt: String):
	var harm := prompt.contains("замороз") or prompt.contains("переверн") or prompt.contains("вниз")
	return _best(options, func(opt):
		var side: int = int(opt["p"])
		var lane: int = int(opt["lane"])
		var c = game.players[side].creatures[lane]
		var weight := 1.0 + (float(game.atk_of(side, lane)) if c != null else 0.0)
		if prompt.contains("замороз") and game.is_frozen(side, lane):
			return -100.0 - weight     # a frozen land gets no second token
		if harm:
			return weight if game.is_foe(p, side) else -weight
		return weight if not game.is_foe(p, side) else -weight)


# ---------------------------------------------------------------- hero cards

## Answers prepared together with a hero command, used before the heuristics.
static func _from_plan(game, options: Array):
	if not game.has_meta("ai_plan"):
		return null
	var plan: Array = game.get_meta("ai_plan")
	while not plan.is_empty():
		var a = plan.pop_front()
		if options.has(a):
			return a
	return null


static func clear_plan(game) -> void:
	if game != null and game.has_meta("ai_plan"):
		game.remove_meta("ai_plan")


## A hero card ability worth using right now, as a command ({} if none).
static func hero_command(game, p: int) -> Dictionary:
	if game.phase != "main" or not game.can_hero_power(p):
		return {}
	var plan := []
	match game.players[p].hero_card:
		"monica", "tree_trunks":
			pass
		"ricardio":
			if game.players[p].hp < 12:
				return {}
		"pb":
			if game.is_first_turn():
				return {}
			var lane := -1
			var best := -1
			for l in 4:
				var c = game.players[p].creatures[l]
				if c != null and not c.exhausted and game.hp_of(p, l) >= 3 and game.atk_of(p, l) > best:
					best = game.atk_of(p, l)
					lane = l
			if lane < 0:
				return {}
			plan = [{"p": p, "lane": lane}]
		"bmo":
			if game.players[p].hand.size() < 3:
				return {}
			var target = null
			for opt in game.creature_opts(p, game.foes(p)):
				if game.hp_of(int(opt["p"]), int(opt["lane"])) == 1:
					target = opt
			if target == null:
				return {}
			var hand: Array = game.players[p].hand.map(func(h): return h.uid)
			plan = [_best(hand, func(u): return -_keep(game, p, u)), target]
		"charlie":
			if game.is_first_turn():
				return {}
			for l in 4:
				var c = game.players[p].creatures[l]
				if c == null or c.exhausted or game.foe_creature(p, l) == null:
					continue
				for a in game.adjacent(l):
					if game.players[p].creatures[a] == null and game.foe_creature(p, a) == null:
						plan = [{"p": p, "lane": l}, {"p": p, "lane": a, "row": "creature"}]
			if plan.is_empty():
				return {}
		"susan_strong":
			var best_score := 0.0
			for l in 4:
				var c = game.players[p].creatures[l]
				if c == null:
					continue
				var n: int = c.def()["cost"]
				var kills := 0
				for o in game.foes(p):
					for e in 4:
						if game.players[o].creatures[e] != null and game.hp_of(o, e) <= n:
							kills += 1
				var score := kills * 10.0 - _value(game, {"p": p, "lane": l})
				if kills >= 2 and score > best_score:
					best_score = score
					plan = [{"p": p, "lane": l}]
			if plan.is_empty():
				return {}
		_:
			return {}
	game.set_meta("ai_plan", plan)
	return {"cmd": "hero"}


## Hero abilities that are only worth an action that would be wasted anyway.
static func spare_action_command(game, p: int) -> Dictionary:
	if game.phase != "main" or game.players[p].actions < 1 or not game.can_hero_power(p):
		return {}
	if game.players[p].hero_card in ["cosmic_owl", "abracadaniel"]:
		return {"cmd": "hero"}
	return {}
