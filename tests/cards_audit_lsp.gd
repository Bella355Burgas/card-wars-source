extends "res://tests/cards_audit_base.gd"
## Card audit: Принцесса Пупырка (Бесплодные болота и Синие равнины). See docs/CARDS_AUDIT.md.


func t_crystal_ally() -> void:
	_fresh(["finn", "jake", "pb", "bmo"])
	lands(0, "plain")
	bot.answers = ["Тянет союзник"]
	var n: int = g.players[2].hand.size()
	await play(0, hand(0, "strength_crystal"))
	ok(g.players[2].hand.size() == n + 5, "Кристалл силы в 2 на 2: может взять союзник")
	_fresh()
	lands(0, "plain")
	bot.answers = ["Тянет соперник"]
	await play(0, hand(0, "strength_crystal"))
	ok(g.players[1].hand.size() == 5 and not bot.asked[0]["options"].has("Тянет союзник"), "Кристалл силы: соперник, союзника в 1 на 1 нет")


func t_pump_limits() -> void:
	await put(0, "dogboy", 0)
	hand(0, "cow")
	hand(0, "cow")
	var base: int = atk(0, 0)
	await g.cmd_activate(0, "creature", 0)
	ok(atk(0, 0) == base + 2 and not g.can_activate(0, "creature", 0), "Псой: +2, раз за ход")
	_fresh()
	await put(0, "dragon_foot", 0)
	for i in 6:
		hand(0, "cow")
	base = atk(0, 0)
	for i in 5:
		await g.cmd_activate(0, "creature", 0)
	ok(atk(0, 0) == base + 5 and not g.can_activate(0, "creature", 0), "Драконья нога: не чаще пяти раз")
	_fresh()
	await put(0, "infinite_figure", 0)
	hand(0, "cow")
	ok(not g.can_activate(0, "creature", 0), "Бродячая бесконечность: напротив пусто")
	var e = await put(1, "cow", 0)
	e.perm_def = 5
	await g.cmd_activate(0, "creature", 0)
	ok(e.damage == 1, "Бродячая бесконечность: 1 урон напротив")


func t_replacers() -> void:
	lands(0, "plain")
	await put(0, "cow", 0)
	var c = hand(0, "future_scholar")
	var a: int = g.players[0].actions
	await play(0, c, 0)
	ok(g.players[0].actions == a - 2 + 1, "Грамотей из будущего: заменил, +1 действие")
	_fresh()
	lands(0, "plain")
	a = g.players[0].actions
	await play(0, hand(0, "future_scholar"), 0)
	ok(g.players[0].actions == a - 2, "Грамотей из будущего: на пустую землю без действия")
	_fresh()
	lands(0, "plain")
	await put(0, "cow", 1)
	var e = await put(1, "cow", 1)
	e.perm_def = 5
	await play(0, hand(0, "headphone_jerk"), 1)
	ok(e.damage == 3, "Нахал в наушниках: заменил, 3 урона напротив")
	_fresh()
	lands(0, "plain")
	await put(0, "cow", 1)
	var d = dis(0, "gnome_snot")
	bot.skip_optional = true
	await play(0, hand(0, "grape_djini"), 1)
	ok(g.players[0].discard.has(d), "Виноградный джинн: можно не класть")


func t_steakchop() -> void:
	var s = await put(0, "steakchop", 0)
	hand(0, "cow")
	await g._trigger_own(0, "after_draw_")
	ok(g.where(s.uid)["zone"] == "discard", "Антрекот-мясник: одна карта на руке, только уничтожить")
	_fresh()
	s = await put(0, "steakchop", 0)
	hand(0, "cow")
	hand(0, "cow")
	await g._trigger_own(0, "after_draw_")
	ok(g.players[0].creatures[0] == s and g.players[0].hand.is_empty(), "Антрекот-мясник: сбросил 2 карты")


func t_pyramidia_lane_action() -> void:
	lands(0, "plain")
	await build(0, "pyramidia", 1)
	await put(0, "cow", 1)
	await floop(0, 1, "building")
	g.players[0].actions = 1
	var c = hand(0, "future_scholar")
	ok(g.can_play(0, c.uid, 1) and not g.can_play(0, c.uid, 2), "Пирамидия: на 1 меньше только в этой зоне")


func t_spells() -> void:
	lands(0, "plain")
	await put(0, "cow", 0)
	var base: int = atk(0, 0)
	g.players[0].actions = 5
	await play(0, hand(0, "gnome_snot"))
	await play(0, hand(0, "subliminal_strength"))
	ok(atk(0, 0) == base + 4, "Подсознательная мощь: считает и себя")
	_fresh()
	lands(0, "plain")
	g.players[0].lands[3]["type"] = "swamp"
	await put(0, "cow", 0)
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "pants_of_awesome"))
	ok(g.players[0].creatures[0] == null and g.players[0].creatures[3] == null and g.players[0].hand.size() == n + 1, "Портки отпадности: на синюю равнину и карта")


func t_volcano() -> void:
	await build(1, "blood_fortress", 2)
	var e = await put(1, "cow", 2)
	e.perm_def = 5
	bot.skip_optional = true
	await play(0, hand(0, "volcano"))
	ok(g.players[1].buildings[2] == null and e.damage == 0 and g.players[0].lands[2]["flipped"], "Вулкан: строение, урон можно не наносить, своя земля перевёрнута")


func t_night_tower_and_hand() -> void:
	await build(0, "night_tower", 0)
	hand(1, "cow")
	await put(1, "cow", 0)
	ok(not g.can_floop(0, "building", 0), "Башня ночи: у соперника есть существо в зоне")
	g.players[1].creatures[0] = null
	await floop(0, 0, "building")
	ok(g.players[1].hand.is_empty(), "Башня ночи: соперник сбросил карту")
	_fresh()
	await put(0, "skeletal_hand", 0)
	top(0, "cow")
	top(0, "gnome_snot")
	top(0, "teleport")
	hand(1, "cow")
	hand(1, "cow")
	hand(1, "cow")
	await floop(0, 0)
	ok(g.players[1].hand.size() == 1, "Рука скелета: по карте за каждое сброшенное заклинание")
