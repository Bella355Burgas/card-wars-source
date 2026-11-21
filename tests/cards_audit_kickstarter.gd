extends "res://tests/cards_audit_base.gd"
## Card audit: промо и Kickstarter. See docs/CARDS_AUDIT.md. Most of the set is in tests/cards_test.gd.


func t_party_energy_choice() -> void:
	lands(0, "sandy")
	var a = await put(0, "woadic_marauder", 0)
	var b = await put(0, "cow", 1)
	var base: int = atk(0, 0)
	var n: int = g.players[0].hand.size()
	bot.answers = [{"p": 0, "lane": 3}, {"p": 0, "lane": 0}]
	await play(0, hand(0, "party_energy"))
	ok(g.players[0].creatures[3] == a and g.players[0].creatures[0] == b, "Энергия вечеринки: игрок выбирает новые зоны")
	ok(g.atk_of(0, 3) == base + 2 and a.moved_this_turn, "Энергия вечеринки: +2 к атаке, существо сменило зону")
	ok(g.players[0].hand.size() == n + 1, "Энергия вечеринки: Синюшный злопыхатель берёт карту")
	_fresh()
	lands(0, "sandy")
	for l in 4:
		await put(0, "cow", l)
	var old: Array = g.players[0].creatures.duplicate()
	await play(0, hand(0, "party_energy"))
	var moved := true
	for l in 4:
		if g.players[0].creatures[l] == old[l] or g.players[0].creatures[l] == null:
			moved = false
	ok(moved, "Энергия вечеринки: четыре существа, каждое в новой зоне")
