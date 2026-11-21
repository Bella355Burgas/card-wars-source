extends "res://scripts/core/rules/base.gd"
## «Во имя славы» (набор 9): карты для своих колод, в основном о типах земель.


func _any(p: int) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


## The land type under a creature in play ("" when face down or not in play).
func _land_of(c) -> String:
	var w: Dictionary = g.where(c.uid)
	return g.land_type(w["p"], w["lane"]) if w["zone"] == "creature" else ""


func _three_types(p: int) -> bool:
	return g.unique_land_types(p) >= 3


## Your creatures get +2 ATK this turn when they attack a creature on a land of type t.
func _vs_land(p: int, t: String) -> void:
	var d: Dictionary = players(p).turn.get("vs_land", {})
	d[t] = int(d.get(t, 0)) + 2
	players(p).turn["vs_land"] = d
	await say("В этот ход существа игрока %s получают +2 к атаке против существ на земле «%s»." % [players(p).name, CardDB.land_name(t)])


## 1 damage to each opposing creature on a land of type t (гномы).
func _gnome(p: int, t: String) -> void:
	await hit_foes(p, 1, func(_x, s, l): return g.land_type(s, l) == t)


## Fight bonus against a creature on a land of type t: when attacking (attacking = true) or defending.
func _vs(other, attacking: bool, want_attacking: bool, t: String, n: int) -> int:
	return n if other != null and attacking == want_attacking and _land_of(other) == t else 0


# ---------------------------------------------------------------- spells

func spell_confectionary_ring(_c, p) -> void:
	await _vs_land(p, "corn")


func spell_ring_of_third_eye(_c, p) -> void:
	await _vs_land(p, "corn")


func spell_husker_amulet(_c, p) -> void:
	await _vs_land(p, "cute")


func spell_scroll_of_bad_breath(_c, p) -> void:
	await _vs_land(p, "cute")


func spell_lucky_penny(_c, p) -> void:
	await _vs_land(p, "plain")


func spell_popcorn_power(_c, p) -> void:
	await _vs_land(p, "plain")


func spell_magic_lamp(_c, p) -> void:
	await _vs_land(p, "sandy")


func spell_pink_candy(_c, p) -> void:
	await _vs_land(p, "sandy")


func spell_scroll_of_fresh_breath(_c, p) -> void:
	await _vs_land(p, "swamp")


func spell_snake_eyes(_c, p) -> void:
	await _vs_land(p, "swamp")


# Цельнометаллический гвалт
func playable_full_metal_racket(_c, p) -> bool:
	return _any(p)


func spell_full_metal_racket(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Цельнометаллический гвалт: 2 урона выбранному существу")
	if t != null:
		await hit(t["p"], t["lane"], 2, p)


# Виноградный зад
func playable_grape_butt(_c, p) -> bool:
	return g.played_not(p, "corn") >= 1 and _any(p)


func spell_grape_butt(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Виноградный зад: 5 урона выбранному существу")
	if t != null:
		await hit(t["p"], t["lane"], 5, p)


# Невероятное яйцо
func spell_incredible_egg(_c, p) -> void:
	var deck: Array = players(p).deck
	var top := []
	for i in mini(2, deck.size()):
		top.append(deck[deck.size() - 1 - i])
	if top.is_empty():
		return
	await g.emit_event({"type": "reveal", "p": p, "uids": top.map(func(x): return x.uid)})
	var corn: Array = top.filter(func(x): return g.play_land(x) == "corn")
	var keep = null
	if not corn.is_empty():
		keep = await g.pick_card(p, corn, "Невероятное яйцо: взять на руку кукурузную карту?", true)
	for x in top:
		deck.erase(x)
		if x == keep:
			players(p).hand.append(x)
			await g.emit_event({"type": "to_hand", "p": p, "uid": x.uid, "from": "deck"})
		else:
			await g._to_discard(x, "deck")


# Сила кунг-фу: one creature of each type is readied.
func spell_kung_fu_power(_c, p) -> void:
	var done := {}
	while true:
		var opts: Array = g.creature_opts(p, [p], func(x, s, l): return x.exhausted and not done.has(g.card_types(x, s, l)[0]))
		if opts.is_empty():
			return
		var t = await g.pick_creature(p, [p], "Сила кунг-фу: какое существо подготовить (по одному каждого типа)?",
			func(x, s, l): return x.exhausted and not done.has(g.card_types(x, s, l)[0]), true)
		if t == null:
			return
		var x = creature(p, t["lane"])
		done[g.card_types(x, p, t["lane"])[0]] = true
		x.exhausted = false
		x.flooped = false
		await g.emit_event({"type": "ready", "p": p, "uid": x.uid})


# Мастер маскировки
func spell_master_of_disguise(_c, p) -> void:
	for o in g.foes(p):
		for l in LANES:
			if creature(o, l) != null:
				await g.buff(creature(o, l), -1)


# Музыкальный стул: up to two of your lands get another type for good.
func spell_musical_chair(_c, p) -> void:
	for i in 2:
		var land = await g.pick_land(p, g.land_opts([p]), "Музыкальный стул: какую свою землю заменить?", true)
		if land == null:
			return
		var types: Array = CardDB.land_types()
		var names: Array = types.map(func(t): return CardDB.land_name(t))
		var pick = await g.pick_option(p, names, "Музыкальный стул: на какую землю заменить?")
		players(p).lands[land["lane"]]["type"] = types[maxi(names.find(pick), 0)]
		await g.emit_event({"type": "land", "p": p, "lane": land["lane"]})
		await say("%s: земля в зоне %d теперь «%s»." % [players(p).name, int(land["lane"]) + 1, pick])


# Подтяжки огра
func spell_ogre_braces(_c, p) -> void:
	await g.heal_player(p, g.discard_fives(p))


# Портал отзыва
func playable_portal_of_unsummoning(_c, p) -> bool:
	return _any(p)


func spell_portal_of_unsummoning(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Портал отзыва: какое существо вернуть на руку?")
	if t != null:
		await g.bounce_creature(t["p"], t["lane"])


# Портал в никуда
func _can_shift(o: int, l: int) -> bool:
	return adj(l).any(func(a): return creature(o, a) == null)


func playable_portal_to_nowhere(_c, p) -> bool:
	return not g.creature_opts(p, g.foes(p), func(_x, s, l): return _can_shift(s, l)).is_empty()


func spell_portal_to_nowhere(_c, p) -> void:
	var t = await g.pick_creature(p, g.foes(p), "Портал в никуда: какое существо соперника передвинуть?",
		func(_x, s, l): return _can_shift(s, l))
	if t == null:
		return
	var o: int = t["p"]
	var dest: int = await g.pick_lane(p, o, adj(t["lane"]).filter(func(a): return creature(o, a) == null), "Портал в никуда: в какую соседнюю зону?")
	if dest >= 0:
		await g.move_creature(o, t["lane"], dest)


# Психическая буря
func spell_psychic_tempest(_c, p) -> void:
	for l in LANES:
		if creature(p, l) != null:
			await g.bounce_creature(p, l)


# Лапа пумы
func playable_puma_paw(_c, p) -> bool:
	return not g.creature_opts(p, [p], func(x, _s, _l): return x.flooped).is_empty()


func spell_puma_paw(_c, p) -> void:
	var t = await g.pick_creature(p, [p], "Лапа пумы: какое флюпнутое существо подготовить?", func(x, _s, _l): return x.flooped)
	if t == null:
		return
	var x = creature(p, t["lane"])
	x.exhausted = false
	x.flooped = false
	await g.emit_event({"type": "ready", "p": p, "uid": x.uid})
	await g.buff(x, 2)


# Восстание мертвецов
func spell_raise_the_dead(_c, p) -> void:
	var pool: Array = g.discard_pool(p, func(x): return x.kind() == "creature" and int(x.def()["cost"]) <= 2)
	if pool.is_empty():
		return
	var pick = await g.pick_card(p, pool, "Восстание мертвецов: какое существо ввести в игру?")
	if pick != null:
		await g.play_free(p, pick, "Восстание мертвецов: в какую зону?")


# Кольцо урона
func spell_ring_of_damage(_c, p) -> void:
	for l in LANES:
		if creature(p, l) != null:
			await g.buff(creature(p, l), 2)


# Носки стойкости
func spell_socks_of_fortitude(_c, p) -> void:
	for l in LANES:
		var x = creature(p, l)
		if x != null and x.moved_this_turn:
			x.exhausted = false
			x.flooped = false
			await g.emit_event({"type": "ready", "p": p, "uid": x.uid})
			await g.buff(x, 2)


# Искажение чар
func playable_spell_warp(_c, p) -> bool:
	return g.creature_count(p) >= 2


func spell_spell_warp(_c, p) -> void:
	var a = await g.pick_creature(p, [p], "Искажение чар: какое существо поменять местами?")
	if a == null:
		return
	var first: int = a["lane"]
	var b = await g.pick_creature(p, [p], "Искажение чар: с каким?", func(_x, _s, l): return l != first)
	if b != null:
		await g.swap_creatures(p, first, b["lane"])


# Снижение налогов: buildings may move to lanes without one, yours and the opponent's.
func spell_tax_reduction(_c, p) -> void:
	for s in [p] + g.foes(p):
		for l in LANES:
			var b = players(s).buildings[l]
			if b == null or b.flags.get("taxed", false):
				continue
			var free: Array = range(LANES).filter(func(x): return players(s).buildings[x] == null)
			if free.is_empty():
				break
			var dest: int = await g.pick_lane(p, s, free, "Снижение налогов: переместить «%s»?" % b.card_name(), "building", true)
			if dest >= 0:
				b.flags["taxed"] = true
				await g.move_building(s, l, dest)
		for l in LANES:
			if players(s).buildings[l] != null:
				players(s).buildings[l].flags.erase("taxed")


# Ведьмина пощёчина
func spell_witch_slap(_c, p) -> void:
	var o: int = await g.pick_foe(p, "Ведьмина пощёчина: какой соперник?")
	if o < 0:
		return
	var n: int = maxi(players(o).hand.size() - 5, 0)
	var done: int = await g.force_discard(o, n, "%s: сбрось карты до 5" % players(o).name)
	if done > 0:
		await g.damage_player(o, done, null, {"kind": "effect", "p": p})


# Ведьмин путь
func spell_witch_way(_c, p) -> void:
	for l in LANES:
		if creature(p, l) != null and g.land_type(p, l) == "swamp":
			await g.buff(creature(p, l), 2)


# ---------------------------------------------------------------- buildings

# Хижина эльфа (1 action)
func act_elf_hut(_c, p, _kind, lane) -> void:
	var n := 0
	for s in g.bld_spots(p, lane):
		if creature(s[0], s[1]) != null:
			n += 1
	await g.draw_cards(p, n)


# Фонтан слёз
func aura_atk_fountain_of_tears(_src, sp, slane, c, p, lane) -> int:
	return 3 if sp == p and slane == lane and c.damage == 3 else 0


# Башня страха (1 action)
func act_ok_fright_tower(_c, p, _kind, lane) -> bool:
	return not g.creature_opts(p, g.sides(), func(_x, s, l): return g.bld_on_lane(p, lane, s, l)).is_empty()


func act_fright_tower(_c, p, _kind, lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Башня страха: какому существу в этой зоне +%d к атаке?" % g.discard_fives(p),
		func(_x, s, l): return g.bld_on_lane(p, lane, s, l))
	if t != null:
		await g.buff(creature(t["p"], t["lane"]), g.discard_fives(p))


# Иглу-убежище
func floop_ok_igloo_of_sanctuary(_c, p, _kind, lane) -> bool:
	return bld_targets(p, lane).any(func(l): return creature(p, l).moved_this_turn)


func floop_igloo_of_sanctuary(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Иглу святилища: какое существо получит +3 к атаке?")
	if l >= 0:
		await g.buff(creature(p, l), 3)


# Добрая мельница (1 action)
func act_ok_nice_windmill(_c, p, _kind, lane) -> bool:
	return not bld_targets(p, lane).is_empty()


func act_nice_windmill(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Добрая мельница: с каким существом?")
	if l < 0:
		return
	lane = l
	var x = creature(p, lane)
	var opts := ["Снять 2 урона", "Снять 1 урон", "Нанести 1 урон", "Нанести 2 урона"]
	var pick = await g.pick_option(p, opts, "Добрая мельница: что сделать с «%s»?" % x.card_name())
	match pick:
		"Снять 2 урона":
			await g.heal_creature(p, lane, 2)
		"Снять 1 урон":
			await g.heal_creature(p, lane, 1)
		"Нанести 1 урон":
			await hit(p, lane, 1, p)
		"Нанести 2 урона":
			await hit(p, lane, 2, p)


# Песчаная пирамида (2 actions)
func act_sand_pyramid(_c, p, _kind, lane) -> void:
	for s in g.lane_spots(p, lane):
		if creature(s[0], s[1]) != null:
			await g.bounce_creature(s[0], s[1])


# Тёмная пирамида
func floop_shadowy_pyramid(_c, p, _kind, lane) -> void:
	await g._draw(p)
	if not bld_targets(p, lane).is_empty():
		await g.force_discard(p, 1, "Тёмная пирамида: сбрось карту")


# Амбар правосудия (1 action)
func act_ok_silo_of_justice(_c, p, _kind, lane) -> bool:
	return not g.creature_opts(p, g.sides(), func(_x, s, l): return g.bld_on_lane(p, lane, s, l)).is_empty()


func act_silo_of_justice(_c, p, _kind, lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Амбар правосудия: какому существу в этой зоне 1 урон?",
		func(_x, s, l): return g.bld_on_lane(p, lane, s, l))
	if t == null:
		return
	await hit(t["p"], t["lane"], 1, p)
	await g.lose_hp(int(t["p"]), 1, "Амбар правосудия")


# Храм солнца
func sees_enter_temple_of_the_sun(_src, sp, _skind, slane, c, p, lane) -> bool:
	return p == sp and lane == slane and p == g.turn_player and g.is_type(c, "sandy", p, lane) and int(c.def()["cost"]) >= 1


func on_enter_temple_of_the_sun(_src, _sp, _skind, _slane, c, p, lane) -> void:
	if await g.pick_option(p, ["Вернуть на руку", "Оставить"], "Храм солнца: вернуть «%s» на руку?" % c.card_name()) == "Вернуть на руку":
		await g.bounce_creature(p, lane)


# Жёлтый маяк
func start_yellow_lighthouse(_c, p, _kind, lane) -> void:
	for s in g.bld_spots(p, lane):
		if creature(s[0], s[1]) != null:
			await g._draw(s[0])


# ---------------------------------------------------------------- creatures

# Чёрный паладин
func atk_black_paladin(_c, _p, _lane) -> int:
	return int(g.turn_value(g.turn_player, "hand_discards"))


func floop_blue_gnome(_c, p, _kind, _lane) -> void:
	await _gnome(p, "swamp")


func floop_fancy_pants_gnome(_c, p, _kind, _lane) -> void:
	await _gnome(p, "corn")


func floop_green_gnome(_c, p, _kind, _lane) -> void:
	await _gnome(p, "plain")


func floop_life_beater_gnome(_c, p, _kind, _lane) -> void:
	await _gnome(p, "sandy")


func floop_yellow_gnome(_c, p, _kind, _lane) -> void:
	await _gnome(p, "cute")


# Синий мерлок
func floop_blue_merlock(_c, p, _kind, _lane) -> void:
	await g._draw(p)
	await g.force_discard(p, 1, "Синий мерлок: сбрось карту")


# Синий огр
func atk_blue_ogre(_c, p, _lane) -> int:
	return int(g.turn_value(p, "drawn"))


# Синий слизень
func enter_blue_slimey(c, p, lane) -> void:
	if not _three_types(p):
		return
	var t = await g.pick_creature(p, g.sides(), "Синий слизень: какое существо из этой зоны вернуть на руку?",
		func(x, s, l): return x != c and g.on_lane(p, lane, s, l))
	if t != null:
		await g.bounce_creature(t["p"], t["lane"])


# Черничный пироклоп
func cost_blueberry_pieclops(_c, p) -> int:
	return -int(g.turn_value(p, "spells"))


# Кактус-громила
func aura_atk_cactus_thug(_src, sp, slane, c, p, lane) -> int:
	return 1 if sp == p and absi(slane - lane) == 1 and g.is_type(c, "corn", p, lane) else 0


# Коровидение
func aura_def_cowsper(_src, sp, slane, c, p, lane) -> int:
	return 1 if sp == p and absi(slane - lane) == 1 and g.is_type(c, "corn", p, lane) else 0


# Капитан Тако
func enter_captain_taco(_c, _p, _lane) -> void:
	for s in g.sides():
		for l in LANES:
			if creature(s, l) != null and g.land_type(s, l) != "corn":
				await hit(s, l, 1, g.opp(s))
	await g._check_state()


# Кукурузная летучая мышь (1 action)
func act_ok_corn_bat(_c, p, _kind, lane) -> bool:
	return not g.creature_opts(p, g.sides(), func(_x, s, l): return g.on_lane(p, lane, s, l)).is_empty()


func act_corn_bat(_c, p, _kind, lane) -> void:
	var n: int = g.unique_land_types(p)
	var t = await g.pick_creature(p, g.sides(), "Кукурузная летучая мышь: %d урона существу в этой зоне" % n,
		func(_x, s, l): return g.on_lane(p, lane, s, l))
	if t != null:
		await hit(t["p"], t["lane"], n, p)


func def_cotton_devil(_c, p, _lane) -> int:
	return g.unique_land_types(p)


func def_little_freezy(_c, p, _lane) -> int:
	return g.unique_land_types(p)


func def_polterclops(_c, p, _lane) -> int:
	return g.unique_land_types(p)


func def_swamp_horn(_c, p, _lane) -> int:
	return g.unique_land_types(p)


# Защитники: +2 when defending against a creature on a land of one type.
func vs_davey_bones(_c, _p, _lane, other, _olane, attacking) -> int:
	return _vs(other, attacking, false, "sandy", 2)


func vs_ghost_hag(_c, _p, _lane, other, _olane, attacking) -> int:
	return _vs(other, attacking, false, "plain", 2)


func vs_ghost_tree(_c, _p, _lane, other, _olane, attacking) -> int:
	return _vs(other, attacking, false, "corn", 2)


func vs_ghost(_c, _p, _lane, other, _olane, attacking) -> int:
	return _vs(other, attacking, false, "swamp", 2)


# Нападающие: +1 when attacking a creature on a land of one type.
func vs_rocktopus(_c, _p, _lane, other, _olane, attacking) -> int:
	return _vs(other, attacking, true, "sandy", 1)


func vs_sea_hag(_c, _p, _lane, other, _olane, attacking) -> int:
	return _vs(other, attacking, true, "swamp", 1)


func vs_timmy_magic_eyes(_c, _p, _lane, other, _olane, attacking) -> int:
	return _vs(other, attacking, true, "plain", 1)


func vs_well_dressed_wolf(_c, _p, _lane, other, _olane, attacking) -> int:
	return _vs(other, attacking, true, "corn", 1)


# Алмазный Дэн: leaving play from a NiceLands land, it goes back to the hand.
func leave_diamond_dan(c, p, lane, _reason, _info) -> void:
	if g.land_type(p, lane) == "cute" and g.where(c.uid)["zone"] == "discard":
		await g.return_to_hand(c)


# Призрак-джинн
func floop_djinni_ghost(_c, p, _kind, _lane) -> void:
	g.add_turn(p, "spell_discount", 2)
	await say("Следующее заклинание игрока %s в этот ход стоит на 2 меньше." % players(p).name)


# Итан Всеогонь
func leave_ethan_allfire(_c, p, _lane, _reason, _info) -> void:
	await g.draw_cards(p, g.corn_count(p))


# Глазастик
func start_eye_guy(_c, p, _kind, _lane) -> void:
	var deck: Array = players(p).deck
	if deck.is_empty():
		return
	var top = deck.back()
	await g.emit_event({"type": "peek", "p": p, "uids": [top.uid]})
	if await g.pick_option(p, ["Оставить сверху", "Под низ колоды"], "Глазастик: сверху «%s»." % top.card_name()) == "Под низ колоды":
		deck.erase(top)
		deck.push_front(top)


# Рыба-рыболов
func enter_fisher_fish(_c, p, lane) -> void:
	if g.land_type(p, lane) == "plain":
		for o in g.foes(p):
			await g.damage_player(o, 2, null, {"kind": "effect", "p": p})


# Призрачный мимимимик
func leave_ghost_chest_burster(_c, p, _lane, _reason, _info) -> void:
	await g.draw_bottom(p)


# Призрачный ниндзя: no spells for that player in their next turn (Game.spell_castable).
func dealt_ghost_ninja(_c, _p, _lane, _amount, target) -> void:
	if target == "player":
		players(int(g.dealt_to["p"])).hero_state["no_spells_at"] = g.turn_number


# Гигантская рука мумии
func floop_giant_mummy_hand(_c, p, _kind, lane) -> void:
	var n := 0
	for a in adj(lane):
		if g.land_type(p, a) == "corn":
			n += 1
	if n <= 0 or not _any(p):
		return
	var t = await g.pick_creature(p, g.sides(), "Гигантская рука мумии: %d урона выбранному существу" % n)
	if t != null:
		await hit(t["p"], t["lane"], n, p)


# Золотой ниндзя
func enter_gold_ninja(_c, p, _lane) -> void:
	var n: int = g.unique_land_types(p)
	var t = await g.pick_creature(p, g.sides(), "Золотой ниндзя: %d урона выбранному существу" % n)
	if t != null:
		await hit(t["p"], t["lane"], n, p)
		await g._check_state()


# Пень с золотым топором
func on_draw_golden_axe_stump(_src, sp, _skind, _slane, p) -> void:
	if g.is_foe(sp, p):
		await g.damage_player(p, 1, null, {"kind": "effect", "p": sp})


# Золотой шакал: FLOOP and discard a SandyLands card.
func _sandy_card(x) -> bool:
	return g.play_land(x) == "sandy"


func floop_ok_golden_jackal(_c, p, _kind, _lane) -> bool:
	return players(p).hand.any(_sandy_card)


func floop_golden_jackal(_c, p, _kind, _lane) -> void:
	if await g.force_discard(p, 1, "Золотой шакал: сбрось песчаную карту", _sandy_card) > 0:
		await hit_foes(p, 1)


# Зелёный огр-тусовщик
func on_leave_green_party_ogre(src, sp, _skind, slane, c, p, _lane, _reason) -> void:
	if p == sp and c != src and src.damage > 0:
		await g.heal_creature(sp, slane, 1)


# Зелёная змейка
func leave_green_snakey(_c, p, lane, _reason, _info) -> void:
	var a: Array = g.across(p, lane)
	if creature(a[0], a[1]) != null:
		await hit(a[0], a[1], 1, p)


# Божья коровка
func start_lady_beetle(_c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, [p], "Божья коровка: вернуть на руку своё существо с 2 или меньше защиты?",
		func(_x, s, l): return g.hp_of(s, l) <= 2, true)
	if t != null:
		await g.bounce_creature(p, t["lane"])


# Лаймовый слизень
func enter_lime_slimey(_c, p, _lane) -> void:
	if _three_types(p):
		await g.draw_cards(p, 2)


# Бревенчатый рыцарь: a building from the hand into play in this lane (no replacing).
func floop_ok_log_knight(_c, p, _kind, lane) -> bool:
	return players(p).buildings[lane] == null and players(p).hand.any(func(x): return x.kind() == "building")


func floop_log_knight(_c, p, _kind, lane) -> void:
	var pool: Array = players(p).hand.filter(func(x): return x.kind() == "building")
	var pick = await g.pick_card(p, pool, "Бревенчатый рыцарь: какое строение ввести в игру?")
	if pick != null and players(p).buildings[lane] == null:
		await g._put_building(p, pick, lane)


# Лейтенант Грибок
func leave_lt_mushroom(_c, p, _lane, _reason, _info) -> void:
	if g.is_foe(p, g.turn_player):
		await g.force_discard(g.turn_player, 3, "Лейтенант Грибок: сбрось 3 карты")


# Оранжевый слизень
func enter_orange_slimey(_c, p, _lane) -> void:
	if _three_types(p):
		var o: int = await g.pick_foe(p, "Оранжевый слизень: какому сопернику 3 урона?")
		if o >= 0:
			await g.damage_player(o, 3, null, {"kind": "effect", "p": p})


# Паладим
func aura_atk_paladim(_src, sp, _slane, c, p, _lane) -> int:
	return 3 if sp == p and c.moved_this_turn else 0


# Огурчик (destroy itself)
func act_ok_pickler(_c, p, _kind, _lane) -> bool:
	return g.creature_count(p) > 1 or not g.creature_opts(p, g.foes(p)).is_empty()


func act_pickler(_c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Огурчик: 3 урона выбранному существу")
	if t != null:
		await hit(t["p"], t["lane"], 3, p)


# Квадурай
func start_quadurai(_c, p, _kind, _lane) -> void:
	for o in g.foes(p):
		if players(o).hand.size() >= 4:
			await g.damage_player(o, 2, null, {"kind": "effect", "p": p})


# Мешок боли
func atk_sack_of_pain(c, _p, _lane) -> int:
	return 6 if c.damage == 6 else 0


# Песчаный шакал
func killed_sand_jackal(_c, p, lane, _victim, _vp, _vlane) -> void:
	if g.land_type(p, lane) == "cute":
		await g.heal_player(p, 3)


# Тлеющий старейшина
func enter_smoldering_elder(_c, p, _lane) -> void:
	for s in g.seats_from(p):
		await g.force_discard(s, 2, "Тлеющий старейшина: %s, сбрось 2 карты" % players(s).name)


# Клубничный слизень
func enter_strawberry_slimey(_c, p, _lane) -> void:
	if _three_types(p):
		for l in LANES:
			if creature(p, l) != null:
				await g.heal_creature(p, l, 4)


# Тинник: name a card, every card with that name leaves the target player's discard pile.
func floop_ok_the_sludger(_c, _p, _kind, _lane) -> bool:
	return g.sides().any(func(s): return not players(s).discard.is_empty())


func floop_the_sludger(_c, p, _kind, _lane) -> void:
	var sides: Array = g.sides().filter(func(s): return not players(s).discard.is_empty())
	var names: Array = sides.map(func(s): return players(s).name)
	var o: int = sides[maxi(names.find(await g.pick_option(p, names, "Тинник: чей сброс?")), 0)] if sides.size() > 1 else sides[0]
	var cards := []
	for x in players(o).discard:
		if not cards.has(x.card_name()):
			cards.append(x.card_name())
	var named = await g.pick_option(p, cards, "Тинник: назови карту")
	for x in players(o).discard.duplicate():
		if x.card_name() == named:
			await g.remove_from_game(x)


# Странствующий волшебник: it and the opposing creature of its lane change sides.
func enter_travelin_wizard(c, p, lane) -> void:
	var a: Array = g.across(p, lane)
	var foe = creature(a[0], a[1])
	if foe == null or creature(p, lane) != c:
		return
	players(p).creatures[lane] = foe
	players(a[0]).creatures[a[1]] = c
	await g.emit_event({"type": "move", "p": p, "uid": foe.uid, "from": a[1], "to": lane})
	await g.emit_event({"type": "move", "p": a[0], "uid": c.uid, "from": lane, "to": a[1]})
	await say("Странствующий волшебник и «%s» меняются сторонами." % foe.card_name())


# Жёлтый слизень
func atk_yellow_slimey(_c, p, _lane) -> int:
	return 3 if _three_types(p) else 0
