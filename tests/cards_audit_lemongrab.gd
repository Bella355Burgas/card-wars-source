extends "res://tests/cards_audit_base.gd"
## Card audit: Лимонохват (Кукурузные поля и Песчаные земли). See docs/CARDS_AUDIT.md.


func t_lunchpad_counts_lane() -> void:
	await build(0, "lunchpad", 1)
	await put(0, "cow", 1)
	await put(0, "cow", 2)
	var n: int = g.players[0].hand.size()
	await floop(0, 1, "building")
	ok(g.players[0].hand.size() == n + 1, "Взлётная площадка: только существа, вошедшие в этой зоне")


func t_silo_of_freedom() -> void:
	lands(0, "corn")
	await build(0, "silo_of_freedom", 0)
	ok(not g.can_activate(0, "building", 0), "Амбар свободы: без карты в руке нельзя")
	hand(0, "cow")
	bot.answers = [null, CardDB.land_name("cute")]
	bot.answers = [CardDB.land_name("cute")]
	await g.cmd_activate(0, "building", 0)
	ok(g.land_type(0, 0) == "cute" and g.players[0].hand.is_empty(), "Амбар свободы: карта сброшена, тип сменился")
	await pass_turn(0)
	ok(g.land_type(0, 0) == "cute", "Амбар свободы: держится в ход соперника")
	await pass_turn(1)
	ok(g.land_type(0, 0) == "corn", "Амбар свободы: до начала твоего следующего хода")
	g.players[0].lands[1]["flipped"] = true
	await build(0, "silo_of_freedom", 1)
	hand(0, "cow")
	ok(not g.can_activate(0, "building", 1), "Амбар свободы: на перевёрнутой земле нельзя")


func t_sinkhole_and_rock_out() -> void:
	await build(0, "sinkhole", 2)
	ok(not g.can_floop(0, "building", 2), "Провал: без карты в руке флюпа нет")
	hand(0, "cow")
	bot.answers = [spot(1, 2)]
	await floop(0, 2, "building")
	ok(g.players[1].lands[2]["flipped"], "Провал: земля соперника в этой зоне перевёрнута")
	await pass_turn(0)
	ok(g.players[1].lands[2]["flipped"], "Провал: держится в ход соперника")
	await pass_turn(1)
	ok(not g.players[1].lands[2]["flipped"], "Провал: до начала следующего хода")


func t_flip_and_restore() -> void:
	bot.answers = [spot(1, 0)]
	await put(0, "mantle_masher", 0)
	ok(g.players[1].lands[0]["flipped"], "Крушитель недр: перевернул землю в этой зоне")
	await g.destroy_creature(0, 0)
	ok(not g.players[1].lands[0]["flipped"], "Крушитель недр: ушёл, земля снова открыта")
	var h = await put(0, "husky_parrotrooper", 1)
	var at: Dictionary = g.where(h.uid)
	ok(g.players[at["p"]].lands[at["lane"]]["flipped"], "Хаски-попугайчик: его земля перевёрнута")
	await g.destroy_creature(at["p"], at["lane"])
	ok(not g.players[at["p"]].lands[at["lane"]]["flipped"], "Хаски-попугайчик: ушёл, земля открыта")


func t_parrotrooper_no_replace() -> void:
	lands(0, "corn")
	var d = await put(0, "dragoon_parrotrooper", 0)
	var w: Dictionary = g.where(d.uid)
	ok(w["zone"] == "creature", "Драгун-попугайчик: в игре")
	if int(w["p"]) == 0:
		var c = hand(0, "cow")
		ok(not g.can_play(0, c.uid, int(w["lane"])), "Драгун-попугайчик: его нельзя заменить")
	var s = await put(0, "static_parrotrooper", 3)
	var ws: Dictionary = g.where(s.uid)
	var hp: int = g.players[ws["p"]].hp
	await g._start_effects(int(ws["p"]))
	ok(g.players[ws["p"]].hp == hp - 1, "Статичный попугайчик: −1 жизнь тому, кто им управляет")


func t_mummy_and_magus() -> void:
	var m = await put(0, "grand_mummy", 0)
	bot.answers = ["Оставить"]
	await g._start_effects(0)
	ok(g.players[0].creatures[0] == m, "Великая мумия: можно оставить")
	var n: int = g.players[0].hand.size()
	bot.answers = ["Вернуть и взять 2 карты"]
	await g._start_effects(0)
	ok(g.players[0].creatures[0] == null and g.players[0].hand.size() == n + 3, "Великая мумия: на руку и 2 карты")
	_fresh()
	await put(0, "sandmagus", 0)
	var o = await put(0, "cow", 1)
	var base: int = atk(0, 1)
	bot.answers = ["Вернуть (+1 к атаке другим)"]
	await g._start_effects(0)
	ok(g.players[0].creatures[0] == null and atk(0, 1) == base + 1, "Песчаный маг: на руку, другим +1")


func t_ska_pion_and_quick() -> void:
	lands(0, "sandy")
	var s = hand(0, "ska_pion")
	var full: int = g.cost_of(0, s)
	await put(1, "cow", 0, 0)
	ok(g.cost_of(0, s) == full - 1, "Ска-рпион: дешевле, пока соперник держит твоё существо")
	_fresh()
	lands(0, "sandy")
	await put(0, "husker_knight", 0)
	var a: int = g.players[0].actions
	await play(0, hand(0, "quick_pick_me_up"))
	ok(g.players[0].creatures[0] == null and g.players[0].actions == a - 1 + 2, "Быстрый подъём: действия по стоимости")


func t_camel_optional() -> void:
	var cam = await put(0, "carmel_camel", 0)
	await put(0, "cow", 1)
	bot.answers = ["В сброс"]
	await g.destroy_creature(0, 1)
	ok(cam.under.is_empty(), "Карамельный верблюд: можно не подкладывать")
	await put(0, "cow", 1)
	var base: int = atk(0, 0)
	bot.answers = ["Под Карамельный верблюд"]
	await g.destroy_creature(0, 1)
	ok(cam.under.size() == 1 and atk(0, 0) == base + 1, "Карамельный верблюд: +1/+1 за карту под ним")
	await g.destroy_creature(0, 0)
	ok(g.players[0].discard.size() == 3, "Карамельный верблюд: ушёл, карты под ним в сбросе")


func t_outpost_and_rex() -> void:
	await put(0, "cow", 0)
	await put(1, "cow", 0)
	g.players[0].creatures[0].perm_atk = 3
	g.players[1].creatures[0].perm_atk = 3
	var a0: int = atk(0, 0)
	var a1: int = atk(1, 0)
	await build(0, "parrotmilitary_outpost", 0)
	ok(atk(0, 0) == a0 - 1 and atk(1, 0) == a1 - 1, "Аванпост попугаев: −1 каждому существу в зоне")
	_fresh()
	await put(0, "sandasaurus_rex", 0)
	ok(atk(0, 0) == mk("sandasaurus_rex").def()["atk"] + 6, "Пескозавр Рекс: +2 за каждую пустую землю")
