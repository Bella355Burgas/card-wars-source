extends "res://scripts/core/rules/base.gd"
## Финн (Синие равнины).


func atk_struzann_jinn(_c, p, _lane) -> int:
	return 2 * g.count_flooped(p)


func atk_woadic_chief(_c, p, _lane) -> int:
	return 2 * int(g.turn_value(p, "spells")) if p == g.turn_player else 0


func aura_atk_spirit_soldier(_src, sp, slane, _c, p, lane) -> int:
	return 1 if sp == p and absi(slane - lane) == 1 else 0


func aura_atk_punk_cat(_src, _sp, _slane, c, _p, _lane) -> int:
	return 2 if c.moved_this_turn else 0


# Древний грамотей
func floop_ancient_scholar(c, p, _kind, lane) -> void:
	var pool: Array = g.discard_pool(p, func(x): return x.def()["land"] == "rainbow")
	if not pool.is_empty():
		await g.return_to_hand(pool[g.rng.randi() % pool.size()])
	if not g.buildings_at(p, lane).is_empty():
		await g.gain_actions(p, 1)


# Лапа дракона
func floop_ok_dragon_claw(_c, p, _kind, _lane) -> bool:
	return g.creature_count(p) > 0 and not g.empty_lanes(p).is_empty()


func floop_dragon_claw(c, p, _kind, _lane) -> void:
	await move_own_creature(p, "%s: выбери своё существо" % c.card_name())


# Стеснительный бард
func floop_embarrassing_bard(_c, p, _kind, _lane) -> void:
	await g.draw_cards(p, g.count_flooped(p))


# Благо одноглазое
func floop_ok_heavenly_gazer(_c, p, _kind, _lane) -> bool:
	return not g.discard_pool(p, func(x): return x.kind() == "spell").is_empty()


func floop_heavenly_gazer(_c, p, _kind, _lane) -> void:
	var pool: Array = g.discard_pool(p, func(x): return x.kind() == "spell")
	var pick = await g.pick_card(p, pool, "Благо одноглазое: выбери заклинание — оно ляжет наверх колоды")
	if pick != null:
		g.players[p].discard.erase(pick)
		g.players[p].deck.append(pick)
		await say("«%s» кладётся наверх колоды." % pick.card_name())
		await g.emit_event({"type": "to_deck", "p": p, "uid": pick.uid})


# Архитектор разума
func enter_psionic_architect(_c, p, _lane) -> void:
	var pick = await g.pick_creature(p, [p], "Архитектор разума: можешь подготовить флюпнутое существо",
		func(x, _s, _l): return x.flooped, true)
	if pick != null:
		var t = creature(p, pick["lane"])
		t.exhausted = false
		t.flooped = false
		await say("«%s» снова готово." % t.card_name())
		await g.emit_event({"type": "ready", "p": p, "uid": t.uid})


# Синюшный злопыхатель
func moved_woadic_marauder(_c, p, _from, _to) -> void:
	await say("Синюшный злопыхатель сменил зону: %s берёт карту." % players(p).name)
	await g._draw(p)


# Велорыцарь
func act_ok_uni_knight(_c, p, _kind, lane) -> bool:
	return not g.creature_opts(p, g.sides(), func(_x, s, l): return g.on_lane(p, lane, s, l)).is_empty()


func act_uni_knight(_c, p, _kind, lane) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Велорыцарь: выбери существо в этой зоне (−10 ATK в этом ходу)",
		func(_x, s, l): return g.on_lane(p, lane, s, l))
	if pick != null:
		await g.buff(creature(pick["p"], pick["lane"]), -10)


# Школа
func _floop_creatures_in(cards: Array) -> Array:
	var ids := []
	for c in cards:
		if c.kind() == "creature" and c.def().get("floop", false) and not ids.has(c.id):
			ids.append(c.id)
	return ids


func floop_ok_schoolhouse(_c, p, _kind, lane) -> bool:
	return not bld_targets(p, lane).is_empty() and not _floop_creatures_in(players(p).discard).is_empty()


func floop_schoolhouse(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Школа: какое существо?")
	var target = creature(p, l) if l >= 0 else null
	var pool := _floop_creatures_in(players(p).discard)
	if target == null or pool.is_empty():
		return
	var borrowed: String = pool[g.rng.randi() % pool.size()]
	target.lost_abilities = true
	target.granted_floop = borrowed
	var nm: String = CardDB.get_def(borrowed)["name"]
	await say("«%s» теряет способности и получает флюп «%s» до конца хода." % [target.card_name(), nm])
	await flash(target, "Флюп: " + nm)


# Синюшный вигвам
func floop_ok_woad_mobile_home(_c, p, _kind, lane) -> bool:
	if creature(p, lane) != null:
		return false
	for a in adj(lane):
		if creature(p, a) != null:
			return true
	return false


func floop_woad_mobile_home(_c, p, _kind, lane) -> void:
	var pick = await g.pick_creature(p, [p], "Синюшный вигвам: выбери существо с соседней зоны",
		func(_x, _s, l): return absi(l - lane) == 1)
	if pick != null:
		await g.move_creature(p, pick["lane"], lane)


# Свинья
func floop_ok_the_pig(_c, p, _kind, lane) -> bool:
	return g.lane_spots(p, lane).any(func(s): return g.land_type(s[0], s[1]) == "corn")


func floop_the_pig(_c, p, _kind, lane) -> void:
	var pick = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return g.on_lane(p, lane, s, l) and g.land_type(s, l) == "corn"),
		"Свинья: выбери Кукурузное поле в этой зоне")
	if pick != null:
		await g.flip_land(pick["p"], pick["lane"], true)


# Синюшная кровь
## Every creature, either side, that has changed Lanes by now; one that moves later gets nothing.
func spell_woad_blood(_c, _p) -> void:
	await say("Сменившие зону существа получают +2 ATK.")
	for e in g.in_play():
		if e[2] == "creature" and e[0].moved_this_turn:
			await g.buff(e[0], 2)


# Синюшный талисман
func playable_woad_talisman(_c, p) -> bool:
	return not g.creature_opts(p, [p], func(x, s, l): return g.is_type(x, "plain", s, l)).is_empty()


func spell_woad_talisman(_c, p) -> void:
	var pick = await g.pick_creature(p, [p], "Синюшный талисман: выбери существо Синей равнины (+2 ATK)",
		func(x, s, l): return g.is_type(x, "plain", s, l))
	if pick != null:
		await g.buff(creature(p, pick["lane"]), 2)


# Гномьи сопли
func spell_gnome_snot(_c, p) -> void:
	await g.draw_cards(p, 3)
