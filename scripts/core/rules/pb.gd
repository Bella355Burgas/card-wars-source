extends "res://scripts/core/rules/base.gd"
## Принцесса Бубльгум (Милые земли).


func _exact(c, n: int, bonus: int) -> int:
	return bonus if c.damage == n else 0


func atk_albino_eyebat(c, _p, _lane) -> int:
	return _exact(c, 2, 2)


func atk_cotton_eyebat(c, _p, _lane) -> int:
	return _exact(c, 4, 4)


func atk_ms_fluff(c, _p, _lane) -> int:
	return _exact(c, 7, 7)


func atk_angel_heart(c, _p, _lane) -> int:
	return _exact(c, 3, 3)


func atk_wall_of_chocolate(c, _p, _lane) -> int:
	return 3 if c.damage == 0 else 0


# Мельница процветания
func aura_atk_windmill_of_health(_src, sp, slane, c, p, lane) -> int:
	return 2 if sp == p and slane == lane and c.damage == 0 else 0


# Фей-чабан
func aura_def_fairy_shepard(_src, sp, slane, c, p, lane) -> int:
	return 2 if sp == p and absi(slane - lane) == 1 and g.is_type(c, "cute", p, lane) else 0


# Пещера одиночества
func act_ok_cave_of_solitude(_c, p, _kind, lane) -> bool:
	return not bld_targets(p, lane).is_empty()


func act_cave_of_solitude(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Пещера одиночества: какое существо спрятать?")
	var t = creature(p, l) if l >= 0 else null
	if t == null:
		return
	t.flags["shield_until"] = p
	await say("«%s» прячется в Пещере одиночества до начала следующего хода." % t.card_name())
	await flash(t, "Укрыто!")


# Радужный крылоглаз
func start_rainbow_eyebat(_c, p, _kind, _lane) -> void:
	await g.heal_player(p, g.unique_land_types(p))


# Пироклоп
func enter_pieclops(_c, p, lane) -> void:
	for a in adj(lane):
		await g.heal_creature(p, a, 1)


# Доброзавр Рекс
func start_niceasaurus_rex(c, p, _kind, _lane) -> void:
	if c.damage > 0:
		await say("Доброзавр Рекс ранен: %s берёт карту." % players(p).name)
		await g._draw(p)


# Милашка
func floop_cutie(_c, p, _kind, _lane) -> void:
	await g.heal_player(p, 1)


# Мятнозмей
func dealt_snakemint(_c, p, _lane, amount, target) -> void:
	if target == "player":
		await g.heal_player(p, amount)


# Шоколадный и Ванильный ангелы
func act_ok_angel_of_chocolate(c, _p, _kind, _lane) -> bool:
	return c.damage > 0


func act_angel_of_chocolate(c, p, _kind, lane) -> void:
	await g.heal_creature(p, lane, c.damage)


func act_ok_angel_of_vanilla(c, _p, _kind, _lane) -> bool:
	return c.damage > 0


func act_angel_of_vanilla(c, p, _kind, lane) -> void:
	await g.heal_creature(p, lane, c.damage)


# Яблочный пироклоп
func start_apple_pieclops(_c, p, _kind, _lane) -> void:
	for l in LANES:
		var t = creature(p, l)
		if t != null:
			await heal_or_hit(p, p, l, "Яблочный пироклоп: «%s» — восстановить или нанести 1 урон?" % t.card_name())
	await g._check_state()


# Пиропад
func spell_piestorm(_c, p) -> void:
	for l in LANES:
		var t = creature(p, l)
		if t != null and t.damage == 0:
			await g.buff(t, 2)


# Падающая звезда
func spell_falling_star(_c, p) -> void:
	players(p).turn["falling_star"] = true
	await say("В этом ходу существа игрока %s не получают урон от существ соперника." % players(p).name)


# Синяя сахарная вата
func playable_blue_candy(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_blue_candy(_c, p) -> void:
	var pick = await g.pick_creature(p, [p], "Синяя сахарная вата: восстанови до 3 урона")
	if pick != null:
		await g.heal_creature(p, pick["lane"], 3)


# Кольцо пушистости
func playable_ring_of_fluffy(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_ring_of_fluffy(_c, p) -> void:
	var pick = await g.pick_creature(p, [p], "Кольцо пушистости: +ATK, равный урону на существе")
	if pick != null:
		var t = creature(p, pick["lane"])
		await g.buff(t, t.damage)


# Зелёная сахарная вата
func playable_green_candy(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_green_candy(_c, p) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Зелёная сахарная вата: выбери существо")
	if pick != null:
		await heal_or_hit(p, pick["p"], pick["lane"], "Восстановить или нанести 1 урон?")
