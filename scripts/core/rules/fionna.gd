extends "res://scripts/core/rules/base.gd"
## Фионна (Синие равнины).


# Нефтезавод
func aura_def_oil_refinery(_src, sp, slane, _c, p, lane) -> int:
	return 2 * g.count_text(sp, "oil_refinery") if sp == p and slane == lane else 0


# Грамотей-младенец
func atk_infant_scholar(_c, p, _lane) -> int:
	return 3 if p == g.turn_player and int(g.turn_value(p, "rainbow_played")) > 0 else 0


# Пёс-бизнесмен
## «Пёс» as a word or a word's end (Ультрапёс, Пёс-бизнесмен), not «Песчаный», «Песнь», «Пёстрые»;
## «Щенок» and its forms (Заштопанный щенок, Щенячий парад).
var _dog_word := RegEx.create_from_string("пес(?![а-я])|щен")


func atk_business_dog(_c, p, _lane) -> int:
	if p != g.turn_player:
		return 0
	var n := 0
	for id in g.turn_value(p, "played", []):
		var nm: String = CardDB.get_def(id)["name"].to_lower().replace("ё", "е")
		if _dog_word.search(nm) != null:
			n += 1
	return 2 * n


# Безумная кошатница
func aura_atk_crazy_cat_lady(_src, sp, _slane, c, p, lane) -> int:
	return 1 if sp == p and g.is_type(c, "rainbow", p, lane) else 0


# Синюшная матриарх
func atk_woadic_matriarch(_c, p, _lane) -> int:
	var n := 0
	for l in LANES:
		var o = creature(p, l)
		if o != null and g.is_type(o, "rainbow", p, l):
			n += 1
	return n


# Одинокая панда
func enter_lonely_panda(_c, p, _lane) -> void:
	if g.creature_count(p) == 1:
		await say("Одинокая панда одна на поле: %s берёт карту." % players(p).name)
		await g._draw(p)


# Пси-головорез
func enter_psionic_swashbuckler(_c, p, _lane) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Пси-головорез: можешь нанести 3 урона флюпнутому существу",
		func(x, _s, _l): return x.flooped, true)
	if pick != null:
		await hit(pick["p"], pick["lane"], 3, p)


# Осмелевший ретривер
func attack_emboldened_retriever(_c, p, _lane) -> void:
	if players(p).deck.is_empty():
		return
	if await g.pick_option(p, ["Взять карту", "Не брать"], "Осмелевший ретривер нападает: взять карту?") != "Взять карту":
		return
	await say("Осмелевший ретривер атакует: %s берёт карту." % players(p).name)
	await g._draw(p)


# Хорёк-скрипач
func floop_fiddling_ferret(_c, p, _kind, _lane) -> void:
	await g._draw(p)
	var pick = await g._choose({"kind": "hand_card", "player": p, "options": players(p).hand.map(func(h): return h.uid),
		"prompt": "Хорёк-скрипач: сбрось карту (Радужная — +1 действие)"})
	if pick == null:
		return
	var c = g._find(players(p).hand, pick)
	var rainbow: bool = g.play_land(c) == "rainbow"
	await g.discard_card(p, c)
	if rainbow:
		await g.gain_actions(p, 1)


# Невозможный опоссум
func discarded_impossible_possum(c) -> void:
	var p: int = c.owner
	if players(p).hand.is_empty() or g.phase == "over":
		return
	var pick = await g._choose({"kind": "hand_card", "player": p, "optional": true,
		"options": players(p).hand.map(func(h): return h.uid),
		"prompt": "Невозможный опоссум в сбросе: сбрось карту, чтобы вернуть его в руку?"})
	if pick == null:
		return
	await g.discard_card(p, g._find(players(p).hand, pick))
	if g.where(c.uid)["zone"] == "discard":
		await g.return_to_hand(c)


# Синюшный чудила
func floop_ok_woadic_weirdo(_c, p, _kind, _lane) -> bool:
	for h in players(p).hand:
		if g.play_land(h) != "rainbow":
			return true
	return false


func floop_woadic_weirdo(_c, p, _kind, _lane) -> void:
	var opts := []
	for h in players(p).hand:
		if g.play_land(h) != "rainbow":
			opts.append(h.uid)
	var pick = await g._choose({"kind": "hand_card", "player": p, "options": opts,
		"prompt": "Синюшный чудила: покажи карту — до конца хода она станет Радужной"})
	if pick != null:
		var c = g.card(pick)
		c.flags["rainbow"] = true
		c.flags["rainbow_turn"] = g.turn_number     # stays Rainbow in play too, see Game._keep_rainbow
		await say("«%s» становится Радужной картой до конца хода." % c.card_name())


# Пёс: its text is checked by the engine (building_blanked).
func floop_ok_the_dog(_c, p, _kind, lane) -> bool:
	var a: Array = g.across(p, lane)
	return not g.buildings_at(a[0], a[1]).is_empty()


func floop_the_dog(_c, p, _kind, lane) -> void:
	await say("Гав! Строения соперника в зоне %d без текста, пока Пёс применён." % (lane + 1))


# Повелитель вампиров
func dealt_vampire_lord(c, p, lane, amount, _target) -> void:
	if c.damage > 0:
		await g.heal_creature(p, lane, amount)


# Славный граммофон
func spell_glorious_gramophone(_c, p) -> void:
	await g.draw_cards(p, 4)
	await g.force_discard(p, 2, "Славный граммофон: сбрось карту")


# Щенячий парад
func spell_puppy_parade(_c, p) -> void:
	for l in LANES:
		await g.heal_creature(p, l, 2)
	players(p).turn["rainbow_creatures"] = true
	await say("Существа игрока %s стали Радужными на этот ход." % players(p).name)


# Букет мечей
func playable_sword_bouquet(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_sword_bouquet(_c, p) -> void:
	var n := int(g.turn_value(p, "drawn"))
	var pick = await g.pick_creature(p, g.sides(), "Букет мечей: %d урона выбранному существу" % n)
	if pick != null:
		await hit(pick["p"], pick["lane"], n, p)


# Браслет дружбы
func playable_friendship_bracelet(_c, p) -> bool:
	if g.creature_count(p) < 2:
		return false
	for l in LANES:
		var t = creature(p, l)
		if t != null and t.damage > 0:
			return true
	return false


func spell_friendship_bracelet(_c, p) -> void:
	var src = await g.pick_creature(p, [p], "Браслет дружбы: с какого существа забрать урон?",
		func(x, _s, _l): return x.damage > 0)
	if src == null:
		return
	var dst = await g.pick_creature(p, [p], "Браслет дружбы: на какое существо его переложить?",
		func(_x, _s, l): return l != src["lane"])
	if dst == null:
		return
	var from = creature(p, src["lane"])
	var opts := []
	for i in range(from.damage, 0, -1):
		opts.append(str(i))
	var amount := int(await g.pick_option(p, opts, "Сколько урона переложить?"))
	from.damage -= amount
	await g.emit_event({"type": "heal", "p": p, "lane": src["lane"], "uid": from.uid, "amount": amount})
	var to = creature(p, dst["lane"])
	to.damage += amount
	await g.emit_event({"type": "damage", "p": p, "lane": dst["lane"], "uid": to.uid, "amount": amount})
	await say("Браслет дружбы перекладывает %d урона." % amount)


# Поющий меч
func playable_singing_sword(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_singing_sword(_c, p) -> void:
	var n := int(g.turn_value(p, "drawn")) / 2
	var pick = await g.pick_creature(p, g.sides(), "Поющий меч: выбранное существо получает +%d ATK" % n)
	if pick != null:
		await g.buff(creature(pick["p"], pick["lane"]), n)


# Река мечей
func spell_river_of_swords(_c, p) -> void:
	for l in LANES:
		if creature(p, l) != null:
			await g.buff(creature(p, l), 2)
	await g.draw_cards(p, 2)
