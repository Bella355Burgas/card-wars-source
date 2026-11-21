extends "res://tests/cards_audit_base.gd"
## Card audit: Гантер (Ледяные земли и Синие равнины). See docs/CARDS_AUDIT.md.


func fill_lanes(p: int, except: int) -> void:
	for l in 4:
		if l != except and g.players[p].creatures[l] == null:
			await put(p, "cow", l)


func t_wanderers() -> void:
	var c = await put(0, "drained_cleric", 0)
	await g._start_effects(0)
	ok(g.players[0].creatures[0] == null and g.where(c.uid)["zone"] == "creature", "Измождённый клирик: перешёл на пустую землю")
	_fresh()
	await put(0, "drained_cleric", 0)
	await fill_lanes(0, 0)
	hand(0, "cow")
	await g._start_effects(0)
	ok(g.players[0].hand.is_empty(), "Измождённый клирик: некуда идти, сбрасывает карту")
	_fresh()
	var w = await put(0, "tired_wombat", 0)
	await fill_lanes(0, 0)
	await g._start_effects(0)
	ok(g.where(w.uid)["p"] == 1, "Усталый вомбат: некуда идти, уходит к сопернику")
	_fresh()
	var r = await put(0, "woadic_ring_leader", 0)
	await fill_lanes(0, 0)
	await g._start_effects(0)
	ok(g.where(r.uid)["zone"] == "discard", "Синюшный заводила: некуда идти, уничтожен")


func t_tired_creatures() -> void:
	var lib = await put(0, "fatigued_librarian", 0)
	ok(lib.exhausted, "Усталый библиотекарь: входит повёрнутым")
	await pass_turn(0)
	await pass_turn(1)
	ok(lib.exhausted, "Усталый библиотекарь: не готовится в начале хода")
	await g.move_creature(0, 0, 1)
	ok(not lib.exhausted, "Усталый библиотекарь: сменил зону, готов")


func t_snow_camp_and_baller() -> void:
	await build(0, "snow_training_camp", 1)
	await g.freeze(1, 3)
	ok(not g.can_floop(0, "building", 1), "Снежный лагерь: в игре есть мороз")
	_fresh()
	await build(0, "snow_training_camp", 1)
	await floop(0, 1, "building")
	ok(g.is_frozen(0, 1) and g.is_frozen(1, 1), "Снежный лагерь: обе земли в зоне")
	_fresh()
	await put(0, "snow_baller", 0)
	await put(1, "cow", 0)
	g.players[1].creatures[0].perm_def = 10
	ok(not g.can_activate(0, "creature", 0), "Снежкометатель: на его земле нет мороза")
	await g.freeze(0, 0)
	bot.answers = [spot(1, 0)]
	await g.cmd_activate(0, "creature", 0)
	ok(not g.is_frozen(0, 0) and g.players[1].creatures[0].damage == 3, "Снежкометатель: мороз снят, 3 урона")


func t_palace_and_racer() -> void:
	await put(0, "cow", 0)
	var base: int = atk(0, 0)
	await build(0, "floating_ice_palace", 0)
	await g.freeze(1, 2)
	await g.freeze(1, 3)
	ok(atk(0, 0) == base + 2, "Плавучий ледяной дворец: +1 за каждую замороженную землю")
	g.turn_player = 1
	ok(atk(0, 0) == base, "Плавучий ледяной дворец: только в твой ход")
	_fresh()
	await put(0, "glacier_racer", 0)
	base = atk(0, 0)
	await g.freeze(0, 0)
	ok(atk(0, 0) == base, "Ледниковый гонщик: одна земля мало")
	await g.freeze(1, 0)
	ok(atk(0, 0) == base + 4, "Ледниковый гонщик: обе земли")


func t_spa_and_tapped_out() -> void:
	await build(0, "fancy_spa", 0)
	var c = await put(0, "cow", 0)
	var n: int = g.players[0].hand.size()
	await g.cmd_begin_attack(0)
	ok(g.players[0].hand.size() == n, "Шикарный спа-салон: существо не повёрнуто")
	_fresh()
	await build(0, "fancy_spa", 0)
	c = await put(0, "cow", 0)
	c.exhausted = true
	n = g.players[0].hand.size()
	await g.cmd_begin_attack(0)
	ok(g.players[0].hand.size() == n + 1, "Шикарный спа-салон: повёрнутое существо, карта")
	_fresh()
	lands(0, "plain")
	var a = await put(0, "cow", 0)
	var b = await put(0, "cow", 1)
	b.exhausted = true
	var x = await put(0, "cow", 2)
	x.exhausted = true
	var base: int = atk(0, 0)
	bot.answers = [spot(0, 0)]
	await play(0, hand(0, "tapped_out"))
	ok(atk(0, 0) == base + 4, "Выдохся: +2 за каждое повёрнутое существо")


func t_magenapping_limits() -> void:
	lands(0, "plain")
	await put(1, "cow", 0)
	var m = hand(0, "magenapping")
	g.players[0].hp = 16
	ok(not g.can_play(0, m.uid), "Магопохищение: больше 15 жизней нельзя")
	g.players[0].hp = 15
	await put(0, "cow", 0)
	await put(0, "cow", 1)
	ok(not g.can_play(0, m.uid), "Магопохищение: больше 1 существа нельзя")
	g.players[0].creatures[1] = null
	ok(g.can_play(0, m.uid), "Магопохищение: можно")
	bot.answers = [spot(1, 0), spot(0, 3)]
	await play(0, m)
	ok(g.players[0].creatures[3] != null and g.players[1].creatures[0] == null, "Магопохищение: существо соперника перешло ко мне")


func t_overload_and_cola() -> void:
	await put(0, "cow", 0)
	await put(0, "cow", 1)
	await put(0, "cow", 2)
	bot.answers = [spot(0, 0), spot(0, 1), null]
	await play(0, hand(0, "cute_overload"))
	ok(g.creature_count(0) == 1 and g.players[0].hand.size() == 2, "Передоз милоты: сколько угодно, по карте за каждое")
	_fresh()
	await put(0, "cow", 0)
	await put(1, "cow", 0)
	var a0: int = atk(0, 0)
	var a1: int = atk(1, 0)
	await play(0, hand(0, "spazzy_cola"))
	ok(atk(0, 0) == a0 + 1 and atk(1, 0) == a1 + 1, "Шипучая кола: всем существам")


func t_freezers() -> void:
	await put(0, "icy_infiltrator", 2)
	ok(g.is_frozen(0, 2), "Ледяной лазутчик: его земля")
	await put(0, "frosted_snowwoman", 1)
	ok(g.is_frozen(0, 1) and g.is_frozen(1, 1), "Морозная снеговичка: обе земли зоны")
	await put(0, "the_cooler", 3)
	await g.destroy_creature(0, 3)
	ok(g.is_frozen(0, 3), "Холодильник: ушёл, его земля заморожена")
	await put(0, "icy_intruder", 0)
	bot.answers = [spot(1, 0)]
	await floop(0, 0)
	ok(g.is_frozen(1, 0) and g.players[0].actions == 1, "Ледяной нарушитель: 1 действие, выбранная земля")
