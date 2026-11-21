extends "res://tests/cards_audit_base.gd"
## Card audit: Леди Ливнерог (Песчаные земли). See docs/CARDS_AUDIT.md.


func t_costs() -> void:
	lands(0, "sandy")
	g.players[0].actions = 5
	var golem = hand(0, "lost_golem")
	ok(g.cost_of(0, golem) == 3, "Блудный голем: полная цена")
	await play(0, hand(0, "fummy"), 0)
	await play(0, hand(0, "tome_of_ankhs"))
	ok(g.cost_of(0, golem) == 2, "Блудный голем: −1 только за существо")
	await play(0, hand(0, "unempty_coffin"))
	var c = hand(0, "sand_knights")
	ok(g.cost_of(0, c) == 0, "Непустой гроб: −2 следующему существу")
	await play(0, c, 1)
	ok(g.cost_of(0, golem) == 1, "Непустой гроб: скидка ушла после существа")


func t_enter_watchers() -> void:
	lands(0, "sandy")
	await put(0, "shark", 0)
	ok(atk(0, 0) == mk("shark").def()["atk"] + 1, "Акула: +1 и себе")
	await put(0, "sand_knights", 1)
	ok(atk(0, 1) == mk("sand_knights").def()["atk"] + 1, "Акула: песчаное существо в твой ход +1")
	g.turn_player = 1
	await put(0, "sand_knights", 2)
	g.turn_player = 0
	ok(atk(0, 2) == mk("sand_knights").def()["atk"], "Акула: в чужой ход бонуса нет")
	_fresh()
	var hp: int = g.players[1].hp
	await put(0, "sandwitch", 0)
	ok(g.players[1].hp == hp - 1, "Песчаная ведьма: урон за себя")
	await put(0, "cow", 1)
	await put(1, "cow", 1)
	ok(g.players[1].hp == hp - 2, "Песчаная ведьма: урон только за свои существа")
	_fresh()
	var e = await put(0, "sand_eyebat", 0)
	var d: int = df(0, 0)
	await put(0, "cow", 1)
	await put(1, "cow", 1)
	ok(df(0, 0) == d + 1, "Песчаный крылоглаз: +1 только за своё существо")
	await pass_turn(0)
	ok(df(0, 0) == d + 1, "Песчаный крылоглаз: навсегда")


func t_wall_and_djinni() -> void:
	lands(0, "sandy")
	await put(0, "wall_of_sand", 0)
	var base: int = atk(0, 0)
	ok(base == mk("wall_of_sand").def()["atk"], "Стена песка: сама не считается")
	await put(0, "cow", 1)
	ok(atk(0, 0) == base, "Стена песка: не песчаное не считается")
	await put(0, "sand_knights", 2)
	ok(atk(0, 0) == base + 2, "Стена песка: другое песчаное +2")
	_fresh()
	await put(0, "peach_djinni", 0)
	var p0: int = atk(0, 0)
	await put(0, "sand_knights", 1)
	await put(0, "cow", 2)
	ok(atk(0, 0) == p0 + 1, "Персиковый джинн: +1 только за песчаное")


func t_ms_mummy() -> void:
	var m = await put(0, "ms_mummy", 0)
	await g._start_effects(0)
	ok(g.players[0].creatures[0] == m and bot.asked.is_empty(), "Мисс мумия: без песчаного существа не спрашивает")
	var k = await put(0, "sand_knights", 1)
	var d: int = df(0, 1)
	bot.answers = ["Вернуть (+1 DEF Песчаному)"]
	await g._start_effects(0)
	ok(g.players[0].creatures[0] == null and df(0, 1) == d + 1, "Мисс мумия: на руку, песчаному +1 защиты")


func t_mummy_sphinx_mariachi() -> void:
	await put(0, "beach_mummy", 1)
	var e = await put(1, "cow", 2)
	await put(1, "cow", 3)
	ok(g.can_floop(0, "creature", 1), "Пляжная мумия: напротив соседней зоны есть существо")
	bot.answers = [spot(1, 2)]
	await floop(0, 1)
	ok(g.players[1].hand.has(e), "Пляжная мумия: существо соперника на руке владельца")
	_fresh()
	await put(0, "the_mariachi", 0)
	g.entered_this_turn = 0
	ok(not g.can_floop(0, "creature", 0), "Мариачи: никто не вошёл")
	var x = await put(1, "cow", 1)
	x.perm_def = 5
	await put(0, "cow", 2)
	bot.answers = [spot(1, 1)]
	await floop(0, 0)
	ok(x.damage == 2, "Мариачи: урон по числу вошедших")


func t_seeds_and_tome() -> void:
	lands(0, "sandy")
	var k = await put(0, "sand_knights", 1)
	var base: int = atk(0, 1)
	await put(0, "cow", 0)
	await put(0, "cow", 3)
	bot.answers = [spot(0, 1)]
	await play(0, hand(0, "zazos_magic_seeds"))
	ok(atk(0, 1) == base + 2, "Волшебные семена Зазо: +2 за существо в соседней зоне")
	_fresh()
	lands(0, "sandy")
	await put(0, "cow", 0)
	await build(0, "blood_fortress", 1)
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "tome_of_ankhs"))
	ok(g.players[0].hand.size() == n + 3, "Фолианкх: карта за каждую зону без существа")


func t_cactiball_devil_snake() -> void:
	await put(0, "green_cactiball", 0)
	var one: int = atk(0, 0)
	await put(0, "green_cactiball", 1)
	ok(atk(0, 0) == one + 2, "Зелёная кактугидра: +2 за каждую, считая себя")
	_fresh()
	var a = await put(0, "cow", 0)
	a.perm_def = 5
	var b = await put(1, "cow", 0)
	b.perm_def = 5
	var dv = await put(0, "sandhorn_devil", 1)
	ok(a.damage == 1 and b.damage == 1 and dv.damage == 1, "Дюнный дьяволёнок: 1 урон каждому, включая себя")
	_fresh()
	var x = await put(1, "cow", 2)
	x.perm_def = 10
	await put(0, "sandsnake", 2)
	ok(x.damage == 4, "Песчаный змей: 4 урона напротив")
