extends "res://tests/cards_audit_base.gd"
## Card audit: Призмо. See docs/CARDS_AUDIT.md. Most of the deck is in tests/cards_test.gd.


func t_sand_synergy_types() -> void:
	lands(0, "sandy")
	await put(0, "sand_knights", 0)
	await put(0, "cow", 1)
	await put(1, "husker_knight", 0)
	await put(1, "corn_dog", 1)
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "sand_synergy"))
	ok(g.players[0].hand.size() == n + 2, "Песчаная синергия: разные типы земель, радужное не считается")


func t_non_plain_cards() -> void:
	await put(0, "duplicast_sorcerer", 0)
	var e = await put(1, "cow", 0)
	e.perm_def = 5
	ok(not g.can_floop(0, "creature", 0), "Колдун двойных чар: неравнинных карт не было")
	g.players[0].turn["played_lands"] = ["corn", "sandy"]
	if g.played_not(0, "plain") >= 2:
		await floop(0, 0)
		ok(e.damage == 2, "Колдун двойных чар: 2 урона каждому существу соперника")
	else:
		ok(false, "played_lands не тот ключ")
	_fresh()
	var m = await put(0, "spellbound_mystic", 1)
	var x = await put(0, "cow", 2)
	x.perm_def = 5
	x.damage = 3
	await g._trigger_own(0, "end_")
	ok(x.damage == 3, "Зачарованный мистик: без 2 неравнинных карт ничего")
	g.players[0].turn["played_lands"] = ["corn", "sandy"]
	await g._trigger_own(0, "end_")
	ok(x.damage == 1, "Зачарованный мистик: 2 урона с соседа")


func t_clampire() -> void:
	var c = await put(0, "clampire_sanguine_shell", 0)
	var x = await put(0, "cow", 3)
	x.perm_def = 5
	x.damage = 2
	bot.answers = [spot(0, 3)]
	await g.cmd_attack(0, 0)
	ok(x.damage == 1, "Мидиляк: нападает, 1 урон снят с дружественного")
