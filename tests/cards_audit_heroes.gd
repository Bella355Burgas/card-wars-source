extends "res://tests/cards_audit_base.gd"
## Card audit: карты героев. See docs/CARDS_AUDIT.md. Most heroes are in tests/cards_test.gd and tests/rules_test.gd.


func t_me_mow_per_creature() -> void:
	g.players[0].hero_card = "me_mow"
	var a = await put(1, "cow", 0)
	a.perm_def = 9
	var b = await put(1, "cow", 1)
	b.perm_def = 9
	var d: int = g.players[1].deck.size()
	await g.damage_creature(1, 0, 1, {"kind": "effect", "p": 0})
	await g.damage_creature(1, 0, 1, {"kind": "effect", "p": 0})
	ok(g.players[1].deck.size() == d - 1, "Мяу-Мяу: одно существо, второй раз за ход не срабатывает")
	await g.damage_creature(1, 1, 1, {"kind": "effect", "p": 0})
	ok(g.players[1].deck.size() == d - 2, "Мяу-Мяу: другое существо соперника, срабатывает снова")
	await g.damage_creature(1, 1, 2, {"kind": "effect", "p": 0})
	ok(g.players[1].deck.size() == d - 2, "Мяу-Мяу: 2 урона не считаются")


func t_jake_2x2_own_lanes() -> void:
	_fresh(["finn", "jake", "pb", "bmo"])
	g.turn_number = 9
	g.players[0].hero_card = "jake_2x2"
	await put(0, "cow", 0)
	g.players[0].creatures[0].perm_atk = 3
	var far = null
	for s in [1, 3]:
		for l in 4:
			if s == 1 and l == 3:
				continue
			far = await put(s, "cow", l)
	await g.cmd_attack(0, 0)
	var asked: Array = bot.asked.filter(func(r): return String(r.get("prompt", "")).begins_with("Джейк"))
	var opts: Array = asked[0]["options"] if not asked.is_empty() else []
	var bad := opts.filter(func(o): return not range(4).any(func(ml): return g.on_lane(0, ml, int(o["p"]), int(o["lane"]))))
	ok(not asked.is_empty() and bad.is_empty(), "Джейк (Парный турнир): только существа в своих зонах")
	var foes_total := 0
	for s in [1, 3]:
		foes_total += g.creature_count(s)
	ok(opts.size() < foes_total + 1, "Джейк (Парный турнир): существа второго соперника вне своих зон не предлагаются (%d из %d)" % [opts.size(), foes_total + 1])
	ok(far != null, "…")
