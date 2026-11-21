extends "res://scripts/core/rules/base.gd"
## Лич (Бесполезные болота и Ледяные земли): сброс карт соперниками и лавиногепарды с морозом.


## Opponent o discards a card that fits `pred`, or shows a hand with none.
func _discard_or_show(o: int, pred: Callable, what: String) -> void:
	if players(o).hand.any(pred):
		await g.force_discard(o, 1, "%s: сбрось %s" % [players(o).name, what], pred)
	else:
		await say("%s показывает руку: %s нет." % [players(o).name, what])
		await g.emit_event({"type": "reveal", "p": o, "uids": players(o).hand.map(func(x): return x.uid)})


## The other player answers "may do X to stop it". Returns true when somebody did.
func _stopped_by_discard(p: int, prompt: String) -> bool:
	for o in g.foes(p):
		if players(o).hand.is_empty():
			continue
		if await g.pick_option(o, ["Сбросить карту", "Нет"], prompt) == "Сбросить карту":
			if await g.force_discard(o, 1, "%s: какую карту сбросить?" % players(o).name) > 0:
				return true
	return false


# Лавиногепард Вьюжная Лапа: 2 cards unless another player freezes one of their unfrozen lands.
func enter_blizzardpaw_avalancheetah(_c, p, _lane) -> void:
	for o in g.foes(p):
		var free: Array = g.land_opts([o], func(s, l): return not g.is_frozen(s, l))
		if free.is_empty():
			continue
		if await g.pick_option(o, ["Заморозить свою землю", "Пусть берёт 2 карты"], "Вьюжная Лапа: заморозить свою землю, чтобы %s не взял 2 карты?" % players(p).name) == "Заморозить свою землю":
			var land = await g.pick_land(o, free, "Какую свою землю заморозить?")
			if land != null:
				await g.freeze(land["p"], land["lane"])
				return
	await g.draw_cards(p, 2)


# Лавиногепард Лютый Холод
func dealt_bitterchill_avalancheetah(_c, _p, _lane, _amount, target) -> void:
	if target == "player":
		await _discard_or_show(int(g.dealt_to["p"]), func(x): return x.kind() == "spell", "заклинание")


# Гнилокорень
func dealt_rotroot_rooter(_c, _p, _lane, _amount, target) -> void:
	if target == "player":
		await _discard_or_show(int(g.dealt_to["p"]), func(x): return x.kind() == "creature", "существо")


# Лавиногепард Морозный Венец
func enter_frostcrown_avalancheetah(_c, p, lane) -> void:
	for s in g.lane_spots(p, lane):
		await g.freeze(s[0], s[1])


func leave_frostcrown_avalancheetah(_c, p, _lane, _reason, _info) -> void:
	var opts: Array = g.land_opts([p], func(s, l): return g.is_frozen(s, l))
	if opts.is_empty():
		return
	var land = await g.pick_land(p, opts, "Морозный Венец: снять жетон мороза со своей земли?", true)
	if land != null:
		await g.thaw(land["p"], land["lane"])


# Паутинный луч
func spell_gossamer_beam(_c, p) -> void:
	var o: int = await g.pick_foe(p, "Паутинный луч: какой соперник сбросит карту?")
	if o >= 0:
		await g.force_discard(o, 1, "%s: сбрось карту" % players(o).name)
	var pool: Array = g.discard_pool(p, func(x): return x.kind() == "creature")
	if not pool.is_empty():
		var pick = await g.pick_card(p, pool, "Паутинный луч: вернуть на руку существо из сброса?", true)
		if pick != null:
			await g.return_to_hand(pick)


# Лавиногепард Ледяной Клык
func on_discard_icefang_avalancheetah(_src, sp, _skind, _slane, victim, _card) -> void:
	if victim == sp or players(sp).deck.is_empty():
		return
	if await g.pick_option(sp, ["Взять карту", "Не брать"], "Ледяной Клык: %s сбросил карту. Взять карту?" % players(victim).name) != "Взять карту":
		return
	await say("Ледяной Клык: %s берёт карту." % players(sp).name)
	await g._draw(sp)


# Гряземетатель
func on_discard_filthflinger(src, sp, _skind, _slane, victim, _card) -> void:
	if victim != sp:
		await g.add_atk_tokens(src)


# Утильное болото Скрэппи: the first discard of another player each turn.
func on_discard_scrappys_salvage_bog(src, sp, _skind, slane, victim, _card) -> void:
	if victim == sp or int(src.flags.get("bog_turn", -1)) == g.turn_number:
		return
	src.flags["bog_turn"] = g.turn_number
	var x = creature(sp, slane)
	if x != null:
		await g.add_atk_tokens(x)


# Робомерзость
func leave_robomination(_c, p, _lane, _reason, _info) -> void:
	var o: int = await g.pick_foe(p, "Робомерзость: какой игрок сбросит карту?")
	if o >= 0:
		await g.force_discard(o, 1, "%s: сбрось карту" % players(o).name)


# Щупалозавр: +3 ATK unless another player discards a card.
func start_tentacreeper(c, p, _kind, _lane) -> void:
	if not await _stopped_by_discard(p, "Щупалозавр: сбросить карту, чтобы он не получил +3 к атаке?"):
		await g.buff(c, 3)


# Лавиногепард Зимняя Шкура
func floop_winterhide_avalancheetah(_c, p, _kind, _lane) -> void:
	var n: int = g.frozen_count()
	for s in g.seats_from(p):
		if n > 0:
			await g.draw_cards(s, n)
			await g.force_discard(s, n, "%s: сбрось карту" % players(s).name)
	var opts: Array = g.freeze_opts(g.foes(p))
	if not opts.is_empty():
		var land = await g.pick_land(p, opts, "Зимняя Шкура: какую землю соперника заморозить?")
		if land != null:
			await g.freeze(land["p"], land["lane"])


# Лавиногепард Хладный Коготь
func enter_coldclaw_avalancheetah(_c, p, _lane) -> void:
	var opts: Array = g.freeze_opts(g.foes(p))
	if not opts.is_empty():
		var land = await g.pick_land(p, opts, "Хладный Коготь: какую землю соперника заморозить?")
		if land != null:
			await g.freeze(land["p"], land["lane"])


func on_thaw_coldclaw_avalancheetah(src, sp, _skind, slane, _side, _lane) -> void:
	if src.damage > 0:
		await say("Хладный Коготь: весь урон снят.")
		await g.heal_creature(sp, slane, src.damage)


# Водопад мечей
func spell_waterfall_of_swords(_c, p) -> void:
	for o in g.foes(p):
		for l in LANES:
			if creature(o, l) != null:
				await hit(o, l, g.atk_of(o, l), p)
	await g._check_state()


# Зомби из грязи
func enter_mudpie_zombies(_c, p, _lane) -> void:
	for s in g.seats_from(p):
		await g.force_discard(s, 1, "Зомби из грязи: %s, сбрось карту" % players(s).name)
	for s in g.seats_from(p):
		await g._draw(s)


# Ночная сова
func atk_night_owl(_c, p, _lane) -> int:
	var n := 0
	for s in g.sides():
		if s != p:
			n += players(s).hand.size()
	return -n


# Яминный питон
func _foe_fives(p: int) -> int:
	var n := 0
	for o in g.foes(p):
		n = maxi(n, g.discard_fives(o))
	return n


func atk_pit_python(_c, p, _lane) -> int:
	return 2 * _foe_fives(p)


# Курганный барон
func cost_barrow_baron(_c, p) -> int:
	return -_foe_fives(p)


# Ягнепир, клыкастый пушок
func fought_lambpire_fanged_fluff(c, p, lane) -> void:
	if c.damage > 0:
		await g.heal_creature(p, lane, 1)


# Кенгуру-Пэт
func dealt_kangaroo_pat(_c, p, _lane, _amount, target) -> void:
	if target != "player" or g.creature_count(p) == 0:
		return
	var t = await g.pick_creature(p, [p], "Кенгуру-Пэт: на какое существо положить жетон атаки?")
	if t != null:
		await g.add_atk_tokens(creature(p, t["lane"]))


# Трясинное безумие
func spell_mire_madness(_c, p) -> void:
	var targets := []
	for o in g.foes(p):
		targets.append("Соперник: " + players(o).name)
	var creatures: Array = g.creature_opts(p, g.foes(p))
	if not creatures.is_empty():
		targets.append("Существо соперника")
	var pick = await g.pick_option(p, targets, "Трясинное безумие: кому 4 урона?")
	if pick == "Существо соперника":
		var t = await g.pick_creature(p, g.foes(p), "Трясинное безумие: какому существу 4 урона?")
		if t != null:
			await hit(t["p"], t["lane"], 4, p)
			await g._check_state()
	else:
		for o in g.foes(p):
			if pick == "Соперник: " + players(o).name:
				await g.damage_player(o, 4, null, {"kind": "effect", "p": p})
	var heal := ["Себе 4 жизни"]
	if g.creature_count(p) > 0:
		heal.append("Своему существу")
	if await g.pick_option(p, heal, "Трясинное безумие: кого лечить?") == "Своему существу":
		var f = await g.pick_creature(p, [p], "Трясинное безумие: с какого существа снять до 4 урона?")
		if f != null:
			await g.heal_creature(p, f["lane"], 4)
	else:
		await g.heal_player(p, 4)
	var o2: int = await g.pick_foe(p, "Трясинное безумие: какой соперник сбросит карту?")
	if o2 >= 0:
		await g.force_discard(o2, 1, "%s: сбрось карту" % players(o2).name)
	await g._draw(p)


# Белая мгла
func spell_whiteout(_c, p) -> void:
	for s in g.seats_from(p):
		await g.emit_event({"type": "reveal", "p": s, "uids": players(s).hand.map(func(x): return x.uid)})
		for x in players(s).hand.duplicate():
			if int(x.def()["cost"]) == 1:
				await g.discard_card(s, x)
	for s in g.seats_from(p):
		await g.draw_cards(s, 2)


# Ледниковый дрейф
func playable_glacial_drift(_c, p) -> bool:
	return g.creature_count(p) > 0 and not g.empty_lanes(p).is_empty()


func spell_glacial_drift(_c, p) -> void:
	var t = await g.pick_creature(p, [p], "Ледниковый дрейф: какое своё существо переместить?")
	if t == null:
		return
	var dest: int = await g.pick_lane(p, p, g.empty_lanes(p), "Ледниковый дрейф: в какую пустую зону?")
	if dest < 0:
		return
	await g.move_creature(p, t["lane"], dest)
	var a: Array = g.across(p, dest)
	await g.freeze(a[0], a[1])


# Призрачная сторожка: a creature entering this lane: its controller discards and then draws.
func sees_enter_wraithwood_lodge(_src, sp, _skind, slane, _c, p, lane) -> bool:
	return g.on_lane(sp, slane, p, lane) and not players(p).hand.is_empty()


func on_enter_wraithwood_lodge(_src, _sp, _skind, _slane, _c, p, _lane) -> void:
	if await g.force_discard(p, 1, "Призрачная сторожка: %s, сбрось карту" % players(p).name) > 0:
		await g._draw(p)


# Кафе «Холодный рожок» (thawing its lane costs one more card: Game.thaw_cost)
func enter_cool_cone_cafe(_c, p, lane) -> void:
	var a: Array = g.across(p, lane)
	await g.freeze(a[0], a[1])


# Костёр феникса: a destroyed creature of this lane comes back, the pyre goes.
func on_leave_phoenix_pyre(_src, sp, skind, slane, c, p, lane, reason) -> void:
	if reason != "destroy" or not (g.bld_on_lane(sp, slane, p, lane) or g.bld_own_lane(sp, slane, p, lane, c)) or creature(p, lane) != null:
		return
	if g.where(c.uid)["zone"] != "discard":
		return
	if await g.pick_option(sp, ["Вернуть", "Нет"], "Костёр феникса: уничтожить его и вернуть «%s» в игру?" % c.card_name()) != "Вернуть":
		return
	await g.destroy_building(sp, slane, skind)
	if g.where(c.uid)["zone"] == "discard" and creature(p, lane) == null:
		await say("Костёр феникса: «%s» возвращается." % c.card_name())
		await g._put_creature(p, c, lane)
