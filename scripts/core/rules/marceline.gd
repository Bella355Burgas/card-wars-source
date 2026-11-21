extends "res://scripts/core/rules/base.gd"
## Марселин (Бесплодные болота и Милые земли).


# Мертвополь
func on_discard_funeral_home(_src, sp, _skind, slane, victim, _card) -> void:
	if not g.is_foe(sp, victim):
		return
	for l in bld_targets(sp, slane):
		await g.buff(creature(sp, l), 1)


# Ведьмак
func on_discard_man_witch(_src, sp, _skind, _slane, victim, _card) -> void:
	if g.is_foe(sp, victim):
		await say("Ведьмак: 1 урон игроку %s за сброшенную карту." % players(victim).name)
		await g.damage_player(victim, 1)


# Картонный домик
func cost_cardboard_mansion(_c, p) -> int:
	return -g.discard_fives(p)


func floop_cardboard_mansion(_c, p, _kind, _lane) -> void:
	await g.gain_actions(p, 1)


# Моноциклоп
func start_unicyclops(_c, p, _kind, _lane) -> void:
	await say("Моноциклоп: каждый игрок берёт карту и сбрасывает карту.")
	for side in g.seats_from(p):
		await g._draw(side)
		await g.force_discard(side, 1, "Моноциклоп: %s сбрасывает карту" % players(side).name)


# Мушка-хлопушка
## «Каждый соперник»: both foes in 2 на 2 and на троих.
func floop_fly_swatter(_c, p, _kind, _lane) -> void:
	var zero := func(h): return h.def()["cost"] == 0
	for o in g.foes(p):
		if players(o).out:
			continue
		if players(o).hand.any(zero):
			await g.force_discard(o, 1, "Мушка-хлопушка: %s сбрасывает карту стоимостью 0" % players(o).name, zero)
		else:
			await say("У игрока %s нет карт стоимостью 0, он показывает руку." % players(o).name)
			await g.emit_event({"type": "reveal", "p": o, "uids": players(o).hand.map(func(h): return h.uid)})


# Принцесса и Королева банши: may remove an Ice token from a neighbouring land.
func _unfreeze_adjacent(p: int, lane: int) -> void:
	var opts: Array = g.land_opts(g.sides(),
		func(s, l): return g.is_frozen(s, l) and adj(lane).any(func(a): return g.on_lane(p, a, s, l)))
	var pick = await g.pick_land(p, opts, "Можешь убрать жетон мороза с соседней земли", true)
	if pick != null:
		await g.thaw(pick["p"], pick["lane"])


func enter_ban_she_princess(_c, p, lane) -> void:
	await _unfreeze_adjacent(p, lane)


func enter_ban_she_queen(_c, p, lane) -> void:
	await _unfreeze_adjacent(p, lane)


# Болотный ангел-банши
func act_ok_bog_ban_she_angel(c, p, _kind, lane) -> bool:
	return c.damage > 0 and not g.creature_opts(p, g.sides(), func(x, _s, _l): return x != c).is_empty()


func act_bog_ban_she_angel(c, p, _kind, lane) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Болотный ангел-банши: на кого переложить весь свой урон?",
		func(x, _s, _l): return x != c)
	if pick == null:
		return
	var n: int = c.damage
	await g.heal_creature(p, lane, n, g.MOVED)
	await hit(pick["p"], pick["lane"], n, p)


# Болотный босяк / Жабомба: only when they leave while ready.
func leave_bog_bum(_c, p, _lane, _reason, info) -> void:
	if not info["exhausted"]:
		await say("Болотный босяк уходит подготовленным: каждый соперник сбрасывает случайную карту.")
		for o in g.foes(p):
			if not players(o).out:
				await g.random_discard(o, 1)


func leave_bog_frog_bomb(_c, p, _lane, _reason, info) -> void:
	if not info["exhausted"]:
		await say("Жабомба взрывается: 2 урона каждому существу соперника.")
		await hit_foes(p, 2)


# Доктор Мягкенштейн
func floop_dr_stuffenstein(c, p, _kind, lane) -> void:
	if c.damage >= 5:
		for l in LANES:
			await g.heal_creature(p, l, 2)
		return
	var pick = await g.pick_creature(p, [p], "Доктор Мягкенштейн: восстанови 2 урона соседнему существу",
		func(_x, _s, l): return absi(l - lane) == 1)
	if pick != null:
		await g.heal_creature(p, pick["lane"], 2)


# Хлопкомёт
func floop_cottonpult(c, p, _kind, lane) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Хлопкомёт: 1 урон выбранному существу")
	if pick != null:
		await hit(pick["p"], pick["lane"], 1, p)
	if creature(p, lane) == c and c.damage >= 5:
		await g.heal_creature(p, lane, 1)
		c.exhausted = false
		c.flooped = false
		await g.emit_event({"type": "ready", "p": p, "uid": c.uid})


# Яростные курочки: +1 ATK per damage.
func atk_furious_hen(c, _p, _lane) -> int:
	return c.damage


func atk_furious_rooster(c, _p, _lane) -> int:
	return c.damage


func atk_furious_chick(c, _p, _lane) -> int:
	return c.damage


# Бумажный тигрик
func atk_papercut_tiger(c, _p, _lane) -> int:
	return 5 if c.damage == 5 else 0


# Курвейер
func floop_ok_auto_plucker(_c, p, _kind, lane) -> bool:
	return not bld_targets(p, lane).is_empty()


func floop_auto_plucker(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Курвейер: с каким существом?")
	if l < 0:
		return
	await heal_or_hit(p, p, l, "Курвейер: восстановить или нанести 1 урон своему существу?")
	await g._check_state()


# Гусьляр
func floop_music_mallard(c, p, _kind, _lane) -> void:
	await g.draw_cards(p, 2 if c.damage >= 5 else 1)


# Петушатник
func start_big_hen_house(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Петушатник: какому своему существу нанести урон?")
	if l >= 0:
		var pick = await g.pick_option(p, ["1 урон", "2 урона"], "Петушатник: сколько урона нанести своему существу?")
		await hit(p, l, 2 if pick == "2 урона" else 1, p)
	await g.heal_player(p, 1)


# Кровавая банька
func spell_blood_bath(_c, p) -> void:
	var o: int = await g.pick_foe(p, "Кровавая банька: на кого из соперников?")
	var n: int = await g.force_discard(o, 1, "Кровавая банька: сбрось карту стоимостью 2+ — иначе получишь 5 урона",
		func(h): return h.def()["cost"] >= 2, true)
	if n == 0:
		await say("%s не сбрасывает карту и получает 5 урона." % players(o).name)
		await g.damage_player(o, 5)


# Бомбёжка
func spell_bums_away(_c, p) -> void:
	var o: int = await g.pick_foe(p, "Бомбёжка: на кого из соперников?")
	var n: int = await g.force_discard(o, 1, "Бомбёжка: сбрось карту — иначе 2 урона каждому твоему существу",
		Callable(), true)
	if n == 0:
		await hit_all(o, 2)


# Пентапластырь
func playable_pentaid(_c, p) -> bool:
	return not g.creature_opts(p, [p], func(x, _s, _l): return x.damage >= 5).is_empty()


func spell_pentaid(_c, p) -> void:
	var pick = await g.pick_creature(p, [p], "Пентапластырь: восстанови ровно 5 урона",
		func(x, _s, _l): return x.damage >= 5)
	if pick != null:
		await g.heal_creature(p, pick["lane"], 5)


# Ожерелье чёрной дыры
func playable_black_hole_pendant(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_black_hole_pendant(_c, p) -> void:
	var n := 0
	for o in g.foes(p):
		n = maxi(n, g.unique_land_types(o))
	var pick = await g.pick_creature(p, g.sides(), "Ожерелье чёрной дыры: +%d ATK выбранному существу" % n)
	if pick != null:
		await g.buff(creature(pick["p"], pick["lane"]), n)


# Переливание крови
func playable_blood_transfusion(_c, p) -> bool:
	return g.sides().any(func(s): return not players(s).discard.is_empty()) and not g.creature_opts(p, g.sides()).is_empty()


func spell_blood_transfusion(_c, p) -> void:
	var pool := []
	for s in g.seats_from(p):
		pool += players(s).discard
	var pick = await g.pick_card(p, pool, "Переливание крови: какую карту из сброса удалить из игры?")
	if pick == null:
		return
	var x: int = pick.def()["cost"]
	await g.remove_from_game(pick)
	var t = await g.pick_creature(p, g.sides(), "Переливание крови: восстанови %d урона существу" % x)
	if t != null:
		await g.heal_creature(t["p"], t["lane"], x, p)
