extends "res://scripts/core/rules/base.gd"
## Гантер (Ледяные земли и Синие равнины).


func _freeze_lane(p: int, lane: int) -> void:
	for s in g.lane_spots(p, lane):
		await g.freeze(s[0], s[1])


## Frozen lands may be picked too: they get no second token, but freezing still happens.
func _pick_freeze(p: int, prompt: String, pred := Callable()) -> void:
	var opts: Array = g.freeze_opts(g.sides(), pred)
	var pick = await g.pick_land(p, opts, prompt)
	if pick != null:
		await g.freeze(pick["p"], pick["lane"])


# Ледяной лазутчик
func enter_icy_infiltrator(_c, p, lane) -> void:
	await g.freeze(p, lane)


# Плавучий ледяной дворец
func aura_atk_floating_ice_palace(_src, sp, slane, _c, p, lane) -> int:
	return g.frozen_count() if sp == p and slane == lane and p == g.turn_player else 0


# Измождённый клирик / Усталый вомбат / Синюшный заводила: wander every turn.
func start_drained_cleric(c, p, _kind, lane) -> void:
	if not await relocate(p, lane, "Измождённый клирик: на какую пустую землю перейти?"):
		await say("Тонущему клирику некуда идти — %s сбрасывает карту." % players(p).name)
		await g.force_discard(p, 1, "Измождённый клирик: сбрось карту")


func start_tired_wombat(c, p, _kind, lane) -> void:
	if await relocate(p, lane, "Усталый вомбат: на какую пустую землю перейти?"):
		return
	var spots := []
	for o in g.foes(p):
		for l in g.empty_lanes(o):
			spots.append({"p": o, "lane": l})
	if spots.is_empty():
		return
	var dest = await g.pick_spot(p, spots, "Усталому вомбату некуда идти — на какую пустую землю соперника он уйдёт?")
	if dest != null:
		await g.take_control(p, lane, int(dest["p"]), int(dest["lane"]))


func start_woadic_ring_leader(_c, p, _kind, lane) -> void:
	if not await relocate(p, lane, "Синюшный заводила: на какую пустую землю перейти?"):
		await say("Предводителю Вайда некуда идти — он уничтожен.")
		await g.destroy_creature(p, lane)


# Морозная снеговичка
func enter_frosted_snowwoman(_c, p, lane) -> void:
	await _freeze_lane(p, lane)


# Ледниковый гонщик
func atk_glacier_racer(_c, p, lane) -> int:
	return 4 if g.lane_spots(p, lane).all(func(s): return g.is_frozen(s[0], s[1])) else 0


# Ледяной коммандос
func atk_icy_commando(_c, _p, _lane) -> int:
	return g.frozen_count()


# Ледяной нарушитель (cost: 1 action)
func floop_ok_icy_intruder(_c, _p, _kind, _lane) -> bool:
	return g.total_lands() > 0


func floop_icy_intruder(_c, p, _kind, _lane) -> void:
	await _pick_freeze(p, "Ледяной нарушитель: какую землю заморозить?")


# Снежкометатель (cost: remove the Ice token from its own land)
func act_ok_snow_baller(_c, p, _kind, _lane) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func act_snow_baller(_c, p, _kind, _lane) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Снежкометатель: 3 урона выбранному существу")
	if pick != null:
		await hit(pick["p"], pick["lane"], 3, p)


# Холодильник
func leave_the_cooler(_c, p, lane, _reason, _info) -> void:
	await g.freeze(p, lane)


# Шикарный спа-салон
func battle_fancy_spa(_c, p, _kind, lane) -> void:
	var t = null
	for l in bld_targets(p, lane):
		if creature(p, l).exhausted:
			t = creature(p, l)
			break
	if t != null:
		await say("Шикарный спа-салон: %s берёт карту." % players(p).name)
		await g._draw(p)


# Усталые библиотекарь и воин: ready again whenever they change lanes.
func _wake(c, p: int) -> void:
	if c.exhausted:
		c.exhausted = false
		c.flooped = false
		await g.emit_event({"type": "ready", "p": p, "uid": c.uid})


func moved_fatigued_librarian(c, p, _from, _to) -> void:
	await _wake(c, p)


func moved_weakened_warrior(c, p, _from, _to) -> void:
	await _wake(c, p)


# Промышленный убийца (cost: destroy one of your creatures)
func floop_industrial_assassin(_c, p, _kind, _lane) -> void:
	await g._draw(p)


# Унылая фактория
func floop_ok_weary_trading_post(_c, p, _kind, lane) -> bool:
	if creature(p, lane) != null:
		return false
	for l in LANES:
		var t = creature(p, l)
		if t != null and t.exhausted:
			return true
	return false


func floop_weary_trading_post(_c, p, _kind, lane) -> void:
	var pick = await g.pick_creature(p, [p], "Унылая фактория: какое неактивное существо перевести сюда?",
		func(x, _s, _l): return x.exhausted)
	if pick != null:
		await g.move_creature(p, pick["lane"], lane)


# Снежный тренировочный лагерь
func floop_ok_snow_training_camp(_c, _p, _kind, _lane) -> bool:
	return g.frozen_count() == 0


func floop_snow_training_camp(_c, p, _kind, lane) -> void:
	await _freeze_lane(p, lane)


# Шипучая кола
func spell_spazzy_cola(_c, _p) -> void:
	for side in g.sides():
		for l in LANES:
			if creature(side, l) != null:
				await g.buff(creature(side, l), 1)


# Передоз милоты
func playable_cute_overload(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_cute_overload(_c, p) -> void:
	var n := 0
	while g.creature_count(p) > 0 and g.phase != "over":
		var pick = await g.pick_creature(p, [p], "Передоз милоты: уничтожить ещё существо? (уничтожено: %d)" % n,
			Callable(), true)
		if pick == null:
			break
		await g.destroy_creature(p, pick["lane"])
		n += 1
	await g.draw_cards(p, n)


# Снеголавина
func spell_snowvalanche(_c, p) -> void:
	await hit_foes(p, 2, func(_x, s, l): return g.is_frozen(s, l))


# Снегомёт
func spell_snowblower(_c, p) -> void:
	var opts := []
	for l in LANES:
		opts.append({"p": p, "lane": l, "row": "creature"})
	var pick = await g._choose({"kind": "lane", "player": p, "options": opts, "prompt": "Снегомёт: выбери линию — обе её земли замёрзнут"})
	if pick != null:
		await _freeze_lane(p, pick["lane"])


# Подъём!
func spell_wake_up_call(_c, p) -> void:
	for l in LANES:
		var t = creature(p, l)
		if t != null and t.exhausted:
			t.exhausted = false
			t.flooped = false
			await g.emit_event({"type": "ready", "p": p, "uid": t.uid})


# Магопохищение
func playable_magenapping(_c, p) -> bool:
	return g.creature_count(p) <= 1 and players(p).hp <= 15 and not g.empty_lanes(p).is_empty() and not g.creature_opts(p, g.sides()).is_empty()


func spell_magenapping(_c, p) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Магопохищение: какое существо переместить?")
	if pick == null:
		return
	var dest: int = await g.pick_lane(p, p, g.empty_lanes(p), "Магопохищение: на какую свою пустую землю его поставить?")
	if dest < 0:
		return
	if int(pick["p"]) == p:
		await g.move_creature(p, pick["lane"], dest)
	else:
		await g.take_control(pick["p"], pick["lane"], p, dest)


# Выдохся
func playable_tapped_out(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_tapped_out(_c, p) -> void:
	var n: int = g.count_exhausted(p)
	var pick = await g.pick_creature(p, [p], "Выдохся: +%d ATK своему существу" % (2 * n))
	if pick != null:
		await g.buff(creature(p, pick["lane"]), 2 * n)
