extends "res://scripts/core/rules/base.gd"
## Волшебник (Песчаные и Добрые земли): заклинания, «Зелья» и заклинания в сбросе.


func _spells_in_discard(p: int) -> int:
	return players(p).discard.filter(func(x): return x.kind() == "spell").size()


func _any(p: int) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


## A creature or a player as a target: {"p", "lane"} (lane -1: the player itself).
func _creature_or_player(p: int, sides: Array, prompt: String, creature_sides: Array = []) -> Dictionary:
	if creature_sides.is_empty():
		creature_sides = sides
	var names := []
	var spots := []
	for s in sides:
		names.append("Игрок: " + players(s).name)
		spots.append({"p": s, "lane": -1})
	if not g.creature_opts(p, creature_sides).is_empty():
		names.append("Существо")
		spots.append({})
	var pick = await g.pick_option(p, names, prompt)
	var i: int = maxi(names.find(pick), 0)
	if not spots[i].is_empty():
		return spots[i]
	var t = await g.pick_creature(p, creature_sides, prompt)
	return {} if t == null else {"p": int(t["p"]), "lane": int(t["lane"])}


## Who heals: p's own side by default (a target player may be anybody).
func _heal_target(p: int, prompt: String) -> int:
	var names: Array = g.sides().map(func(s): return players(s).name)
	return g.sides()[maxi(names.find(await g.pick_option(p, names, prompt)), 0)]


# Водоворот клинков: every token that is not damage goes, 2 damage per token to one creature.
func playable_bladespire_maelstrom(_c, p) -> bool:
	return _any(p)


func spell_bladespire_maelstrom(_c, p) -> void:
	var n := 0
	for s in g.sides():
		for l in LANES:
			var x = creature(s, l)
			if x != null:
				for k in g.TOKEN_KINDS:
					n += await g.remove_token(x, k, 99)
			if g.is_frozen(s, l):
				n += 1
				await g.thaw(s, l)
		n += players(s).burn
		players(s).burn = 0
	await say("Водоворот клинков: убрано жетонов — %d." % n)
	if n <= 0 or not _any(p):
		return
	var t = await g.pick_creature(p, g.sides(), "Водоворот клинков: %d урона выбранному существу" % (2 * n))
	if t != null:
		await hit(t["p"], t["lane"], 2 * n, p)


# Бутылобород Крутой
func enter_bottlebeard_the_cool(_c, p, _lane) -> void:
	for i in 2:
		var pool: Array = g.discard_pool(p, func(x): return g.is_potion(x))
		if pool.is_empty():
			return
		var pick = await g.pick_card(p, pool, "Бутылобород: взять на руку «Зелье» из сброса?", true)
		if pick == null:
			return
		await g.return_to_hand(pick)


# Узел светлого сердца
func on_played_brightheart_nexus(_src, sp, _skind, slane, p, c) -> void:
	if p != sp or c.kind() != "spell":
		return
	var lanes: Array = bld_targets(sp, slane)
	if not lanes.is_empty():
		for l in lanes:
			await g.heal_creature(sp, l, 1)
	else:
		await g.heal_player(await _heal_target(sp, "Узел светлого сердца: кто восстановит 1 жизнь?"), 1)


# Бычья печать
func playable_bull_sigil(_c, p) -> bool:
	return _any(p)


func spell_bull_sigil(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Бычья печать: на какое существо жетон атаки?")
	if t == null:
		return
	var x = creature(t["p"], t["lane"])
	await g.add_atk_tokens(x)
	if g.tokens(x, "atk_tok") >= 2 and not players(p).deck.is_empty() 			and await g.pick_option(p, ["Взять карту", "Не брать"], "Бычья печать: взять карту?") == "Взять карту":
		await g._draw(p)


# Чаша Жестокий
func on_played_chalice_the_cruel(_src, sp, _skind, _slane, p, c) -> void:
	if p != sp or c.kind() != "spell" or g.creature_opts(sp, g.foes(sp)).is_empty():
		return
	var t = await g.pick_creature(sp, g.foes(sp), "Чаша Жестокий: какому существу соперника 2 урона?")
	if t != null:
		await hit(t["p"], t["lane"], 2, sp)


# Шпаргалка (the discount: Game.cost_of)
func spell_cheat_sheet(_c, p) -> void:
	await g._draw(p)
	players(p).turn["potion_discount"] = 2


# Адская лопата
func playable_infernal_spade(_c, p) -> bool:
	return _any(p)


func spell_infernal_spade(_c, p) -> void:
	var n := _spells_in_discard(p)
	var t = await g.pick_creature(p, g.sides(), "Адская лопата: %d урона выбранному существу" % n)
	if t != null and n > 0:
		await hit(t["p"], t["lane"], n, p)


# Математическое зелье
func spell_math_potion(_c, p) -> void:
	await g.draw_cards(p, 3)
	var hand: Array = players(p).hand
	if hand.is_empty():
		return
	var pick = await g.pick_card(p, hand, "Математическое зелье: какую карту с руки положить на верх колоды?")
	if pick != null:
		hand.erase(pick)
		players(p).deck.append(pick)
		await g.emit_event({"type": "to_deck", "p": p, "uid": pick.uid})


# Зелье удара
func spell_punch_potion(_c, p) -> void:
	var own: Array = g.sides().filter(func(s): return not g.foes(p).has(s))
	var t: Dictionary = await _creature_or_player(p, g.foes(p) + own, "Зелье удара: кому 3 урона?", g.sides())
	if t.is_empty():
		return
	if int(t["lane"]) < 0:
		await g.damage_player(int(t["p"]), 3, null, {"kind": "effect", "p": p})
	else:
		await hit(t["p"], t["lane"], 3, p)


# Желтковое зелье
func playable_yolked_potion(_c, p) -> bool:
	return _any(p)


func spell_yolked_potion(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Желтковое зелье: какое существо?")
	if t == null:
		return
	await g.heal_creature(t["p"], t["lane"], 2, p)
	await g.add_atk_tokens(creature(t["p"], t["lane"]), 2)
	if g.atk_of(t["p"], t["lane"]) >= 5:
		await g._draw(p)


# Рог-меч
func playable_sword_horn(_c, p) -> bool:
	return _any(p)


func spell_sword_horn(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Рог-меч: на какое существо жетоны атаки?")
	if t != null:
		await g.add_atk_tokens(creature(t["p"], t["lane"]), 1 + _spells_in_discard(p) / 2)


# Фиал мести
func playable_vial_of_vengeance(_c, p) -> bool:
	return g.creature_count(p) > 0 and not g.creature_opts(p, g.foes(p)).is_empty()


func spell_vial_of_vengeance(_c, p) -> void:
	var mine = await g.pick_creature(p, [p], "Фиал мести: урон какого своего существа перенести?")
	var t = await g.pick_creature(p, g.foes(p), "Фиал мести: на какое существо соперника?")
	if mine == null or t == null:
		return
	var x = creature(p, mine["lane"])
	var n: int = x.damage
	x.damage = 0
	await g.emit_event({"type": "heal", "p": p, "lane": mine["lane"], "uid": x.uid, "amount": n})
	if n > 0:
		var y = creature(t["p"], t["lane"])
		y.damage += n
		await g.emit_event({"type": "damage", "p": t["p"], "lane": t["lane"], "uid": y.uid, "amount": n})
	await g.bounce_creature(p, mine["lane"])
	await g._check_state()


# Фиалис Смотритель
func enter_phialis_the_caretaker(_c, p, _lane) -> void:
	var spells: Array = players(p).hand.filter(func(x): return x.kind() == "spell")
	if spells.is_empty():
		return
	var all := "Показать все: %d" % spells.size()
	var opts := [all, "Выбрать", "Нет"] if spells.size() > 1 else [all, "Нет"]
	var pick = await g.pick_option(p, opts, "Фиалис: показать заклинания с руки?")
	if pick == "Нет":
		return
	if pick == "Выбрать":
		var left := spells.duplicate()
		spells = []
		while not left.is_empty():
			var uid = await g._choose({"kind": "hand_card", "player": p, "optional": not spells.is_empty(),
				"options": left.map(func(x): return x.uid),
				"prompt": "Фиалис: какое заклинание показать?" if spells.is_empty() else "Фиалис: показать ещё заклинание?"})
			if uid == null:
				break
			var x = g.card(int(uid))
			left.erase(x)
			spells.append(x)
		if spells.is_empty():
			return
	await g.emit_event({"type": "reveal", "p": p, "uids": spells.map(func(x): return x.uid)})
	await g.heal_player(await _heal_target(p, "Фиалис: кто восстановит жизни?"), 2 * spells.size())


# Канопа Церемониальный
func enter_canopic_the_ceremonial(_c, p, _lane) -> void:
	var pool: Array = g.discard_pool(p, func(x): return x.kind() == "spell")
	if pool.is_empty():
		return
	var pick = await g.pick_card(p, pool, "Канопа: какое заклинание положить на верх колоды?")
	if pick != null:
		players(p).discard.erase(pick)
		players(p).deck.append(pick)
		await g.emit_event({"type": "to_deck", "p": p, "uid": pick.uid})


# Аксолотль
func floop_axolotl(_c, p, _kind, _lane) -> void:
	await g.heal_player(await _heal_target(p, "Аксолотль: кто восстановит 3 жизни?"), 3)


# Глазолоза
func enter_eye_viner(c, p, _lane) -> void:
	if _spells_in_discard(p) >= 3:
		await g.add_atk_tokens(c, 3)


# Сердечное зелье
func spell_heart_potion(_c, p) -> void:
	var t: Dictionary = await _creature_or_player(p, g.sides(), "Сердечное зелье: кого лечить на 5?")
	if t.is_empty():
		return
	if int(t["lane"]) < 0:
		var s: int = t["p"]
		await g.heal_player(s, 5)
		if players(s).hp >= players(s).max_hp:
			await g._draw(p)
	else:
		await g.heal_creature(t["p"], t["lane"], 5, p)
		if creature(t["p"], t["lane"]).damage == 0:
			await g._draw(p)


# Хрустальный шар: name a card from your deck list, reveal the top card.
func spell_crystal_ball(_c, p) -> void:
	if players(p).deck.is_empty():
		return
	var names := []
	for x in g.all_cards(p):
		if not names.has(x.card_name()):
			names.append(x.card_name())
	names.sort()
	var named = await g.pick_option(p, names, "Хрустальный шар: назови карту")
	var top = players(p).deck.back()
	await g.emit_event({"type": "reveal", "p": p, "uids": [top.uid]})
	await say("Хрустальный шар: «%s» — сверху «%s»." % [named, top.card_name()])
	if top.card_name() == named:
		await g.play_free(p, top)


# Талисман феникса (Game._die sends friendly creatures home this turn)
func spell_phoenix_talisman(_c, p) -> void:
	players(p).turn["phoenix_talisman"] = true


# Буря заклинаний
func spell_spellstorm(_c, p) -> void:
	await hit_foes(p, 2)
	var n := 0
	for i in 3:
		var x = await g.mill(p)
		if x != null and x.kind() == "spell":
			n += 1
	await g.gain_actions(p, n)


# Проводник огня чар
func on_played_spellfire_conduit(_src, sp, _skind, slane, p, c) -> void:
	if p != sp or c.kind() != "spell":
		return
	var hit_any := false
	for s in g.lane_spots(sp, slane):
		if g.is_foe(sp, s[0]) and creature(s[0], s[1]) != null:
			hit_any = true
			await hit(s[0], s[1], 1, sp)
	if not hit_any:
		var o: int = await g.pick_foe(sp, "Проводник огня чар: какому игроку 1 урон?")
		if o >= 0:
			await g.damage_player(o, 1, null, {"kind": "effect", "p": sp})


# Пролитиус Калечащий
func enter_spillith_the_crippler(_c, p, _lane) -> void:
	var n := 0
	for i in 3:
		var x = await g.mill(p)
		if x != null and x.kind() == "spell":
			n += 1
	if n <= 0 or not _any(p):
		return
	var t = await g.pick_creature(p, g.sides(), "Пролитиус: %d урона выбранному существу" % (2 * n))
	if t != null:
		await hit(t["p"], t["lane"], 2 * n, p)
