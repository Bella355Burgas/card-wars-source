extends "res://tests/cards_audit_base.gd"
## Card audit: Фионна (Синие равнины). See docs/CARDS_AUDIT.md.


func t_business_dog_words() -> void:
	await put(0, "business_dog", 0)
	var base: int = atk(0, 0)
	g.players[0].turn["played"] = ["sand_angel", "ice_sing", "motley_otters", "sandasaurus_rex"]
	ok(atk(0, 0) == base, "Пёс-бизнесмен: «Песчаный», «Песнь», «Пёстрые» не считаются")
	g.players[0].turn["played"] = ["the_dog", "ultra_dog", "patched_puppy", "puppy_parade", "fire_dog"]
	ok(atk(0, 0) == base + 10, "Пёс-бизнесмен: Пёс, Ультрапёс, щенок, Щенячий парад, Огненный пёс")
	g.turn_player = 1
	ok(atk(0, 0) == base, "Пёс-бизнесмен: в чужой ход бонуса нет")


func t_retriever_may_draw() -> void:
	await put(0, "emboldened_retriever", 0)
	top(0, "cow")
	bot.answers = ["Не брать"]
	await g.cmd_attack(0, 0)
	ok(g.players[0].hand.is_empty(), "Осмелевший ретривер: можно не брать карту")
	_fresh()
	await put(0, "emboldened_retriever", 0)
	top(0, "cow")
	await g.cmd_attack(0, 0)
	ok(g.players[0].hand.size() == 1, "Осмелевший ретривер: берёт карту")


func t_ferret_rainbow_action() -> void:
	await put(0, "fiddling_ferret", 0)
	var r = top(0, "cow")
	var a: int = g.players[0].actions
	bot.answers = [r.uid]
	await floop(0, 0)
	ok(g.players[0].discard.has(r) and g.players[0].actions == a + 1, "Хорёк-скрипач: сбросил радужную, +1 действие")
	_fresh()
	await put(0, "fiddling_ferret", 0)
	var x = top(0, "gnome_snot")
	a = g.players[0].actions
	await floop(0, 0)
	ok(g.players[0].discard.has(x) and g.players[0].actions == a, "Хорёк-скрипач: не радужная, без действия")


func t_possum_optional() -> void:
	var o = hand(0, "impossible_possum")
	var x = hand(0, "cow")
	bot.skip_optional = true
	await g.discard_card(0, o)
	ok(g.players[0].discard.has(o) and g.players[0].hand.has(x), "Невозможный опоссум: можно остаться в сбросе")
	_fresh()
	o = hand(0, "impossible_possum")
	x = hand(0, "cow")
	await g.discard_card(0, o)
	ok(g.players[0].hand.has(o) and g.players[0].discard.has(x), "Невозможный опоссум: сброс карты возвращает его")


func t_panda_and_swashbuckler() -> void:
	top(0, "cow")
	await put(0, "lonely_panda", 0)
	ok(g.players[0].hand.size() == 1, "Одинокая панда: одна, берёт карту")
	_fresh()
	top(0, "cow")
	await put(0, "cow", 1)
	await put(0, "lonely_panda", 0)
	ok(g.players[0].hand.is_empty(), "Одинокая панда: не одна, карты нет")
	_fresh()
	var e = await put(1, "cow", 0)
	e.perm_def = 5
	await put(0, "psionic_swashbuckler", 0)
	ok(e.damage == 0, "Пси-головорез: только флюпнутое")
	e.flooped = true
	bot.skip_optional = true
	await put(0, "psionic_swashbuckler", 1)
	ok(e.damage == 0, "Пси-головорез: можно отказаться")
	bot.skip_optional = false
	await put(0, "psionic_swashbuckler", 2)
	ok(e.damage == 3, "Пси-головорез: 3 урона флюпнутому")


func t_the_dog_blanks() -> void:
	await put(0, "the_dog", 0)
	await put(1, "cow", 0)
	var c1: int = df(1, 0)
	await build(1, "celestial_castle", 0)
	ok(df(1, 0) == c1 + 3, "Небесный замок работает")
	await floop(0, 0)
	ok(df(1, 0) == c1, "Пёс флюпнут: строение соперника без способностей")


func t_matriarch_cat_lady_infant() -> void:
	await put(0, "woadic_matriarch", 0)
	var base: int = atk(0, 0)
	await put(0, "cow", 1)
	ok(atk(0, 0) == base + 1, "Синюшная матриарх: +1 за радужное существо")
	var c = g.players[0].creatures[1]
	var cb: int = atk(0, 1)
	await put(0, "crazy_cat_lady", 2)
	ok(atk(0, 1) == cb + 1 and atk(0, 0) == base + 1, "Безумная кошатница: +1 только радужным")
	_fresh()
	lands(0, "plain")
	await put(0, "infant_scholar", 0)
	base = atk(0, 0)
	await play(0, hand(0, "teleport"))
	ok(atk(0, 0) == base + 3 or g.creature_count(0) == 1, "Грамотей-младенец: +3 после радужной карты")


func t_bracelet_and_vampire() -> void:
	var a = await put(0, "cow", 0)
	a.perm_def = 10
	a.damage = 3
	var b = await put(0, "cow", 1)
	b.perm_def = 10
	bot.answers = ["2"]
	await play(0, hand(0, "friendship_bracelet"))
	ok(a.damage == 1 and b.damage == 2, "Браслет дружбы: часть урона переложена")
	_fresh()
	var v = await put(0, "vampire_lord", 0)
	v.damage = 1
	await g.cmd_attack(0, 0)
	ok(v.damage == 0, "Повелитель вампиров: урон снят после удара")


func t_parade_and_swords() -> void:
	lands(0, "plain")
	var a = await put(0, "cow", 0)
	a.perm_def = 5
	a.damage = 3
	await play(0, hand(0, "puppy_parade"))
	ok(a.damage == 1, "Щенячий парад: −2 урона")
	_fresh()
	var e = await put(1, "cow", 0)
	e.perm_def = 10
	g.players[0].turn["drawn"] = 3
	await play(0, hand(0, "sword_bouquet"))
	ok(e.damage == 3, "Букет мечей: урон по взятым картам")
	g.players[0].actions = 2
	var c = await put(0, "cow", 1)
	var base: int = atk(0, 1)
	g.players[0].turn["drawn"] = 5
	bot.answers = [spot(0, 1)]
	await play(0, hand(0, "singing_sword"))
	ok(atk(0, 1) == base + 2, "Поющий меч: +1 за каждые 2 карты")
