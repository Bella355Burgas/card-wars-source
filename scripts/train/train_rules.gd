extends RefCounted
## «Бесконечный поезд» inside a fight: the rule of the wagon, the hero's stats and items,
## the second enemy of a double wagon, Усталость. The engine (scripts/core/game.gd) owns
## one of these as `train` and calls it at fixed moments; in a plain game it stays off
## (`active` false) and the engine does not call it at all, so ordinary games, replays
## and AI training play exactly as without it.
##
## What it keeps is part of the game state (Game.state_hash, Game.clone):
##   wagon        the wagon's rule (train_wagons.gd ids, "" for none),
##   wagon_state  what the rule keeps track of: the lane the blizzard closed ("closed"),
##                who played no card in their last turn ("idle_0", "idle_1"),
##   follow       the second enemy {pick, hp, stats[, deck_min]} who walks in when the first
##                is beaten (set_follow, next_enemy); empty: the game ends as usual.
## The hero stats live in PlayerState.stats (set_stats), what items remember in a fight in
## PlayerState.item_state.

const CardInst = preload("res://scripts/core/card_inst.gd")
const PlayerState = preload("res://scripts/core/player_state.gd")

const CRIT_BASE := 200     # a crit deals this % of the damage (the crit_dmg stat adds)
const LANES := 4

var wagon := ""
var wagon_state: Dictionary = {}
var follow: Dictionary = {}
## A fight of the train: a wagon rule or stats of either side (not a plain game or AI training).
var active := false

## The game. Held weakly, as the card rules hold it (rules/base.gd).
var g:
	get:
		return _game_ref.get_ref() if _game_ref != null else null
	set(value):
		_game_ref = weakref(value)

var _game_ref: WeakRef = null


func _init(game) -> void:
	g = game


func _update_active() -> void:
	active = wagon != "" or not g.players[0].stats.is_empty() or not g.players[1].stats.is_empty()


## The state of `other` (a copy of the game's train) in this one.
func copy_from(other) -> void:
	wagon = other.wagon
	wagon_state = other.wagon_state.duplicate(true)
	follow = other.follow.duplicate(true)
	active = other.active


## Part of Game.state_hash: nothing in a plain game, so their hashes stay as they were.
func hash_parts(parts: Array) -> void:
	if wagon != "":
		parts.append([wagon, wagon_state])
	if not follow.is_empty():
		parts.append(follow)


# ---------------------------------------------------------------- setting up a fight

## The hero stats of player p for this fight (TrainRun.fight_stats): a bigger or smaller
## starting hand is drawn or put back under the deck now.
func set_stats(p: int, stats: Dictionary) -> void:
	var ps: PlayerState = g.players[p]
	ps.stats = stats.duplicate()
	for n in stat(p, "hand"):
		if not ps.deck.is_empty():
			ps.hand.append(ps.deck.pop_back())
	while ps.hand.size() > g.hand_size(p) and not ps.hand.is_empty():
		ps.deck.push_front(ps.hand.pop_back())
	_update_active()


func stat(p: int, key: String) -> int:
	return int(g.players[p].stats.get(key, 0))


## The rule of the wagon for the whole game (train_wagons.gd).
func set_wagon(id: String) -> void:
	wagon = id
	wagon_state = {}
	_update_active()


## A double wagon: the enemy who comes after the one in the seat now (a ready deck's id),
## with its hit points and stats (see set_stats).
func set_follow(pick: String, hp: int, stats: Dictionary, deck_min := 0) -> void:
	follow = {"pick": pick, "hp": hp, "stats": stats.duplicate()}
	if deck_min > 0:
		follow["deck_min"] = deck_min


## The enemy plays with as many cards as the hero has (hand and deck), never fewer than
## min_cards: the ones at the bottom of its deck are left out. So the deck runs out for both
## about together and Усталость hits the two the same way.
func limit_enemy_deck(min_cards: int) -> void:
	var cap := maxi(min_cards, g.players[0].deck.size() + g.players[0].hand.size())
	var ps: PlayerState = g.players[1]
	while ps.deck.size() + ps.hand.size() > cap and not ps.deck.is_empty():
		ps.deck.pop_front()


# ---------------------------------------------------------------- what the wagon changes

## What the wagon hides from the player `viewer` of side's cards: the cards in play
## (Туман, Прозрачный вагон), their numbers (Ночной вагон). Прозрачный вагон shows the hands.
func field_hidden(viewer: int, side: int) -> bool:
	return side != viewer and wagon in ["fog", "glass"]


func numbers_hidden(viewer: int, side: int) -> bool:
	return side != viewer and wagon == "night"


func hand_shown(viewer: int, side: int) -> bool:
	return side != viewer and wagon == "glass"


## Lanes the wagon closes: the outer two in Узкий проход, one in the blizzard.
func lane_open(lane: int) -> bool:
	if wagon == "narrow" and (lane == 0 or lane == LANES - 1):
		return false
	return int(wagon_state.get("closed", -1)) != lane


## How many actions a turn of p has more (or fewer) than usual: Пробка, items, Лемонград.
func action_change(p: int) -> int:
	var n := (-1 if wagon == "jam" else 0) + stat(p, "actions")
	if wagon_state.get("idle_%d" % p, false):
		n -= 1
	return n


## Щит Магического человека: no attacks on a hero who has creatures in play. It holds
## while the hero has a deck: else two sides that never meet in a lane could not end the game.
func hero_shielded(side: int) -> bool:
	return wagon == "shield" and g.creature_count(side) > 0 and not g.players[side].deck.is_empty()


func spells_banned() -> bool:
	return wagon == "silence"


## Жара: a creature needs one land more (never more than there are lands).
func lands_needed(c: CardInst, cost: int) -> int:
	if wagon == "heat" and c.kind() == "creature":
		return mini(cost + 1, LANES)
	return cost


## Склеп: the dead go back to their owner's hand.
func dead_to_hand() -> bool:
	return wagon == "crypt"


## ATK the stats, the items and the wagon give p's creature.
func atk_bonus(p: int) -> int:
	var a := stat(p, "atk")
	if stat(p, "lone") > 0 and g.creature_count(p) == 1:
		a += stat(p, "lone")
	if wagon == "concert":
		a += 1
	return a


## DEF of p's creature c with what the items and the wagon change (d: DEF without them).
func def_of(p: int, lane: int, c: CardInst, d: int) -> int:
	if not g.players[p].stats.is_empty():
		d += _item_def(p, lane, c)
	if wagon == "concert" and d > 1:
		d -= 1
	return d


## DEF the hero's items give p's creature: Забор Древесного, Шлем Банановой стражи,
## Колпак Отшельника, Кирпич Конфетного замка.
func _item_def(p: int, lane: int, c: CardInst) -> int:
	var d := 0
	if lane == 0 or lane == LANES - 1:
		d += stat(p, "edge_def")
	if c.flooped:
		d += stat(p, "floop_def")
	if stat(p, "lone") > 0 and g.creature_count(p) == 1:
		d += stat(p, "lone")
	if stat(p, "building_def") > 0 and not g.buildings_at(p, lane).is_empty():
		d += stat(p, "building_def")
	return d


## Перчатка Джейка against a creature, Рогатка Финна against the hero.
func attack_bonus(p: int, vs_creature: bool) -> int:
	return stat(p, "vs_atk") if vs_creature else stat(p, "face_dmg")


## What the hero's items take off a card's cost.
func item_cost(p: int, c: CardInst, cost: int) -> int:
	if g.players[p].stats.is_empty():
		return cost
	var ps: PlayerState = g.players[p]
	match c.kind():
		"creature":
			if stat(p, "first_free") > 0 and not ps.item_state.get("first_free", false):
				return 0
		"spell":
			cost += stat(p, "spell_tax")      # a curse of the Lich
			if stat(p, "third_spell") > 0 and int(ps.item_state.get("spells", 0)) % 3 == 2:
				return 0
			if stat(p, "spell_cheap") > 0 and cost > 1:
				cost -= 1
		"building":
			cost -= stat(p, "building_cheap")
	if stat(p, "rainbow_cheap") > 0 and g.play_land(c) == "rainbow" and cost > 1:
		cost -= 1
	return cost


## Свисток Финна: a creature was paid for, only the first one is free.
func creature_paid(p: int) -> void:
	if stat(p, "first_free") > 0:
		g.players[p].item_state["first_free"] = true


## Подушка Ооо: DEF a creature of p gets when it enters play.
func enter_def(p: int) -> int:
	return stat(p, "enter_def")


## Варежки Ледяного короля: p's lands do not freeze.
func no_freeze(p: int) -> bool:
	return stat(p, "no_freeze") > 0


# ---------------------------------------------------------------- items once a turn / a fight

## An item rule of player p that works once a turn (or once a fight): true the first time,
## and the next time it is false.
func _turn_once(p: int, key: String) -> bool:
	if stat(p, key) <= 0 or g.players[p].turn.get("item_" + key, false):
		return false
	g.players[p].turn["item_" + key] = true
	return true


func _fight_once(p: int, key: String) -> bool:
	if stat(p, key) <= 0 or g.players[p].item_state.get(key, false):
		return false
	g.players[p].item_state[key] = true
	return true


## A chance stat of player p comes up. No stat, no roll: the RNG is used only when it is set.
func roll(p: int, key: String) -> bool:
	var chance := stat(p, key)
	return chance > 0 and g.rng.randi_range(1, 100) <= chance


# ---------------------------------------------------------------- fights

## A crit of p's attacking creature: the damage it deals now, or 0 when there is no crit.
func crit(p: int, amount: int) -> int:
	if amount <= 0:
		return 0
	# Травяной меч: the first attack of the turn is a crit for sure.
	if not _turn_once(p, "first_crit") and not roll(p, "crit"):
		return 0
	return ceili(amount * (CRIT_BASE + stat(p, "crit_dmg")) / 100.0)


func show_crit(attacker: CardInst, amount: int, crit_amount: int) -> int:
	await g._log("Крит! «%s» наносит %d урона вместо %d." % [attacker.card_name(), crit_amount, amount])
	await g._emit({"type": "buff", "uid": attacker.uid, "text": "КРИТ! %d" % crit_amount, "good": true, "crit": true})
	return crit_amount


## p's attacking creature dealt `dealt`: Вампиризм heals a share of it (the rest of a share
## is a chance of one more).
func after_hit(p: int, dealt: int) -> void:
	var x := dealt * stat(p, "lifesteal")
	if wagon == "boss_marceline":
		x /= 2
	if x <= 0 or g.phase == "over":
		return
	var n := x / 100 + (1 if g.rng.randi_range(0, 99) < x % 100 else 0)
	if n > 0:
		await g.heal_player(p, n)


## A creature declared an attack: Ленивый вагон notes it.
func attack_declared(c: CardInst) -> void:
	if wagon == "lazy":
		c.flags["attacked"] = g.turn_number


## Растяжка Джейка: p's attacking creature c trips.
func attack_started(p: int, lane: int, c: CardInst) -> void:
	if wagon == "jake_trip" and g.phase != "over" and g.players[p].creatures[lane] == c:
		await g._log("Растяжка Джейка: «%s» спотыкается." % c.card_name())
		await g.damage_creature(p, lane, 1, {"kind": "effect", "p": g.opp(p)})
		await g._check_state()


## Марселин: a creature that hit the hero grows.
func hit_hero(p: int, lane: int, attacker: CardInst) -> void:
	if wagon == "boss_marceline" and g.phase != "over" and g.players[p].creatures[lane] == attacker:
		await g.buff(attacker, 1, "+1 ATK", true)


## A blow to the hero of `side`: Уклонение takes all of it (true: nothing more happens).
func dodged(side: int) -> bool:
	if not roll(side, "dodge"):
		return false
	await g._log("%s уклоняется от удара." % g.players[side].name)
	await g._emit({"type": "hero_text", "p": side, "text": "Уклонение!", "good": true})
	return true


## Броня: the damage the hero of `side` really takes.
func armor(side: int, amount: int) -> int:
	var a := stat(side, "armor")
	if a > 0 and amount > 1:
		await g._log("Броня: %s получает %d урона вместо %d." % [g.players[side].name, maxi(amount - a, 1), amount])
		amount = maxi(amount - a, 1)
	return amount


## Шипы: the creature that hit the hero of `side` in a fight is hurt back.
func thorns(side: int, source: CardInst) -> void:
	var w: Dictionary = g.where(source.uid)
	if stat(side, "thorns") > 0 and w["zone"] == "creature" and g.is_foe(side, w["p"]) and g.phase != "over":
		await g._log("Шипы ранят «%s»." % source.card_name())
		await g.damage_creature(w["p"], w["lane"], stat(side, "thorns"), {"kind": "effect", "p": side})
		await g._check_state()


# ---------------------------------------------------------------- turns

## The wagon's rule at the start of p's turn (before the draw).
func turn_start(p: int) -> void:
	var ps: PlayerState = g.players[p]
	match wagon:
		"burning":
			await g.lose_hp(p, 1, "Горящий вагон")
		"ice":
			var lanes := []
			for lane in LANES:
				if not g.is_frozen(p, lane):
					lanes.append(lane)
			if not lanes.is_empty():
				await g.freeze(p, lanes[g.rng.randi() % lanes.size()])
		"lsp":
			if not ps.hand.is_empty():
				await g._log("Вагон Лумпи Спейс: карта вылетает в окно.")
				await g.random_discard(p, 1)
		"picnic":
			# Healing stops with the deck, as Регенерация does.
			if not ps.deck.is_empty():
				await g.heal_player(p, 1)
		"lich_dice":
			var r: int = g.rng.randi_range(1, 6)
			await g._log("Кубик Лича: выпало %d." % r)
			await g._emit({"type": "hero_text", "p": p, "text": "Кубик: %d" % r, "good": r > 3})
			if r <= 3:
				for side in 2:
					for lane in LANES:
						await g.damage_creature(side, lane, 1, {"kind": "effect", "p": -1})
				await g._check_state()
			else:
				for side in [p, g.opp(p)]:
					if not g.players[side].deck.is_empty():
						await g.heal_player(side, 2)
		"gunter":
			await _gunter_swap(p)
		"boss_lich":
			if ps.hand.size() > 5:
				await g.lose_hp(p, 1, "Проклятие Лича")
		"boss_ice_king":
			wagon_state.erase("closed")
			if g.turn_number % 3 == 0:
				var lane: int = g.rng.randi() % LANES
				wagon_state["closed"] = lane
				await g._log("Метель закрывает зону %d на этот ход." % (lane + 1))
				await g._emit({"type": "hero_text", "p": p, "text": "Метель: зона %d" % (lane + 1), "good": false})
		"boss_lemongrab":
			if wagon_state.get("idle_%d" % p, false):
				await g._log("Лемонград: %s не сыграл ни одной карты и теряет действие." % ps.name)
				await g._emit({"type": "hero_text", "p": p, "text": "−1 действие", "good": false})


## The draw of p's turn: what the stats and the wagon add to it, Регенерация, Часы
## Лемонграда and Усталость. `draw` is the engine's usual draw, a Callable that awaits.
## Returns true when Усталость hit.
func turn_draw(p: int, draw: Callable) -> bool:
	var ps: PlayerState = g.players[p]
	# Регенерация stops with the deck: two healing sides could not end a fight otherwise.
	# Колокол Лимонграда heals for every building, and stops with the deck as well.
	var regen: int = (stat(p, "regen") + stat(p, "building_regen") * g.building_count(p)) if not ps.deck.is_empty() else 0
	var tired: bool = ps.deck.is_empty() or g.players[g.opp(p)].deck.is_empty()
	await draw.call()
	if roll(p, "draw"):
		await g._emit({"type": "hero_text", "p": p, "text": "Лишняя карта!", "good": true})
		await g._draw(p)
	if wagon == "books" and ps.hand.size() < 4:
		await g._draw(p)
	if regen > 0:
		await g.heal_player(p, regen)
	await _bleed(p)
	if tired:
		await _fatigue(p)
	return tired


## Actions the hero's items add to this turn: Яблочный пирог in the first one, Демонический
## кровавый меч after a kill.
func item_actions(p: int) -> int:
	if g.players[p].stats.is_empty():
		return 0
	var st: Dictionary = g.players[p].item_state
	var n := int(st.get("next_actions", 0))
	st.erase("next_actions")
	if not st.get("turned", false):
		st["turned"] = true
		n += stat(p, "first_action")
	return n


## The wagon's rule at the end of p's turn (after the attacks).
func turn_end(p: int) -> void:
	var ps: PlayerState = g.players[p]
	match wagon:
		"lazy":
			if g.is_first_turn():
				return
			for lane in LANES:
				var c: CardInst = ps.creatures[lane]
				if c != null and int(c.flags.get("attacked", -1)) != g.turn_number:
					await g._log("Ленивый вагон: «%s» не атаковал." % c.card_name())
					await g.damage_creature(p, lane, 1, {"kind": "effect", "p": -1})
			await g._check_state()
		"carousel":
			await _carousel(p)
		"boss_lemongrab":
			wagon_state["idle_%d" % p] = ps.turn.get("played", []).is_empty()


## Кубок Гантера: the weakest of p's creatures grows at the end of the turn.
func item_turn_end(p: int) -> void:
	if stat(p, "weak_up") <= 0:
		return
	var weakest := -1
	for lane in g.creature_lanes(p):
		if weakest < 0 or g.atk_of(p, lane) < g.atk_of(p, weakest):
			weakest = lane
	if weakest >= 0:
		await g.buff(g.players[p].creatures[weakest], stat(p, "weak_up"), "", true)


## Часы Лемонграда: the hero loses HP at the start of the turn, never the last one.
func _bleed(p: int) -> void:
	var ps: PlayerState = g.players[p]
	var n := mini(stat(p, "bleed"), ps.hp - 1)
	if n <= 0 or g.phase == "over":
		return
	ps.hp -= n
	await g._emit({"type": "player_damage", "p": p, "amount": n, "uid": -1})
	await g._log("%s теряет %d HP." % [ps.name, n])


## Усталость: once the deck of either hero is empty, both start their turns losing 1, 2, 3…
## HP, the last ones too, so a fight with no damage left still ends and neither side is hit
## alone (the enemy plays with as many cards as the hero, see limit_enemy_deck).
func _fatigue(p: int) -> void:
	var st: Dictionary = g.players[p].item_state
	st["fatigue"] = int(st.get("fatigue", 0)) + 1
	await g._emit({"type": "hero_text", "p": p, "text": "Усталость", "good": false})
	await g.lose_hp(p, int(st["fatigue"]), "Усталость")


## Вагон Гунтера: p swaps two of their creatures.
func _gunter_swap(p: int) -> void:
	if g.creature_count(p) < 2:
		return
	var a = await g.pick_creature(p, [p], "Вагон Гунтера: какое существо поменять местами?")
	if a == null:
		return
	var first := int(a["lane"])
	var b = await g.pick_creature(p, [p], "Вагон Гунтера: с кем поменять «%s»?" % g.players[p].creatures[first].card_name(),
		func(_c, _side, lane): return lane != first)
	if b != null:
		await g.swap_creatures(p, first, int(b["lane"]))
		await g._check_state()


## Карусель: p's creatures move one lane to the right, the last one to the first lane.
func _carousel(p: int) -> void:
	var ps: PlayerState = g.players[p]
	if g.creature_count(p) == 0:
		return
	var old: Array = ps.creatures.duplicate()
	for lane in LANES:
		ps.creatures[(lane + 1) % LANES] = old[lane]
	await g._log("Карусель: существа игрока %s едут в зону вправо." % ps.name)
	for lane in LANES:
		var c: CardInst = old[lane]
		if c != null:
			c.moved_this_turn = true
			await g._emit({"type": "move", "p": p, "uid": c.uid, "from": lane, "to": (lane + 1) % LANES})
	for lane in LANES:
		var c: CardInst = old[lane]
		var to := (lane + 1) % LANES
		if c == null or ps.creatures[to] != c or g.phase == "over":
			continue
		for id: String in g.texts(c, p, "creature", to):
			await g.run_hook("moved_" + id, [c, p, lane, to])
	await g._check_state()


# ---------------------------------------------------------------- cards

## Лаборатория Пи Би: a creature that has just entered play takes 1.
func entered(c: CardInst) -> void:
	if wagon == "pb_lab" and g.phase != "over":
		var w: Dictionary = g.where(c.uid)
		if w["zone"] == "creature":
			await g._log("Лаборатория Пи Би: «%s» получает 1 урона." % c.card_name())
			await g.damage_creature(w["p"], w["lane"], 1, {"kind": "effect", "p": -1})


## Джойстик BMO: a card after a floop, once a turn.
func flooped(p: int) -> void:
	if g.phase != "over" and _turn_once(p, "floop_draw"):
		await g._log("Джойстик BMO: %s берёт карту." % g.players[p].name)
		await g._draw(p)


## Чертёж Принцессы Жвачки: a card for every building.
func built(p: int) -> void:
	if stat(p, "building_draw") > 0 and g.phase != "over":
		await g._log("Чертёж Принцессы Жвачки: %s берёт карту." % g.players[p].name)
		await g._draw(p)


## The hero's items after p's spell. Энхиридион counts the spells.
func spell_cast(p: int) -> void:
	var ps: PlayerState = g.players[p]
	if ps.stats.is_empty():
		return
	if stat(p, "third_spell") > 0:
		ps.item_state["spells"] = int(ps.item_state.get("spells", 0)) + 1
	if g.phase == "over":
		return
	if stat(p, "spell_dmg") > 0:
		await g._log("Искра Принцессы Пламени обжигает героя.")
		await g.damage_player(g.opp(p), stat(p, "spell_dmg"), null, {"kind": "effect", "p": p})
	if stat(p, "spell_heal") > 0:
		await g.heal_player(p, stat(p, "spell_heal"))
	var lanes: Array = g.creature_lanes(p)
	if stat(p, "spell_buff") > 0 and not lanes.is_empty() and g.phase != "over":
		await g.buff(ps.creatures[lanes[g.rng.randi() % lanes.size()]], stat(p, "spell_buff"))
	if g.phase != "over" and _turn_once(p, "spell_draw"):
		await g._log("Свиток Магического человека: %s берёт карту." % ps.name)
		await g._draw(p)
	await g._check_state()


## Фонарь из склепа: the first creature of `side` that dies in a fight goes back to the hand.
func returns_first_dead(side: int) -> bool:
	return _fight_once(side, "first_return")


## p's creature `killer` has killed one. Клык вампира, Демонический меч.
func killed(p: int, killer: CardInst) -> void:
	if g.phase == "over":
		return
	if stat(p, "kill_atk") > 0 and g.where(killer.uid)["zone"] == "creature":
		await g.buff(killer, stat(p, "kill_atk"), "", true)
	if _turn_once(p, "kill_action"):
		g.players[p].item_state["next_actions"] = 1
		await g._emit({"type": "hero_text", "p": p, "text": "+1 действие в следующем ходу", "good": true})


## A creature of `side` has died. Медальон Призрачной принцессы, Блокнот Мятного дворецкого,
## and the other side's Амулет Хансона Абадира.
func died(side: int) -> void:
	if g.phase == "over":
		return
	if stat(side, "death_heal") > 0:
		await g.heal_player(side, stat(side, "death_heal"))
	if _turn_once(side, "death_draw"):
		await g._log("Блокнот Мятного дворецкого: %s берёт карту." % g.players[side].name)
		await g._draw(side)
	if stat(g.opp(side), "death_bleed") > 0:
		await g.lose_hp(side, stat(g.opp(side), "death_bleed"), "Амулет Хансона Абадира")


# ---------------------------------------------------------------- the end of a fight

## A hero at 0 HP or less: Желание Призмо, then Слеза Принцессы Пламени leave them with 1 HP,
## each once in a fight (the run takes the tear away when the fight is won, see TrainRun.fight_won).
func save_heroes() -> void:
	for side in 2:
		if g.players[side].hp <= 0 and _fight_once(side, "last_stand"):
			var back: int = 1 - g.players[side].hp
			g.players[side].hp = 1
			await g._log("Желание Призмо: %s остаётся с 1 HP." % g.players[side].name)
			await g._emit({"type": "player_heal", "p": side, "amount": back})
			await g._emit({"type": "hero_text", "p": side, "text": "Желание Призмо!", "good": true})
	for side in 2:
		if g.players[side].hp <= 0 and _fight_once(side, "revive"):
			var back: int = 1 - g.players[side].hp
			g.players[side].hp = 1
			await g._log("Слеза Принцессы Пламени: %s остаётся с 1 HP." % g.players[side].name)
			await g._emit({"type": "player_heal", "p": side, "amount": back})
			await g._emit({"type": "hero_text", "p": side, "text": "Слеза!", "good": true})


## The first enemy of a double wagon is beaten: the second sits down in its seat, with its
## deck, hit points, stats and starting hand (a hero card sets up as in a new game). The
## other player keeps everything. The seat's PlayerState stays the same object, so code
## in the middle of that player's turn goes on with the new enemy. The old enemy's cards
## are gone; the player's own cards they held go to the player's discard pile.
func next_enemy() -> void:
	var f := follow
	follow = {}
	var gone := _drop_enemy_cards()
	var fresh: PlayerState = g._new_player(1, f["pick"])
	var ps: PlayerState = g.players[1]
	for prop: Dictionary in fresh.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			ps.set(prop["name"], fresh.get(prop["name"]))
	if ps.name == g.players[0].name:
		ps.name += " 2"
	ps.hp = int(f["hp"])
	ps.max_hp = int(f["hp"])
	for n in g.START_HAND:
		ps.hand.append(ps.deck.pop_back())
	set_stats(1, f["stats"])
	if int(f.get("deck_min", 0)) > 0:
		limit_enemy_deck(int(f["deck_min"]))
	wagon_state.erase("idle_1")
	await g._log("Враг побеждён. Выходит %s." % ps.name)
	await g._emit({"type": "next_enemy", "p": 1, "gone": gone})
	await g._hero_event(1, "setup")


## The beaten enemy leaves the table with all its cards: returns their numbers.
func _drop_enemy_cards() -> Array:
	var mine: PlayerState = g.players[0]
	var theirs: PlayerState = g.players[1]
	# The player's own cards the enemy held go home.
	var held := []
	for lane in LANES:
		for c in [theirs.creatures[lane], theirs.buildings[lane]] + theirs.extra_buildings[lane]:
			if c != null:
				held.append(c)
				held.append_array(c.under)
	for c: CardInst in held:
		if c.owner == 0:
			c.reset_board_state()
			mine.discard.append(c)
	# The enemy's cards the player holds vanish.
	for lane in LANES:
		for row in [mine.creatures, mine.buildings]:
			var c: CardInst = row[lane]
			if c != null and c.owner == 1:
				row[lane] = null
			elif c != null:
				c.under = c.under.filter(func(u): return u.owner != 1)
		mine.extra_buildings[lane] = mine.extra_buildings[lane].filter(func(b): return b.owner != 1)
	for zone in ["hand", "deck", "discard", "removed"]:
		mine.set(zone, mine.get(zone).filter(func(c): return c.owner != 1))
	var gone := []
	for uid in g._cards.keys():
		if g._cards[uid].owner == 1:
			gone.append(uid)
			g._cards.erase(uid)
	return gone
