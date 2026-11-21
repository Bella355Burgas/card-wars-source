extends "res://tests/cards_audit_base.gd"
## Card audit: Лич. See docs/CARDS_AUDIT.md. Most of the deck is in tests/cards_test.gd.


func t_icefang_may_draw() -> void:
	await put(0, "icefang_avalancheetah", 0)
	hand(1, "cow")
	var n: int = g.players[0].hand.size()
	bot.answers = ["Не брать"]
	await g.force_discard(1, 1)
	ok(g.players[0].hand.size() == n, "Лавиногепард Ледяной Клык: можно не брать")
	hand(1, "cow")
	await g.force_discard(1, 1)
	ok(g.players[0].hand.size() == n + 1, "Лавиногепард Ледяной Клык: берёт карту")
	g.players[0].hand.clear()
	await g.discard_card(0, hand(0, "cow"))
	ok(g.players[0].hand.is_empty(), "Лавиногепард Ледяной Клык: свой сброс не считается")
