extends "res://scripts/core/rules/base.gd"
## Призмо (всех земель понемногу): карты, сыгранные с землями другого типа (Game.played_not),
## и существа стоимостью 1.


func _cost1(x) -> bool:
	return int(x.def()["cost"]) == 1


## Different land types among p's creatures in play (Призматархия, Песчаная синергия: all creatures).
func _creature_types(sides: Array) -> int:
	var seen := {}
	for s in sides:
		for l in LANES:
			var x = creature(s, l)
			if x != null:
				for t in g.card_types(x, s, l):
					if t != "rainbow":    # a rainbow creature has no land type
						seen[t] = true
	return seen.size()


# Адепт двойных чар
func end_dualcast_adept(_c, p, _kind, _lane) -> void:
	if g.played_not(p, "plain") >= 2:
		await say("Адепт двойных чар: %s берёт карту." % players(p).name)
		await g._draw(p)


# Зачарованный мистик
func end_spellbound_mystic(_c, p, _kind, lane) -> void:
	if g.played_not(p, "plain") < 2:
		return
	var near := func(_x, s, l): return adj(lane).any(func(a): return g.on_lane(p, a, s, l))
	var t = await g.pick_creature(p, g.sides(), "Зачарованный мистик: с какого существа в соседней зоне снять 2 урона?", near)
	if t != null:
		await g.heal_creature(t["p"], t["lane"], 2, p)


# Колдун двойных чар
func floop_ok_duplicast_sorcerer(_c, p, _kind, _lane) -> bool:
	return g.played_not(p, "plain") >= 2


func floop_duplicast_sorcerer(_c, p, _kind, _lane) -> void:
	await hit_foes(p, 2)


# Дюнный багги-жук
func enter_dune_bug_buggie(_c, p, _lane) -> void:
	if players(p).deck.is_empty():
		return
	if await g.pick_option(p, ["Открыть", "Нет"], "Дюнный багги-жук: открыть верхнюю карту колоды?") != "Открыть":
		return
	var top = players(p).deck.back()
	await say("Дюнный багги-жук: сверху «%s»." % top.card_name())
	await g.emit_event({"type": "reveal", "p": p, "uids": [top.uid]})
	if g.play_land(top) == "sandy":
		return
	if await g.pick_option(p, ["Сыграть бесплатно", "Оставить"], "Сыграть «%s» бесплатно?" % top.card_name()) == "Сыграть бесплатно":
		await g.play_free(p, top)


# Горячая голова
func cost_hothead(_c, p) -> int:
	var n := 0
	for l in LANES:
		var x = creature(p, l)
		if x != null and _cost1(x):
			n += 1
	return -n


# Призматархия
func cost_prismatarchia(_c, p) -> int:
	return -_creature_types([p])


# Страж оазиса
func on_played_oasis_guardian(_src, sp, _skind, _slane, p, c) -> void:
	if p == sp and g.play_land(c) != "sandy":
		await hit_foes(sp, 1)


# Призматический боевой жук
func on_played_prismatic_war_beetle(src, sp, _skind, _slane, p, c) -> void:
	if p == sp and g.play_land(c) != "sandy":
		await g.buff(src, 1)


# Лавовые муравьи: once a turn, when the second non-LavaFlats card is played.
func on_played_lava_ants(src, sp, _skind, _slane, p, _c) -> void:
	if p == sp and g.played_not(p, "lava") >= 2 and int(src.flags.get("ants_turn", -1)) != g.turn_number:
		src.flags["ants_turn"] = g.turn_number
		await g.add_atk_tokens(src)


# Тектонический тихоход
func dmg_in_tectonic_tardigrade(_c, p, _lane, amount, info) -> int:
	if g.is_foe(p, int(info.get("p", -1))) and info.get("card") != null and g.played_not(p, "lava") >= 2:
		return 0
	return amount


# Президент Сладкий Початок
func enter_president_sweetcorn(_c, p, _lane) -> void:
	await g.gain_actions(p, 1)


# Сагуаро поддержки
func aura_atk_support_saguaro(_src, sp, _slane, c, p, lane) -> int:
	return 1 if sp == p and not g.is_type(c, "sandy", p, lane) else 0


# Апартаменты «Родник»
func aura_atk_wellspring_apartments(_src, sp, slane, _c, p, lane) -> int:
	return g.played_not(sp, "sandy") if sp == p and slane == lane else 0


# Лагерь «Зёрнышко»
func aura_atk_camp_kernel(_src, sp, slane, c, p, lane) -> int:
	return 1 if sp == p and slane == lane and _cost1(c) else 0


func aura_def_camp_kernel(_src, sp, slane, c, p, lane) -> int:
	return 1 if sp == p and slane == lane and _cost1(c) else 0


# Перечный дворец
func aura_atk_pepper_palace(_src, sp, slane, _c, p, lane) -> int:
	return 2 if not g.is_foe(sp, p) and g.on_lane(sp, slane, p, lane) and g.played_not(sp, "lava") >= 2 else 0


# Наездник брога
func leave_broog_rider(_c, p, _lane, _reason, _info) -> void:
	for l in LANES:
		var x = creature(p, l)
		if x != null and _cost1(x):
			await g.add_atk_tokens(x)


# Мидиляк, кровавая раковина
func attack_clampire_sanguine_shell(_c, p, _lane) -> void:
	var t = await g.pick_creature(p, [p], "Мидиляк: с какого своего существа снять 1 урон?")
	if t != null:
		await g.heal_creature(p, t["lane"], 1)


# Краб-носильщик
func enter_carrier_crab(_c, p, _lane) -> void:
	var pool: Array = players(p).hand.filter(func(x): return int(x.def()["cost"]) == 1)
	if pool.is_empty():
		return
	var pick = await g.pick_card(p, pool, "Краб-носильщик: сыграть бесплатно карту стоимостью 1?", true)
	if pick != null:
		await g.play_free(p, pick)


# Хамелеон: its land type is chosen when it is played.
func enter_chameleon(c, p, _lane) -> void:
	var types: Array = CardDB.land_types()
	var names: Array = types.map(func(t): return CardDB.land_name(t))
	var pick = await g.pick_option(p, names, "Хамелеон: какой у него будет тип земель?")
	var t: String = types[maxi(names.find(pick), 0)]
	c.flags["land_as"] = t
	var lands: Array = players(p).turn.get("played_lands", [])
	if c.flags.get("from_hand", false) and not lands.is_empty():
		lands[lands.size() - 1] = t
	await flash(c, CardDB.land_name(t))


# Убийственные ходули
func spell_killer_stilts(_c, p) -> void:
	var n := 0
	for l in LANES:
		var x = creature(p, l)
		if x != null and _cost1(x):
			n += 1
			await g.buff(x, 1)
	if n >= 3:
		await g.gain_actions(p, 1)


# Смерч штормового клинка
func playable_galeblade_tornado(_c, p) -> bool:
	return g.creature_count(p) > 0 and not g.creature_opts(p, g.foes(p)).is_empty()


func spell_galeblade_tornado(_c, p) -> void:
	var a = await g.pick_creature(p, [p], "Смерч штормового клинка: какое своё существо вернуть на руку?")
	var b = await g.pick_creature(p, g.foes(p), "Смерч штормового клинка: какое существо соперника вернуть на руку?")
	if a != null:
		await g.bounce_creature(a["p"], a["lane"])
	if b != null:
		await g.bounce_creature(b["p"], b["lane"])


# Песчаная синергия
func spell_sand_synergy(_c, p) -> void:
	await g.draw_cards(p, _creature_types(g.sides()))


# Циклон
func spell_cyclone(_c, _p) -> void:
	for s in g.sides():
		await hit_all(s, 4, func(x, _s, _l): return not _cost1(x))
	await g._check_state()


# Мрачный обмен: destroy your creature, play another player's top card as a Rainbow card for free.
func playable_grim_exchange(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_grim_exchange(_c, p) -> void:
	var t = await g.pick_creature(p, [p], "Мрачный обмен: какое своё существо уничтожить?")
	if t == null:
		return
	await g.destroy_creature(p, t["lane"])
	var others: Array = g.sides().filter(func(s): return s != p and not players(s).deck.is_empty())
	if others.is_empty():
		return
	var o: int = others[0]
	if others.size() > 1:
		var names: Array = others.map(func(s): return players(s).name)
		o = others[maxi(names.find(await g.pick_option(p, names, "Мрачный обмен: чью колоду открыть?")), 0)]
	var top = players(o).deck.back()
	await say("Мрачный обмен: сверху колоды %s «%s»." % [players(o).name, top.card_name()])
	await g.emit_event({"type": "reveal", "p": o, "uids": [top.uid]})
	top.flags["rainbow"] = true
	if await g.pick_option(p, ["Сыграть бесплатно", "Нет"], "Сыграть «%s» бесплатно?" % top.card_name()) == "Сыграть бесплатно":
		if await g.play_free(p, top):
			return
	top.flags.erase("rainbow")
