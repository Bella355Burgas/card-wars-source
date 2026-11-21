extends "res://tests/cards_audit_base.gd"
## Card audit: «Земля легенд». See docs/CARDS_AUDIT.md. Most of the set is in tests/cards_test.gd.


func t_eye_see_all_choice() -> void:
	lands(0, "plain")
	var a = top(0, "husker_knight")
	var b = top(0, "corn_dog")
	var c = top(0, "gnome_snot")
	var d = top(0, "cow")
	var e = top(0, "woadic_chief")
	bot.answers = [e.uid, b.uid]
	await play(0, hand(0, "eye_see_all"))
	var h: Array = g.players[0].hand
	ok(h.has(b) and not h.has(a), "Всевидящее око: из двух кукурузных выбирает игрок")
	ok(h.has(e) and not h.has(c) and not h.has(d), "Всевидящее око: по одной карте типа, радужная в сброс")
	ok(g.players[0].discard.has(a) and g.players[0].discard.has(c) and g.players[0].discard.has(d), "Всевидящее око: остальные сброшены")


func t_penguin_own_heal_only() -> void:
	var pg = await put(0, "puffy_penguin", 0)
	pg.damage = 3
	var x = await put(0, "cow", 1)
	await g.heal_creature(0, 0, 1, 1)
	ok(g.tokens(x, "atk_tok") == 0, "Пухлый пингвин: урон снял соперник, жетонов нет")
	await g.heal_creature(0, 0, 1, 0)
	ok(g.tokens(x, "atk_tok") == 1 and g.tokens(pg, "atk_tok") == 1, "Пухлый пингвин: снял ты, жетон каждому своему")
	await g.heal_creature(0, 0, 1)
	ok(g.tokens(x, "atk_tok") == 2, "Пухлый пингвин: своя способность без указания игрока тоже считается")


func t_hot_box_any_leave() -> void:
	await build(0, "hot_box", 1)
	var e = await put(1, "cow", 1)
	var hp: int = g.players[1].hp
	var n: int = g.players[0].hand.size()
	await g.move_creature(1, 1, 3)
	ok(g.players[1].hp == hp - 2 and g.players[0].hand.size() == n + 1, "Пекло: существо соперника перешло в другую зону")
	await g.move_creature(1, 3, 2)
	ok(g.players[1].hp == hp - 2, "Пекло: уход из чужой зоны не считается")
	_fresh()
	await build(0, "hot_box", 1)
	var mine = await put(1, "cow", 1, 0)
	hp = g.players[0].hp
	await g.destroy_creature(1, 1)
	ok(g.players[0].hp == hp - 2, "Пекло: моё существо под контролем соперника ушло, урон мне")
	_fresh()
	await build(0, "hot_box", 1)
	e = await put(1, "cow", 1)
	await put(1, "cow", 3)
	hp = g.players[1].hp
	await g.swap_creatures(1, 1, 3)
	ok(g.players[1].hp == hp - 2, "Пекло: обмен зонами, ушедшее из этой зоны существо считается")
	_fresh()
	await build(0, "hot_box", 1)
	e = await put(1, "cow", 1)
	hp = g.players[1].hp
	await g.take_control(1, 1, 0, 3)
	ok(g.players[1].hp == hp - 2, "Пекло: существо забрали на другую сторону, тоже уход")
