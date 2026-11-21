extends "res://tests/cards_audit_base.gd"
## Card audit: Джейк (Кукурузные поля). See docs/CARDS_AUDIT.md.


func t_reaper_choice() -> void:
	var e = await put(1, "cow", 1)
	var r = await put(0, "field_reaper", 1)
	ok(g.players[0].creatures[0] == e or g.players[0].creatures[2] == e, "Жнец: по умолчанию забирает существо напротив")
	_fresh()
	e = await put(1, "cow", 1)
	bot.answers = [spot(0, 1), spot(0, 2)]
	r = await put(0, "field_reaper", 1)
	ok(g.players[0].creatures[2] == r and g.players[1].creatures[1] == e, "Жнец: можно выбрать и передвинуть самого Жнеца")
	_fresh()
	await put(0, "cow", 0)
	await put(0, "cow", 2)
	e = await put(1, "cow", 1)
	await put(0, "field_reaper", 1)
	ok(g.players[1].creatures[1] == e, "Жнец: рядом нет пустой зоны, ничего не происходит")
	_fresh()
	r = await put(0, "field_reaper", 1)
	ok(g.players[0].creatures[0] == r or g.players[0].creatures[2] == r, "Жнец: напротив пусто, Жнец переходит сам")


func t_reaper_needs_discard() -> void:
	lands(0, "corn")
	var r = hand(0, "field_reaper")
	ok(not g.can_play(0, r.uid), "Жнец: без другой карты в руке сыграть нельзя")
	hand(0, "cow")
	ok(g.can_play(0, r.uid), "Жнец: со второй картой можно")


func t_corn_counts() -> void:
	lands(0, "corn")
	lands(1, "plain")
	await put(0, "corn_dog", 0)
	var d = mk("corn_dog")
	ok(df(0, 0) == d.def()["def"] + 4 and atk(0, 0) == d.def()["atk"], "Кукутузик: 4 поля, +4 защиты, без +1 к атаке")
	g.players[0].lands[3]["type"] = "plain"
	ok(df(0, 0) == d.def()["def"] + 3 and atk(0, 0) == d.def()["atk"] + 1, "Кукутузик: 3 поля, +1 к атаке")
	g.players[0].lands[2]["flipped"] = true
	ok(df(0, 0) == d.def()["def"] + 2, "Кукутузик: перевёрнутое поле не считается")
	_fresh()
	lands(0, "corn")
	lands(1, "corn")
	await put(0, "wall_of_ears", 0)
	ok(df(0, 0) == mk("wall_of_ears").def()["def"] + 8, "Стена початков: поля всех игроков")
	_fresh()
	mixed_lands()
	await put(0, "corn_ronin", 1)
	ok(atk(0, 1) == mk("corn_ronin").def()["atk"] + 2, "Кукурузный ронин: два соседних поля")
	await put(0, "corn_lord", 3)
	ok(atk(0, 3) == mk("corn_lord").def()["atk"] + 1, "Царь полей: другое кукурузное существо")


func mixed_lands() -> void:
	for l in 4:
		g.players[0].lands[l]["type"] = "corn" if l != 1 else "plain"


func t_legion_optional() -> void:
	var e = await put(1, "cow", 0)
	bot.skip_optional = true
	await put(0, "legion_of_earlings", 0)
	ok(g.players[1].creatures[0] == e, "Легион початочков: можно не возвращать")
	_fresh()
	e = await put(1, "cow", 0)
	await put(0, "legion_of_earlings", 0)
	ok(g.players[1].creatures[0] == null and g.players[1].hand.has(e), "Легион початочков: существо на руке владельца")


func t_pumpkin_once_each() -> void:
	lands(0, "corn")
	await put(0, "patchy_pumpkin", 0)
	var a = await put(1, "cow", 0)
	a.perm_def = 10
	var b = await put(1, "cow", 1)
	b.perm_def = 10
	bot.answers = [spot(1, 0), spot(1, 1)]
	await floop(0, 0)
	ok(a.damage == 1 and b.damage == 1, "Тыквустьер: по 1 урону, каждое существо один раз")
	ok(bot.asked.size() == 2, "Тыквустьер: уже выбранные не предлагаются")
	# Спорное (docs/CARDS_AUDIT.md): when only its own creatures are left, each extra hit must go to one of them.
	ok(g.players[0].creatures[0].damage == 1, "Тыквустьер: оставшиеся удары идут по своим существам")


func t_farmer_and_stalker() -> void:
	hand(1, "cow")
	hand(1, "cow")
	var hp: int = g.players[1].hp
	await put(0, "travelin_farmer", 0)
	await g.destroy_creature(0, 0)
	ok(g.players[1].hp == hp - 2, "Фермер-покатун: урон по числу карт на руке соперника")
	await put(0, "field_stalker", 0)
	var n0: int = g.players[0].hand.size()
	var n1: int = g.players[1].hand.size()
	await g._start_effects(0)
	ok(g.players[0].hand.size() == n0 + 1 and g.players[1].hand.size() == n1 + 1, "Призрак полей: каждый игрок берёт карту")


func t_reclaim_optional() -> void:
	g.players[0].lands[0]["flipped"] = true
	await build(0, "blood_fortress", 1)
	bot.skip_optional = true
	await play(0, hand(0, "reclaim_landscape"))
	ok(g.players[0].lands[0]["flipped"] and g.players[0].buildings[1] != null, "Поднятие целины: оба шага необязательны")
	_fresh()
	g.players[0].lands[0]["flipped"] = true
	var b = await build(0, "blood_fortress", 1)
	bot.answers = [spot(0, 0), spot(0, 1), spot(0, 3)]
	await play(0, hand(0, "reclaim_landscape"))
	ok(not g.players[0].lands[0]["flipped"] and g.players[0].buildings[3] == b, "Поднятие целины: земля открыта, строение перемещено")


func t_silo_and_archer() -> void:
	await build(0, "silo_of_truth", 0)
	ok(not g.can_activate(0, "building", 0), "Амбар истины: у соперника пустая рука")
	hand(1, "gnome_snot")
	ok(g.can_activate(0, "building", 0), "Амбар истины: есть что красть")
	var n: int = g.players[0].hand.size()
	await g.cmd_activate(0, "building", 0)
	ok(g.players[1].hand.is_empty() and g.players[0].hand.size() == n + 3 and g.players[0].actions == 0, "Амбар истины: 2 действия, украл и разыграл бесплатно")
	_fresh()
	await put(0, "archer_dan", 1)
	ok(not g.can_floop(0, "creature", 1), "Лучник Дэн: в зоне нет строений")
	await build(1, "blood_fortress", 1)
	await floop(0, 1)
	ok(g.players[1].buildings[1] == null, "Лучник Дэн: строение соперника в этой зоне уничтожено")
