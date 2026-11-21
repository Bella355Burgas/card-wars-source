extends "res://tests/cards_audit_base.gd"
## Card audit: Принцесса Бубльгум (Милые земли). See docs/CARDS_AUDIT.md.


func t_exact_damage() -> void:
	for row in [["albino_eyebat", 2, 2], ["angel_heart", 3, 3], ["cotton_eyebat", 4, 4], ["ms_fluff", 7, 7]]:
		var c = await put(0, row[0], 0)
		c.perm_def = 20
		var base: int = atk(0, 0)
		c.damage = row[1] - 1
		var under: int = atk(0, 0)
		c.damage = row[1]
		var at: int = atk(0, 0)
		c.damage = row[1] + 1
		var over: int = atk(0, 0)
		ok(under == base and at == base + row[2] and over == base, "%s: бонус только при уроне ровно %d" % [c.card_name(), row[1]])
		g.players[0].creatures[0] = null


func t_no_damage_bonuses() -> void:
	var w = await put(0, "wall_of_chocolate", 0)
	var base: int = atk(0, 0)
	w.damage = 1
	ok(atk(0, 0) == base - 3, "Стена шоколада: +3 только без урона")
	var c = await put(0, "cow", 1)
	var cb: int = atk(0, 1)
	await build(0, "windmill_of_health", 1)
	ok(atk(0, 1) == cb + 2, "Мельница процветания: +2 существу без урона")
	c.damage = 1
	ok(atk(0, 1) == cb, "Мельница процветания: с уроном бонуса нет")


func t_angels() -> void:
	var a = await put(0, "angel_of_vanilla", 0)
	ok(not g.can_activate(0, "creature", 0), "Ванильный ангел: без урона нечего снимать")
	a.damage = 3
	await g.cmd_activate(0, "creature", 0)
	ok(a.damage == 0 and g.players[0].actions == 1, "Ванильный ангел: 1 действие, весь урон снят")
	var b = await put(0, "angel_of_chocolate", 1)
	b.damage = 2
	await g.cmd_activate(0, "creature", 1)
	ok(b.damage == 0 and g.players[0].actions == 0, "Шоколадный ангел: 1 действие, весь урон снят")


func t_apple_pieclops_each() -> void:
	await put(0, "apple_pieclops", 0)
	var x = await put(0, "cow", 1)
	x.damage = 1
	x.perm_def = 5
	var y = await put(0, "cow", 2)
	y.perm_def = 5
	bot.answers = ["Ничего", "Восстановить 1", "Нанести 1 урон"]
	await g._start_effects(0)
	ok(g.players[0].creatures[0].damage == 0 and x.damage == 0 and y.damage == 1, "Яблочный пироклоп: выбор для каждого существа, можно ничего")


func t_falling_star_combat_only() -> void:
	lands(0, "cute")
	var mine = await put(0, "cow", 0)
	mine.perm_def = 10
	await put(1, "cow", 0)
	g.players[1].creatures[0].perm_atk = 5
	await play(0, hand(0, "falling_star"))
	await g.cmd_attack(0, 0)
	ok(mine.damage == 0, "Падающая звезда: защитник не наносит урона")


func t_ring_and_shepard() -> void:
	lands(0, "cute")
	var c = await put(0, "cow", 0)
	c.perm_def = 10
	c.damage = 3
	var base: int = atk(0, 0)
	await play(0, hand(0, "ring_of_fluffy"))
	ok(atk(0, 0) == base + 3, "Кольцо пушистости: +X по урону")
	_fresh()
	await put(0, "fairy_shepard", 1)
	var cute = await put(0, "cutie", 0)
	var other = await put(0, "cow", 2)
	ok(df(0, 0) == cute.def()["def"] + 2 and df(0, 2) == other.def()["def"], "Фей-чабан: +2 только доброму соседу")


func t_start_effects() -> void:
	var r = await put(0, "niceasaurus_rex", 0)
	var n: int = g.players[0].hand.size()
	await g._start_effects(0)
	ok(g.players[0].hand.size() == n, "Доброзавр Рекс: без урона карты нет")
	r.damage = 1
	await g._start_effects(0)
	ok(g.players[0].hand.size() == n + 1, "Доброзавр Рекс: с уроном берёт карту")
	_fresh()
	g.players[0].hp = 10
	g.players[0].lands[0]["type"] = "cute"
	g.players[0].lands[1]["type"] = "corn"
	g.players[0].lands[2]["type"] = "corn"
	g.players[0].lands[3]["type"] = "plain"
	await put(0, "rainbow_eyebat", 0)
	await g._start_effects(0)
	ok(g.players[0].hp == 13, "Радужный крылоглаз: жизнь за каждый тип земель")
	g.players[0].hp = 25
	await put(0, "cutie", 1)
	await floop(0, 1)
	ok(g.players[0].hp == 25, "Милашка: не больше 25")


func t_snakemint_and_candy() -> void:
	await put(0, "snakemint", 0)
	g.players[0].hp = 10
	var hp: int = g.players[1].hp
	await g.cmd_attack(0, 0)
	ok(g.players[0].hp == 10 + (hp - g.players[1].hp), "Мятнозмей: лечит столько, сколько нанёс")
	_fresh()
	var e = await put(1, "cow", 0)
	e.perm_def = 5
	bot.answers = ["Нанести 1 урон"]
	await play(0, hand(0, "green_candy"))
	ok(e.damage == 1, "Зелёная сахарная вата: можно нанести урон чужому существу")
