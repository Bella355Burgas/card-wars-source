extends "res://scripts/core/rules/base.gd"
## «Земля легенд» (набор 18): карты для своих колод. Глазмеи считают друг друга, почти
## пустая рука, жетоны огня и атаки.


func _any(p: int) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func _low(p: int) -> bool:
	return players(p).hand.size() <= 1


func _friendly(p: int) -> Array:
	return [p] if not g.teams() else [p, (p + 2) % 4]


## «Глазмей» (Eyesnek) in the name.
func _eyesnek(x) -> bool:
	return x.card_name().to_lower().contains("глазме") or String(x.def().get("en", "")).to_lower().contains("eyesnek")


func _eyesneks(sides: Array) -> int:
	var n := 0
	for s in sides:
		for l in LANES:
			var x = creature(s, l)
			if x != null and _eyesnek(x):
				n += 1
	return n


func _spells_in_discard(p: int) -> int:
	return players(p).discard.filter(func(x): return x.kind() == "spell").size()


## Different land types among the creatures p controls (a rainbow one has none).
func _creature_types(p: int) -> int:
	var seen := {}
	for l in LANES:
		var x = creature(p, l)
		if x != null:
			for t in g.card_types(x, p, l):
				if t != "rainbow":
					seen[t] = true
	return seen.size()


## A token off a creature or a frost token off a land; true when one was removed.
func _take_any_token(p: int, prompt: String, optional := true) -> bool:
	var opts := []
	if not g.creature_opts(p, g.sides(), func(x, _s, _l): return g.non_damage_tokens(x) > 0).is_empty():
		opts.append("С существа")
	if g.frozen_count() > 0:
		opts.append("Жетон мороза с земли")
	if opts.is_empty():
		return false
	var pick = await g.pick_option(p, opts + (["Нет"] if optional else []), prompt)
	if pick == "С существа":
		var t = await g.pick_creature(p, g.sides(), prompt, func(x, _s, _l): return g.non_damage_tokens(x) > 0)
		return t != null and await take_token(p, creature(t["p"], t["lane"])) != ""
	if pick == "Жетон мороза с земли":
		var land = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return g.is_frozen(s, l)), prompt)
		if land != null:
			await g.thaw(land["p"], land["lane"])
			return true
	return false


## Frozen lands may be picked too: they get no second token, but freezing still happens.
func _freeze_one(p: int, sides: Array, prompt: String, optional := false) -> void:
	var opts: Array = g.freeze_opts(sides)
	if opts.is_empty():
		return
	var land = await g.pick_land(p, opts, prompt, optional)
	if land != null:
		await g.freeze(land["p"], land["lane"])


# ---------------------------------------------------------------- spells

# Поглощение эфира: once, and once more for every player with 1 card in hand or none.
func spell_absorb_aether(_c, p) -> void:
	var times: int = 1 + g.sides().filter(func(s): return _low(s)).size()
	for i in times:
		if _any(p):
			var t = await g.pick_creature(p, g.sides(), "Поглощение эфира: 3 урона существу (%d из %d)" % [i + 1, times])
			if t != null:
				await hit(t["p"], t["lane"], 3, p)
				await g._check_state()
		await g.heal_player(p, 3)


# Арктическая чистка
func spell_arctic_purge(_c, p) -> void:
	await g.draw_cards(p, 2)
	if await _take_any_token(p, "Арктическая чистка: убрать жетон?"):
		var o: int = await g.pick_foe(p, "Арктическая чистка: какой соперник сбросит карту?")
		if o >= 0:
			await g.force_discard(o, 1, "%s: сбрось карту" % players(o).name)


# Пепельное облако
func playable_ashcloud(_c, p) -> bool:
	return not g.creature_opts(p, g.foes(p)).is_empty()


func spell_ashcloud(_c, p) -> void:
	var t = await g.pick_creature(p, g.foes(p), "Пепельное облако: какое существо соперника?")
	if t == null:
		return
	var o: int = t["p"]
	var l0: int = t["lane"]
	for l in [l0] + adj(l0):
		if creature(o, l) != null:
			await hit(o, l, 2, p)
	await g._check_state()


# Мозгоклинки
func playable_brainblades(_c, p) -> bool:
	return _any(p)


func spell_brainblades(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Мозгоклинки: на какое существо жетоны атаки?")
	if t != null:
		await g.add_atk_tokens(creature(t["p"], t["lane"]), 1 + players(p).hand.size())


# Масляный таран: exhaust your creatures, 2 damage to an opponent for each.
func spell_buttering_ram(_c, p) -> void:
	var n := 0
	while true:
		var t = await g.pick_creature(p, [p], "Масляный таран: повернуть ещё существо (2 урона сопернику)?",
			func(x, _s, _l): return not x.exhausted, true)
		if t == null:
			break
		creature(p, t["lane"]).exhausted = true
		n += 1
	if n > 0:
		var o: int = await g.pick_foe(p, "Масляный таран: какому сопернику %d урона?" % (2 * n))
		if o >= 0:
			await g.damage_player(o, 2 * n, null, {"kind": "effect", "p": p})


# Холодная волна
func spell_chillwave(_c, p) -> void:
	for o in g.foes(p):
		for l in LANES:
			var x = creature(o, l)
			if x != null and g.non_damage_tokens(x) > 0:
				await hit(o, l, g.non_damage_tokens(x) * (2 if g.is_frozen(o, l) else 1), p)
	await g._check_state()


# Початкогоблинизация: Gobble this turn (Game.gobbles).
func playable_cobnoblify(_c, p) -> bool:
	return _any(p)


func spell_cobnoblify(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Початкогоблинизация: какому существу дать «Хрум»?")
	if t != null:
		creature(t["p"], t["lane"]).flags["gobble_turn"] = g.turn_number
		await flash(creature(t["p"], t["lane"]), "Хрум")


# Пожарище
func spell_conflagration(_c, p) -> void:
	for o in g.foes(p):
		for l in LANES:
			var x = creature(o, l)
			if g.burning(x):
				await hit(o, l, g.tokens(x, "burn"), p)
	await g._check_state()
	await g._draw(p)


# Черепной крем
func spell_cranial_buttercream(_c, p) -> void:
	var types: Array = CardDB.land_types()
	var names: Array = types.map(func(t): return CardDB.land_name(t))
	var t: String = types[maxi(names.find(await g.pick_option(p, names, "Черепной крем: какой тип земель пощадить?")), 0)]
	for s in g.sides():
		for l in LANES:
			if creature(s, l) != null and g.land_type(s, l) != t:
				await hit(s, l, 2, p)
	await g._check_state()


# Пустынная разборка: the two creatures of a lane fight until one is defeated.
func spell_desert_duke_out(_c, p) -> void:
	var lanes: Array = range(LANES).filter(func(l): return creature(p, l) != null and opposite(p, l) != null)
	if lanes.is_empty():
		return
	var lane: int = await g.pick_lane(p, p, lanes, "Пустынная разборка: в какой зоне?")
	if lane < 0:
		return
	var a: Array = g.across(p, lane)
	var x = creature(p, lane)
	var y = creature(a[0], a[1])
	for i in 30:
		if creature(p, lane) != x or creature(a[0], a[1]) != y or g.phase == "over":
			break
		var ax: int = g.atk_of(p, lane)
		var ay: int = g.atk_of(a[0], a[1])
		if ax <= 0 and ay <= 0:
			break
		await g.damage_creature(a[0], a[1], ax, {"kind": "effect", "p": p})
		await g.damage_creature(p, lane, ay, {"kind": "effect", "p": a[0]})
		await g._check_state()


# Зелье энергии
func spell_energy_potion(_c, p) -> void:
	players(p).next_actions += 2
	await say("%s получит 2 действия в следующий ход." % players(p).name)


# Всевидящее око: one card of each land type into the hand, the rest discarded.
func spell_eye_see_all(_c, p) -> void:
	var deck: Array = players(p).deck
	var top := []
	for i in mini(5, deck.size()):
		top.append(deck[deck.size() - 1 - i])
	if top.is_empty():
		return
	await g.emit_event({"type": "reveal", "p": p, "uids": top.map(func(x): return x.uid)})
	# One card of each land type: p picks when a type came up more than once.
	var keep := []
	var by_type := {}
	for x in top:
		var t: String = g.play_land(x)
		if t != "rainbow":
			by_type[t] = by_type.get(t, []) + [x]
	for t in by_type:
		var same: Array = by_type[t]
		var pick = same[0]
		if same.size() > 1:
			pick = await g.pick_card(p, same, "Всевидящее око: какую карту земли «%s» взять?" % CardDB.land_name(t))
			if pick == null:
				pick = same[0]
		keep.append(pick)
	for x in top:
		deck.erase(x)
		if keep.has(x):
			players(p).hand.append(x)
			await g.emit_event({"type": "to_hand", "p": p, "uid": x.uid, "from": "deck"})
		else:
			await g._to_discard(x, "deck")


# Облик феникса: two creatures back from the discard pile until the end of the turn.
func spell_form_of_the_phoenix(_c, p) -> void:
	for i in 2:
		var pool: Array = g.discard_pool(p, func(x): return x.kind() == "creature")
		if pool.is_empty() or g.empty_lanes(p).is_empty():
			return
		var pick = await g.pick_card(p, pool, "Облик феникса: какое существо вернуть в игру?")
		if pick != null and await g.play_free(p, pick, "Облик феникса: в какую зону?"):
			pick.flags["phoenix_form"] = g.turn_number


# Зелье дружбы: one creature of p's and one of somebody else's.
func playable_friendship_potion(_c, p) -> bool:
	return g.creature_count(p) > 0 and not g.creature_opts(p, g.sides().filter(func(s): return s != p)).is_empty()


func spell_friendship_potion(_c, p) -> void:
	var a = await g.pick_creature(p, [p], "Зелье дружбы: со своего существа снять 3 урона")
	if a != null:
		await g.heal_creature(p, a["lane"], 3)
	var others: Array = g.sides().filter(func(s): return s != p)
	var b = await g.pick_creature(p, others, "Зелье дружбы: с чужого существа снять 3 урона")
	if b != null:
		await g.heal_creature(b["p"], b["lane"], 3, p)


# Зелье морозного пламени
func playable_frostfire_potion(_c, p) -> bool:
	return _any(p)


func spell_frostfire_potion(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Зелье морозного пламени: какое существо поджечь?")
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"])
	var x = creature(t["p"], t["lane"]) if t != null else null
	var f = await g.pick_creature(p, g.sides(), "Зелье морозного пламени: на какое другое существо жетон атаки?", func(y, _s, _l): return y != x)
	if f != null:
		await g.add_atk_tokens(creature(f["p"], f["lane"]))
	await _freeze_one(p, g.sides(), "Зелье морозного пламени: какую землю заморозить?")


# Тепловой удар: each player, you first, picks a different creature for 4 damage.
func spell_heat_stroke(_c, p) -> void:
	var used := []
	for s in g.seats_from(p):
		var t = await g.pick_creature(s, g.sides(), "Тепловой удар: %s, какому существу 4 урона?" % players(s).name,
			func(x, _s2, _l): return not used.has(x.uid))
		if t != null:
			used.append(creature(t["p"], t["lane"]).uid)
			await hit(t["p"], t["lane"], 4, s)
	await g._check_state()


# Ледяной жар
func spell_icy_hot(_c, p) -> void:
	for s in g.sides():
		for l in LANES:
			if creature(s, l) != null and g.is_frozen(s, l):
				await g.burn_creature(p, s, l)
	for s in g.sides():
		for l in LANES:
			if g.burning(creature(s, l)):
				await g.freeze(s, l)


# Заряженная молния
func spell_juiced_lightning(_c, p) -> void:
	var tokens: bool = _spells_in_discard(p) >= 3
	for l in LANES:
		if creature(p, l) != null:
			await g.heal_creature(p, l, 2)
			if tokens:
				await g.add_atk_tokens(creature(p, l))


# Танец костра
func spell_pyre_dance(_c, p) -> void:
	var pool: Array = g.discard_pool(p, func(x): return x.kind() == "creature")
	if pool.is_empty():
		return
	var pick = await g.pick_card(p, pool, "Танец костра: какое существо вернуть в игру?")
	if pick == null or not await g.play_free(p, pick, "Танец костра: в какую зону?"):
		return
	var w: Dictionary = g.where(pick.uid)
	if w["zone"] == "creature":
		var n: int = g.hp_of(w["p"], w["lane"]) - 1
		if n > 0:
			pick.damage += n
			await g.emit_event({"type": "damage", "p": w["p"], "lane": w["lane"], "uid": pick.uid, "amount": n})


# Доспех огненного сердца
func playable_pyroheart_plate(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_pyroheart_plate(_c, p) -> void:
	var t = await g.pick_creature(p, _friendly(p), "Доспех огненного сердца: какое своё существо?")
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"])
		await g.heal_creature(t["p"], t["lane"], creature(t["p"], t["lane"]).damage, p)
	await g._draw(p)


# Зелье переезда
func playable_relocation_potion(_c, p) -> bool:
	return g.building_count(p) > 0


func spell_relocation_potion(_c, p) -> void:
	var opts := []
	for l in LANES:
		if players(p).buildings[l] != null:
			opts.append({"p": p, "lane": l, "kind": "building"})
	var pick = await g._choose({"kind": "building", "player": p, "options": opts, "prompt": "Зелье переезда: какое строение подготовить?"})
	if pick == null:
		return
	var b = players(p).buildings[pick["lane"]]
	b.exhausted = false
	b.flooped = false
	await g.emit_event({"type": "ready", "p": p, "uid": b.uid})
	var free: Array = range(LANES).filter(func(l): return players(p).buildings[l] == null)
	if not free.is_empty():
		var dest: int = await g.pick_lane(p, p, free, "Зелье переезда: переместить строение?", "building", true)
		if dest >= 0:
			await g.move_building(p, pick["lane"], dest)


# Шок-коробка: each player shuffles up to 3 cards of their discard pile into the deck and heals for them.
func spell_shock_box(_c, p) -> void:
	for s in g.seats_from(p):
		var n := 0
		for i in 3:
			var pool: Array = players(s).discard
			if pool.is_empty():
				break
			var pick = await g.pick_card(s, pool, "Шок-коробка: %s, замешать карту из сброса в колоду?" % players(s).name, true)
			if pick == null:
				break
			players(s).discard.erase(pick)
			players(s).deck.append(pick)
			n += 1
		if n > 0:
			await g.shuffle_deck(s)
			await g.heal_player(s, n)


# Болотный газ
func playable_swamp_gas(_c, p) -> bool:
	return _any(p)


func spell_swamp_gas(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Болотный газ: 3 урона выбранному существу")
	if t == null:
		return
	var x = creature(t["p"], t["lane"])
	await hit(t["p"], t["lane"], 3, p)
	await g._check_state()
	if g.where(x.uid)["zone"] != "creature":
		await g.force_discard(x.owner, 1, "Болотный газ: %s, сбрось карту" % players(x.owner).name)


# Жезл колдовства: a spell another player discards may be played as Rainbow for free.
func spell_wand_of_hexcraft(_c, p) -> void:
	var others: Array = g.sides().filter(func(s): return s != p and not players(s).hand.is_empty())
	if others.is_empty():
		return
	var o: int = others[0]
	if others.size() > 1:
		var names: Array = others.map(func(s): return players(s).name)
		o = others[maxi(names.find(await g.pick_option(p, names, "Жезл колдовства: какой игрок сбросит карту?")), 0)]
	var before: Array = players(o).discard.duplicate()
	await g.force_discard(o, 1, "Жезл колдовства: %s, сбрось карту" % players(o).name)
	var gone: Array = players(o).discard.filter(func(x): return not before.has(x))
	if gone.is_empty() or gone[0].kind() != "spell":
		return
	var sp = gone[0]
	if await g.pick_option(p, ["Сыграть бесплатно", "Нет"], "Жезл колдовства: сыграть «%s» бесплатно?" % sp.card_name()) == "Сыграть бесплатно":
		sp.flags["rainbow"] = true
		await g.play_free(p, sp)
		sp.flags.erase("rainbow")


# ---------------------------------------------------------------- buildings

# Початочная крепость
func cost_cob_keep(c, _p) -> int:
	return -int(c.def()["cost"]) if g.sides().any(func(s): return _low(s)) else 0


func aura_atk_cob_keep(_src, sp, slane, _c, p, lane) -> int:
	return 2 if sp == p and slane == lane else 0


func aura_def_cob_keep(_src, sp, slane, _c, p, lane) -> int:
	return 2 if sp == p and slane == lane else 0


# Боевая арена
func floop_ok_combatarium(_c, p, _kind, lane) -> bool:
	return not g.creature_opts(p, g.sides(), func(_x, s, l): return g.bld_on_lane(p, lane, s, l)).is_empty()


func floop_combatarium(_c, p, _kind, lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Боевая арена: какое существо в этой зоне подготовить?",
		func(_x, s, l): return g.bld_on_lane(p, lane, s, l))
	if t == null:
		return
	var x = creature(t["p"], t["lane"])
	x.exhausted = false
	x.flooped = false
	await g.emit_event({"type": "ready", "p": t["p"], "uid": x.uid})
	await hit(t["p"], t["lane"], 1, p)
	await g._check_state()


# Фонтан стойкости
func enter_fortitude_fountain(_c, p, _lane) -> void:
	players(p).max_hp += 5


func leave_fortitude_fountain(_c, p, _lane, _reason, _info) -> void:
	players(p).max_hp -= 5
	if players(p).hp > players(p).max_hp:
		players(p).hp = players(p).max_hp
		await g.emit_event({"type": "player_damage", "p": p, "amount": 0, "uid": -1})


# Медовое убежище
func on_hit_player_honeycomb_haven(_src, sp, _skind, slane, p, lane, _c, _o, dealt) -> void:
	if g.bld_own_lane(sp, slane, p, lane):
		await g.heal_player(sp, dealt)


# Хижина черепной тени
func on_hit_player_skullshade_shanty(_src, sp, _skind, slane, p, lane, c, o, dealt) -> void:
	if o == sp and g.facing(sp, slane, p, lane):
		var w: Dictionary = g.where(c.uid)
		if w["zone"] == "creature":
			await hit(w["p"], w["lane"], dealt, sp)
			await g._check_state()


# Пекло: an opposing creature leaves this lane in any way (leaves play, moves, changes sides);
# the damage goes to its owner, even when the owner is the Пекло's controller.
func _hot_box(sp: int, c) -> void:
	await g.damage_player(c.owner, 2, null, {"kind": "effect", "p": sp})
	await g._draw(sp)


func on_leave_hot_box(_src, sp, _skind, slane, c, p, lane, _reason) -> void:
	if g.is_foe(sp, p) and g.facing(sp, slane, p, lane):
		await _hot_box(sp, c)


func on_lane_left_hot_box(_src, sp, _skind, slane, c, from_side, from_lane, to_side, to_lane) -> void:
	if g.is_foe(sp, from_side) and g.facing(sp, slane, from_side, from_lane) and not g.on_lane(sp, slane, to_side, to_lane):
		await _hot_box(sp, c)


# Приют лавопада
func enter_lavafall_retreat(_c, p, lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Приют лавопада: какое существо в этой зоне поджечь?",
		func(_x, s, l): return g.on_lane(p, lane, s, l))
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"])


func sees_enter_lavafall_retreat(_src, sp, _skind, slane, _c, p, lane) -> bool:
	return g.on_lane(sp, slane, p, lane)


func on_enter_lavafall_retreat(_src, sp, _skind, _slane, _c, p, lane) -> void:
	await g.burn_creature(sp, p, lane)


# Магмовые каналы
func floop_magma_canals(_c, p, _kind, lane) -> void:
	var n := 0
	for s in g.sides():
		for l in LANES:
			if not g.on_lane(p, lane, s, l):
				n += g.tokens(creature(s, l), "burn")
	if n <= 0:
		return
	for s in g.lane_spots(p, lane):
		if g.is_foe(p, s[0]) and creature(s[0], s[1]) != null:
			await hit(s[0], s[1], n, p)
	await g._check_state()


# Башня небесного погребения
func floop_ok_sky_burial_tower(_c, p, _kind, _lane) -> bool:
	return g.foes(p).any(func(o): return _low(o))


func floop_sky_burial_tower(_c, p, _kind, _lane) -> void:
	await g.gain_actions(p, 1)


# Станция снегоделов: FLOOP and remove a frost token >>> freeze another land, draw.
func floop_ok_snowmaker_station(_c, _p, _kind, _lane) -> bool:
	return g.frozen_count() > 0


func floop_snowmaker_station(_c, p, _kind, _lane) -> void:
	var land = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return g.is_frozen(s, l)), "Станция снегоделов: с какой земли снять жетон мороза?")
	if land == null:
		return
	await g.thaw(land["p"], land["lane"])
	var opts: Array = g.freeze_opts(g.sides(), func(s, l): return not (s == land["p"] and l == land["lane"]))
	var other = await g.pick_land(p, opts, "Станция снегоделов: какую другую землю заморозить?")
	if other != null:
		await g.freeze(other["p"], other["lane"])
	await g._draw(p)


# Бродячая мастерская
func floop_wandering_workshop(c, p, kind, lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Бродячая мастерская: на какое существо в этой зоне жетон атаки?",
		func(_x, s, l): return g.bld_on_lane(p, lane, s, l))
	if t != null:
		await g.add_atk_tokens(creature(t["p"], t["lane"]))
	var free: Array = adj(lane).filter(func(l): return players(p).buildings[l] == null)
	if not free.is_empty() and kind == "building" and players(p).buildings[lane] == c:
		var dest: int = await g.pick_lane(p, p, free, "Бродячая мастерская: куда переехать?", "building")
		if dest >= 0:
			await g.move_building(p, lane, dest)


# Зиккурат проклятых
func aura_atk_ziggurat_of_the_darned(_src, sp, slane, _c, p, lane) -> int:
	return -2 if g.is_foe(sp, p) and g.facing(sp, slane, p, lane) else 0


# ---------------------------------------------------------------- creatures

# Древний волшебный дракон-фараон: the discard pile, shuffled, becomes the deck and the deck the pile.
func _pharaoh(p: int) -> void:
	var ps = players(p)
	var old_deck: Array = ps.deck
	ps.deck = ps.discard
	ps.discard = old_deck
	await g.shuffle_deck(p)
	await say("%s меняет местами колоду и сброс." % ps.name)


func enter_ancient_magic_pharaoh_dragon(_c, p, _lane) -> void:
	await _pharaoh(p)


func leave_ancient_magic_pharaoh_dragon(_c, p, _lane, _reason, _info) -> void:
	await _pharaoh(p)


# Базальтовый бегемот
func floop_ok_basalt_behemoth(_c, p, _kind, _lane) -> bool:
	return not g.creature_opts(p, g.foes(p)).is_empty()


func floop_basalt_behemoth(_c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, g.foes(p), "Базальтовый бегемот: какое существо соперника поджечь?")
	if t == null:
		return
	await g.burn_creature(p, t["p"], t["lane"])
	if creature(t["p"], t["lane"]) != null:
		await hit(t["p"], t["lane"], g.burn_tokens_in_play(), p)
		await g._check_state()


# Удав из протоки (destroy a creature you control)
func act_ok_bayou_boa(c, p, _kind, _lane) -> bool:
	return not g.creature_opts(p, [p], func(x, _s, _l): return x != c).is_empty()


func act_bayou_boa(c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, [p], "Удав из протоки: какое своё существо уничтожить?", func(x, _s, _l): return x != c)
	if t == null:
		return
	await g.destroy_creature(p, t["lane"])
	var w: Dictionary = g.where(c.uid)
	if w["zone"] == "creature":
		await g.add_atk_tokens(c, 2)
		await g.heal_creature(w["p"], w["lane"], 2, p)


# Пляжный червь
func enter_beach_worm(_c, p, _lane) -> void:
	if _creature_types(p) < 4:
		return
	var t = await g.pick_creature(p, g.foes(p), "Пляжный червь: уничтожить существо соперника?", Callable(), true)
	if t != null:
		await g.destroy_creature(t["p"], t["lane"])


# Болотный глазмей
func enter_bog_eyesnek(_c, p, _lane) -> void:
	var n := _eyesneks(g.sides())
	var o: int = await g.pick_foe(p, "Болотный глазмей: какому сопернику %d урона?" % n)
	if o >= 0:
		await g.damage_player(o, n, null, {"kind": "effect", "p": p})
	await g.heal_player(p, n)


# Лазурный глазмей
func enter_cerulean_eyesnek(_c, p, _lane) -> void:
	for s in g.seats_from(p):
		await g.draw_cards(s, _eyesneks([s]))


# Холмовой глазмей
func enter_hillside_eyesnek(_c, p, _lane) -> void:
	var n := _eyesneks(g.sides())
	for s in _friendly(p):
		for l in LANES:
			if creature(s, l) != null:
				await g.heal_creature(s, l, n, p)


# Расплавленный глазмей
func enter_molten_eyesnek(_c, _p, _lane) -> void:
	for s in g.sides():
		for l in LANES:
			var x = creature(s, l)
			if x != null and _eyesnek(x):
				await g.add_atk_tokens(x)


# Снегослепой глазмей
func enter_snowblind_eyesnek(_c, p, _lane) -> void:
	for i in _eyesneks([p]):
		await _freeze_one(p, g.sides(), "Снегослепой глазмей: какую землю заморозить?")


# Стебельчатый глазмей
func enter_stalk_eyesnek(_c, _p, _lane) -> void:
	var n := _eyesneks(g.sides())
	for s in g.sides():
		for l in LANES:
			var x = creature(s, l)
			if x != null and _eyesnek(x):
				await g.buff(x, n)


# Солнцепёчный глазмей
func enter_sunscorch_eyesnek(_c, p, _lane) -> void:
	var n := _eyesneks(g.sides())
	var t = await g.pick_creature(p, g.sides(), "Солнцепёчный глазмей: %d урона выбранному существу" % n)
	if t != null:
		await hit(t["p"], t["lane"], n, p)
		await g._check_state()


# Варево-хаха: a «Зелье» from the deck, played for free.
func enter_brew_haha(_c, p, _lane) -> void:
	var pool: Array = players(p).deck.filter(func(x): return g.is_potion(x))
	if pool.is_empty():
		await g.shuffle_deck(p)
		return
	var pick = await g.pick_card(p, pool, "Варево-хаха: какое «Зелье» из колоды сыграть?")
	await g.shuffle_deck(p)
	if pick != null:
		await g.play_free(p, pick)


# Придворный броненосец
func enter_courtly_armourdillo(c, p, _lane) -> void:
	if not c.flags.get("from_hand", false):
		return
	for s in g.sides():
		for l in LANES:
			var x = creature(s, l)
			if x != null and x != c:
				await hit(s, l, 8, p)
	await g._check_state()


# Доктор Пироклоп
func on_played_dr_pieclops(_src, sp, _skind, _slane, p, c) -> void:
	if p != sp or c.kind() != "spell":
		return
	if players(sp).hp >= players(sp).max_hp:
		var o: int = await g.pick_foe(sp, "Доктор Пироклоп: какому сопернику 2 урона?")
		if o >= 0:
			await g.damage_player(o, 2, null, {"kind": "effect", "p": sp})
	else:
		await g.heal_player(sp, 2)


# Шлаковый голем: half the damage (rounded up) with 1 card in hand or none.
func dmg_in_cinder_construct(_c, p, _lane, amount, _info) -> int:
	return ceili(amount / 2.0) if _low(p) else amount


# Итан-ас
func cost_ethan_the_ace(c, p) -> int:
	var n := 0
	for id in g.turn_value(p, "played", []):
		var d: Dictionary = CardDB.get_def(id)
		if d["kind"] == "creature" and int(d["cost"]) == 1:
			n += 1
	return -int(c.def()["cost"]) if n >= 2 else 0


# Огненная буря фениксов
func enter_firestorm_of_phoenixes(_c, p, _lane) -> void:
	if _low(p):
		for o in g.foes(p):
			for l in LANES:
				if creature(o, l) != null:
					await g.burn_creature(p, o, l)


# Пламинго-укротитель огня: the first 2 damage from burning creatures each turn are prevented.
func dmg_in_flameingo_flame_tamer(c, _p, _lane, amount, info) -> int:
	var src = info.get("card")
	if src == null or not g.burning(src):
		return amount
	var used := int(c.flags.get("tamer_%d" % g.turn_number, 0))
	var stop: int = mini(2 - used, amount)
	if stop <= 0:
		return amount
	c.flags["tamer_%d" % g.turn_number] = used + stop
	return amount - stop


# Оживитель гнилых вод
func floop_ok_foulwater_reviver(_c, p, _kind, _lane) -> bool:
	return not g.discard_pool(p, func(x): return x.kind() == "creature" and int(x.def()["cost"]) == 1).is_empty()


func floop_foulwater_reviver(_c, p, _kind, _lane) -> void:
	var pool: Array = g.discard_pool(p, func(x): return x.kind() == "creature" and int(x.def()["cost"]) == 1)
	var pick = await g.pick_card(p, pool, "Оживитель гнилых вод: какое существо сыграть из сброса?")
	if pick != null:
		await g.play_free(p, pick)


# Призрачная колдунья
func on_played_ghost_sorceress(_src, sp, _skind, _slane, p, c) -> void:
	if p == sp and c.kind() == "spell" and int(g.turn_value(sp, "spells")) == 1:
		await g.draw_cards(sp, 2)
		await g.force_discard(sp, 1, "Призрачная колдунья: сбрось карту")


# Тлеющий фантом
func on_played_smoldering_phantom(_src, sp, _skind, _slane, p, c) -> void:
	if p != sp or c.kind() != "spell" or int(g.turn_value(sp, "spells")) != 2:
		return
	var t = await g.pick_creature(sp, [sp], "Тлеющий фантом: подготовить своё существо?", func(x, _s, _l): return x.exhausted, true)
	if t != null:
		var x = creature(sp, t["lane"])
		x.exhausted = false
		x.flooped = false
		await g.emit_event({"type": "ready", "p": sp, "uid": x.uid})


# Бродяга колдовского бриза: a token moves from a creature or land to another.
func floop_ok_hexbreeze_drifter(_c, p, _kind, _lane) -> bool:
	return g.frozen_count() > 0 or not g.creature_opts(p, g.sides(), func(x, _s, _l): return g.non_damage_tokens(x) > 0).is_empty()


func floop_hexbreeze_drifter(_c, p, _kind, _lane) -> void:
	var opts := []
	if not g.creature_opts(p, g.sides(), func(x, _s, _l): return g.non_damage_tokens(x) > 0).is_empty():
		opts.append("С существа")
	if g.frozen_count() > 0:
		opts.append("Жетон мороза с земли")
	var pick = await g.pick_option(p, opts, "Бродяга колдовского бриза: откуда взять жетон?")
	if pick == "С существа":
		var t = await g.pick_creature(p, g.sides(), "Бродяга колдовского бриза: с какого существа?", func(x, _s, _l): return g.non_damage_tokens(x) > 0)
		if t == null:
			return
		var src = creature(t["p"], t["lane"])
		var kind: String = await take_token(p, src)
		var d = await g.pick_creature(p, g.sides(), "Бродяга колдовского бриза: на какое другое существо?", func(x, _s, _l): return x != src)
		if d == null:
			return
		if kind == "burn":
			await g.burn_creature(p, d["p"], d["lane"])
		elif kind == "atk_tok":
			await g.add_atk_tokens(creature(d["p"], d["lane"]))
	else:
		var land = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return g.is_frozen(s, l)), "Бродяга колдовского бриза: с какой земли?")
		if land == null:
			return
		await g.thaw(land["p"], land["lane"])
		await _freeze_one(p, g.sides(), "Бродяга колдовского бриза: какую землю заморозить?")


# Медоед
func enter_honey_badger(c, p, _lane) -> void:
	var n := 0
	for l in LANES:
		var x = creature(p, l)
		if x != null and x != c and g.is_type(x, "rainbow", p, l):
			n += 1
	if n >= 3:
		await g.add_atk_tokens(c, 4)


func def_honey_badger(c, _p, _lane) -> int:
	return g.tokens(c, "atk_tok")


# Лавиногепард Ледяная Тень
func on_discard_iceshadow_avalancheetah(_src, sp, _skind, _slane, victim, _card) -> void:
	if victim == sp or not _any(sp):
		return
	var t = await g.pick_creature(sp, g.sides(), "Ледяная Тень: нанести 2 урона выбранному существу?", Callable(), true)
	if t != null:
		await hit(t["p"], t["lane"], 2, sp)
		await g._check_state()


# Добрый огонёк
func aura_atk_kind_ling(src, sp, _slane, c, p, lane) -> int:
	return 1 if sp == p and c != src and g.is_type(c, "lava", p, lane) else 0


# Пёстрые выдры
func enter_motley_otters(c, p, _lane) -> void:
	await g.add_atk_tokens(c, _creature_types(p))


# Болтун-драчун
func atk_mouth_beater(_c, p, _lane) -> int:
	return players(p).hand.size()


func killed_mouth_beater(_c, p, _lane, _victim, _vp, _vlane) -> void:
	await g._draw(p)


# Ониксовый мерлок
func end_onyx_merlock(_c, p, _kind, _lane) -> void:
	var o: int = await g.pick_foe(p, "Ониксовый мерлок: чью колоду сбросить на 2 карты?")
	if o >= 0:
		await g.mill(o)
		await g.mill(o)


# Убедительный броненосец
func floop_persuasive_armourdillo(_c, p, _kind, _lane) -> void:
	g.add_turn(p, "spell_discount", 9)
	await say("Следующее заклинание игрока %s в этот ход бесплатно." % players(p).name)


# Психоделический скальный геккон
func sees_enter_psychedelic_rock_gecko(src, _sp, _skind, _slane, c, _p, _lane) -> bool:
	return c != src


func on_enter_psychedelic_rock_gecko(_src, sp, _skind, _slane, _c, _p, _lane) -> void:
	await g.mill(sp)


# Пухлый пингвин
## «Когда ты снимаешь урон»: only a heal by its controller's card or ability (or its team's).
func healed_puffy_penguin(_c, p, _lane, _amount) -> void:
	if g.heal_by < 0 or g.is_foe(p, g.heal_by):
		return
	for l in LANES:
		if creature(p, l) != null:
			await g.add_atk_tokens(creature(p, l))


# Страж пиропара
func leave_pyrovent_sentinel(_c, p, _lane, _reason, _info) -> void:
	if g.creature_opts(p, g.foes(p)).is_empty():
		return
	var t = await g.pick_creature(p, g.foes(p), "Страж пиропара: какому существу соперника 3 урона?")
	if t != null:
		await hit(t["p"], t["lane"], 3, p)


# Жгучий скорпион
func floop_scorchpion(c, p, _kind, lane) -> void:
	if creature(p, lane) == c:
		await g.burn_creature(p, p, lane)
	var pool: Array = players(p).hand.filter(func(x): return x.kind() == "spell" and int(x.def()["cost"]) == 1)
	if pool.is_empty():
		return
	var pick = await g.pick_card(p, pool, "Жгучий скорпион: сыграть бесплатно заклинание стоимостью 1?", true)
	if pick != null:
		await g.play_free(p, pick)


# Лавиногепард Снежный Плен
func end_snowbound_avalancheetah(_c, p, _kind, _lane) -> void:
	if g.played_not(p, "ice") >= 2:
		await _freeze_one(p, g.sides(), "Снежный Плен: заморозить землю?", true)


# Зимняя ткачиха
func floop_winter_weaver(_c, p, _kind, _lane) -> void:
	await g._draw(p)
	for s in g.seats_from(p):
		if g.frozen_count(s) > 0:
			await g.force_discard(s, 1, "Зимняя ткачиха: %s, сбрось карту" % players(s).name)


# Синюшный огнеходный спринтер: only into the rightmost lane (data "only_lane"); it walks left.
func floop_ok_woadic_blazetrail_sprinter(_c, p, _kind, lane) -> bool:
	return lane > 0 and creature(p, lane - 1) == null


func floop_woadic_blazetrail_sprinter(c, p, _kind, lane) -> void:
	await g.move_creature(p, lane, lane - 1)
	if creature(p, lane - 1) == c:
		await g.add_atk_tokens(c)
