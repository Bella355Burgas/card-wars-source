extends "res://scripts/core/rules/base.gd"
## Принцесса Пупырка (Бесплодные болота и Синие равнины).


# Мавзолей
func aura_def_mausoleum(_src, sp, slane, _c, p, lane) -> int:
	return g.discard_fives(sp) if sp == p and slane == lane else 0


func atk_fatapillar(_c, p, _lane) -> int:
	return 2 * g.discard_fives(p)


# Башня ночи
func floop_ok_night_tower(_c, p, _kind, lane) -> bool:
	return opposite(p, lane) == null and not players(g.across(p, lane)[0]).hand.is_empty()


func floop_night_tower(_c, p, _kind, lane) -> void:
	var o: int = g.across(p, lane)[0]
	if opposite(p, lane) == null:
		await g.force_discard(o, 1, "Башня ночи: %s сбрасывает карту" % players(o).name)


# Discard-to-pump creatures (the discard is paid by the engine).
func act_dragon_foot(c, _p, _kind, _lane) -> void:
	await g.buff(c, 1)


func act_herculeye(c, _p, _kind, _lane) -> void:
	await g.buff(c, 4)


func act_dogboy(c, _p, _kind, _lane) -> void:
	await g.buff(c, 2)


# Бродячая бесконечность
func act_ok_infinite_figure(_c, p, _kind, lane) -> bool:
	return opposite_open(p, lane)


func act_infinite_figure(_c, p, _kind, lane) -> void:
	var a: Array = g.across(p, lane)
	await hit(a[0], a[1], 1, p)


# Розовая ундинка
func act_pink_merwitch(_c, p, _kind, _lane) -> void:
	await hit_foes(p, 1)


# Лысый приседун
func act_ok_squatting_bald_man(c, _p, _kind, _lane) -> bool:
	return c.damage > 0


func act_squatting_bald_man(_c, p, _kind, lane) -> void:
	await g.heal_creature(p, lane, 1)


# Рука скелета
func floop_skeletal_hand(_c, p, _kind, _lane) -> void:
	var spells := 0
	for i in 3:
		var c = await g.mill(p)
		if c != null and c.kind() == "spell":
			spells += 1
	if spells > 0:
		var o: int = await g.pick_foe(p, "Рука скелета: кто из соперников сбросит карты?")
		await g.force_discard(o, spells, "Рука скелета: %s сбрасывает карту" % players(o).name)


# Антрекот-мясник
func after_draw_steakchop(_c, p, _kind, lane) -> void:
	var opts := ["Уничтожить Антрекот-мясник"]
	if players(p).hand.size() >= 2:
		opts.push_front("Сбросить 2 карты")
	var pick = await g.pick_option(p, opts, "Антрекот-мясник: сбросить 2 карты или уничтожить его?")
	if pick == "Сбросить 2 карты":
		await g.force_discard(p, 2, "Антрекот-мясник: сбрось карту")
	else:
		await g.destroy_creature(p, lane)


# Пирамидия
func floop_ok_pyramidia(_c, p, _kind, lane) -> bool:
	return creature(p, lane) != null


func floop_pyramidia(_c, p, _kind, lane) -> void:
	var la: Dictionary = players(p).turn.get("lane_actions", {})
	la[lane] = int(la.get(lane, 0)) + 1
	players(p).turn["lane_actions"] = la
	await say("%s получает 1 действие — только для существа в зону %d." % [players(p).name, lane + 1])
	await g.emit_event({"type": "actions", "p": p, "gain": 1})


# Скелет-покатун
func floop_ok_travelin_skeleton(_c, p, _kind, _lane) -> bool:
	return g.creature_count(p) >= 2


func floop_travelin_skeleton(_c, p, _kind, lane) -> void:
	var pick = await g.pick_creature(p, [p], "Скелет-покатун: с каким существом поменяться зонами?",
		func(_x, _s, l): return l != lane)
	if pick != null:
		await g.swap_creatures(p, lane, pick["lane"])


# Replacing a creature: djinis, goat and friends.
func _replaced(c) -> bool:
	return c.flags.get("replaced", false)


func enter_blueberry_djini(c, p, _lane) -> void:
	if _replaced(c):
		await g.draw_cards(p, 2)


func enter_grape_djini(c, p, _lane) -> void:
	if not _replaced(c):
		return
	var pool: Array = g.discard_pool(p)
	if pool.is_empty():
		return
	var pick = await g.pick_card(p, pool, "Виноградный джинн: можешь положить карту из сброса наверх колоды", true)
	if pick != null:
		players(p).discard.erase(pick)
		players(p).deck.append(pick)
		await say("«%s» кладётся наверх колоды." % pick.card_name())
		await g.emit_event({"type": "to_deck", "p": p, "uid": pick.uid})


func enter_brain_gooey(c, _p, _lane) -> void:
	if _replaced(c):
		await g.buff(c, 2)


func enter_future_scholar(c, p, _lane) -> void:
	if _replaced(c):
		await g.gain_actions(p, 1)


func enter_headphone_jerk(c, p, lane) -> void:
	if _replaced(c) and opposite_open(p, lane):
		var a: Array = g.across(p, lane)
		await hit(a[0], a[1], 3, p)


func enter_goat(c, p, _lane) -> void:
	if _replaced(c):
		await g._draw(p)


# Роковой сортир
func playable_toilet_of_doom(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_toilet_of_doom(_c, p) -> void:
	var n: int = g.discard_fives(p)
	var pick = await g.pick_creature(p, [p], "Роковой сортир: +%d ATK своему существу" % n)
	if pick != null:
		await g.buff(creature(p, pick["lane"]), n)


# Кристалл силы
func spell_strength_crystal(_c, p) -> void:
	# «Выбранный игрок»: in 2 на 2 the teammate may be picked too.
	var opts := ["Тянуть мне", "Тянет соперник"]
	if g.teammate(p) >= 0:
		opts.append("Тянет союзник")
	var pick = await g.pick_option(p, opts, "Кристалл силы: кто берёт 5 карт?")
	if pick == "Тянет союзник":
		await g.draw_cards(g.teammate(p), 5)
	elif pick != "Тянет соперник":
		await g.draw_cards(p, 5)
	else:
		await g.draw_cards(await g.pick_foe(p, "Кристалл силы: кто из соперников тянет?"), 5)


# Подсознательная мощь
func playable_subliminal_strength(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_subliminal_strength(_c, p) -> void:
	var n := 2 * int(g.turn_value(p, "spells"))
	var pick = await g.pick_creature(p, [p], "Подсознательная мощь: +%d ATK своему существу" % n)
	if pick != null:
		await g.buff(creature(p, pick["lane"]), n)


# Портки отпадности
func _empty_plains(p: int) -> Array:
	var out := []
	for l in g.empty_lanes(p):
		if g.land_type(p, l) == "plain":
			out.append(l)
	return out


func playable_pants_of_awesome(_c, p) -> bool:
	return g.creature_count(p) > 0 and not _empty_plains(p).is_empty()


func spell_pants_of_awesome(_c, p) -> void:
	var pick = await g.pick_creature(p, [p], "Портки отпадности: кого переместить?")
	if pick != null:
		var dest: int = await g.pick_lane(p, p, _empty_plains(p), "На какую пустую Синюю равнину?")
		if dest >= 0:
			await g.move_creature(p, pick["lane"], dest)
	await g._draw(p)


# Сила труселей
func playable_brief_power(_c, p) -> bool:
	return not g.creature_opts(p, [p], func(x, s, l): return g.is_type(x, "swamp", s, l)).is_empty()


func spell_brief_power(_c, p) -> void:
	var pick = await g.pick_creature(p, [p], "Сила труселей: +2 ATK своему Болотному существу",
		func(x, s, l): return g.is_type(x, "swamp", s, l))
	if pick != null:
		await g.buff(creature(p, pick["lane"]), 2)


# Вулкан
func playable_volcano(_c, _p) -> bool:
	return g.sides().any(func(s): return g.building_count(s) > 0)


func spell_volcano(_c, p) -> void:
	var opts := []
	for s in g.sides():
		for l in LANES:
			for e in g.buildings_at(s, l):
				opts.append({"p": s, "lane": l, "kind": e[1]})
	var pick = await g._choose({"kind": "building", "player": p, "options": opts, "prompt": "Вулкан: какое строение уничтожить?"})
	if pick == null:
		return
	var side: int = pick["p"]
	var lane: int = pick["lane"]
	await g.destroy_building(side, lane, pick.get("kind", "building"))
	var t = await g.pick_creature(p, g.sides(), "Вулкан: можешь нанести 3 урона существу в этой зоне",
		func(_x, s, l): return g.on_lane(side, lane, s, l), true)
	if t != null:
		await hit(t["p"], t["lane"], 3, p)
	# p's own land on that lane (2 на 2 the lane may be other players' only).
	for s in g.lane_spots(side, lane):
		if s[0] == p:
			await g.flip_land(p, s[1], true)
