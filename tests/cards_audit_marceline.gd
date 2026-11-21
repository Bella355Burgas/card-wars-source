extends "res://tests/cards_audit_base.gd"
## Card audit: Марселин (Бесплодные болота и Милые земли). See docs/CARDS_AUDIT.md.


func t_witch_foes_only() -> void:
	_fresh(["finn", "jake", "pb", "bmo"])
	await put(0, "man_witch", 0)
	var hp: int = g.players[0].hp
	var c = hand(2, "cow")
	await g.discard_card(2, c)
	ok(g.players[0].hp == hp, "Ведьмак в 2 на 2: сброс союзника не бьёт свою команду")
	var fhp: int = g.players[1].hp
	c = hand(1, "cow")
	await g.discard_card(1, c)
	ok(g.players[1].hp == fhp - 1, "Ведьмак: сброс соперника, 1 урон")
	_fresh(["finn", "jake", "pb", "bmo"])
	await build(0, "funeral_home", 0)
	await put(0, "cow", 0)
	var base: int = atk(0, 0)
	await g.discard_card(2, hand(2, "cow"))
	ok(atk(0, 0) == base, "Мертвополь в 2 на 2: сброс союзника не считается")
	await g.discard_card(3, hand(3, "cow"))
	ok(atk(0, 0) == base + 1, "Мертвополь: сброс соперника +1")


func t_each_foe() -> void:
	_fresh(["finn", "jake", "bmo"])
	await put(0, "fly_swatter", 0)
	var z1 = hand(1, "cow")
	hand(1, "husker_knight")
	var z2 = hand(2, "sheep")
	await floop(0, 0)
	ok(g.players[1].discard.has(z1) and g.players[2].discard.has(z2), "Мушка-хлопушка: каждый соперник сбросил карту стоимостью 0")
	_fresh(["finn", "jake", "bmo"])
	await put(0, "bog_bum", 0)
	hand(1, "cow")
	hand(2, "cow")
	await g.destroy_creature(0, 0)
	ok(g.players[1].hand.is_empty() and g.players[2].hand.is_empty(), "Болотный босяк: каждый соперник сбросил случайную карту")
	_fresh()
	var b = await put(0, "bog_bum", 0)
	b.exhausted = true
	hand(1, "cow")
	await g.destroy_creature(0, 0)
	ok(g.players[1].hand.size() == 1, "Болотный босяк: повёрнутый ушёл, сброса нет")


func t_frog_bomb_ready_only() -> void:
	var f = await put(0, "bog_frog_bomb", 0)
	var e = await put(1, "cow", 1)
	e.perm_def = 5
	f.exhausted = true
	await g.destroy_creature(0, 0)
	ok(e.damage == 0, "Жабомба: повёрнутая не взрывается")
	await put(0, "bog_frog_bomb", 0)
	await g.destroy_creature(0, 0)
	ok(e.damage == 2, "Жабомба: подготовленная, 2 урона каждому")


func t_five_damage_cards() -> void:
	var m = await put(0, "music_mallard", 0)
	m.perm_def = 10
	var n: int = g.players[0].hand.size()
	await floop(0, 0)
	ok(g.players[0].hand.size() == n + 1, "Гусьляр: 1 карта")
	_fresh()
	m = await put(0, "music_mallard", 0)
	m.perm_def = 10
	m.damage = 5
	await floop(0, 0)
	ok(g.players[0].hand.size() == 2, "Гусьляр: 5 урона, 2 карты")
	_fresh()
	var c = await put(0, "cottonpult", 0)
	c.perm_def = 10
	c.damage = 5
	var e = await put(1, "cow", 0)
	e.perm_def = 5
	bot.answers = [spot(1, 0)]
	await floop(0, 0)
	ok(e.damage == 1 and c.damage == 4 and not c.exhausted, "Хлопкомёт: 5 урона, подготовлен и −1 урон")
	_fresh()
	var d = await put(0, "dr_stuffenstein", 1)
	d.perm_def = 10
	var a = await put(0, "cow", 0)
	a.perm_def = 10
	a.damage = 3
	var far = await put(0, "cow", 3)
	far.perm_def = 10
	far.damage = 3
	await floop(0, 1)
	ok(a.damage == 1 and far.damage == 3, "Доктор Мягкенштейн: только сосед")
	_fresh()
	d = await put(0, "dr_stuffenstein", 1)
	d.perm_def = 10
	d.damage = 5
	far = await put(0, "cow", 3)
	far.perm_def = 10
	far.damage = 3
	await floop(0, 1)
	ok(d.damage == 3 and far.damage == 1, "Доктор Мягкенштейн: 5 урона, всем своим по 2")


func t_spells() -> void:
	lands(0, "swamp")
	hand(1, "cow")
	var hp: int = g.players[1].hp
	await play(0, hand(0, "blood_bath"))
	ok(g.players[1].hp == hp - 5, "Кровавая банька: нет карты за 2, 5 урона")
	_fresh()
	lands(0, "swamp")
	var big = hand(1, "husker_knight")
	hp = g.players[1].hp
	await play(0, hand(0, "blood_bath"))
	ok(g.players[1].discard.has(big) and g.players[1].hp == hp, "Кровавая банька: сбросил карту за 2")
	_fresh()
	lands(0, "swamp")
	var e = await put(1, "cow", 0)
	e.perm_def = 5
	hand(1, "cow")
	bot.skip_optional = true
	await play(0, hand(0, "bums_away"))
	ok(e.damage == 2 and g.players[1].hand.size() == 1, "Бомбёжка: не сбросил, 2 урона каждому")
	_fresh()
	lands(0, "cute")
	var x = await put(0, "cow", 0)
	x.perm_def = 10
	x.damage = 4
	ok(not g.can_play(0, hand(0, "pentaid").uid), "Пентапластырь: меньше 5 урона нельзя")


func t_hen_house_and_angel() -> void:
	await build(0, "big_hen_house", 0)
	var c = await put(0, "cow", 0)
	c.perm_def = 5
	g.players[0].hp = 20
	bot.answers = ["2 урона"]
	await g._start_effects(0)
	ok(c.damage == 2 and g.players[0].hp == 21, "Петушатник: 2 урона своему, +1 жизнь")
	_fresh()
	var a = await put(0, "bog_ban_she_angel", 0)
	a.damage = 3
	var e = await put(1, "cow", 0)
	e.perm_def = 10
	bot.answers = [spot(1, 0)]
	await g.cmd_activate(0, "creature", 0)
	ok(a.damage == 0 and e.damage == 3 and g.players[0].actions == 1, "Болотный ангел-банши: весь урон перенесён за 1 действие")


func t_unicyclops() -> void:
	await put(0, "unicyclops", 0)
	top(0, "cow")
	top(1, "cow")
	await g._start_effects(0)
	ok(g.players[0].hand.is_empty() and g.players[1].hand.is_empty() and g.players[1].discard.size() == 1, "Моноциклоп: каждый взял и сбросил")
