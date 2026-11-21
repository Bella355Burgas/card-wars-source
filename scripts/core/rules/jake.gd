extends "res://scripts/core/rules/base.gd"
## Джейк (Кукурузные поля).


func atk_husker_knight(_c, p, _lane) -> int:
	return g.corn_count(p)


func def_husker_knight(_c, p, _lane) -> int:
	return 2 * g.corn_count(p)


func atk_corn_dog(_c, p, _lane) -> int:
	return 1 if g.corn_count(p) <= 3 else 0


func def_corn_dog(_c, p, _lane) -> int:
	return g.corn_count(p)


func def_wall_of_ears(_c, _p, _lane) -> int:
	var n := 0
	for s in g.sides():
		n += g.corn_count(s)
	return n


func atk_corn_lord(c, p, _lane) -> int:
	var n := 0
	for l in LANES:
		var o = creature(p, l)
		if o != null and o != c and g.is_type(o, "corn", p, l):
			n += 1
	return n


func atk_corn_ronin(_c, p, lane) -> int:
	var n := 0
	for a in adj(lane):
		if g.land_type(p, a) == "corn":
			n += 1
	return n


# Фермер-покатун
func leave_travelin_farmer(_c, p, lane, _reason, _info) -> void:
	var o: int = g.across(p, lane)[0]
	var n: int = players(o).hand.size()
	await say("Фермер-покатун уходит: %d урона %s." % [n, players(o).name])
	await g.damage_player(o, n)


# Жнец
## «Перемести выбранное существо из этой зоны в соседнюю пустую зону под твоим контролем»:
## the Reaper itself or a creature across (that one changes hands, original: "target Creature").
func enter_field_reaper(c, p, lane) -> void:
	var lanes := []
	for a in adj(lane):
		if creature(p, a) == null and g._lane_open(a):
			lanes.append(a)
	if lanes.is_empty():
		await say("Жнец: рядом нет пустой зоны.")
		return
	var opts: Array = g.creature_opts(p, g.sides(), func(x, s, l): return g.on_lane(p, lane, s, l) and (s != p or x == c))
	if opts.is_empty():
		return
	# The foe's creature first: taking it is what the card is for.
	opts = opts.filter(func(o): return g.is_foe(p, int(o["p"]))) + opts.filter(func(o): return not g.is_foe(p, int(o["p"])))
	var pick = await g._choose({"kind": "creature", "player": p, "options": opts,
		"prompt": "Жнец: какое существо из этой зоны взять под контроль или передвинуть?"})
	if pick == null:
		return
	var dest: int = await g.pick_lane(p, p, lanes, "Жнец: в какую соседнюю зону?")
	if dest < 0:
		return
	var x = creature(int(pick["p"]), int(pick["lane"]))
	if x == null:
		return
	if int(pick["p"]) == p:
		await g.move_creature(p, int(pick["lane"]), dest)
		return
	# Clarification booklet: it does not ready until the start of your next turn.
	x.exhausted = true
	await g.take_control(int(pick["p"]), int(pick["lane"]), p, dest)
	await g.changed_lanes(x, p, int(pick["lane"]), dest)


# Шаи-Кукуруз
func enter_husker_worm(_c, p, _lane) -> void:
	var pick = await g.pick_land(p, g.land_opts([p], func(s, l): return g.land_type(s, l) == "corn"),
		"Шаи-Кукуруз: переверни своё кукурузное поле")
	if pick != null:
		await g.flip_land(p, pick["lane"], true)


# Легион початочков
func enter_legion_of_earlings(_c, p, lane) -> void:
	var opts: Array = opposite_opts(p, lane)
	if opts.is_empty():
		return
	var pick = await g._choose({"kind": "creature", "player": p, "optional": true, "options": opts,
		"prompt": "Легион початочков: вернуть существо в этой зоне владельцу в руку?"})
	if pick != null:
		await g.bounce_creature(int(pick["p"]), int(pick["lane"]))


# Зернотавр
func enter_cornataur(c, p, lane) -> void:
	var n: int = g.corn_count(p)
	var o: int = g.across(p, lane)[0]
	await say("Зернотавр: %d урона %s." % [n, players(o).name])
	await g.damage_player(o, n, c)


# Призрак полей
func start_field_stalker(_c, p, _kind, _lane) -> void:
	await say("Призрак полей: каждый игрок берёт карту.")
	for s in g.seats_from(p):
		await g._draw(s)


# Тыквустьер
func floop_ok_patchy_pumpkin(_c, p, _kind, _lane) -> bool:
	return g.corn_count(p) > 0 and not g.creature_opts(p, g.sides()).is_empty()


func floop_patchy_pumpkin(_c, p, _kind, _lane) -> void:
	var hit_uids := {}
	var n: int = g.corn_count(p)
	for i in n:
		var pick = await g.pick_creature(p, g.sides(), "Тыквустьер: 1 урон выбранному существу (%d из %d)" % [i + 1, n],
			func(x, _s, _l): return not hit_uids.has(x.uid))
		if pick == null or g.phase == "over":
			break
		hit_uids[creature(pick["p"], pick["lane"]).uid] = true
		await hit(pick["p"], pick["lane"], 1, p)
		await g._check_state()


# Лучник Дэн
func floop_ok_archer_dan(_c, p, _kind, lane) -> bool:
	return g.lane_spots(p, lane).any(func(s): return not g.buildings_at(s[0], s[1]).is_empty())


func floop_archer_dan(_c, p, _kind, lane) -> void:
	var opts := []
	for s in g.lane_spots(p, lane):
		for e in g.buildings_at(s[0], s[1]):
			opts.append({"p": s[0], "lane": s[1], "kind": e[1]})
	var pick = await g._choose({"kind": "building", "player": p, "options": opts,
		"prompt": "Лучник Дэн: выбери строение в этой зоне"})
	if pick != null:
		await g.destroy_building(pick["p"], pick["lane"], pick.get("kind", "building"))


# Бигфут
func floop_ok_big_foot(_c, p, _kind, _lane) -> bool:
	for l in LANES:
		if players(p).lands[l]["flipped"]:
			return true
	return false


func floop_big_foot(_c, p, _kind, _lane) -> void:
	var pick = await g.pick_land(p, g.land_opts([p], func(s, l): return players(s).lands[l]["flipped"]),
		"Бигфут: выбери свою перевёрнутую землю")
	if pick != null:
		await g.flip_land(p, pick["lane"], false)


# Амбар истины
func act_ok_silo_of_truth(_c, p, _kind, _lane) -> bool:
	return g.foes(p).any(func(o): return not players(o).hand.is_empty())


func act_silo_of_truth(_c, p, _kind, _lane) -> void:
	var o: int = await g.pick_foe(p, "Амбар истины: у кого украсть карту?", func(q): return not players(q).hand.is_empty())
	if o < 0:
		return
	var victim = players(o)
	if victim.hand.is_empty():
		return
	var c = victim.hand[g.rng.randi() % victim.hand.size()]
	victim.hand.erase(c)
	await say("Амбар истины: %s крадёт «%s» и разыгрывает бесплатно." % [players(p).name, c.card_name()])
	await g.emit_event({"type": "steal", "p": p, "from": o, "uid": c.uid})
	if not await g.play_free(p, c):
		await g._to_discard(c, "steal")


# Поля кошмара
func spell_field_of_nightmares(c, p) -> void:
	var o: int = await g.pick_foe(p, "Поля кошмара: по чьей руке считать урон?")
	var n: int = players(o).hand.size()
	await say("Поля кошмара: %d урона %s." % [n, players(o).name])
	await g.damage_player(o, n, c)


# Перекрёстное опыление
func spell_cross_pollination(_c, p) -> void:
	g.add_turn(p, "cross_poll")
	var bonus: int = g.unique_land_types(p)
	for l in LANES:
		var t = creature(p, l)
		if t != null and g.is_type(t, "corn", p, l):
			await flash(t, "+%d ATK" % bonus)


# Поднятие целины
func spell_reclaim_landscape(_c, p) -> void:
	var flipped: Array = g.land_opts([p], func(s, l): return players(s).lands[l]["flipped"])
	if not flipped.is_empty():
		var pick = await g.pick_land(p, flipped, "Поднятие целины: перевернуть свою землю лицом вверх?", true)
		if pick != null:
			await g.flip_land(p, pick["lane"], false)
	var builds := []
	var free := []
	for l in LANES:
		if players(p).buildings[l] != null:
			builds.append({"p": p, "lane": l})
		elif not g.is_frozen(p, l):
			free.append(l)
	if builds.is_empty() or free.is_empty():
		return
	var b = await g._choose({"kind": "building", "player": p, "options": builds, "optional": true,
		"prompt": "Поднятие целины: переместить своё строение?"})
	if b == null:
		return
	var dest: int = await g.pick_lane(p, p, free, "Куда переместить строение?", "building")
	if dest >= 0:
		await g.move_building(p, b["lane"], dest)


# Кукурузный скипетр
func playable_corn_scepter(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_corn_scepter(_c, p) -> void:
	var n: int = g.corn_count(p)
	var pick = await g.pick_creature(p, g.sides(), "Кукурузный скипетр: выбери существо (%d урона)" % n)
	if pick != null:
		await hit(pick["p"], pick["lane"], n, p)
