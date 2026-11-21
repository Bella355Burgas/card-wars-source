extends "res://tests/cards_audit_base.gd"
## Card audit: Снежный король (Ледяные земли). See docs/CARDS_AUDIT.md.


func t_lone_and_counts() -> void:
	await put(0, "cold_soldier", 0)
	var base: int = atk(0, 0)
	await put(1, "cow", 0)
	ok(atk(0, 0) == base - 3, "Охлаждённый воин: +3 только без существа напротив")
	await put(0, "sprucy_lucy", 1)
	var l: int = atk(0, 1)
	await g.freeze(1, 3)
	await g.freeze(0, 3)
	ok(atk(0, 1) == l + 2, "Ёлочка-тёлочка: +1 за каждую замороженную землю")
	g.players[0].creatures[1].perm_atk = 5
	var a: int = atk(0, 1)
	await put(0, "emperor_penguin", 2)
	await g.freeze(0, 1)
	ok(atk(0, 1) == a + 1 - 1, "Императорский пингвин: −1 существу на замороженной земле")


func t_collie_action() -> void:
	await put(0, "boarder_collie", 0)
	await g.freeze(1, 2)
	var a: int = g.players[0].actions
	bot.answers = [spot(0, 2)]
	await floop(0, 0)
	ok(g.players[0].creatures[2] != null and g.players[0].actions == a + 1, "Хаски на Аляске: земля соперника в той зоне заморожена, +1 действие")
	_fresh()
	await put(0, "boarder_collie", 0)
	a = g.players[0].actions
	bot.answers = [spot(0, 3)]
	await floop(0, 0)
	ok(g.players[0].actions == a, "Хаски на Аляске: без мороза действия нет")


func t_freezing_buildings() -> void:
	await build(0, "crystal_palace", 1)
	var e = await put(1, "cow", 3)
	e.perm_def = 5
	bot.answers = [spot(1, 3)]
	await g.freeze(1, 1)
	ok(e.damage == 2, "Хрустальный дворец: земля в его зоне замёрзла, 2 урона")
	await g.freeze(1, 2)
	ok(e.damage == 2, "Хрустальный дворец: другая зона не считается")
	_fresh()
	await build(0, "snow_business", 2)
	bot.answers = [spot(1, 2)]
	await g.cmd_activate(0, "building", 2)
	ok(g.is_frozen(1, 2) and g.players[0].actions == 1, "Бизнес-центр «Снежный»: 1 действие, земля в этой зоне")


func t_fish_optional() -> void:
	await put(0, "frozen_fish", 0)
	var e = await put(1, "cow", 0)
	e.perm_def = 10
	bot.skip_optional = true
	await g.cmd_attack(0, 0)
	ok(not g.is_frozen(0, 0) and not g.is_frozen(1, 0), "Отмороженная рыбка: можно не замораживать")
	_fresh()
	await put(0, "frozen_fish", 0)
	e = await put(1, "cow", 0)
	e.perm_def = 10
	await g.cmd_attack(0, 0)
	ok(g.is_frozen(0, 0) or g.is_frozen(1, 0), "Отмороженная рыбка: заморозила землю в зоне")


func t_frozen_damage() -> void:
	await put(0, "icemeister", 0)
	var a = await put(1, "cow", 1)
	a.perm_def = 5
	var b = await put(1, "cow", 2)
	b.perm_def = 5
	await g.freeze(1, 1)
	await g._start_effects(0)
	ok(a.damage == 1 and b.damage == 0, "Генерал Мороз: 1 урон только на замороженной земле")
	await put(0, "slay_rider", 3)
	await floop(0, 3)
	ok(a.damage == 4, "Бобзлей: 3 урона на замороженной земле")
	_fresh()
	var x = await put(1, "cow", 0)
	x.perm_def = 10
	await play(0, hand(0, "frozen_heart"))
	ok(x.damage == 1, "Холодное сердце: 1 урон")
	await g.freeze(1, 0)
	g.players[0].actions = 2
	await play(0, hand(0, "frozen_heart"))
	ok(x.damage == 4, "Холодное сердце: на замороженной земле 3")


func t_snow_angel_and_deer() -> void:
	var s = await put(0, "snow_angel", 0)
	s.perm_def = 10
	s.damage = 4
	var c = await put(0, "cow", 1)
	c.perm_def = 10
	c.damage = 1
	await g.freeze(1, 0)
	await g.freeze(1, 1)
	await floop(0, 0)
	ok(s.damage == 2 and c.damage == 0, "Снежный ангел: по 1 за каждую замороженную землю")
	await put(0, "reign_deer", 2)
	var n: int = g.players[0].hand.size()
	await floop(0, 2)
	ok(g.players[0].hand.size() == n + 2, "Королень: карта за каждую замороженную землю")


func t_spells() -> void:
	lands(0, "ice")
	bot.answers = [spot(1, 0)]
	await play(0, hand(0, "snow_way"))
	ok(g.frozen_count() == 2 and not bot.asked[1]["options"].has(spot(1, 0)), "Лыжню!: две разные земли")
	_fresh()
	lands(0, "ice")
	await g.freeze(1, 0)
	await g.freeze(1, 1)
	for i in 3:
		hand(1, "cow")
	await play(0, hand(0, "frosty_frolic"))
	ok(g.players[1].hand.size() == 1, "Зимние выкрутасы: по карте за каждую замороженную землю")
	_fresh()
	await put(0, "snow_dog", 1)
	await put(0, "cow", 0)
	await put(0, "cow", 3)
	var a0: int = atk(0, 0)
	var a3: int = atk(0, 3)
	await floop(0, 1)
	ok(atk(0, 0) == a0 + 2 and atk(0, 3) == a3, "Хладная псина: +2 только соседям")
