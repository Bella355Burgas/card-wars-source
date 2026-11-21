extends "res://scripts/core/rules/base.gd"
## Снежный король (Ледяные земли).


func _lone(p: int, lane: int) -> int:
	return 3 if opposite(p, lane) == null else 0


func atk_abdominal_snowman(_c, p, lane) -> int:
	return _lone(p, lane)


func atk_cold_soldier(_c, p, lane) -> int:
	return _lone(p, lane)


# Императорский пингвин
func aura_atk_emperor_penguin(_src, _sp, _slane, _c, p, lane) -> int:
	return -1 if g.is_frozen(p, lane) else 0


func atk_sprucy_lucy(_c, _p, _lane) -> int:
	return g.frozen_count()


## Frozen lands may be picked too: they get no second token, but freezing still happens.
func _freeze_pick(p: int, prompt: String, pred := Callable(), optional := false):
	var opts: Array = g.freeze_opts(g.sides(), pred)
	var pick = await g.pick_land(p, opts, prompt, optional)
	if pick != null:
		await g.freeze(pick["p"], pick["lane"])
	return pick


# Хаски на Аляске
func floop_ok_boarder_collie(_c, p, _kind, _lane) -> bool:
	return not g.empty_lanes(p).is_empty()


func floop_boarder_collie(c, p, _kind, lane) -> void:
	await relocate(p, lane, "Хаски на Аляске: на какую пустую землю перебежать?")
	var w: Dictionary = g.where(c.uid)
	if w["zone"] == "creature" and _lane_frozen(w["p"], w["lane"]) > 0:
		await g.gain_actions(p, 1)


## Frozen lands on the lane of (p, lane): 0, 1 or 2.
func _lane_frozen(p: int, lane: int) -> int:
	return g.lane_spots(p, lane).filter(func(s): return g.is_frozen(s[0], s[1])).size()


# Морозный дракон
func act_frost_dragon(_c, p, _kind, lane) -> void:
	await _freeze_pick(p, "Морозный дракон: какую землю в этой зоне заморозить?", func(s, l): return g.on_lane(p, lane, s, l))


# Бизнес-центр «Снежный»
func act_ok_snow_business(_c, _p, _kind, _lane) -> bool:
	return true


func act_snow_business(_c, p, _kind, lane) -> void:
	await _freeze_pick(p, "Бизнес-центр «Снежный»: какую землю в этой зоне заморозить?", func(s, l): return g.on_lane(p, lane, s, l))


# Генерал Мороз
func start_icemeister(_c, _p, _kind, _lane) -> void:
	for side in g.sides():
		for l in LANES:
			if creature(side, l) != null and g.is_frozen(side, l):
				await hit(side, l, 1, g.opp(side))
	await g._check_state()


# Отмороженная рыбка
func dealt_frozen_fish(_c, p, lane, _amount, target) -> void:
	if target == "creature":
		await _freeze_pick(p, "Отмороженная рыбка: можешь заморозить землю в этой зоне", func(s, l): return g.on_lane(p, lane, s, l), true)


# Бобзлей
func floop_ok_slay_rider(_c, p, _kind, _lane) -> bool:
	return not g.creature_opts(p, g.sides(), func(_x, s, l): return g.is_frozen(s, l)).is_empty()


func floop_slay_rider(_c, p, _kind, _lane) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Бобзлей: 3 урона существу на замёрзшей земле",
		func(_x, s, l): return g.is_frozen(s, l))
	if pick != null:
		await hit(pick["p"], pick["lane"], 3, p)


# Королень
func floop_reign_deer(_c, p, _kind, _lane) -> void:
	await g.draw_cards(p, g.frozen_count())


# Снежный зайчик (cost: destroy itself)
func act_ok_snow_bunny(_c, _p, _kind, _lane) -> bool:
	return g.total_lands() > 0


func act_snow_bunny(_c, p, _kind, _lane) -> void:
	await _freeze_pick(p, "Снежный зайчик: какую землю заморозить?")


# Снежный ангел
func floop_snow_angel(_c, p, _kind, _lane) -> void:
	var n: int = g.frozen_count()
	for l in LANES:
		await g.heal_creature(p, l, n)


# Хладная псина
func floop_snow_dog(_c, p, _kind, lane) -> void:
	for a in adj(lane):
		if creature(p, a) != null:
			await g.buff(creature(p, a), 2)


# Хрустальный дворец
func on_freeze_crystal_palace(_src, sp, _skind, slane, side, lane) -> void:
	if not g.on_lane(sp, slane, side, lane):
		return
	var pick = await g.pick_creature(sp, g.sides(), "Хрустальный дворец: 2 урона выбранному существу")
	if pick != null:
		await hit(pick["p"], pick["lane"], 2, sp)
		await g._check_state()


# Ледяное касание
func spell_freezing_point(_c, p) -> void:
	var o: int = await g.pick_foe(p, "Ледяное касание: чьи земли заморозить?")
	for l in LANES:
		await g.freeze(o, l)


# УЗИ
func playable_freeze_ray(_c, _p) -> bool:
	return g.total_lands() > 0


func spell_freeze_ray(_c, p) -> void:
	await _freeze_pick(p, "УЗИ: какую землю заморозить?")
	await g._draw(p)


# Лыжню!: two different lands.
func playable_snow_way(_c, _p) -> bool:
	return g.total_lands() >= 2


func spell_snow_way(_c, p) -> void:
	var first = await _freeze_pick(p, "Лыжню!: заморозь землю, 1 из 2")
	if first != null:
		await _freeze_pick(p, "Лыжню!: заморозь землю, 2 из 2",
			func(s, l): return s != int(first["p"]) or l != int(first["lane"]))


# Зимние выкрутасы
func spell_frosty_frolic(_c, p) -> void:
	var o: int = await g.pick_foe(p, "Зимние выкрутасы: кто из соперников сбросит карты?")
	var n: int = g.frozen_count(o)
	await g.force_discard(o, n, "Зимние выкрутасы: %s сбрасывает карту" % players(o).name)


# Холодное сердце
func playable_frozen_heart(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_frozen_heart(_c, p) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Холодное сердце: 1 урон (3, если земля замёрзла)")
	if pick != null:
		await hit(pick["p"], pick["lane"], 3 if g.is_frozen(pick["p"], pick["lane"]) else 1, p)
