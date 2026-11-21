extends "res://tests/cards_audit_base.gd"
## Card audit: Кейк (Кукурузные поля). See docs/CARDS_AUDIT.md.


func t_void_thimble_is_loss() -> void:
	await build(0, "bongo_bounce_house", 0)
	var hp: int = g.players[0].hp
	var a: int = g.players[0].actions
	await play(0, hand(0, "void_thimble"))
	ok(g.players[0].hp == hp - 2 and g.players[0].actions == a + 1, "Напёрсток пустоты: 2 жизни теряются, замок Бонго их не берёт")


func t_castle_and_fortress() -> void:
	var e = await put(1, "cow", 0)
	e.perm_def = 10
	await build(0, "blood_castle", 0)
	await g.damage_creature(1, 0, 2, {"kind": "effect", "p": 0})
	ok(e.damage == 3, "Кровавый замок: +1 к урону существу соперника в зоне")
	var mine = await put(0, "cow", 0)
	mine.perm_def = 10
	await g.damage_creature(0, 0, 2, {"kind": "effect", "p": 1})
	ok(mine.damage == 2, "Кровавый замок: своё существо без добавки")
	var d: int = df(1, 0)
	await build(0, "celestial_fortress", 1)
	var x = await put(1, "cow", 1)
	ok(df(1, 1) == x.def()["def"] - 2 and df(0, 0) == mine.def()["def"] + 10, "Небесная крепость: −2 только сопернику в зоне")


func t_flooped_counts() -> void:
	lands(0, "corn")
	var a = await put(0, "cow", 0)
	a.flooped = true
	var b = await put(0, "cow", 1)
	b.flooped = true
	var cab = hand(0, "cabin_of_many_woods")
	ok(g.cost_of(0, cab) == 3, "Хижина из многих лесов: на 1 меньше за флюпнутое")
	var aa: int = atk(0, 0)
	var bb: int = atk(0, 1)
	await put(0, "druid_of_the_cob", 2)
	ok(atk(0, 0) == aa + 1 and atk(0, 1) == bb + 1, "Друид початка: флюпнутым +1")
	await put(0, "kernel_queen", 3)
	ok(atk(0, 3) == mk("kernel_queen").def()["atk"] + 2, "Королева зёрен: +1 за флюпнутое")
	var t = await put(1, "tornado_wall_of_fire", 0)
	ok(atk(1, 0) == t.def()["atk"], "Огненная стена-торнадо: без флюпа без бонуса")
	t.flooped = true
	ok(atk(1, 0) == t.def()["atk"] + 3, "Огненная стена-торнадо: +3, пока флюпнута")


func t_built_lanes() -> void:
	await put(0, "husker_champion", 0)
	var base: int = atk(0, 0)
	await build(0, "blood_fortress", 1)
	ok(atk(0, 0) == base, "Кожурыцарь-чемпион: строение в другой зоне не считается")
	await build(0, "celestial_castle", 0)
	ok(atk(0, 0) == base + 2, "Кожурыцарь-чемпион: строение в этой зоне")
	lands(0, "corn")
	await put(0, "cow", 1)
	var c1: int = atk(0, 1)
	var c0: int = atk(0, 0)
	await put(0, "cow", 2)
	var c2: int = atk(0, 2)
	await play(0, hand(0, "log_rhythm"))
	ok(atk(0, 1) == c1 + 2 and atk(0, 0) == c0 + 2 and atk(0, 2) == c2, "Бревенчатый ритм: только в зонах со строением")


func t_danica_and_templar() -> void:
	await put(0, "archer_danica", 0)
	ok(not g.can_floop(0, "creature", 0), "Лучница Даника: без строения флюпа нет")
	await build(0, "blood_fortress", 1)
	var e = await put(1, "cow", 2)
	e.perm_def = 5
	await floop(0, 0)
	ok(g.players[0].buildings[1] == null and e.damage == 3, "Лучница Даника: строение уничтожено, 3 урона")
	var t = await put(0, "corns_templar", 3)
	ok(not g.can_floop(0, "creature", 3), "Кукурузный тамплиер: без урона флюпа нет")
	t.damage = 2
	await floop(0, 3)
	ok(t.damage == 1, "Кукурузный тамплиер: −1 урон")


func t_deck_and_discard() -> void:
	lands(0, "corn")
	g.players[0].deck.clear()
	var b = top(0, "blood_fortress")
	top(0, "cow")
	await put(0, "cow", 0)
	await play(0, hand(0, "deforestation"))
	ok(g.where(b.uid)["zone"] == "building" and g.players[0].creatures[0].exhausted, "Вырубка леса: существо повёрнуто, строение из колоды в игре")
	_fresh()
	lands(0, "corn")
	var c = hand(0, "deforestation")
	ok(not g.can_play(0, c.uid), "Вырубка леса: без готового существа нельзя")
	_fresh()
	lands(0, "corn")
	var d = dis(0, "celestial_castle")
	await play(0, hand(0, "harvest_moon"))
	ok(g.where(d.uid)["zone"] == "building", "Урожайная луна: строение из сброса в игре")


func t_butterfly_lumberjill_sharp() -> void:
	await build(0, "blood_fortress", 0)
	await build(0, "celestial_castle", 1)
	await put(0, "popcorn_butterfly", 2)
	var n: int = g.players[0].hand.size()
	await floop(0, 2)
	ok(g.players[0].hand.size() == n + 2, "Попкорновая бабочка: карта за каждое строение")
	var hp: int = g.players[1].hp
	await put(0, "tough_lumberjill", 3)
	ok(g.players[1].hp == hp - 2, "Суровая лесорубка: урон по числу строений")
	_fresh()
	await put(0, "sharp_guy", 0)
	ok(not g.can_floop(0, "creature", 0), "Мистер Шинковщик: напротив пусто")
	var e = await put(1, "cow", 0)
	e.perm_def = 5
	await floop(0, 0)
	ok(e.damage == 2, "Мистер Шинковщик: 2 урона напротив")
