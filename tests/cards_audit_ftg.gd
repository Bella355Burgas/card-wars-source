extends "res://tests/cards_audit_base.gd"
## Card audit: «Во имя славы». See docs/CARDS_AUDIT.md. Most of the set is in tests/cards_test.gd.


func t_ghost_chest_burster_draws() -> void:
	await put(1, "golden_axe_stump", 0)
	var ogre = await put(0, "blue_ogre", 1)
	var base: int = atk(0, 1)
	var bottom = mk("cow")
	g.players[0].deck.push_front(bottom)
	var hp: int = g.players[0].hp
	await put(0, "ghost_chest_burster", 0)
	await g.destroy_creature(0, 0)
	ok(g.players[0].hand.has(bottom), "Призрачный мимимимик: нижняя карта колоды на руке")
	ok(g.players[0].hp == hp - 1, "Призрачный мимимимик: это взятие карты, Пень с золотым топором бьёт")
	ok(atk(0, 1) == base + 1, "Призрачный мимимимик: Синий огр видит взятую карту")


func t_land_vs_bonuses() -> void:
	lands(1, "corn")
	lands(0, "plain")
	await put(0, "cow", 0)
	var x = await put(1, "cow", 0)
	var base: int = g.combat_atk(0, 0, x, 0, true)
	await play(0, hand(0, "ring_of_third_eye"))
	ok(g.combat_atk(0, 0, x, 0, true) == base + 2, "Кольцо третьего глаза: +2 при нападении на кукурузное поле")
	ok(g.combat_atk(0, 0, x, 0, false) == base, "Кольцо третьего глаза: при защите бонуса нет")
	var g2 = await put(1, "ghost_tree", 1)
	var y = await put(0, "cow", 1)
	g.players[0].lands[1]["type"] = "corn"
	var gb: int = g.combat_atk(1, 1, y, 1, false)
	ok(gb == g.atk_of(1, 1) + 2 and g.combat_atk(1, 1, y, 1, true) == g.atk_of(1, 1), "Призрачное дерево: +2 только при защите от существа на кукурузном поле")
