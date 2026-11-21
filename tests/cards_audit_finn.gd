extends "res://tests/cards_audit_base.gd"
## Card audit: Финн (Синие равнины). See docs/CARDS_AUDIT.md.


func t_bard_counts_itself() -> void:
	var b = await put(0, "embarrassing_bard", 0)
	var o = await put(0, "cow", 1)
	o.flooped = true
	o.exhausted = true
	var n: int = g.players[0].hand.size()
	await floop(0, 0)
	ok(b.flooped and g.players[0].hand.size() == n + 2, "Стеснительный бард: карта за себя и за другое флюпнутое")


func t_woadic_chief_own_turn() -> void:
	lands(0, "plain")
	await put(0, "woadic_chief", 0)
	var base: int = atk(0, 0)
	await play(0, hand(0, "gnome_snot"))
	ok(atk(0, 0) == base + 2, "Синюшный вождь: +2 за сыгранное заклинание")
	g.turn_player = 1
	ok(atk(0, 0) == base, "Синюшный вождь: в чужой ход бонуса нет")


func t_ancient_scholar_building() -> void:
	await put(0, "ancient_scholar", 0)
	var r = dis(0, "cow")
	await build(0, "blood_fortress", 0)
	var a: int = g.players[0].actions
	await floop(0, 0)
	ok(g.players[0].hand.has(r) and g.players[0].actions == a + 1, "Древний грамотей: радужная карта на руку и действие при строении")
	_fresh()
	await put(0, "ancient_scholar", 1)
	await build(0, "blood_fortress", 0)
	a = g.players[0].actions
	await floop(0, 1)
	ok(g.players[0].actions == a, "Древний грамотей: строение в другой зоне не даёт действия")


func t_mobile_home_needs_empty() -> void:
	await build(0, "woad_mobile_home", 1)
	await put(0, "cow", 1)
	await put(0, "cow", 2)
	ok(not g.can_floop(0, "building", 1), "Синюшный вигвам: зона занята, флюпа нет")
	_fresh()
	await build(0, "woad_mobile_home", 1)
	var c = await put(0, "cow", 2)
	await floop(0, 1, "building")
	ok(g.players[0].creatures[1] == c, "Синюшный вигвам: существо с соседней зоны переходит сюда")


func t_psionic_architect_optional() -> void:
	var o = await put(0, "cow", 1)
	o.flooped = true
	o.exhausted = true
	bot.skip_optional = true
	await put(0, "psionic_architect", 0)
	ok(o.flooped, "Архитектор разума: можно отказаться")
	_fresh()
	o = await put(0, "cow", 1)
	o.flooped = true
	o.exhausted = true
	await put(0, "psionic_architect", 0)
	ok(not o.flooped and not o.exhausted, "Архитектор разума: флюпнутое существо готово")


func t_uni_knight_this_turn() -> void:
	await put(0, "uni_knight", 0)
	await put(1, "cow", 0)
	await put(1, "cow", 1)
	var before: int = atk(1, 1)
	g.players[1].creatures[0].perm_atk = 12
	var a0: int = atk(1, 0)
	bot.answers = [spot(1, 0)]
	await g.cmd_activate(0, "creature", 0)
	ok(atk(1, 0) == a0 - 10 and atk(1, 1) == before, "Велорыцарь: −10 только существу в этой зоне")
	ok(g.players[0].actions == 1, "Велорыцарь: стоит 1 действие")
	await pass_turn(0)
	ok(atk(1, 0) == a0, "Велорыцарь: −10 только на этот ход")


func t_jinn_and_spirit() -> void:
	var j = await put(0, "struzann_jinn", 0)
	var base: int = atk(0, 0)
	var o = await put(0, "cow", 2)
	o.flooped = true
	ok(atk(0, 0) == base + 2, "Джинн Стрюзан: +2 за флюпнутое существо")
	j.flooped = true
	ok(atk(0, 0) == base + 4, "Джинн Стрюзан: считает и себя")
	_fresh()
	var a = await put(0, "cow", 0)
	var b = await put(0, "cow", 3)
	var x = await put(1, "cow", 2)
	var c0: int = atk(0, 0)
	var c3: int = atk(0, 3)
	var x2: int = atk(1, 2)
	await put(0, "spirit_soldier", 1)
	ok(atk(0, 0) == c0 + 1 and atk(0, 3) == c3 and atk(1, 2) == x2, "Необъятный солдат-дух: +1 только своему соседу")


func t_gazer_needs_spell() -> void:
	await put(0, "heavenly_gazer", 0)
	ok(not g.can_floop(0, "creature", 0), "Благо одноглазое: без заклинаний в сбросе флюпа нет")
	var s = dis(0, "gnome_snot")
	ok(g.can_floop(0, "creature", 0), "Благо одноглазое: есть заклинание")
	await floop(0, 0)
	ok(g.players[0].deck.back() == s, "Благо одноглазое: заклинание наверху колоды")


func t_marauder_both_turns() -> void:
	await put(0, "woadic_marauder", 0)
	var n: int = g.players[0].hand.size()
	g.turn_player = 1
	await g.move_creature(0, 0, 2)
	ok(g.players[0].hand.size() == n + 1, "Синюшный злопыхатель: карта и в ход соперника")


func t_pig_corn_only() -> void:
	lands(0, "plain")
	lands(1, "plain")
	await put(0, "the_pig", 1)
	ok(not g.can_floop(0, "creature", 1), "Свинья: без кукурузного поля в зоне флюпа нет")
	g.players[1].lands[1]["type"] = "corn"
	await floop(0, 1)
	ok(g.players[1].lands[1].get("flipped", false), "Свинья: кукурузное поле соперника перевёрнуто")
