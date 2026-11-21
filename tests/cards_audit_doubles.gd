extends "res://tests/cards_audit_base.gd"
## Card audit: «Парный турнир» (2 на 2). See docs/CARDS_AUDIT.md. Most of the set is in tests/cards_test.gd.


func t_lemon_aid_each_once() -> void:
	lands(0, "ice")
	var a = await put(0, "cow", 0)
	a.perm_def = 9
	a.damage = 3
	var b = await put(0, "cow", 1)
	b.perm_def = 9
	b.damage = 3
	await g.freeze(1, 0)
	await g.freeze(1, 1)
	await g.freeze(1, 2)
	await play(0, hand(0, "frozen_lemon_aid"))
	ok(a.damage == 2 and b.damage == 2, "Замороженный лимонад: каждое существо по одному разу")


func t_jinx_picks_players() -> void:
	_fresh(["finn", "jake", "pb", "bmo"])
	for s in 4:
		hand(s, "cow" if s != 2 else "husker_knight")
	bot.answers = [g.players[2].name, g.players[3].name]
	await play(0, hand(0, "jinx"))
	ok(g.players[2].hand.is_empty() and g.players[3].hand.is_empty() and g.players[1].hand.size() == 1,
		"Сглаз: показывают карты выбранные игроки")
	_fresh()
	hand(0, "cow")
	hand(1, "husker_knight")
	await play(0, hand(0, "jinx"))
	ok(g.players[0].hand.is_empty() and g.players[1].hand.is_empty() and bot.asked.is_empty(), "Сглаз: вдвоём ничего не спрашивает")
	# Bug report: на троих the game picked the players itself, the caster wants two foes.
	_fresh(["finn", "jake", "pb"])
	hand(0, "cow")
	hand(1, "cow")
	hand(2, "husker_knight")
	bot.answers = [g.players[1].name, g.players[2].name]
	await play(0, hand(0, "jinx"))
	ok(bot.asked.size() == 2 and bot.asked[0]["options"].size() == 3 and bot.asked[1]["options"].size() == 2,
		"Сглаз на троих: игрок выбирает первого из трёх и второго из двух")
	ok(g.players[1].hand.is_empty() and g.players[2].hand.is_empty() and g.players[0].hand.size() == 1,
		"Сглаз на троих: два соперника сбрасывают, своя карта остаётся")


func t_untested_doubles() -> void:
	var c = await put(0, "chocolate_tacody", 0)
	var e = await put(1, "cow", 1)
	e.perm_def = 5
	await g.cmd_begin_attack(0)
	ok(e.damage == 0, "Шоколадный ТаКоди: без мороза в зоне ничего")
	_fresh()
	await put(0, "chocolate_tacody", 0)
	e = await put(1, "cow", 1)
	e.perm_def = 5
	await g.freeze(1, 0)
	bot.answers = [g.players[1].name]
	await g.cmd_begin_attack(0)
	ok(e.damage == 1, "Шоколадный ТаКоди: мороз в зоне, 1 урон каждому существу выбранного игрока")
	_fresh()
	var geo = await put(0, "geomancer", 0)
	bot.skip_optional = true
	await g._start_effects(0)
	ok(g.players[0].creatures[0] == geo, "Геомант: можно остаться")
	bot.skip_optional = false
	bot.answers = [{"p": 0, "lane": 2}]
	await g._start_effects(0)
	ok(g.players[0].creatures[2] == geo, "Геомант: переходит на пустую землю")
	_fresh()
	var s = await put(0, "shielded_zebracorn", 1)
	var n = await put(0, "cow", 2)
	n.perm_def = 5
	n.damage = 2
	await g.cmd_attack(0, 1)
	ok(n.damage == 1, "Щитоносный ЗеброРог: нападает, 1 урон снят с соседа")
	_fresh()
	var hp: int = g.players[1].hp
	await put(0, "grizzled_zebracorn", 0)
	await put(1, "cow", 0)
	g.players[1].creatures[0].perm_def = 20
	await g.cmd_attack(0, 0)
	ok(g.players[1].hp == hp - 2, "Седой ЗеброРог: 2 урона сопернику при нападении")


func t_cuddle_puddle_bonus_only_for_spell() -> void:
	lands(0, "cute")
	var a = await put(0, "cow", 1)
	a.perm_atk = 3
	a.perm_def = 9
	var x = await put(1, "cow", 1)
	x.perm_atk = 3
	x.perm_def = 9
	var before: int = atk(0, 1)
	await play(0, hand(0, "cuddle_puddle"))
	ok(x.damage == before + 1 and a.damage == atk(1, 1), "Лужица обнимашек: свои бьют с +1, чужие без")
	ok(atk(0, 1) == before, "Лужица обнимашек: +1 пропадает после заклинания")
	ok(not a.exhausted, "Лужица обнимашек: это не нападение, существо не повёрнуто")


func t_fluffy_fox_per_turn() -> void:
	var f = await put(0, "fluffy_fox", 3)
	f.perm_def = 20
	f.damage = 4
	var y = await put(1, "cow", 3)
	await g.damage_creature(0, 3, 1, {"kind": "combat", "p": 1, "card": y})
	ok(f.damage == 4, "Пушистый лис: первый урон проигнорирован")
	await g.damage_creature(0, 3, 3, {"kind": "combat", "p": 1, "card": y})
	ok(f.damage == 6, "Пушистый лис: за ход игнорируется всего 2 урона")
	await g.damage_creature(0, 3, 2, {"kind": "combat", "p": 1, "card": y})
	ok(f.damage == 8, "Пушистый лис: дальше урон проходит")
	g.turn_number += 1
	await g.damage_creature(0, 3, 2, {"kind": "combat", "p": 1, "card": y})
	ok(f.damage == 8, "Пушистый лис: в новый ход снова 2")


func t_fluffy_fox_sources() -> void:
	var f = await put(1, "fluffy_fox", 0)
	f.perm_def = 20
	f.damage = 4
	await put(0, "sharp_guy", 0)
	await floop(0, 0)
	ok(f.damage == 4, "Пушистый лис: урон от флюпа существа соперника игнорируется")
	bot.answers = [spot(1, 0)]
	await play(0, hand(0, "full_metal_racket"))
	ok(f.damage == 6, "Пушистый лис: урон от заклинания не игнорируется")
	_fresh()
	f = await put(1, "fluffy_fox", 0)
	f.perm_def = 20
	f.damage = 4
	await put(0, "sandsnake", 0)
	ok(f.damage == 6, "Пушистый лис: из 4 урона при входе существа игнорируются 2")
	_fresh()
	f = await put(1, "fluffy_fox", 0)
	f.perm_def = 20
	f.damage = 3
	await put(0, "sharp_guy", 0)
	await floop(0, 0)
	ok(f.damage == 5, "Пушистый лис: меньше 4 урона, ничего не игнорирует")
