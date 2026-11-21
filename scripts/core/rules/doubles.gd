extends "res://scripts/core/rules/base.gd"
## «Парный турнир» (набор 7): колоды для 2 на 2 и командные карты. Командная карта лежит у
## земель игрока (Game.put_teamwork) и работает на обоих союзников; в игре вдвоём союзника нет.


func _any(p: int) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func _friendly(p: int) -> Array:
	return g.team_of(p)


func _hurt4(c) -> bool:
	return c.damage >= 4


## After it is played, the spell may go to the teammate's hand instead of the discard pile.
func _pass_to_mate(c, p: int) -> void:
	var m: int = g.teammate(p)
	if m < 0:
		return
	if await g.pick_option(p, ["Отдать союзнику", "Нет"], "«%s»: отдать карту союзнику?" % c.card_name()) == "Отдать союзнику":
		c.flags["to_mate"] = m


func _move_to_mate(c) -> void:
	var m := int(c.flags.get("to_mate", -1))
	if m < 0:
		return
	c.flags.erase("to_mate")
	players(c.owner).discard.erase(c)
	players(m).hand.append(c)
	await g.emit_event({"type": "to_hand", "p": m, "uid": c.uid, "from": "discard"})
	await say("«%s» уходит на руку игроку %s." % [c.card_name(), players(m).name])


func _foe_dmg(p: int, n: int, prompt: String) -> void:
	var o: int = await g.pick_foe(p, prompt)
	if o >= 0:
		await g.damage_player(o, n, null, {"kind": "effect", "p": p})


func _heal_or_hit(p: int, side: int, lane: int, n: int, prompt: String) -> void:
	var x = creature(side, lane)
	if x == null:
		return
	var opts := ["Снять %d урона" % n, "Нанести %d урона" % n]
	if await g.pick_option(p, opts, prompt) == "Нанести %d урона" % n:
		await hit(side, lane, n, p)
	else:
		await g.heal_creature(side, lane, n, p)


# ---------------------------------------------------------------- командные карты

# Помощь: a creature of cost 2+ played this turn by the team: the other teammate may draw.
func on_battle_assistance(_src, sp, _skind, _slane, p) -> void:
	if not g.team_of(sp).has(p) or g.teammate(p) < 0:
		return
	var big: bool = g.turn_value(p, "played", []).any(func(id):
		var d: Dictionary = CardDB.get_def(id)
		return d["kind"] == "creature" and int(d["cost"]) >= 2)
	if big:
		var m: int = g.teammate(p)
		if await g.pick_option(m, ["Взять карту", "Нет"], "Помощь: %s, взять карту?" % players(m).name) == "Взять карту":
			await g._draw(m)


# Вклад: 3+ cards drawn this turn: the other teammate may draw.
func on_battle_contribution(_src, sp, _skind, _slane, p) -> void:
	if not g.team_of(sp).has(p) or g.teammate(p) < 0 or int(g.turn_value(p, "drawn")) < 3:
		return
	var m: int = g.teammate(p)
	if await g.pick_option(m, ["Взять карту", "Нет"], "Вклад: %s, взять карту?" % players(m).name) == "Взять карту":
		await g._draw(m)


# Кооперация / Синхронизация: no creature (spell) played this turn: the teammate may play one of cost 1 or less for free.
func _out_of_turn(sp: int, p: int, kind: String, word: String) -> void:
	if p != sp or g.teammate(p) < 0:
		return
	if g.turn_value(p, "played", []).any(func(id): return CardDB.get_def(id)["kind"] == kind):
		return
	var m: int = g.teammate(p)
	var pool: Array = players(m).hand.filter(func(x): return x.kind() == kind and int(x.def()["cost"]) <= 1)
	if pool.is_empty():
		return
	var pick = await g.pick_card(m, pool, "%s: %s, сыграть бесплатно вне очереди?" % [word, players(m).name], true)
	if pick != null:
		await g.play_free(m, pick)


func on_battle_cooperation(_src, sp, _skind, _slane, p) -> void:
	await _out_of_turn(sp, p, "creature", "Кооперация")


func on_battle_synchronization(_src, sp, _skind, _slane, p) -> void:
	await _out_of_turn(sp, p, "spell", "Синхронизация")


# Товарищество: an opposing creature hits your team: 1 damage to the opposing team.
func on_hit_player_camaraderie(_src, sp, _skind, _slane, p, _lane, _c, o, _dealt) -> void:
	if g.team_of(sp).has(o) and g.is_foe(sp, p):
		await g.damage_player(p, 1, null, {"kind": "effect", "p": sp})


# Братство: the first damage to an opponent in the team's fight phase: the other teammate deals 1 to a creature of their lanes.
func on_hit_player_fellowship(_src, sp, _skind, _slane, p, _lane, _c, _o, _dealt) -> void:
	if not g.team_of(sp).has(p) or p != sp or g.teammate(p) < 0 or players(p).turn.get("fellowship", false):
		return
	players(p).turn["fellowship"] = true
	var m: int = g.teammate(p)
	var t = await g.pick_creature(m, g.sides(), "Братство: %s, 1 урон существу в одной из своих зон?" % players(m).name,
		func(_x, s, l): return range(LANES).any(func(ml): return g.on_lane(m, ml, s, l)), true)
	if t != null:
		await hit(t["p"], t["lane"], 1, m)


# Сотрудничество / Общение: the first Rainbow spell of a turn: the other teammate gets a free one (or a copy).
func on_played_collaboration(_src, sp, _skind, _slane, p, c) -> void:
	if p != sp or p != g.turn_player or g.teammate(p) < 0 or c.kind() != "spell" or g.play_land(c) != "rainbow":
		return
	if players(p).turn.get("collab", false):
		return
	players(p).turn["collab"] = true
	var m: int = g.teammate(p)
	var cost: int = c.def()["cost"]
	var pool: Array = players(m).hand.filter(func(x): return x.kind() == "spell" and g.play_land(x) == "rainbow" and int(x.def()["cost"]) == cost)
	if pool.is_empty():
		return
	var pick = await g.pick_card(m, pool, "Сотрудничество: %s, сыграть бесплатно радужное заклинание?" % players(m).name, true)
	if pick != null:
		await g.play_free(m, pick)


func on_played_communication(_src, sp, _skind, _slane, p, c) -> void:
	if p != sp or p != g.turn_player or g.teammate(p) < 0 or c.kind() != "spell" or g.play_land(c) != "rainbow" \
			or int(c.def()["cost"]) != 0 or players(p).turn.get("communication", false):
		return
	players(p).turn["communication"] = true
	var m: int = g.teammate(p)
	if await g.pick_option(m, ["Скопировать", "Нет"], "Общение: %s, скопировать «%s»?" % [players(m).name, c.card_name()]) == "Скопировать":
		await g.run_hook("spell_" + c.id, [c, m])
		await g._check_state()


# Координация (Game._coordinated) and Солидарность (Game.cmd_attack) work in the engine.


# ---------------------------------------------------------------- заклинания

# Выручка
func _owned(p: int) -> Callable:
	return func(x, _s, _l): return x.owner == p


func playable_bail_out(_c, p) -> bool:
	return not g.creature_opts(p, g.sides(), _owned(p)).is_empty()


func spell_bail_out(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Выручка: какое своё существо вернуть на руку и сыграть снова?", _owned(p))
	if t == null:
		return
	var x = creature(t["p"], t["lane"])
	await g.bounce_creature(t["p"], t["lane"])
	if g.where(x.uid)["zone"] == "hand":
		await g.play_free(p, x)


# Тюк спасения (Game._die keeps it in play this fight phase)
func playable_bale_out(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_bale_out(_c, p) -> void:
	var t = await g.pick_creature(p, _friendly(p), "Тюк спасения: какое существо уберечь?")
	if t != null:
		creature(t["p"], t["lane"]).flags["bale_out"] = g.turn_number


# Пляжный взрыв
func spell_beach_blast(c, p) -> void:
	var deck: Array = players(p).deck
	var top := []
	for i in mini(3, deck.size()):
		top.append(deck[deck.size() - 1 - i])
	if not top.is_empty():
		await g.emit_event({"type": "reveal", "p": p, "uids": top.map(func(x): return x.uid)})
		var keep = await g.pick_card(p, top, "Пляжный взрыв: какую карту взять?")
		for x in top:
			deck.erase(x)
			if x == keep:
				players(p).hand.append(x)
				await g.emit_event({"type": "to_hand", "p": p, "uid": x.uid, "from": "deck"})
			else:
				await g._to_discard(x, "deck")
	await _pass_to_mate(c, p)


func discarded_beach_blast(c) -> void:
	await _move_to_mate(c)


# Эскимо-бомба
func _on_frozen() -> Callable:
	return func(_x, s, l): return g.is_frozen(s, l)


func playable_bomb_pop(_c, p) -> bool:
	return not g.creature_opts(p, g.sides(), _on_frozen()).is_empty()


func spell_bomb_pop(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Эскимо-бомба: какое существо на замороженной земле уничтожить?", _on_frozen())
	if t != null:
		await g.destroy_creature(t["p"], t["lane"])


# Клон: the next creature or building is free when a card of that name is in play.
func spell_clone(_c, p) -> void:
	players(p).turn["clone"] = true


# Передача мудрости
func spell_convey_wisdom(_c, p) -> void:
	var sides: Array = g.sides().filter(func(s): return not players(s).deck.is_empty())
	if not sides.is_empty():
		var names: Array = sides.map(func(s): return players(s).name)
		var o: int = sides[maxi(names.find(await g.pick_option(p, names, "Передача мудрости: чью колоду посмотреть?")), 0)]
		var deck: Array = players(o).deck
		var top := []
		for i in mini(4, deck.size()):
			top.append(deck[deck.size() - 1 - i])
		var order := []
		var left := top.duplicate()
		while left.size() > 1:
			var pick = await g.pick_card(p, left, "Передача мудрости: какую карту положить %s?" % ("наверх" if order.is_empty() else "под неё"))
			if pick == null:
				pick = left[0]
			order.append(pick)
			left.erase(pick)
		order.append_array(left)
		for x in top:
			deck.erase(x)
		order.reverse()
		deck.append_array(order)
	await g._draw(p)


# Лужица обнимашек: every creature hits the one across, friendly ones with +1 ATK for this
# damage only (the +1 is gone once the spell is done). It is no fight: no fight phase, no fight hooks.
func spell_cuddle_puddle(_c, p) -> void:
	var hits := []
	for s in g.sides():
		for l in LANES:
			if creature(s, l) != null and opposite(s, l) != null:
				var a: Array = g.across(s, l)
				hits.append([a[0], a[1], g.atk_of(s, l) + (1 if _friendly(p).has(s) else 0), s])
	for h in hits:
		await g.damage_creature(h[0], h[1], h[2], {"kind": "effect", "p": h[3]})
	await g._check_state()


# Дуэт
func spell_duet(_c, p) -> void:
	var a = await g.pick_creature(p, [p], "Дуэт: со своего существа снять 1 урон")
	if a != null:
		await g.heal_creature(p, a["lane"], 1)
	var others: Array = g.sides().filter(func(s): return s != p)
	var b = await g.pick_creature(p, others, "Дуэт: с чужого существа снять 1 урон")
	if b != null:
		await g.heal_creature(b["p"], b["lane"], 1, p)


# Волшебное празднество
func _can_slide(x, s: int, l: int) -> bool:
	return x.owner == s and adj(l).any(func(a): return creature(s, a) == null)


func playable_enchanted_celebration(_c, p) -> bool:
	return not g.creature_opts(p, g.sides(), func(x, s, l): return _can_slide(x, s, l)).is_empty()


func spell_enchanted_celebration(c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Волшебное празднество: какое существо передвинуть?", func(x, s, l): return _can_slide(x, s, l))
	if t != null:
		var s: int = t["p"]
		var dest: int = await g.pick_lane(p, s, adj(t["lane"]).filter(func(a): return creature(s, a) == null), "Волшебное празднество: на какую соседнюю землю?")
		if dest >= 0:
			await g.move_creature(s, t["lane"], dest)
	await _pass_to_mate(c, p)


func discarded_enchanted_celebration(c) -> void:
	await _move_to_mate(c)


# Мегапятюня
func playable_extreme_high_five(_c, p) -> bool:
	return _any(p)


func spell_extreme_high_five(c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Мегапятюня: какое существо?")
	if t != null:
		await _heal_or_hit(p, t["p"], t["lane"], 1, "Мегапятюня: снять или нанести 1 урон?")
	await _pass_to_mate(c, p)


func discarded_extreme_high_five(c) -> void:
	await _move_to_mate(c)


# Семейный сбор
func spell_family_gathering(_c, p) -> void:
	var others: Array = g.sides().filter(func(s): return s != p)
	var names: Array = others.map(func(s): return players(s).name)
	var o: int = others[maxi(names.find(await g.pick_option(p, names, "Семейный сбор: какой игрок?")), 0)]
	var land = await g.pick_land(p, g.land_opts([p], func(s, l): return g.land_type(s, l) != ""), "Семейный сбор: какая твоя земля?")
	if land == null:
		return
	var t: String = g.land_type(p, land["lane"])
	var n := 0
	for l in LANES:
		if creature(o, l) != null and g.is_type(creature(o, l), t, o, l):
			n += 1
	await g.draw_cards(p, n)


# Крепкое рукопожатие
func spell_firm_handshake(_c, p) -> void:
	await g.damage_player(p, 5, null, {"kind": "effect", "p": p})
	await _foe_dmg(p, 5, "Крепкое рукопожатие: какому сопернику 5 урона?")


# Замороженный лимонад
func spell_frozen_lemon_aid(_c, p) -> void:
	# «Со стольких же дружественных существ»: each creature once.
	var n: int = g.frozen_count()
	var done := []
	for i in n:
		var t = await g.pick_creature(p, _friendly(p), "Замороженный лимонад: с какого существа снять 1 урон?",
			func(x, _s, _l): return not done.has(x.uid))
		if t == null:
			return
		done.append(creature(t["p"], t["lane"]).uid)
		await g.heal_creature(t["p"], t["lane"], 1, p)


# Обнимемся!
func playable_hug_it_out(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_hug_it_out(_c, p) -> void:
	var t = await g.pick_creature(p, [p], "Обнимемся!: какое своё существо уничтожить?")
	if t == null:
		return
	var a: Array = g.across(p, t["lane"])
	await g.destroy_creature(p, t["lane"])
	if creature(a[0], a[1]) != null:
		await g.destroy_creature(a[0], a[1])


# Ледяная песнь
func spell_ice_sing(_c, p) -> void:
	for s in g.seats_from(p):
		var opts: Array = g.freeze_opts([s])
		if not opts.is_empty():
			var land = await g.pick_land(p, opts, "Ледяная песнь: какую землю игрока %s заморозить?" % players(s).name)
			if land != null:
				await g.freeze(land["p"], land["lane"])
	await g._draw(p)


# Бесконечный хук
func playable_infinite_haymaker(_c, p) -> bool:
	return _any(p)


func spell_infinite_haymaker(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Бесконечный хук: какое существо уничтожить?")
	if t == null:
		return
	await g.damage_player(p, maxi(g.hp_of(t["p"], t["lane"]), 0), null, {"kind": "effect", "p": p})
	if creature(t["p"], t["lane"]) != null:
		await g.destroy_creature(t["p"], t["lane"])


# Сглаз
func spell_jinx(_c, p) -> void:
	var sides: Array = g.sides().filter(func(s): return not players(s).hand.is_empty())
	if sides.size() < 2:
		return
	# «Выбери двух игроков»: p picks them (with only two to pick from there is nothing to ask).
	# p first and a foe next, so a default answer is the usual pick.
	var order: Array = ([p] if sides.has(p) else []) + sides.filter(func(s): return s != p and g.is_foe(p, s)) 		+ sides.filter(func(s): return s != p and not g.is_foe(p, s))
	var picked := []
	if order.size() == 2:
		picked = order
	else:
		for k in 2:
			var left: Array = order.filter(func(s): return not picked.has(s))
			var names: Array = left.map(func(s): return players(s).name)
			var who = await g.pick_option(p, names, "Сглаз: выбери %s игрока" % ("первого" if k == 0 else "второго"))
			picked.append(left[maxi(names.find(who), 0)])
	var cards := []
	for s in picked:
		var h: Array = players(s).hand
		cards.append(h[g.rng.randi() % h.size()])
	await g.emit_event({"type": "reveal", "p": picked[0], "uids": cards.map(func(x): return x.uid)})
	await say("Сглаз: «%s» и «%s»." % [cards[0].card_name(), cards[1].card_name()])
	if int(cards[0].def()["cost"]) != int(cards[1].def()["cost"]):
		for i in 2:
			await g.discard_card(picked[i], cards[i])


# Одинаковые
func spell_matchy_matchy(c, p) -> void:
	var a = await g.mill(p)
	var b = await g.mill(p)
	if a != null and b != null and int(a.def()["cost"]) == int(b.def()["cost"]):
		var n: int = int(a.def()["cost"]) * 2
		if n > 0:
			await _foe_dmg(p, n, "Одинаковые: какому сопернику %d урона?" % n)
	await _pass_to_mate(c, p)


func discarded_matchy_matchy(c) -> void:
	await _move_to_mate(c)


# Лоскутки: the damage of your creatures is dealt out again.
func spell_patchwork(_c, p) -> void:
	var lanes: Array = g.creature_lanes(p)
	var total := 0
	for l in lanes:
		total += creature(p, l).damage
	if total <= 0 or lanes.size() < 2:
		return
	for l in lanes:
		creature(p, l).damage = 0
	for i in lanes.size():
		var l: int = lanes[i]
		var x = creature(p, l)
		var room: int = g.def_of(p, l)
		var most: int = mini(room, total)
		# What the others can still take: this one must take the rest of it.
		var rest := 0
		for j in range(i + 1, lanes.size()):
			rest += g.def_of(p, lanes[j])
		var least: int = maxi(total - rest, 0)
		var n := most
		if i < lanes.size() - 1 and least < most:
			var opts := []
			for k in range(most, least - 1, -1):
				opts.append(str(k))
			n = int(await g.pick_option(p, opts, "Лоскутки: сколько урона на «%s»? (осталось %d)" % [x.card_name(), total]))
		x.damage = n
		total -= n
		await g.emit_event({"type": "damage", "p": p, "lane": l, "uid": x.uid, "amount": n})
	await g._check_state()


# Перенаправь опасность
func playable_redirect_danger(_c, p) -> bool:
	return not g.creature_opts(p, [p], func(x, _s, l): return x.damage > 0 and opposite(p, l) != null).is_empty()


func spell_redirect_danger(_c, p) -> void:
	var t = await g.pick_creature(p, [p], "Перенаправь опасность: с какого своего существа?", func(x, _s, l): return x.damage > 0 and opposite(p, l) != null)
	if t == null:
		return
	var x = creature(p, t["lane"])
	var n: int = mini(3, x.damage)
	x.damage -= n
	await g.emit_event({"type": "heal", "p": p, "lane": t["lane"], "uid": x.uid, "amount": n})
	var a: Array = g.across(p, t["lane"])
	await g.damage_creature(a[0], a[1], n, {"kind": "effect", "p": p})
	await g._check_state()


# Королевский кутёж (Game.cmd_attack: 2 more damage)
func playable_royal_revelry(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_royal_revelry(c, p) -> void:
	var t = await g.pick_creature(p, [p], "Королевский кутёж: какое своё существо?")
	if t != null:
		creature(p, t["lane"]).flags["revelry"] = g.turn_number
	await _pass_to_mate(c, p)


func discarded_royal_revelry(c) -> void:
	await _move_to_mate(c)


# Обжигающая подача
func playable_scorching_serve(_c, p) -> bool:
	return not g.creature_opts(p, g.foes(p)).is_empty()


func spell_scorching_serve(_c, p) -> void:
	var t = await g.pick_creature(p, g.foes(p), "Обжигающая подача: какое существо соперника уничтожить?")
	if t == null:
		return
	var n: int = creature(t["p"], t["lane"]).def()["cost"]
	await g.destroy_creature(t["p"], t["lane"])
	for o in g.foes(p):
		await g.draw_cards(o, n)


# Залп слаша
func playable_slushie_salvo(_c, _p) -> bool:
	return g.total_lands() > 0


func spell_slushie_salvo(_c, p) -> void:
	var opts: Array = g.freeze_opts(g.sides())
	if not opts.is_empty():
		var land = await g.pick_land(p, opts, "Залп слаша: какую землю заморозить?")
		if land != null:
			await g.freeze(land["p"], land["lane"])
	# Each token moves once, one token per land: a land a token left or came to is done.
	var used := []
	while true:
		var from = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return g.is_frozen(s, l) and not used.has([s, l])), "Залп слаша: переместить жетон мороза? (с какой земли)", true)
		if from == null:
			return
		var to = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return not g.is_frozen(s, l) and not used.has([s, l])), "Залп слаша: на какую землю?", true)
		if to == null:
			return
		used.append([int(from["p"]), int(from["lane"])])
		used.append([int(to["p"]), int(to["lane"])])
		await g.thaw(from["p"], from["lane"])
		await g.freeze(to["p"], to["lane"])


# Посох немощи
func playable_staff_of_frailty(_c, p) -> bool:
	return _any(p)


func spell_staff_of_frailty(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Посох немощи: какому существу оставить 1 защиты?")
	if t == null:
		return
	var n: int = g.hp_of(t["p"], t["lane"]) - 1
	if n > 0:
		await g.damage_creature(t["p"], t["lane"], n, {"kind": "effect", "p": p})


# Объелся
func playable_stuffed(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_stuffed(_c, p) -> void:
	var t = await g.pick_creature(p, [p], "Объелся: какое своё существо?")
	if t == null:
		return
	var x = creature(p, t["lane"])
	await hit(p, t["lane"], g.atk_of(p, t["lane"]), p)
	await g._check_state()
	if creature(p, t["lane"]) == x:
		await g.buff(x, g.atk_of(p, t["lane"]))


# Тандем
func playable_tandem_bike(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_tandem_bike(_c, p) -> void:
	var t = await g.pick_creature(p, [p], "Тандем: какое своё существо вернуть на руку?")
	if t != null:
		await g.bounce_creature(p, t["lane"])
	var others: Array = g.sides().filter(func(s): return s != p and g.creature_count(s) > 0)
	if others.is_empty():
		return
	var names: Array = others.map(func(s): return players(s).name)
	var o: int = others[maxi(names.find(await g.pick_option(p, names, "Тандем: какой игрок вернёт своё существо?")), 0)]
	var u = await g.pick_creature(o, [o], "Тандем: %s, какое своё существо вернуть на руку?" % players(o).name)
	if u != null:
		await g.bounce_creature(o, u["lane"])


# Близняшки
func spell_twinsies(_c, p) -> void:
	if not await g._draw(p):
		return
	var mine = players(p).hand.back()
	await g.emit_event({"type": "reveal", "p": p, "uids": [mine.uid]})
	var others: Array = g.sides().filter(func(s): return s != p and not players(s).deck.is_empty())
	if others.is_empty():
		return
	var names: Array = others.map(func(s): return players(s).name)
	var o: int = others[maxi(names.find(await g.pick_option(p, names, "Близняшки: какой игрок откроет верхнюю карту?")), 0)]
	var top = players(o).deck.back()
	await g.emit_event({"type": "reveal", "p": o, "uids": [top.uid]})
	if int(top.def()["cost"]) == int(mine.def()["cost"]):
		await say("Близняшки: стоимости совпали — %s берёт «%s»." % [players(o).name, top.card_name()])
		await g._draw(o)


# Подмокшие
func spell_water_logged(_c, p) -> void:
	for o in g.foes(p):
		for l in LANES:
			if creature(o, l) != null:
				await g.buff(creature(o, l), -2)


# ---------------------------------------------------------------- строения

# Фонтан в протоке (discard)
func act_ok_bayou_fountain(_c, p, _kind, lane) -> bool:
	return not bld_targets(p, lane).is_empty()


func act_bayou_fountain(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Фонтан в протоке: какое существо получит +1 к атаке?")
	if l >= 0:
		await g.buff(creature(p, l), 1)


# Бомба из бобов: your creature of this lane ends up with exactly 4 damage.
func floop_ok_bean_ball_bomba(_c, p, _kind, lane) -> bool:
	return not bld_targets(p, lane).is_empty()


func floop_bean_ball_bomba(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Бомба из бобов: с каким существом?")
	if l < 0:
		return
	var x = creature(p, l)
	if x.damage > 4:
		await g.heal_creature(p, l, x.damage - 4)
	elif x.damage < 4:
		await hit(p, l, 4 - x.damage, p)
		await g._check_state()


# Болотный дворец
func aura_atk_bog_palace(_src, sp, slane, _c, p, lane) -> int:
	return 3 if sp == p and slane == lane else 0


func start_bog_palace(_c, p, _kind, _lane) -> void:
	await g.force_discard(p, 1, "Болотный дворец: сбрось карту")


# Облачная башня (protection: Game.cloud_hidden)
func floop_ok_cloud_tower(_c, p, _kind, lane) -> bool:
	return creature(p, lane) == null and g.creature_count(p) > 0


func floop_cloud_tower(_c, p, _kind, lane) -> void:
	var t = await g.pick_creature(p, [p], "Облачная башня: какое существо переместить в эту зону?")
	if t != null:
		await g.move_creature(p, t["lane"], lane)


# Остров крабьего черепа (FLOOP and 1 action)
func floop_ok_crab_skull_island(_c, p, _kind, lane) -> bool:
	return creature(p, lane) == null and players(p).deck.any(func(x): return x.kind() == "creature")


func floop_crab_skull_island(_c, p, _kind, lane) -> void:
	var deck: Array = players(p).deck
	var shown := []
	var found = null
	while not deck.is_empty():
		var x = deck.pop_back()
		shown.append(x)
		if x.kind() == "creature":
			found = x
			break
	await g.emit_event({"type": "reveal", "p": p, "uids": shown.map(func(x): return x.uid)})
	for x in shown:
		if x != found:
			deck.append(x)
	await g.shuffle_deck(p)
	if found != null and creature(p, lane) == null:
		await g._put_creature(p, found, lane)


# Купольная твердыня
func aura_def_domed_stronghold(_src, sp, slane, _c, p, lane) -> int:
	return 2 if sp == p and slane == lane else 0


func aura_dmg_domed_stronghold(_src, sp, slane, _c, p, lane, amount, info) -> int:
	if not g.bld_own_lane(sp, slane, p, lane) or not g.is_foe(sp, int(info.get("p", -1))) or info.get("kind", "") == "combat":
		return 0
	if CardDB.has_def(g.cmd_source) and CardDB.get_def(g.cmd_source)["kind"] == "spell":
		return -amount
	return 0


# Сеновал (FLOOP and 1 action): a Кормилец from the discard pile onto your empty land of this lane.
func _feedman(x) -> bool:
	return x.id == "feedman"


func floop_ok_haybarn(_c, p, _kind, lane) -> bool:
	return creature(p, lane) == null and not g.discard_pool(p, _feedman).is_empty()


func floop_haybarn(_c, p, _kind, lane) -> void:
	var pool: Array = g.discard_pool(p, _feedman)
	if not pool.is_empty() and creature(p, lane) == null:
		await g._put_creature(p, pool[0], lane)


func leave_haybarn(_c, p, lane, _reason, _info) -> void:
	var x = creature(p, lane)
	if x != null and _feedman(x):
		await g.destroy_creature(p, lane)


# Гарнизон кожурыцарей
func _corn_count(p: int) -> int:
	var n := 0
	for l in LANES:
		if creature(p, l) != null and g.is_type(creature(p, l), "corn", p, l):
			n += 1
	return n


func aura_atk_husker_garrison(_src, sp, slane, _c, p, lane) -> int:
	return _corn_count(sp) if sp == p and slane == lane else 0


func aura_def_husker_garrison(_src, sp, slane, _c, p, lane) -> int:
	return _corn_count(sp) if sp == p and slane == lane else 0


# Ледяная база (creatures onto its frozen lane: Game.creature_lane_ok)
func enter_ice_base(_c, p, lane) -> void:
	for s in g.lane_spots(p, lane):
		await g.freeze(s[0], s[1])


# Подушечная крепость (FLOOP and 1 action)
func floop_ok_pillow_fortress(_c, p, _kind, lane) -> bool:
	return not bld_targets(p, lane).is_empty()


func floop_pillow_fortress(_c, p, _kind, lane) -> void:
	var first: int = await bld_target(p, lane, "Подушечная крепость: с каким существом?")
	if first < 0:
		return
	var opts := ["Снять 2 урона", "Нанести 2 урона"]
	var pick = await g.pick_option(p, opts, "Подушечная крепость: что сделать с существом этой зоны?")
	var heal: bool = pick == "Снять 2 урона"
	for i in 2:
		var t = {"p": p, "lane": first} if i == 0 else await g.pick_creature(p, _friendly(p), "Подушечная крепость: то же с каким дружественным существом?")
		if t == null or creature(t["p"], t["lane"]) == null:
			continue
		if heal:
			await g.heal_creature(t["p"], t["lane"], 2, p)
		else:
			await hit(t["p"], t["lane"], 2, p)
	await g._check_state()


# Песчаный замок (destroy itself)
func act_ok_sand_castle(_c, p, _kind, lane) -> bool:
	return bld_targets(p, lane).any(func(l): return creature(p, l).owner == p)


func act_sand_castle(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Песчаный замок: какое существо вернуть и сыграть?")
	var x = creature(p, l) if l >= 0 else null
	if x == null:
		return
	await g.bounce_creature(p, l)
	if g.where(x.uid)["zone"] == "hand":
		await g.play_free(p, x)


# Снежный банк: FLOOP and remove a frost token of this lane >>> 3 damage to an opponent.
func floop_ok_snow_bank(_c, p, _kind, lane) -> bool:
	return g.lane_spots(p, lane).any(func(s): return g.is_frozen(s[0], s[1]))


func floop_snow_bank(_c, p, _kind, lane) -> void:
	var land = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return g.on_lane(p, lane, s, l) and g.is_frozen(s, l)), "Снежный банк: с какой земли снять жетон мороза?")
	if land == null:
		return
	await g.thaw(land["p"], land["lane"])
	await _foe_dmg(p, 3, "Снежный банк: какому сопернику 3 урона?")


# ---------------------------------------------------------------- существа

func start_adorabunny(c, p, _kind, _lane) -> void:
	if _hurt4(c):
		await _foe_dmg(p, 3, "Милокрольчик: какому сопернику 3 урона?")


func enter_aeromancer(_c, p, _lane) -> void:
	var sides: Array = g.sides().filter(func(s): return g.creature_count(s) >= 2)
	if sides.is_empty():
		return
	var names: Array = sides.map(func(s): return players(s).name)
	var pick = await g.pick_option(p, names + ["Нет"], "Аэромант: поменять местами существ какого игрока?")
	if pick == "Нет":
		return
	var s: int = sides[maxi(names.find(pick), 0)]
	var a = await g.pick_creature(p, [s], "Аэромант: первое существо")
	if a == null:
		return
	var first: int = a["lane"]
	var b = await g.pick_creature(p, [s], "Аэромант: второе существо", func(_x, _s2, l): return l != first)
	if b != null:
		await g.swap_creatures(s, first, b["lane"])


func on_moved_biomancer(src, sp, _skind, _slane, _c, side, _from, _to) -> void:
	var w: Dictionary = g.where(src.uid)
	if side == sp and src.damage > 0 and w["zone"] == "creature":
		await g.heal_creature(w["p"], w["lane"], 2, sp)


func attack_brigadier_banana_split(_c, p, _lane) -> void:
	var t = await g.pick_creature(p, g.foes(p), "Бригадир Банана-сплит: 2 урона существу соперника на замороженной земле", _on_frozen())
	if t != null:
		await hit(t["p"], t["lane"], 2, p)


func battle_chocolate_tacody(_c, p, _kind, lane) -> void:
	if not g.lane_spots(p, lane).any(func(s): return g.is_frozen(s[0], s[1])):
		return
	var sides: Array = g.sides().filter(func(s): return g.creature_count(s) > 0)
	if sides.is_empty():
		return
	var names: Array = sides.map(func(s): return players(s).name)
	var s: int = sides[maxi(names.find(await g.pick_option(p, names, "Шоколадный ТаКоди: существам какого игрока по 1 урону?")), 0)]
	await hit_all(s, 1)


func moved_chronomancer(_c, p, _from, _to) -> void:
	await g.gain_actions(p, 1)


func atk_cutie_koala(c, _p, _lane) -> int:
	return 2 if _hurt4(c) else 0


func enter_feedman(_c, p, _lane) -> void:
	g.add_turn(p, "creature_discount", 1)


## The first 2 damage a turn from opposing creatures, while it has 4 damage or more: in a fight
## or from a creature's ability (floop, entering play…), not from spells or buildings.
func dmg_in_fluffy_fox(c, p, _lane, amount, info) -> int:
	if not _hurt4(c) or not g.is_foe(p, int(info.get("p", -1))):
		return amount
	var src = info.get("card")
	if src == null:
		src = g.effect_card
	if src == null or src.kind() != "creature":
		return amount
	var key := "fox_%d" % g.turn_number
	var used := int(c.flags.get(key, 0))
	var stop: int = mini(2 - used, amount)
	if stop <= 0:
		return amount
	c.flags[key] = used + stop
	return amount - stop


func on_freeze_four_star_fudge(_src, sp, _skind, _slane, _side, _lane) -> void:
	await g._draw(sp)


func battle_frozen_bananancy(_c, p, _kind, lane) -> void:
	if g.lane_spots(p, lane).any(func(s): return g.is_frozen(s[0], s[1])):
		await _foe_dmg(p, 2, "Замороженная БанаНэнси: какому сопернику 2 урона?")


func floop_fumigator(_c, p, _kind, _lane) -> void:
	await hit_foes(p, 1)


func start_geomancer(_c, p, _kind, lane) -> void:
	if g.empty_lanes(p).is_empty():
		return
	var dest: int = await g.pick_lane(p, p, g.empty_lanes(p), "Геомант: переместиться на пустую землю?", "creature", true)
	if dest >= 0:
		await g.move_creature(p, lane, dest)


func act_ok_granary_weevil(_c, p, _kind, lane) -> bool:
	return opposite_open(p, lane)


func act_granary_weevil(_c, p, _kind, lane) -> void:
	var a: Array = g.across(p, lane)
	var x = creature(a[0], a[1])
	if x == null:
		return
	var nm: String = x.card_name()
	for s in g.sides():
		for l in LANES:
			if creature(s, l) != null and creature(s, l).card_name() == nm:
				await g.destroy_creature(s, l)


func attack_green_zebracorn(_c, p, _lane) -> void:
	await _foe_dmg(p, 1, "Зелёный ЗеброРог: какому сопернику 1 урон?")


func attack_grizzled_zebracorn(_c, p, _lane) -> void:
	await _foe_dmg(p, 2, "Седой ЗеброРог: какому сопернику 2 урона?")


func attack_spiked_zebracorn(_c, p, lane) -> void:
	for a in adj(lane):
		var s: Array = g.across(p, a)
		if creature(s[0], s[1]) != null:
			await hit(s[0], s[1], 1, p)
	await g._check_state()


func attack_shielded_zebracorn(_c, p, lane) -> void:
	var t = await g.pick_creature(p, [p], "Щитоносный ЗеброРог: снять 1 урон с соседнего существа?", func(_x, _s, l): return absi(l - lane) == 1, true)
	if t != null:
		await g.heal_creature(p, t["lane"], 1)


## Reveal cards from the top until a командная карта, play it for free, shuffle the rest back.
func _find_teamwork(p: int, limit: int, discard_rest: bool) -> void:
	var deck: Array = players(p).deck
	var shown := []
	var found = null
	while not deck.is_empty() and shown.size() < limit:
		var x = deck.pop_back()
		shown.append(x)
		if x.kind() == "teamwork":
			found = x
			break
	if shown.is_empty():
		return
	await g.emit_event({"type": "reveal", "p": p, "uids": shown.map(func(x): return x.uid)})
	for x in shown:
		if x == found:
			continue
		if discard_rest:
			await g._to_discard(x, "deck")
		else:
			deck.append(x)
	if not discard_rest:
		await g.shuffle_deck(p)
	if found != null:
		players(p).hand.append(found)
		if not await g.play_free(p, found):
			players(p).hand.erase(found)
			await g._to_discard(found, "deck")


func enter_hydromancer(_c, p, _lane) -> void:
	if players(p).deck.any(func(x): return x.kind() == "teamwork") and await g.pick_option(p, ["Искать", "Нет"], "Гидромант: искать командную карту?") == "Искать":
		await _find_teamwork(p, 999, false)


func floop_investigator(_c, p, _kind, _lane) -> void:
	await _find_teamwork(p, 3, true)


func cost_ice_cream_captain(_c, _p) -> int:
	return -g.sides().filter(func(s): return g.frozen_count(s) > 0).size()


func floop_ice_cream_sammy(_c, p, _kind, _lane) -> void:
	var dest: int = await g.pick_lane(p, p, range(LANES), "Мороженщик Сэмми: в какой зоне заморозить обе земли?")
	if dest >= 0:
		for s in g.lane_spots(p, dest):
			await g.freeze(s[0], s[1])


func enter_instigator(_c, p, lane) -> void:
	var a: Array = g.across(p, lane)
	if creature(a[0], a[1]) != null:
		return
	# Clarification booklet: the creature can come from any opponent.
	var t = await g.pick_creature(p, g.foes(p), "ПровокАтор: какое существо соперника перевести в эту зону?")
	if t == null:
		return
	if int(t["p"]) == a[0]:
		await g.move_creature(a[0], t["lane"], a[1])
	else:
		await g.take_control(t["p"], t["lane"], a[0], a[1])


func atk_irrigator(_c, p, lane) -> int:
	return 2 if g.land_type(p, lane) == "ice" else 0


func floop_king_baby(_c, p, _kind, _lane) -> void:
	var n: int = g.corn_count(p)
	var t = await g.pick_creature(p, g.sides(), "Король-младенец: %d урона выбранному существу" % n)
	if t != null and n > 0:
		await hit(t["p"], t["lane"], n, p)


func sees_enter_lifeguard_lobster(src, sp, _skind, _slane, c, _p, _lane) -> bool:
	return c != src and sp == g.turn_player


func on_enter_lifeguard_lobster(src, sp, _skind, _slane, _c, _p, _lane) -> void:
	var t = await g.pick_creature(sp, g.sides(), "Омар-спасатель: с какого другого существа снять 1 урон?", func(x, _s, _l): return x != src)
	if t != null:
		await g.heal_creature(t["p"], t["lane"], 1, sp)


func atk_longboard_lobster(_c, _p, _lane) -> int:
	var n := 0
	for s in g.sides():
		for l in LANES:
			if g.land_type(s, l) == "swamp":
				n += 1
	return n


func start_loveable_lamb(c, p, _kind, lane) -> void:
	if _hurt4(c) and opposite_open(p, lane):
		var a: Array = g.across(p, lane)
		await hit(a[0], a[1], 2, p)


func dmg_in_mint_chocouflage(_c, p, lane, amount, info) -> int:
	if opposite(p, lane) == null and info.get("kind", "") != "combat" and g.is_foe(p, int(info.get("p", -1))):
		return 0
	return amount


func floop_mocha_launcher(_c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Мокко-пушка: 2 урона выбранному существу")
	if t == null:
		return
	var x = creature(t["p"], t["lane"])
	await hit(t["p"], t["lane"], 2, p)
	await g._check_state()
	if g.where(x.uid)["zone"] != "creature":
		await g.freeze(t["p"], t["lane"])


# НавиГатор: discard a card >>> + its cost, once a turn.
func act_ok_navigator(_c, p, _kind, _lane) -> bool:
	return not players(p).hand.is_empty()


func act_navigator(c, p, _kind, _lane) -> void:
	var pick = await g.pick_card(p, players(p).hand, "НавиГатор: какую карту сбросить?")
	if pick == null:
		return
	await g.discard_card(p, pick)
	await g.buff(c, int(pick.def()["cost"]))


func on_leave_necromancer(src, sp, _skind, slane, c, p, lane, _reason) -> void:
	if p != sp or c == src or creature(sp, lane) != null:
		return
	if await g.pick_option(sp, ["Переместить", "Нет"], "Некромант: перейти на опустевшую землю?") == "Переместить":
		await g.move_creature(sp, slane, lane)


# Заштопанный щенок: 3 damage to itself >>> +2 ATK.
func act_patched_puppy(c, p, _kind, lane) -> void:
	await hit(p, lane, 3, p)
	await g._check_state()
	if creature(p, lane) == c:
		await g.buff(c, 2)


func enter_patriot_popsicle(_c, p, lane) -> void:
	var opts: Array = g.freeze_opts(g.sides(), func(s, l): return g.on_lane(p, lane, s, l))
	if opts.is_empty():
		return
	var land = await g.pick_land(p, opts, "Эскимо-патриот: заморозить землю в этой зоне?", true)
	if land != null:
		await g.freeze(land["p"], land["lane"])


# Пиромант
func _pyro_hit(p: int, lane: int) -> void:
	var t = await g.pick_creature(p, g.sides(), "Пиромант: 2 урона существу в этой зоне?", func(_x, s, l): return g.on_lane(p, lane, s, l) and not (s == p and l == lane), true)
	if t != null:
		await hit(t["p"], t["lane"], 2, p)
		await g._check_state()


func enter_pyromancer(_c, p, lane) -> void:
	await _pyro_hit(p, lane)


func moved_pyromancer(_c, p, _from, to) -> void:
	await _pyro_hit(p, to)


func act_ok_pyromancer(_c, p, _kind, _lane) -> bool:
	return not g.empty_lanes(p).is_empty()


func act_pyromancer(_c, p, _kind, lane) -> void:
	var dest: int = await g.pick_lane(p, p, g.empty_lanes(p), "Пиромант: на какую пустую землю?")
	if dest >= 0:
		await g.move_creature(p, lane, dest)


func hurt_repelling_rock_crab(_c, p, _lane, amount, by) -> void:
	var w: Dictionary = g.where(by.uid)
	if w["zone"] == "creature":
		await g.damage_creature(w["p"], w["lane"], amount, {"kind": "effect", "p": p})
		await g._check_state()


func atk_robomancer(_c, p, _lane) -> int:
	return int(g.turn_value(p, "moves")) if g.turn_player == p else 0


func hurt_routing_rock_crab(_c, p, _lane, _amount, by) -> void:
	var w: Dictionary = g.where(by.uid)
	if w["zone"] != "creature":
		return
	var s: int = w["p"]
	var free: Array = adj(w["lane"]).filter(func(a): return creature(s, a) == null)
	if free.is_empty():
		return
	var dest: int = await g.pick_lane(p, s, free, "Сбивающий скальный краб: передвинуть обидчика?", "creature", true)
	if dest >= 0:
		await g.move_creature(s, w["lane"], dest)


func enter_sailing_sand_crab(_c, p, _lane) -> void:
	var pool: Array = players(p).hand.filter(func(x): return x.kind() == "creature" and int(x.def()["cost"]) == 1)
	if pool.is_empty():
		return
	var pick = await g.pick_card(p, pool, "Песчаный краб-мореход: сыграть бесплатно существо стоимостью 1?", true)
	if pick != null:
		await g.play_free(p, pick)


func aura_atk_sewn_sloth(src, sp, slane, _c, p, lane) -> int:
	if sp != p or absi(slane - lane) != 1:
		return 0
	return 2 if _hurt4(src) else 1


func sees_enter_shifty_sand_crab(src, sp, _skind, _slane, c, p, _lane) -> bool:
	return c != src and p == sp and sp == g.turn_player


func on_enter_shifty_sand_crab(_src, sp, _skind, slane, c, _p, lane) -> void:
	if await g.pick_option(sp, ["Поменяться", "Нет"], "Юркий песчаный краб: поменяться местами с «%s»?" % c.card_name()) == "Поменяться":
		await g.swap_creatures(sp, slane, lane)


func sees_enter_slashy_sand_crab(src, sp, _skind, slane, c, p, lane) -> bool:
	return c != src and p == sp and absi(lane - slane) == 1 and sp == g.turn_player and opposite_open(sp, slane)


func on_enter_slashy_sand_crab(_src, sp, _skind, slane, _c, _p, _lane) -> void:
	if opposite_open(sp, slane):
		var a: Array = g.across(sp, slane)
		await hit(a[0], a[1], 2, sp)


func floop_ok_smooth_eli(_c, _p, _kind, _lane) -> bool:
	return g.frozen_count() > 0


func floop_smooth_eli(_c, p, _kind, _lane) -> void:
	var from = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return g.is_frozen(s, l)), "Гладкий Илай: какой жетон мороза переместить?")
	if from == null:
		return
	var to = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return not g.is_frozen(s, l)), "Гладкий Илай: на какую землю?")
	if to == null:
		return
	await g.thaw(from["p"], from["lane"])
	await g.freeze(to["p"], to["lane"])


func enter_softie_recruit(_c, p, lane) -> void:
	if opposite(p, lane) == null:
		await g.gain_actions(p, 1)


func start_stitched_squirrel(c, p, _kind, lane) -> void:
	if not _hurt4(c):
		return
	var a: Array = g.across(p, lane)
	if players(a[0]).buildings[a[1]] != null:
		await g.destroy_building(a[0], a[1])


func aura_def_subjugator(_src, sp, slane, _c, p, lane) -> int:
	return -g.discard_fives(sp) if g.facing(sp, slane, p, lane) else 0


func enter_tailgator(_c, p, _lane) -> void:
	await g.draw_cards(p, int(g.turn_value(p, "creatures_discarded")))


func _barrels(c) -> int:
	var n := 0
	for s in g.sides():
		for l in LANES:
			var x = creature(s, l)
			if x != null and x != c and x.id == "the_barrel":
				n += 1
	return n


func atk_the_barrel(c, _p, _lane) -> int:
	return _barrels(c)


func def_the_barrel(c, _p, _lane) -> int:
	return _barrels(c)


func _team_teamwork(p: int) -> Array:
	var out := []
	for s in g.team_of(p):
		if players(s).teamwork != null:
			out.append(players(s).teamwork)
	return out


func floop_the_cooper(_c, p, _kind, _lane) -> void:
	var n := 0
	for x in _team_teamwork(p):
		n += int(x.def()["cost"])
	var t = await g.pick_creature(p, g.sides(), "Бондарь: какому существу +%d к атаке?" % n)
	if t != null and n > 0:
		await g.buff(creature(t["p"], t["lane"]), n)


func atk_trained_zebracorn_husker(_c, p, _lane) -> int:
	return _team_teamwork(p).size()


func leave_trained_zebracorn_husker(c, p, _lane, _reason, _info) -> void:
	if g.phase == "attack" and g.turn_player == p and g.where(c.uid)["zone"] == "discard" \
			and await g.pick_option(p, ["Взять на руку", "Нет"], "Обученный кожурыцарь-зебророг: взять его на руку?") == "Взять на руку":
		await g.return_to_hand(c)


func leave_young_zebracorn_husker(c, p, _lane, _reason, _info) -> void:
	if g.phase == "attack" and g.turn_player == p and g.where(c.uid)["zone"] == "discard" \
			and await g.pick_option(p, ["Наверх колоды", "Нет"], "Юный кожурыцарь-зебророг: положить его на верх колоды?") == "Наверх колоды":
		players(c.owner).discard.erase(c)
		players(c.owner).deck.append(c)
		await g.emit_event({"type": "to_deck", "p": c.owner, "uid": c.uid})


func floop_ok_ultra_dog(_c, p, _kind, _lane) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func floop_ultra_dog(_c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Ультрапёс: землю какого существа заморозить?")
	if t != null:
		await g.freeze(t["p"], t["lane"])
