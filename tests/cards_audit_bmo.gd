extends "res://tests/cards_audit_base.gd"
## Card audit: Бимо (Бесплодные болота). See docs/CARDS_AUDIT.md.


func fill_discard(p: int, n: int) -> void:
	for i in n:
		dis(p, "cow")


func t_chest_burster_each_foe() -> void:
	_fresh(["finn", "jake", "bmo"])
	await put(0, "chest_burster", 0)
	hand(2, "cow")
	var h1: int = g.players[1].hp
	var h2: int = g.players[2].hp
	await g._start_effects(0)
	ok(g.players[1].hp == h1 - 3 and g.players[2].hp == h2, "Мимимимик на троих: 3 урона только сопернику без карт")
	g.players[2].hand.clear()
	await g._start_effects(0)
	ok(g.players[1].hp == h1 - 6 and g.players[2].hp == h2 - 3, "Мимимимик на троих: каждому сопернику без карт")
	_fresh()
	await put(0, "chest_burster", 0)
	hand(1, "cow")
	var hp: int = g.players[1].hp
	await g._start_effects(0)
	ok(g.players[1].hp == hp, "Мимимимик: у соперника есть карта, урона нет")


func t_discard_fives() -> void:
	await put(0, "dark_angel", 0)
	await put(0, "mouthball", 1)
	var a: int = atk(0, 0)
	var d: int = df(0, 1)
	fill_discard(0, 9)
	ok(atk(0, 0) == a + 1 and df(0, 1) == d + 2, "Тёмный ангел и Шарот: за каждые 5 карт")
	fill_discard(0, 1)
	ok(atk(0, 0) == a + 2 and df(0, 1) == d + 4, "Тёмный ангел и Шарот: 10 карт")


func t_hot_eyebat_teeth_leaf() -> void:
	lands(0, "swamp")
	var h = hand(0, "hot_eyebat")
	fill_discard(0, 9)
	ok(not g.can_play(0, h.uid), "Пригоревший крылоглаз: 9 карт в сбросе мало")
	var t = hand(0, "teeth_leaf")
	ok(g.cost_of(0, t) == 2, "Остролист: 9 карт, полная цена")
	fill_discard(0, 1)
	ok(g.can_play(0, h.uid), "Пригоревший крылоглаз: 10 карт")
	ok(g.cost_of(0, t) == 0, "Остролист: на 2 меньше")


func t_ogre_gas() -> void:
	var a = top(0, "cow")
	var b = top(0, "sheep")
	var c = top(0, "phyllis")
	bot.answers = [b.uid]
	await play(0, hand(0, "ogre_gas"))
	ok(g.players[0].deck.front() == b and g.players[0].discard.has(a) and g.players[0].discard.has(c), "Газы огра: одна вниз, две в сброс")
	_fresh()
	g.players[0].deck.clear()
	var only = top(0, "cow")
	await play(0, hand(0, "ogre_gas"))
	ok(g.players[0].deck.size() == 1 and g.players[0].deck[0] == only, "Газы огра: одна карта в колоде остаётся внизу")


func t_dr_death_pays() -> void:
	await put(0, "dr_death", 0)
	var mine = await put(0, "cow", 1)
	ok(not g.can_floop(0, "creature", 0), "Док Смерть: напротив пусто")
	await put(1, "cow", 0)
	bot.answers = [spot(0, 1)]
	await floop(0, 0)
	ok(g.players[0].creatures[1] == null and g.players[1].creatures[0] == null, "Док Смерть: своё существо платит, чужое уничтожено")


func t_merman_and_mermaid() -> void:
	await put(0, "green_merman", 0)
	var e = await put(1, "cow", 0)
	e.perm_def = 10
	top(0, "husker_knight")
	await floop(0, 0)
	ok(e.damage == 2, "Зелёный русал: урон по стоимости сброшенной карты")
	await put(0, "green_mermaid", 1)
	await g.cmd_activate(0, "creature", 1)
	ok(g.players[0].creatures[1] == null and e.damage == 3, "Зелёная русалка: уничтожает себя, 1 урон каждому")


func t_spirit_tower_returns() -> void:
	await build(0, "spirit_tower", 1)
	var e = await put(1, "cow", 1)
	e.exhausted = true
	await floop(0, 1, "building")
	ok(g.players[0].creatures[1] == e and not e.exhausted and g.players[0].actions == 1, "Башня духа: 1 действие, существо перешло и готово")
	await g._end_turn_cleanup(0)
	ok(g.players[1].creatures[1] == e and g.players[0].creatures[1] == null, "Башня духа: в конце хода вернулось")
	_fresh()
	await build(0, "spirit_tower", 1)
	await put(0, "cow", 1)
	await put(1, "cow", 1)
	ok(not g.can_floop(0, "building", 1), "Башня духа: своё существо в зоне, флюпа нет")


func t_returns_and_discards() -> void:
	await put(0, "red_eyeling", 0)
	dis(0, "husker_knight")
	ok(not g.can_floop(0, "creature", 0), "Красный дьяволёнок: нет карт стоимостью 0")
	var z = dis(0, "cow")
	await floop(0, 0)
	ok(g.players[0].hand.has(z), "Красный дьяволёнок: карта стоимостью 0 на руке")
	_fresh()
	fill_discard(0, 10)
	hand(1, "cow")
	hand(1, "cow")
	hand(1, "cow")
	await put(0, "mace_stump", 0)
	await g.cmd_activate(0, "creature", 0)
	ok(g.players[1].hand.size() == 1, "Ошарашенный пень: 2 карты за 10 в сбросе (сброс %d)" % g.players[0].discard.size())
	var hp: int = g.players[1].hp
	await put(0, "extraordinary_spider", 1)
	await g._start_effects(0)
	ok(g.players[1].hp == hp - 2, "Удивительный нечеловек-паук: урон за каждые 5 карт")


func t_bone_wand_needs_swamp() -> void:
	lands(0, "swamp")
	var w = hand(0, "bone_wand")
	ok(not g.can_play(0, w.uid), "Костяная палочка: без болотного существа нельзя")
	await put(0, "gray_eyebat", 0)
	ok(g.can_play(0, w.uid), "Костяная палочка: есть болотное существо")
	ok(not g.can_activate(0, "creature", 0), "Серый крылоглаз: в сбросе нет болотных существ")
