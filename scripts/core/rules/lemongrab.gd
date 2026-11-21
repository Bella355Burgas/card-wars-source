extends "res://scripts/core/rules/base.gd"
## Лимонохват (Кукурузные поля и Песчаные земли).


# Pop-troopers: on entering they move to any empty land, theirs or the opponent's.
# Whoever controls one carries its drawback, and the owner keeps the card.
# Returns the {"p", "lane"} spot it ended up on.
func _drop(c, p: int, lane: int, hurts := false) -> Dictionary:
	var here := {"p": p, "lane": lane}
	if creature(p, lane) != c:
		return here
	var spots := []
	for side in [p] + g.foes(p):
		for l in g.empty_lanes(side):
			spots.append({"p": side, "lane": l})
	if spots.is_empty():
		return here
	var pick = await g.pick_spot(p, spots, "%s: на какую пустую землю десантироваться?" % c.card_name(),
		{"hurts_controller": hurts})
	if pick == null:
		return here
	var side := int(pick["p"])
	var dest := int(pick["lane"])
	if side == p:
		await g.move_creature(p, lane, dest)
	else:
		await g.take_control(p, lane, side, dest)
		c.moved_this_turn = true
	return {"p": side, "lane": dest}


func enter_dragoon_parrotrooper(c, p, lane) -> void:
	await _drop(c, p, lane)


func aura_atk_dragoon_parrotrooper(_src, sp, slane, _c, p, lane) -> int:
	return -1 if sp == p and absi(slane - lane) == 1 else 0


func enter_husky_parrotrooper(c, p, lane) -> void:
	var at: Dictionary = await _drop(c, p, lane)
	await g.flip_land(int(at["p"]), int(at["lane"]), true)
	if g.where(c.uid)["zone"] == "creature":
		c.flags["flipped_land"] = [int(at["p"]), int(at["lane"])]


func leave_husky_parrotrooper(_c, _p, _lane, _reason, info) -> void:
	await _restore_land(info)


func enter_jinxed_parrotrooper(c, p, lane) -> void:
	await _drop(c, p, lane, true)


func start_jinxed_parrotrooper(_c, p, _kind, _lane) -> void:
	await g.force_discard(p, 1, "Сглаженный попугайчик: сбрось карту")


func enter_static_parrotrooper(c, p, lane) -> void:
	await _drop(c, p, lane, true)


func start_static_parrotrooper(_c, p, _kind, _lane) -> void:
	await g.lose_hp(p, 1, "Статичный попугайчик")


# ТНТимми
func leave_tntimmy(_c, p, _lane, _reason, _info) -> void:
	await say("ТНТимми! 1 урон каждому существу соперника.")
	await hit_foes(p, 1)


# Аванпост попугаев: −1 ATK to every creature on its lane (the engine keeps ATK ≥ 0).
func aura_atk_parrotmilitary_outpost(_src, sp, slane, _c, p, lane) -> int:
	return -1 if g.on_lane(sp, slane, p, lane) else 0


func _distinct(p: int) -> int:
	return g.unique_land_types(p)


func def_fancy_zebracorn(_c, p, _lane) -> int:
	return _distinct(p)


func def_ol_corn_eye(_c, p, _lane) -> int:
	return _distinct(p)


func atk_rebounding_zebracorn(_c, p, _lane) -> int:
	return _distinct(p)


func atk_bouncing_zebracorn(_c, p, _lane) -> int:
	return _distinct(p)


func atk_quake_maker(_c, _p, _lane) -> int:
	return 2 * g.flipped_lands()


func atk_earth_mover(_c, _p, _lane) -> int:
	return 2 * g.flipped_lands()


# Крушитель недр / Рок-н-роллер: flip a land in its lane (either side's) on enter, restore it on leave.
func _flip_own_land(c, p: int, lane: int) -> void:
	var pick = await g.pick_land(p, g.land_opts(g.sides(),
		func(s, l): return g.on_lane(p, lane, s, l) and not players(s).lands[l]["flipped"]),
		"%s: какую землю в этой зоне перевернуть?" % c.card_name())
	if pick != null:
		await g.flip_land(pick["p"], pick["lane"], true)
		c.flags["flipped_land"] = [pick["p"], pick["lane"]]


func _restore_land(info: Dictionary) -> void:
	var at = info["flags"].get("flipped_land")
	if at != null:
		await g.flip_land(at[0], at[1], false)


func enter_mantle_masher(c, p, lane) -> void:
	await _flip_own_land(c, p, lane)


func leave_mantle_masher(_c, _p, _lane, _reason, info) -> void:
	await _restore_land(info)


func enter_rock_n_roller(c, p, lane) -> void:
	await _flip_own_land(c, p, lane)


func leave_rock_n_roller(_c, _p, _lane, _reason, info) -> void:
	await _restore_land(info)


# Взлётная площадка
func floop_lunchpad(_c, p, _kind, lane) -> void:
	var n := int(players(p).turn.get("entered_lane", {}).get(lane, 0))
	await g.draw_cards(p, n)


# Амбар свободы (cost: discard)
func act_ok_silo_of_freedom(_c, p, _kind, lane) -> bool:
	return not players(p).lands[lane]["flipped"]


func act_silo_of_freedom(_c, p, _kind, lane) -> void:
	var names := []
	var types := []
	for t in CardDB.land_types():
		types.append(t)
		names.append(CardDB.land_name(t))
	var pick = await g.pick_option(p, names, "Амбар свободы: какой станет твоя земля в зоне %d?" % (lane + 1))
	var i := names.find(pick)
	if i >= 0:
		await g.set_land_override(p, lane, types[i], p)


# Провал (cost: discard)
func floop_ok_sinkhole(_c, p, _kind, lane) -> bool:
	return g.lane_spots(p, lane).any(func(s): return not players(s[0]).lands[s[1]]["flipped"])


func floop_sinkhole(_c, p, _kind, lane) -> void:
	var pick = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return g.on_lane(p, lane, s, l) and not players(s).lands[l]["flipped"]),
		"Провал: какую землю в этой зоне перевернуть до твоего следующего хода?")
	if pick != null:
		await g.flip_land_until(pick["p"], pick["lane"], p)


# Карамельный верблюд: the engine offers to tuck leaving creatures under it.
func atk_carmel_camel(c, _p, _lane) -> int:
	return c.under.size()


func def_carmel_camel(c, _p, _lane) -> int:
	return c.under.size()


# Великая мумия
func start_grand_mummy(_c, p, _kind, lane) -> void:
	var pick = await g.pick_option(p, ["Вернуть и взять 2 карты", "Оставить"], "Великая мумия: вернуть её в руку?")
	if pick == "Вернуть и взять 2 карты":
		await g.bounce_creature(p, lane)
		await g.draw_cards(p, 2)


# Пескозавр Рекс
func atk_sandasaurus_rex(_c, p, _lane) -> int:
	return 2 * g.empty_lanes(p).size()


# Песчаный маг
func start_sandmagus(c, p, _kind, lane) -> void:
	var pick = await g.pick_option(p, ["Вернуть (+1 к атаке другим)", "Оставить"], "Песчаный маг: вернуть его в руку?")
	if pick == "Вернуть (+1 к атаке другим)":
		await g.bounce_creature(p, lane)
		for l in LANES:
			if creature(p, l) != null:
				await g.buff(creature(p, l), 1)
		g.add_turn(p, "enter_atk")      # …and so do the other creatures that enter later this turn
		var skip: Array = players(p).turn.get("enter_atk_skip", [])
		skip.append(c.uid)
		players(p).turn["enter_atk_skip"] = skip


# Ска-рпион: cheaper while the opponent controls a creature you own.
func cost_ska_pion(_c, p) -> int:
	for o in g.foes(p):
		for l in LANES:
			var t = creature(o, l)
			if t != null and t.owner == p:
				return -1
	return 0


# Зона высадки
func _owned(p: int) -> Callable:
	return func(x, _s, _l): return x.owner == p


func playable_drop_zone(_c, p) -> bool:
	return not g.creature_opts(p, g.sides(), _owned(p)).is_empty()


func spell_drop_zone(_c, p) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Зона высадки: какое существо, владелец которого ты, вернуть на руку?",
		_owned(p))
	if pick != null:
		await g.bounce_creature(pick["p"], pick["lane"])


# Окорок-кулак
func playable_ham_fist(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_ham_fist(_c, p) -> void:
	var pick = await g.pick_creature(p, [p], "Окорок-кулак: какое своё существо получит −5 ATK?")
	if pick != null:
		await g.buff(creature(p, pick["lane"]), -5)
	await g._draw(p)


# Зажигай!
func playable_rock_out(_c, _p) -> bool:
	return g.flipped_lands() < g.total_lands()


func spell_rock_out(_c, p) -> void:
	var pick = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return not players(s).lands[l]["flipped"]),
		"Зажигай!: какую землю перевернуть до твоего следующего хода?")
	if pick != null:
		await g.flip_land_until(pick["p"], pick["lane"], p)


# Быстрый подъём
func playable_quick_pick_me_up(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_quick_pick_me_up(_c, p) -> void:
	var pick = await g.pick_creature(p, [p], "Быстрый подъём: какое существо вернуть в руку?")
	if pick == null:
		return
	var n: int = creature(p, pick["lane"]).def()["cost"]
	await g.bounce_creature(p, pick["lane"])
	await g.gain_actions(p, n)


# Кукурузная лавина
func spell_amaizing_avalanche(_c, p) -> void:
	var n: int = g.flipped_lands()
	for l in LANES:
		if creature(p, l) != null and n > 0:
			await g.buff(creature(p, l), n)


# Свободное падение
func spell_free_fall(_c, p) -> void:
	var n: int = g.entered_this_turn
	for l in LANES:
		if creature(p, l) != null and n > 0:
			await g.buff(creature(p, l), n)
