extends "res://scripts/core/rules/base.gd"
## Кейк (Кукурузные поля): buildings and flooped creatures.


# Кровавый замок: enemy creatures on its lane take 1 extra damage.
func aura_dmg_blood_castle(_src, sp, slane, _c, p, lane, _amount, _info) -> int:
	return 1 if g.facing(sp, slane, p, lane) else 0


# Небесная крепость
func aura_def_celestial_fortress(_src, sp, slane, _c, p, lane) -> int:
	return -2 if g.facing(sp, slane, p, lane) else 0


# Хижина из многих лесов
func cost_cabin_of_many_woods(_c, p) -> int:
	return -g.count_flooped(p)


func aura_def_cabin_of_many_woods(_src, sp, slane, _c, p, lane) -> int:
	return 5 if sp == p and slane == lane else 0


# Друид початка / Королева зёрен / Огненная стена-торнадо
func aura_atk_druid_of_the_cob(_src, sp, _slane, c, p, _lane) -> int:
	return 1 if sp == p and c.flooped else 0


func atk_kernel_queen(_c, p, _lane) -> int:
	return g.count_flooped(p)


func atk_tornado_wall_of_fire(c, _p, _lane) -> int:
	return 3 if c.flooped else 0


# Кукурузные чемпион и валькирия
func _built(p: int, lane: int) -> bool:
	return not g.buildings_at(p, lane).is_empty()


func atk_husker_champion(_c, p, lane) -> int:
	return 2 if _built(p, lane) else 0


func def_husker_champion(_c, p, lane) -> int:
	return 2 if _built(p, lane) else 0


func atk_husker_valkyrie(_c, p, lane) -> int:
	return 2 if _built(p, lane) else 0


func def_husker_valkyrie(_c, p, lane) -> int:
	return 2 if _built(p, lane) else 0


# Рука помощи
func floop_ok_helping_hand(_c, p, _kind, _lane) -> bool:
	return not g.discard_pool(p, func(x): return x.kind() == "building").is_empty()


func floop_helping_hand(_c, p, _kind, _lane) -> void:
	var pick = await g.pick_card(p, g.discard_pool(p, func(x): return x.kind() == "building"),
		"Рука помощи: какое строение вернуть в руку?")
	if pick != null:
		await g.return_to_hand(pick)


# Лучница Даника (cost: destroy one of your buildings)
func floop_archer_danica(_c, p, _kind, _lane) -> void:
	await hit_foes(p, 3)


# Кукурузный тамплиер
func floop_ok_corns_templar(c, _p, _kind, _lane) -> bool:
	return c.damage > 0


func floop_corns_templar(_c, p, _kind, lane) -> void:
	await g.heal_creature(p, lane, 1)


# Лесотележка
func floop_ok_lumbercaddy(_c, p, _kind, _lane) -> bool:
	var has_building := false
	var has_free := false
	for l in LANES:
		if players(p).buildings[l] != null:
			has_building = true
		elif not g.is_frozen(p, l):
			has_free = true
	return has_building and has_free


func floop_lumbercaddy(_c, p, _kind, _lane) -> void:
	var opts := []
	for l in LANES:
		for e in g.buildings_at(p, l):
			opts.append({"p": p, "lane": l, "kind": e[1]})
	var pick = await g._choose({"kind": "building", "player": p, "options": opts, "prompt": "Лесотележка: какое строение перенести?"})
	if pick == null:
		return
	var free := []
	for l in LANES:
		if players(p).buildings[l] == null and not g.is_frozen(p, l):
			free.append(l)
	var dest: int = await g.pick_lane(p, p, free, "Куда перенести строение?", "building")
	if dest >= 0:
		await g.move_building(p, pick["lane"], dest, pick.get("kind", "building"))


# Попкорновая бабочка
func floop_popcorn_butterfly(_c, p, _kind, _lane) -> void:
	await g.draw_cards(p, g.building_count(p))


# Мистер Шинковщик
func floop_ok_sharp_guy(_c, p, _kind, lane) -> bool:
	return opposite_open(p, lane)


func floop_sharp_guy(_c, p, _kind, lane) -> void:
	var a: Array = g.across(p, lane)
	await hit(a[0], a[1], 2, p)


# Суровая лесорубка
func enter_tough_lumberjill(c, p, _lane) -> void:
	var n: int = g.building_count(p)
	if n > 0:
		var o: int = await g.foe_to_hit(p, "Суровая лесорубка: какому сопернику %d урона?" % n)
		await say("Суровая лесорубка: %d урона сопернику." % n)
		await g.damage_player(o, n, c)


# Неистовая ярость
func playable_furious_furor(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_furious_furor(_c, p) -> void:
	var n: int = 2 * g.count_flooped(p)
	var pick = await g.pick_creature(p, g.sides(), "Неистовая ярость: +%d ATK выбранному существу" % n)
	if pick != null:
		await g.buff(creature(pick["p"], pick["lane"]), n)


# Урожайная луна
func playable_harvest_moon(_c, p) -> bool:
	if g.discard_pool(p, func(x): return x.kind() == "building").is_empty():
		return false
	for l in LANES:
		if g.building_lane_ok(p, l):
			return true
	return false


func spell_harvest_moon(_c, p) -> void:
	var pick = await g.pick_card(p, g.discard_pool(p, func(x): return x.kind() == "building"),
		"Урожайная луна: какое строение вернуть в игру?")
	if pick != null:
		await g.play_free(p, pick)


# Бревенчатый ритм
func spell_log_rhythm(_c, p) -> void:
	for l in LANES:
		if creature(p, l) != null and _built(p, l):
			await g.buff(creature(p, l), 2)


# Напёрсток пустоты
func spell_void_thimble(_c, p) -> void:
	# «Потеряй 2 жизни»: a loss, not damage (Надувной замок Бонго does not take it).
	await g.lose_hp(p, 2, "Напёрсток пустоты")
	await g.gain_actions(p, 1)


# Вырубка леса (extra cost: floop one of your creatures)
func spell_deforestation(_c, p) -> void:
	var pool := []
	for c in players(p).deck:
		if c.kind() == "building":
			pool.append(c)
	if pool.is_empty():
		await say("В колоде нет строений.")
	else:
		var pick = await g.pick_card(p, pool, "Вырубка леса: какое строение из колоды ввести в игру?")
		if pick != null:
			await g.play_free(p, pick)
	await g.shuffle_deck(p)
