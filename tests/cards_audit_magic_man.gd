extends "res://tests/cards_audit_base.gd"
## Card audit: Волшебник. See docs/CARDS_AUDIT.md. Most of the deck is in tests/cards_test.gd.


func t_bull_sigil_may_draw() -> void:
	var x = await put(0, "cow", 0)
	await g.add_atk_tokens(x)
	var n: int = g.players[0].hand.size()
	bot.answers = ["Не брать"]
	await play(0, hand(0, "bull_sigil"))
	ok(g.tokens(x, "atk_tok") == 2 and g.players[0].hand.size() == n, "Бычья печать: можно не брать карту")
	g.players[0].actions = 2
	await play(0, hand(0, "bull_sigil"))
	ok(g.players[0].hand.size() == n + 1, "Бычья печать: берёт карту")
	_fresh()
	x = await put(0, "cow", 0)
	await play(0, hand(0, "bull_sigil"))
	ok(g.players[0].hand.is_empty() and bot.asked.is_empty(), "Бычья печать: один жетон, карты нет")
