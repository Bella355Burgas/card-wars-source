extends SceneTree
## Scenario checks for every card added from «RU — Русские карты» (sets 7, 9–18), headless:
##   godot --headless --path . -s res://tests/cards_test.gd [-- <test name part>]

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const AIHelper = preload("res://scripts/ai/ai_helper.gd")


## Answers choice requests from a queue; with an empty queue it picks the
## first option (or skips optional ones when `skip_optional`).
class Scripted:
	var answers: Array = []
	var skip_optional := false
	var asked: Array = []
	func choose(req: Dictionary):
		asked.append(req)
		if not answers.is_empty():
			var a = answers.pop_front()
			if a is Callable:
				return a.call(req)
			return a
		if req.get("optional", false) and skip_optional:
			return null
		return req["options"][0]


var failures := 0
var checks := 0
var g
var bot: Scripted


func _initialize() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		only = args[0]
	var tests := []
	for m in get_method_list():
		var n: String = m["name"]
		if n.begins_with("t_") and (only == "" or n.contains(only)):
			tests.append(n)
	tests.sort()
	for t in tests:
		_fresh()
		await call(t)
	print("cards tests: %d tests, %d checks, %d failed" % [tests.size(), checks, failures])
	quit(1 if failures > 0 else 0)


func _fresh(heroes := ["finn", "jake"]) -> void:
	g = Game.new()
	bot = Scripted.new()
	g.chooser = bot
	g.setup(heroes, 0, 7)
	for ps in g.players:
		ps.hero_card = ""    # no hero ability unless a test sets one
		ps.deck.append_array(ps.hand)
		ps.hand.clear()
	g.turn_number = 3
	g.turn_player = 0
	g.phase = "main"
	g.players[0].actions = 2


func ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("ok   ", what)
	else:
		failures += 1
		printerr("FAIL ", what)
		printerr("     log: ", g.log_lines.slice(-6))
		printerr("     asked: ", bot.asked.slice(-3).map(func(r): return String(r.get("prompt", ""))))


func lands(p: int, type: String) -> void:
	for l in 4:
		g.players[p].lands[l]["type"] = type


## Two land types, two of each.
func mixed(p: int, a: String, b: String) -> void:
	for l in 4:
		g.players[p].lands[l]["type"] = a if l % 2 == 0 else b


func mk(id: String, owner := 0):
	return g._make_card(id, owner)


func put(p: int, id: String, lane: int, owner := -1):
	var c = mk(id, p if owner < 0 else owner)
	await g._put_creature(p, c, lane)
	return c


func build(p: int, id: String, lane: int):
	var c = mk(id, p)
	await g._put_building(p, c, lane)
	return c


func hand(p: int, id: String):
	var c = mk(id, p)
	g.players[p].hand.append(c)
	return c


func top(p: int, id: String):
	var c = mk(id, p)
	g.players[p].deck.append(c)
	return c


## Plays a card from hand for real (cost, lands, hooks).
func play(p: int, c, lane := -1) -> void:
	await g.cmd_play(p, c.uid, lane)


func spot(p: int, lane: int) -> Dictionary:
	return {"p": p, "lane": lane}


# ================================================================= 12: Огненная Принцесса

func t_fp_burn_ticks() -> void:
	var x = await put(1, "cow", 0)
	await g.burn_creature(0, 1, 0, 2)
	ok(g.tokens(x, "burn") == 2 and g.burning(x), "огонь: два жетона огня")
	g.turn_player = 1
	await g._start_turn(1)
	ok(x.damage == 4, "огонь: 1 урон за жетон сразу и в начале хода владельца (got %d)" % x.damage)
	await g.burn_player(0, 1, 3)
	var hp: int = g.players[1].hp
	await g._start_turn(1)
	ok(g.players[1].hp == hp - 3, "огонь на игроке: 3 урона в начале его хода")


func t_fp_hero() -> void:
	g.players[0].hero_card = "flame_princess"
	var a = await put(1, "cow", 0)
	var b = await put(1, "cow", 2)
	ok(g.can_hero_power(0), "Огненная Принцесса: способность есть")
	await g.cmd_hero_power(0)
	ok(g.burning(a) and g.burning(b), "Огненная Принцесса: все существа соперника горят")
	g.players[0].turn = {}
	ok(not g.can_hero_power(0), "Огненная Принцесса: раз за игру")


func t_fp_broils_coils() -> void:
	lands(0, "lava")
	var x = await put(1, "cow", 0)     # 1/5
	x.damage = 2
	var c = hand(0, "broils_coils")
	await play(0, c)
	ok(g.players[1].creatures[0] == null and g.players[0].actions == 2, "Жаркие кольца: убили — действие вернулось")


func t_fp_hot_shot_molten() -> void:
	lands(0, "lava")
	var x = await put(1, "cow", 0)
	var y = await put(1, "cow", 1)
	await play(0, hand(0, "hot_shot"))
	ok(g.burning(x) and x.damage == 2, "Меткий выстрел: поджог 1 урон и ещё 1 урон")
	bot.answers = [spot(1, 1)]
	await play(0, hand(0, "molten_potion"))
	ok(g.burning(y) and x.damage == 4 and y.damage == 3, "Расплавленное зелье: 2 урона каждому горящему существу соперника")


func t_fp_titanbane() -> void:
	var x = await put(1, "drooling_dude", 0)    # 3 ATK
	var hp: int = g.players[0].hp
	await play(0, hand(0, "titanbane_amulet"))
	ok(g.players[1].creatures[0] == null and g.players[0].hp == hp - 3, "Амулет погибели титанов: уничтожает, теряешь жизни = атака")
	ok(x.owner == 1, "…")


func t_fp_volcanic_vitality() -> void:
	lands(0, "lava")
	var x = await put(1, "drooling_dude", 0)
	await g.burn_creature(0, 1, 0, 2)
	await play(0, hand(0, "volcanic_vitality"))
	ok(g.tokens(x, "burn") == 4, "Вулканическая живость: жетонов огня вдвое больше")


func t_fp_cozy_kiln_scorchcrawler() -> void:
	await build(0, "cozy_kiln", 0)
	await put(0, "scorchcrawler", 2)
	var x = await put(1, "cow", 0)
	var y = await put(1, "drooling_dude", 1)
	await g.burn_creature(0, 1, 0, 2)
	bot.answers = [spot(1, 1)]
	await g.destroy_creature(1, 0)
	ok(g.players[1].burn == 1, "Уютная печь: горящее существо ушло — владелец горит")
	ok(g.tokens(y, "burn") == 2, "Палеполз: поджигает столько раз, сколько жетонов было (got %d)" % g.tokens(y, "burn"))


func t_fp_hot_huts_heat() -> void:
	await build(0, "hot_huts", 0)
	var eater = await put(0, "flameingo_heat_eater", 1)
	var leap = await put(0, "heat_leapers", 2)
	var x = await put(1, "drooling_dude", 0)
	var hand_n: int = g.players[0].hand.size()
	await g.burn_creature(0, 1, 0)
	await g.burn_creature(0, 1, 0)
	ok(x.damage == 4, "Горячие хижины: +1 урон при каждом поджоге (got %d)" % x.damage)
	ok(g.players[0].hand.size() == hand_n + 1, "Пламинго-жаропожиратель: карта только за первый поджог")
	ok(g.tokens(leap, "atk_tok") == 2 and g.atk_of(0, 2) == 4, "Жаропрыги: жетон атаки за каждый поджог")
	ok(eater != null, "…")


func t_fp_pyrovent_scorchstone() -> void:
	var f = await build(0, "pyrovent_fortress", 0)
	await build(0, "scorchstone_gateway", 1)
	var x = await put(1, "drooling_dude", 1)
	ok(not g.can_floop(0, "building", 0), "Крепость пиропара: без горящих существ нельзя")
	await g.cmd_floop(0, "building", 1)
	ok(g.burning(x) and g.players[0].actions == 1, "Врата палящего камня: поджигает существо в зоне за действие")
	await g.cmd_floop(0, "building", 0)
	ok(not g.burning(x) and x.damage == 4 and f.flooped, "Крепость пиропара: жетон снят, 3 урона")


func t_fp_burnwarden() -> void:
	var w = await put(0, "flameingo_burnwarden", 0)
	var x = await put(1, "cow", 1)
	ok(not g.can_activate(0, "creature", 0), "Пламинго-огнестраж: нет горящих — нельзя")
	await g.burn_creature(0, 1, 1, 2)
	var hp: int = g.players[1].hp
	await g.cmd_activate(0, "creature", 0)
	await g.cmd_activate(0, "creature", 0)
	ok(g.players[1].hp == hp - 2 and not g.burning(x), "Пламинго-огнестраж: 1 урон сопернику за снятый жетон, сколько угодно раз")
	ok(w != null, "…")


func t_fp_flameweaver() -> void:
	await put(0, "flameingo_flameweaver", 0)
	var a = await put(0, "cow", 2)
	var b = await put(1, "cow", 2)
	bot.answers = [{"p": 0, "lane": 2, "row": "creature"}]
	await g.cmd_floop(0, "creature", 0)
	ok(g.burning(a) and g.burning(b), "Пламинго-огнеплёт: горят оба существа выбранной зоны")


func t_fp_hotshot() -> void:
	var h = await put(0, "flameingo_hotshot", 0)
	var x = await put(1, "drooling_dude", 0)
	var y = await put(1, "drooling_dude", 2)
	await g.burn_creature(0, 1, 0)
	bot.answers = [spot(1, 2)]
	await g.cmd_attack(0, 0)
	ok(y.damage == 3 and g.burning(y), "Пламинго-сорвиголова: 2 урона другому и поджигает его")
	ok(h != null and x != null, "…")


func t_fp_captain_blazeling_chief() -> void:
	await put(0, "flameingo_captain", 0)
	await g.cmd_attack(0, 0)
	ok(g.players[1].burn == 1, "Пламинго-капитан: урон сопернику поджигает его")
	var b = await put(0, "flameingo_blazeling", 1)
	var x = await put(1, "drooling_dude", 1)
	await g.cmd_attack(0, 1)
	ok(g.tokens(x, "burn") == 1, "Пламинго-искорка: поджигает раненое существо")
	g.players[0].creatures[1] = null
	var c = await put(0, "flameingo_fireplume_chief", 1)
	c.exhausted = false
	await g.cmd_attack(0, 1)
	ok(g.tokens(x, "burn") == 2 or g.players[1].creatures[1] == null, "Вождь огнепёрых: поджигает даже горящее")
	ok(b != null, "…")


func t_fp_chief_cost() -> void:
	lands(0, "lava")
	var c = hand(0, "flameingo_fireplume_chief")
	ok(g.cost_of(0, c) == 4, "Вождь огнепёрых: стоимость 4")
	await put(1, "cow", 0)
	await g.burn_creature(0, 1, 0, 3)
	ok(g.cost_of(0, c) == 1, "Вождь огнепёрых: −1 за каждый жетон огня")


func t_fp_ignisbeak() -> void:
	await put(0, "flameingo_ignisbeak", 0)
	var x = await put(1, "drooling_dude", 0)
	await g.burn_creature(0, 1, 0)
	var hp: int = g.players[1].hp
	await g.cmd_attack(0, 0)
	ok(g.players[1].hp == hp - 3 and x.damage == 1, "Пламинго-огнеклюв: мимо горящего существа прямо в соперника")


func t_fp_phoenix_firedog() -> void:
	await put(1, "drooling_dude", 0)
	await g.burn_creature(0, 1, 0, 2)
	await put(0, "furious_phoenix", 1)
	ok(g.atk_of(0, 1) == 3, "Яростный феникс: +1 за жетон огня")
	var y = await put(1, "drooling_dude", 2)
	bot.answers = [spot(1, 2)]
	await put(0, "fire_dog", 2)
	ok(y.damage == 2, "Огненный пёс: урон = жетоны огня")


func t_fp_hampire_kangaroo() -> void:
	await put(0, "hampire_pig_of_the_night", 0)
	g.players[0].hp = 10
	await g.cmd_attack(0, 0)
	ok(g.players[0].hp == 13, "Свампир: при нападении лечит = атака")
	var cat = await put(0, "kangaroo_cat", 1)
	await g.cmd_attack(0, 1)
	cat.exhausted = false
	await g.cmd_attack(0, 1)
	ok(g.tokens(cat, "atk_tok") == 1, "Кенгуру-кот: жетон только за первый урон")
	var bat = await put(0, "kangaroo_bat", 2)
	await g.cmd_attack(0, 2)
	bat.exhausted = false
	await g.cmd_attack(0, 2)
	ok(g.tokens(bat, "atk_tok") == 2, "Кенгуру-мышь: жетон за каждый урон")


func t_fp_hot_wheel() -> void:
	await put(0, "hot_wheel", 0)
	var x = await put(1, "drooling_dude", 0)
	top(0, "drooling_dude")     # cost 2
	bot.answers = [spot(1, 0)]
	await g.cmd_activate(0, "creature", 0)
	ok(g.tokens(x, "burn") == 2 and g.players[0].actions == 1, "Горячее колесо: поджигает столько раз, сколько стоит карта")


# ================================================================= 12: Ферн

func t_fern_gobble() -> void:
	lands(0, "corn")
	var cob = await put(0, "darling_cobnoblin", 0)   # 2/3, Хрум
	cob.damage = 1
	await g.add_atk_tokens(cob)
	var c = hand(0, "evil_eye")    # 1/5, cost 0
	await play(0, c, 0)
	ok(c.under.has(cob), "Хрум: заменённый уходит под новое существо")
	ok(g.atk_of(0, 0) == 1 + 2 + 1 and g.def_of(0, 0) == 5 + 3 and c.damage == 1,
		"Хрум: новое получает атаку, защиту, жетоны и урон (%d/%d dmg %d)" % [g.atk_of(0, 0), g.def_of(0, 0), c.damage])
	ok(g.tokens(c, "atk_tok") == 1, "Хрум: жетон атаки остаётся жетоном")
	await g.destroy_creature(0, 0)
	ok(g.players[0].discard.has(cob), "Хрум: при уходе карты из-под существа идут в сброс")


func t_fern_whump() -> void:
	lands(0, "cute")
	var big = hand(0, "valiant_armourdillo")    # cost 5
	ok(not g.can_play(0, big.uid), "Бух: за 5 без замены не сыграть")
	await put(0, "drooling_dude", 1)   # cost 2
	await put(0, "drooling_dude", 2)
	g.players[0].actions = 3
	ok(g.cost_of(0, big, 1) == 3 and g.can_play(0, big.uid, 1), "Бух: заменяет существо за 2 — стоит 3")
	await put(0, "polished_armourdillo", 3)
	ok(g.cost_of(0, big, 1) == 2, "Начищенный броненосец: другие с «Бух» на 1 дешевле")
	var x = await put(1, "cow", 1)
	await play(0, big, 1)
	ok(g.players[0].creatures[1] == big and g.players[1].creatures[1] == null, "Доблестный броненосец: с руки уничтожает существо в зоне")
	ok(x.owner == 1, "…")


func t_fern_hero() -> void:
	g.players[0].hero_card = "fern"
	lands(0, "corn")
	await put(0, "cow", 0)
	var a = hand(0, "darling_cobnoblin")    # cost 1
	var b = hand(0, "treasured_cobnoblin")  # cost 1
	await play(0, a, 0)
	ok(g.players[0].actions == 1, "Ферн: само заменившее существо не бесплатно")
	ok(g.cost_of(0, b) == 0, "Ферн: следующее существо за 1 — бесплатно")
	await play(0, b, 2)
	ok(g.players[0].actions == 1, "Ферн: сыграно бесплатно")
	var c = hand(0, "adored_cobnoblin")
	ok(g.cost_of(0, c) == 1, "Ферн: только одно")


func t_fern_cobnoblins() -> void:
	var a = await put(0, "adored_cobnoblin", 0)
	await g.cmd_floop(0, "creature", 0)
	var d = hand(0, "drooling_dude")
	ok(g.cost_of(0, d) == 1, "Обожаемый початкогоблин: следующее существо на 1 дешевле")
	var t = await put(0, "treasured_cobnoblin", 1)
	var n: int = g.players[0].hand.size()
	await g.cmd_floop(0, "creature", 1)
	ok(g.players[0].hand.size() == n + 1, "Драгоценнейший початкогоблин: берёт карту")
	var dar = await put(0, "darling_cobnoblin", 2)
	bot.answers = [spot(0, 2)]
	await g.cmd_floop(0, "creature", 2)
	ok(g.tokens(dar, "atk_tok") == 1, "Милый початкогоблин: жетон атаки")
	var x = await put(1, "cow", 0)
	await g.burn_creature(1, 1, 0)
	await g.add_atk_tokens(x)
	var ch = await put(0, "cherished_cobnoblin", 3)
	bot.answers = [spot(1, 0), "Убрать 2", "Жетон огня", spot(0, 3)]
	await g.cmd_floop(0, "creature", 3)
	ok(g.non_damage_tokens(x) == 0 and g.tokens(ch, "atk_tok") == 2, "Заветный початкогоблин: 2 жетона сняты, 2 жетона атаки")
	ok(a != null and t != null, "…")


func t_fern_precious() -> void:
	var p = await put(0, "precious_cobnoblin", 0)
	var x = await put(0, "cow", 1)
	x.damage = 3
	bot.answers = [spot(0, 1), "Снять 2 урона"]
	await g.cmd_floop(0, "creature", 0)
	ok(x.damage == 1, "Драгоценный початкогоблин: снимает 2 урона")
	ok(p.flooped, "…")


func t_fern_armourdillos() -> void:
	var x = await put(1, "drooling_dude", 0)
	x.damage = 7
	bot.answers = [spot(1, 0)]
	var n: int = g.players[0].hand.size()
	await put(0, "chivalrous_armourdillo", 1)
	ok(x.damage == 4 and g.players[0].hand.size() == n + 1, "Рыцарственный броненосец: снял 3, урон остался — карта")
	var e = await put(0, "eloquent_armourdillo", 1)
	ok(g.tokens(e, "atk_tok") == 1, "Красноречивый броненосец: при замене жетон атаки")
	top(0, "cow")
	await put(0, "gallant_armourdillo", 1)
	ok(g.players[0].creatures.any(func(c): return c != null and c.id == "cow"), "Галантный броненосец: при замене играет верх колоды")


func t_fern_courageous() -> void:
	await put(0, "courageous_armourdillo", 0)
	var x = await put(1, "cow", 0)
	x.damage = 2
	g.players[0].hp = 10
	var hp: int = g.players[1].hp
	await g.cmd_attack(0, 0)
	ok(g.players[1].creatures[0] == null and g.players[0].hp == 12 and g.players[1].hp == hp - 2,
		"Отважный броненосец: победа — +2 жизни и 2 урона сопернику")
	ok(x.owner == 1, "…")


func t_fern_guard() -> void:
	var gr = await put(1, "gracious_armourdillo", 3)
	await put(0, "drooling_dude", 0)
	var hp: int = g.players[1].hp
	bot.answers = [spot(1, 3)]
	await g.cmd_attack(0, 0)
	ok(g.players[1].hp == hp and gr.damage == 3, "Любезный броненосец: принимает нападение на себя")


func t_fern_refined_rhino() -> void:
	mixed(0, "cute", "corn")
	var r = hand(0, "refined_armourdillo")
	ok(g.cost_of(0, r) == 1, "Утончённый броненосец: обычно 1")
	await play(0, hand(0, "drooling_dude"), 0)
	ok(g.cost_of(0, r) == 0, "Утончённый броненосец: бесплатно после существа за 2")
	_fresh()
	var rh = hand(0, "rhinoceros")
	await play(0, rh, 0)
	ok(g.tokens(rh, "atk_tok") == 1, "Носорог: первая карта хода — жетон атаки")


func t_fern_spells() -> void:
	mixed(0, "cute", "corn")
	var x = await put(0, "drooling_dude", 0)
	x.damage = 5
	await play(0, hand(0, "champions_emblem"))
	ok(x.damage == 2 and g.players[0].actions == 2, "Эмблема чемпиона: урон остался — действие")
	var y = await put(1, "drooling_dude", 0)
	bot.answers = [spot(1, 0)]
	await play(0, hand(0, "kernel_renewal"))
	ok(y.damage == 2, "Обновление зерна: урон = урону своего существа")
	var hp: int = g.players[1].hp
	g.players[1].hp = 10
	bot.answers = [spot(1, 0)]
	g.players[0].actions = 2
	await play(0, hand(0, "sacred_scythe"))
	ok(g.players[1].creatures[0] == null and g.players[1].hp == 15, "Священная коса: уничтожает, владелец +5 жизней")
	ok(hp > 0, "…")


func t_fern_ragepop_herbal() -> void:
	mixed(0, "cute", "corn")
	var a = await put(0, "drooling_dude", 0)
	await put(1, "cow", 0)
	await play(0, hand(0, "ragepop_totem"))
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "herbal_hurlers"))
	await g.cmd_attack(0, 0)
	ok(g.players[0].hand.size() == n + 1, "Тотем ярости: победил — карта")
	ok(a.damage == 0, "Травяные метатели: урон снят на нанесённый")


func t_fern_buildings() -> void:
	var x = await put(0, "drooling_dude", 0)
	x.damage = 2
	await build(0, "lifeward_tower", 0)
	g.turn_player = 0
	await g._start_turn(0)
	ok(x.damage == 1, "Башня жизни: снимает 1 урон в начале хода")
	await build(0, "ascension_silo", 1)
	await put(0, "cow", 1)
	var n: int = g.players[0].hand.size()
	await g.destroy_creature(0, 1)
	ok(g.players[0].hand.size() == n + 1, "Амбар вознесения: ушло существо — карта")
	await put(0, "cow", 1)
	await g.destroy_creature(0, 1)
	ok(g.players[0].hand.size() == n + 1, "Амбар вознесения: раз за ход")
	g.players[0].discard.append(mk("hot_shot"))
	await build(0, "resonant_spellhold", 2)
	var s = g.players[0].discard.back()
	bot.answers = [s.uid]
	await put(0, "drooling_dude", 2)
	ok(g.players[0].hand.has(s), "Резонансная твердыня чар: вернула заклинание дешевле")


func t_fern_mossglen() -> void:
	await build(0, "mossglen_retreat", 0)
	var x = await put(0, "cow", 1)
	await g.burn_creature(1, 0, 1)
	var hurt: int = x.damage
	bot.answers = ["Мшистое убежище, зона 1", "С существа", spot(0, 1)]
	await g._start_turn(0)
	ok(not g.burning(x), "Мшистое убежище: снимает жетон огня")
	ok(x.damage == hurt, "Игрок: Мшистое убежище раньше огня — жетон снят до урона")
	ok(bot.asked.any(func(r): return String(r.get("prompt", "")).begins_with("Начало хода")), "Начало хода: игрок выбирает порядок эффектов")


## Игрок: замороженную землю можно заморозить снова: старый жетон снимается (Саймон, Ледник), новый ложится (Хрустальный дворец).
func t_ice_refreeze() -> void:
	await build(0, "crystal_palace", 0)
	await put(0, "frost_dragon", 0)
	var foe = await put(1, "drooling_dude", 2)
	for s in g.lane_spots(0, 0):
		g.players[s[0]].lands[s[1]]["frozen"] = true
	var n: int = g.frozen_count()
	ok(g.can_activate(0, "creature", 0), "Морозный дракон: можно, даже когда обе земли зоны замёрзли")
	bot.answers = [spot(0, 0), spot(1, 2)]
	await g.cmd_activate(0, "creature", 0)
	ok(foe.damage == 2, "Хрустальный дворец: повторная заморозка тоже считается")
	ok(g.frozen_count() == n and g.players[0].actions == 1, "Повторная заморозка: жетона мороза не прибавилось")
	bot.answers = [spot(0, 1), spot(0, 2)]
	await g.run_hook("spell_snow_way", [mk("snow_way"), 0])
	var picks: Array = bot.asked.filter(func(r): return String(r.get("prompt", "")).begins_with("Лыжню!"))
	ok(picks.size() == 2 and not picks[1]["options"].has(spot(0, 1)), "Лыжню!: две разные земли")


## Игрок: жетонов мороза сколько угодно; повторная заморозка снимает старый жетон и кладёт новый.
func t_frost_unlimited_and_replace() -> void:
	g.players[0].hero_card = "simon_petrikov"
	for s in [0, 1]:
		for l in 4:
			await g.freeze(s, l)
	ok(g.frozen_count() == 8, "Мороз: заморожены все 8 земель, лимита жетонов нет")
	var n: int = g.players[0].hand.size()
	await g.freeze(1, 0)
	ok(g.is_frozen(1, 0) and g.frozen_count() == 8, "Повторная заморозка: земля осталась замороженной")
	ok(g.players[0].hand.size() == n + 1, "Повторная заморозка: старый жетон снят (Саймон Петриков берёт карту)")


## ИИ гонял жетон мороза Залпа слаша туда-обратно без конца.
func t_slushie_moves_once() -> void:
	g.players[1].lands[2]["frozen"] = true
	bot.answers = [spot(0, 0), spot(0, 0), spot(0, 1)]
	await g.run_hook("spell_slushie_salvo", [mk("slushie_salvo"), 0])
	var froms: Array = bot.asked.filter(func(r): return String(r.get("prompt", "")).contains("с какой земли"))
	ok(froms.size() >= 2 and not froms[1]["options"].has(spot(0, 1)) and not froms[1]["options"].has(spot(0, 0)),
		"Залп слаша: жетон с земли, куда он пришёл, второй раз не двигается")
	ok(froms.size() <= g.total_lands() / 2 + 1, "Залп слаша: перемещения заканчиваются")


## Игрок: ИИ лечит себя, а не соперника, и кладёт жетоны атаки на своих.
func t_ai_obvious_choices() -> void:
	var AIHelper = load("res://scripts/ai/ai_helper.gd")
	var names: Array = g.players.map(func(ps): return ps.name)
	var heal: Array = AIHelper.obvious(g, {"kind": "option", "player": 1, "options": names, "prompt": "Аксолотль: кто восстановит 3 жизни?"})
	ok(heal == [names[1]], "ИИ: «кто восстановит» — себе")
	await put(0, "cow", 0)
	await put(1, "cow", 2)
	var t: Array = AIHelper.obvious(g, {"kind": "creature", "player": 1, "options": [spot(0, 0), spot(1, 2)],
		"prompt": "Мозгоклинки: на какое существо жетоны атаки?"})
	ok(t == [spot(1, 2)], "ИИ: жетоны атаки — на своё существо")


# ================================================================= 13: Призмо

func t_prismo_played_counts() -> void:
	mixed(0, "corn", "lava")
	var adept = await put(0, "dualcast_adept", 0)
	var ants = await put(0, "lava_ants", 1)
	await play(0, hand(0, "president_sweetcorn"), 2)    # corn, +1 action
	ok(g.players[0].actions == 2, "Президент Сладкий Початок: +1 действие")
	ok(g.tokens(ants, "atk_tok") == 0, "Лавовые муравьи: после одной нелавовой карты ещё нет")
	await play(0, hand(0, "killer_stilts"))             # corn
	ok(g.tokens(ants, "atk_tok") == 1, "Лавовые муравьи: вторая нелавовая карта — жетон атаки")
	var n: int = g.players[0].hand.size()
	await g._end_turn(0)
	ok(g.players[0].hand.size() == n + 1, "Адепт двойных чар: в конце хода карта за 2 неравнинные карты")
	ok(adept != null, "…")


func t_prismo_shucker_tardigrade() -> void:
	mixed(0, "sandy", "plain")
	var z = await put(0, "zebracorn_seige_shucker", 0)    # 2 ATK
	var t = await put(0, "drooling_dude", 1)
	await play(0, hand(0, "cyclone"))
	ok(t.damage == 4, "Циклон: 4 урона существам не за 1")
	ok(z.damage == 0, "Циклон: существа за 1 целы")
	_fresh()
	z = await put(0, "zebracorn_seige_shucker", 0)
	t = await put(0, "tectonic_tardigrade", 1)
	g.players[0].turn["played_lands"] = ["sandy", "plain"]
	ok(g.atk_of(0, 0) == 4, "Зебророг-осадолущитель: атака удваивается (got %d)" % g.atk_of(0, 0))
	await put(1, "drooling_dude", 1)
	await g.cmd_attack(0, 1)
	ok(t.damage == 0, "Тектонический тихоход: существа соперника не наносят ему урона")


func t_prismo_auras() -> void:
	await put(0, "support_saguaro", 0)
	await put(0, "cow", 1)
	ok(g.atk_of(0, 1) == 2, "Сагуаро поддержки: непесчаные +1")
	await build(0, "camp_kernel", 2)
	var k = await put(0, "president_sweetcorn", 2)
	ok(g.atk_of(0, 2) == 4 and g.def_of(0, 2) == 5, "Лагерь «Зёрнышко»: +1/+1 существу стоимостью 1 (+Сагуаро)")
	await build(0, "wellspring_apartments", 3)
	await put(0, "evil_eye", 3)
	g.players[0].turn["played_lands"] = ["corn", "plain", "sandy"]
	ok(g.atk_of(0, 3) == 1 + 1 + 2, "Апартаменты «Родник»: +1 за каждую непесчаную карту")
	await build(0, "pepper_palace", 0)
	ok(g.atk_of(0, 0) == 2 + 2, "Перечный дворец: +2 после 2 нелавовых карт")
	ok(k != null, "…")


func t_prismo_costs() -> void:
	var h = hand(0, "hothead")
	await put(0, "president_sweetcorn", 0)
	await put(0, "dualcast_adept", 1)
	ok(g.cost_of(0, h) == 1, "Горячая голова: −1 за каждое своё существо за 1")
	var pr = hand(0, "prismatarchia")
	await put(0, "cow", 2)
	ok(g.cost_of(0, pr) == 2, "Призматархия: −1 за каждый разный тип своих существ, радужное не в счёт")


func t_prismo_oasis_beetle() -> void:
	mixed(0, "corn", "sandy")
	await put(0, "oasis_guardian", 0)
	var b = await put(0, "prismatic_war_beetle", 1)
	var x = await put(1, "drooling_dude", 0)
	await play(0, hand(0, "president_sweetcorn"), 2)
	ok(x.damage == 1, "Страж оазиса: непесчаная карта — 1 урон каждому существу соперника")
	ok(g.atk_of(0, 1) == 2, "Призматический боевой жук: +1 за непесчаную карту")
	ok(b != null, "…")


func t_prismo_misc() -> void:
	mixed(0, "corn", "sandy")
	var r = await put(0, "broog_rider", 0)
	var s = await put(0, "president_sweetcorn", 1)
	await g.destroy_creature(0, 0)
	ok(g.tokens(s, "atk_tok") == 1, "Наездник брога: уходя, жетон атаки существам за 1")
	ok(r != null, "…")
	var ch = hand(0, "chameleon")
	bot.answers = ["Лавовая равнина"]
	await play(0, ch, 2)
	ok(g.is_type(ch, "lava", 0, 2), "Хамелеон: выбранный тип земель")
	hand(0, "president_sweetcorn")
	await put(0, "carrier_crab", 3)
	ok(g.players[0].creatures.filter(func(c): return c != null and c.id == "president_sweetcorn").size() == 2,
		"Краб-носильщик: сыграл бесплатно карту стоимостью 1")
	var a = await put(1, "drooling_dude", 0)
	g.players[0].actions = 2
	bot.answers = [spot(0, 1), spot(1, 0)]
	lands(0, "plain")
	await play(0, hand(0, "galeblade_tornado"))
	ok(g.players[1].hand.has(a) and g.players[0].hand.has(s), "Смерч штормового клинка: своё и чужое существо на руку")


func t_prismo_grim_dune() -> void:
	await put(0, "cow", 0)
	top(1, "drooling_dude")
	bot.answers = ["Сыграть бесплатно", {"p": 0, "lane": 1, "row": "creature"}]
	await play(0, hand(0, "grim_exchange"))
	var x = g.players[0].creatures[1]
	ok(x != null and x.id == "drooling_dude" and x.owner == 1, "Мрачный обмен: сыграл карту соперника бесплатно")
	top(0, "cow")
	bot.answers = ["Открыть", "Сыграть бесплатно", {"p": 0, "lane": 2, "row": "creature"}]
	await put(0, "dune_bug_buggie", 3)
	ok(g.players[0].creatures[2] != null and g.players[0].creatures[2].id == "cow", "Дюнный багги-жук: непесчаную карту сверху — бесплатно")


func t_prismo_hero() -> void:
	g.players[0].hero_card = "prismo"
	mixed(0, "corn", "sandy")
	await put(0, "cow", 0)
	ok(not g.can_hero_power(0), "Призмо: без двух карт разных типов нельзя")
	await play(0, hand(0, "president_sweetcorn"), 1)
	await play(0, hand(0, "oasis_guardian"), 2)
	ok(g.can_hero_power(0), "Призмо: после кукурузной и песчаной карты можно")
	bot.answers = [spot(0, 0)]
	await g.cmd_hero_power(0)
	ok(g.non_damage_tokens(g.players[0].creatures[0]) == 1, "Призмо: жетон атаки")


# ================================================================= 13: Лич

func t_lich_hand_war() -> void:
	await put(0, "icefang_avalancheetah", 0)
	var f = await put(0, "filthflinger", 1)
	await build(0, "scrappys_salvage_bog", 1)
	hand(1, "cow")
	hand(1, "cow")
	var n: int = g.players[0].hand.size()
	await g.force_discard(1, 2)
	ok(g.players[0].hand.size() == n + 2, "Лавиногепард Ледяной Клык: карта за каждый сброс соперника")
	ok(g.tokens(f, "atk_tok") == 2 + 1, "Гряземетатель +2, Утильное болото Скрэппи +1 (только первый)")


func t_lich_robo_tentacle() -> void:
	await put(0, "robomination", 0)
	hand(1, "cow")
	await g.destroy_creature(0, 0)
	ok(g.players[1].hand.is_empty(), "Робомерзость: уходя, соперник сбрасывает карту")
	await put(0, "tentacreeper", 1)
	hand(1, "cow")
	bot.answers = ["Нет"]
	await g._start_turn(0)
	ok(g.atk_of(0, 1) == 4, "Щупалозавр: +3, если соперник не сбросил")


func t_lich_cats() -> void:
	await put(1, "cow", 0)
	await put(0, "frostcrown_avalancheetah", 0)
	ok(g.is_frozen(0, 0) and g.is_frozen(1, 0), "Морозный Венец: замораживает обе земли зоны")
	var c = await put(0, "coldclaw_avalancheetah", 2)
	c.damage = 4
	await g.thaw(0, 0)
	ok(c.damage == 0, "Хладный Коготь: сняли жетон мороза — весь урон снят")


func t_lich_blizzardpaw() -> void:
	bot.answers = ["Пусть берёт 2 карты"]
	var n: int = g.players[0].hand.size()
	await put(0, "blizzardpaw_avalancheetah", 0)
	ok(g.players[0].hand.size() == n + 2, "Вьюжная Лапа: соперник не заморозил — 2 карты")
	bot.answers = ["Заморозить свою землю", {"p": 1, "lane": 3}]
	await put(0, "blizzardpaw_avalancheetah", 1)
	ok(g.players[0].hand.size() == n + 2 and g.is_frozen(1, 3), "Вьюжная Лапа: заморозил свою землю — карт нет")


func t_lich_rotroot_bitterchill() -> void:
	await put(0, "rotroot_rooter", 0)
	hand(1, "hot_shot")
	var cr = hand(1, "cow")
	await g.cmd_attack(0, 0)
	ok(g.players[1].discard.has(cr), "Гнилокорень: соперник сбросил существо")
	await put(0, "bitterchill_avalancheetah", 1)
	await g.cmd_attack(0, 1)
	ok(g.players[1].hand.is_empty(), "Лютый Холод: соперник сбросил заклинание")


func t_lich_owl_python() -> void:
	await put(0, "night_owl", 0)
	hand(1, "cow")
	hand(1, "cow")
	ok(g.atk_of(0, 0) == 4, "Ночная сова: −1 за карту на руках соперника")
	for i in 10:
		g.players[1].discard.append(mk("cow", 1))
	await put(0, "pit_python", 1)
	ok(g.atk_of(0, 1) == 6, "Яминный питон: +2 за каждые 5 карт сброса соперника")
	ok(g.cost_of(0, hand(0, "barrow_baron")) == 1, "Курганный барон: −1 за каждые 5 карт сброса соперника")


func t_lich_lambpire_pat() -> void:
	var l = await put(0, "lambpire_fanged_fluff", 0)
	await put(1, "evil_eye", 0)
	await g.cmd_attack(0, 0)
	ok(l.damage == 0, "Ягнепир: после сражения снимает 1 урон")
	await put(0, "kangaroo_pat", 1)
	var dog = await put(0, "cow", 2)
	bot.answers = [spot(0, 2)]
	await g.cmd_attack(0, 1)
	ok(g.tokens(dog, "atk_tok") == 1, "Кенгуру-Пэт: жетон атаки дружественному существу")


func t_lich_spells() -> void:
	mixed(0, "swamp", "ice")
	var x = await put(1, "drooling_dude", 0)    # ATK 3
	g.players[0].actions = 2
	await play(0, hand(0, "waterfall_of_swords"))
	ok(x.damage == 3, "Водопад мечей: урон = атака")
	g.players[0].actions = 2
	await put(0, "cow", 1)
	bot.answers = [{"p": 0, "lane": 3, "row": "creature"}]
	await play(0, hand(0, "glacial_drift"))
	ok(g.players[0].creatures[3] != null and g.is_frozen(1, 3), "Ледниковый дрейф: переместил и заморозил землю соперника")
	hand(0, "president_sweetcorn")
	hand(1, "killer_stilts")
	var n1: int = g.players[1].hand.size()
	await play(0, hand(0, "whiteout"))
	ok(g.players[1].hand.size() == n1 - 1 + 2, "Белая мгла: сброс карт за 1, затем по 2 карты")


func t_lich_mire() -> void:
	mixed(0, "swamp", "ice")
	g.players[0].hp = 10
	hand(1, "cow")
	var hp: int = g.players[1].hp
	bot.answers = ["Соперник: Джейк", "Себе 4 жизни"]
	await play(0, hand(0, "mire_madness"))
	ok(g.players[1].hp == hp - 4 and g.players[0].hp == 14 and g.players[1].hand.is_empty(),
		"Трясинное безумие: 4 урона, 4 жизни, сброс соперника, карта")


func t_lich_buildings() -> void:
	await build(0, "wraithwood_lodge", 0)
	hand(0, "cow")
	var n: int = g.players[0].hand.size()
	await put(0, "drooling_dude", 0)
	ok(g.players[0].hand.size() == n and g.players[0].discard.size() >= 1, "Призрачная сторожка: сбросил и взял карту")
	await build(1, "cool_cone_cafe", 1)
	ok(g.is_frozen(0, 1), "Кафе «Холодный рожок»: замораживает землю соперника в зоне")
	ok(g.thaw_cost(0, 1) == 2, "Кафе «Холодный рожок»: растопить — 2 карты")
	await build(0, "phoenix_pyre", 2)
	var x = await put(0, "drooling_dude", 2)
	bot.answers = ["Вернуть"]
	await g.destroy_creature(0, 2)
	ok(g.players[0].creatures[2] == x and g.players[0].buildings[2] == null, "Костёр феникса: существо вернулось, костёр ушёл")


func t_lich_winterhide_mudpie() -> void:
	await put(0, "mudpie_zombies", 0)
	ok(true, "Зомби из грязи: без ошибок")
	await g.freeze(1, 0)
	hand(1, "cow")
	await put(0, "winterhide_avalancheetah", 1)
	await g.cmd_floop(0, "creature", 1)
	ok(g.frozen_count(1) == 2, "Зимняя Шкура: заморозила ещё землю соперника")


# ================================================================= 14: Мятный Дворецкий

func t_pb2_low_hand() -> void:
	mixed(0, "swamp", "lava")
	var t = await put(0, "tinder_tyrant", 0)     # 2 ATK
	var m = await put(0, "muckatana_the_exploiter", 1)
	hand(0, "cow")
	ok(g.atk_of(0, 0) == 4, "Трутовый тиран: 1 карта на руке — атака ×2")
	ok(g.atk_of(0, 1) == 2 + 2 * 2, "Грязатана: +2 за каждого игрока с 1 картой или меньше")
	hand(0, "cow")
	ok(g.atk_of(0, 0) == 2, "Трутовый тиран: 2 карты — обычная атака")
	var mush = hand(0, "mushkaginawa_the_free")
	ok(g.cost_of(0, mush) == 2, "Мушкагинава: с другими картами на руке — 2")
	g.players[0].hand = [mush]
	ok(g.cost_of(0, mush) == 0, "Мушкагинава: единственная карта — на 2 дешевле")
	ok(t != null and m != null, "…")


func t_pb2_sludge_marshuko() -> void:
	var x = await put(1, "drooling_dude", 0)
	var s = hand(0, "summon_sludge")
	bot.answers = ["Сыграть бесплатно"]
	await g.discard_card(0, s)
	ok(x.damage == 2, "Призыв слизи: сброшен — сыгран бесплатно")
	var m = hand(0, "marshuko_the_stalker")
	bot.answers = ["Сыграть бесплатно"]
	await g.discard_card(0, m)
	ok(g.where(m.uid)["zone"] == "creature", "Болотуко: сброшен — сыгран бесплатно")


func t_pb2_timematron_wizards() -> void:
	hand(0, "cow")
	hand(0, "cow")
	hand(0, "cow")
	await put(0, "timematron", 0)
	ok(g.players[0].hand.size() == 1, "Времятрон: входя, сбрось 2")
	await g.destroy_creature(0, 0)
	ok(g.players[0].hand.size() == 3, "Времятрон: уходя, возьми 2")
	await put(0, "wasteland_wizard", 1)
	ok(g.players[0].hand.size() == 2, "Волшебник пустошей: сбрось карту")
	await put(0, "fenunchaku_the_renegade", 2)
	ok(g.players[0].hand.is_empty(), "Фенунчаку: сбрось всю руку")


func t_pb2_spells() -> void:
	mixed(0, "swamp", "lava")
	var x = await put(1, "drooling_dude", 0)
	await play(0, hand(0, "incinerate"))
	ok(x.damage == 5, "Испепеление: пустая рука — 5 урона")
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "searing_insight"))
	ok(g.burning(x) and g.players[0].hand.size() == n + 3, "Обжигающее озарение: поджёг и 3 карты")
	g.players[0].actions = 2
	hand(0, "cow")
	var y = await put(0, "cow", 1)
	bot.answers = [spot(0, 1)]
	await play(0, hand(0, "triple_threat"))
	ok(g.tokens(y, "atk_tok") == 3, "Тройная угроза: 3 жетона атаки")
	await play(0, hand(0, "boxing_day"))
	ok(g.tokens(y, "atk_tok") == 4, "День подарков: жетон атаки каждому своему существу")


func t_pb2_flare() -> void:
	mixed(0, "swamp", "lava")
	await play(0, hand(0, "brilliant_flare"))
	ok(g.players[0].hand.size() == 5, "Блестящая вспышка: 5 карт")
	await g._end_turn(0)
	ok(g.players[0].hand.size() == 1, "Блестящая вспышка: в конце хода осталась 1 карта")


func t_pb2_trial() -> void:
	mixed(0, "swamp", "lava")
	var a = top(0, "cow")
	var b = top(0, "drooling_dude")
	bot.answers = [b.uid, "Взять на руку"]
	await play(0, hand(0, "trial_by_fire"))
	ok(g.where(b.uid)["zone"] == "creature" and g.players[0].hand.has(a), "Испытание огнём: одну сыграл, другую взял (пустая рука)")
	# Игрок: сброшенного Испытанием огнём Болотуко можно сыграть бесплатно.
	hand(0, "cow")
	hand(0, "cow")
	var m = top(0, "marshuko_the_stalker")
	var c = top(0, "phyllis")
	bot.answers = [c.uid, spot(0, 1), "Сыграть бесплатно", spot(0, 2)]
	await play(0, hand(0, "trial_by_fire"))
	ok(g.where(c.uid)["zone"] == "creature" and g.where(m.uid)["zone"] == "creature",
		"Испытание огнём: сброшенного Болотуко можно сыграть бесплатно")


func t_pb2_creatures() -> void:
	var r = await put(0, "molten_ritualist", 0)
	var n1: int = g.players[1].hand.size()
	await g.cmd_floop(0, "creature", 0)
	ok(g.players[1].hand.size() == n1 + 1, "Расплавленный ритуалист: игроки с 1 картой или меньше берут карту")
	var x = await put(1, "drooling_dude", 0)
	g.players[0].hand.clear()
	var fuel = hand(0, "cow")
	bot.answers = [fuel.uid, spot(1, 0)]
	await put(0, "flameingo_ash_keeper", 1)
	ok(g.burning(x), "Хранитель пепла: сбросил карту — поджёг")
	await put(0, "lava_lamprey_eels", 2)
	g.players[0].hand.clear()
	hand(0, "cow")
	bot.answers = [spot(1, 0)]
	await g.cmd_activate(0, "creature", 2)
	ok(g.tokens(x, "burn") == 2, "Лавовые миноги: сбрось карту — подожги")
	var sh = await put(0, "surprised_shearer", 3)
	bot.answers = [spot(1, 0)]
	var n: int = g.players[1].hand.size()
	await g.cmd_floop(0, "creature", 3)
	ok(x.damage == 4 and g.players[1].hand.size() == n + 1, "Удивлённый стригаль: 2 урона, его хозяин берёт карту")
	ok(r != null and sh != null, "…")


func t_pb2_bulkunai_necro_dusk() -> void:
	var b = await put(0, "bulkunai_the_leech", 0)
	b.damage = 5
	hand(0, "cow")
	hand(0, "cow")
	await g.cmd_activate(0, "creature", 0)
	ok(b.damage == 2 and not g.can_activate(0, "creature", 0), "Пиявкунай: сбрось — снять 3, раз за ход")
	g.players[0].discard.append(mk("drooling_dude"))
	g.players[1].discard.append(mk("cow", 1))
	await put(0, "necromagus", 1)
	ok(g.players[1].hand.size() == 1, "Некромаг: каждый игрок берёт существо из сброса")
	await put(1, "cow", 3)
	await put(0, "duskama_the_betrayer", 2)
	ok(g.players[0].creatures.any(func(c): return c != null and g.tokens(c, "atk_tok") > 0), "Сумракама: сбросил — жетон атаки")


func t_pb2_lamplighter() -> void:
	var cow = top(0, "cow")
	ok(g.xray_top(0) == null, "Светлячок-фонарщик: без него колода закрыта")
	await put(0, "firefly_lamplighter", 0)
	ok(g.xray_top(0) == cow and g.legal_commands(0).has({"cmd": "play", "uid": cow.uid, "lane": 1}),
		"Светлячок-фонарщик: пустая рука, верх колоды открыт и играется")
	g.players[0].hand.append(mk("cow"))
	g.players[0].hand.append(mk("cow"))
	ok(g.xray_top(0) == null, "Светлячок-фонарщик: 2 карты в руке, колода закрыта")
	g.players[0].hand.pop_back()
	ok(g.xray_top(0) == cow, "Светлячок-фонарщик: 1 карта в руке, верх открыт")
	ok(g.xray_top(1) == null, "Светлячок-фонарщик: у соперника колода закрыта")
	var eye = top(0, "evil_eye")
	var acts: int = g.players[0].actions
	await play(0, eye, 1)
	ok(g.players[0].creatures[1] == eye and g.players[0].actions == acts, "Светлячок-фонарщик: первая по обычной цене")
	ok(g.xray_top(0) == cow and g.cost_of(0, cow) == 1, "Светлячок-фонарщик: следующая на 1 дороже")
	var third = top(0, "cow")
	top(0, "cow")
	await play(0, g.xray_top(0), 2)
	ok(g.players[0].actions == acts - 1, "Светлячок-фонарщик: за вторую заплачено 1 действие")
	ok(g.cost_of(0, third) == 2 and not g.can_play(0, third.uid, 3), "Светлячок-фонарщик: третья стоит 2, на 1 действие не сыграть")
	g.players[0].creatures[0].lost_abilities = true
	ok(g.xray_top(0) == null, "Светлячок-фонарщик: без способностей колода закрыта")


func t_pb2_buildings() -> void:
	await build(0, "community_forge", 0)
	await put(0, "cow", 0)
	await put(1, "cow", 0)
	ok(g.atk_of(0, 0) == 3 and g.atk_of(1, 0) == 3, "Общинная кузница: +2 всем в зоне")
	await build(0, "temple_of_the_torch", 1)
	var x = await put(1, "drooling_dude", 1)
	bot.answers = [spot(1, 1)]
	await g.cmd_floop(0, "building", 1)
	ok(g.tokens(x, "burn") == 2, "Храм факела: пустая рука — поджечь дважды")


func t_pb2_hero() -> void:
	g.players[0].hero_card = "peppermint_butler"
	var x = await put(1, "drooling_dude", 0)
	hand(0, "cow")
	hand(0, "cow")
	ok(not g.can_hero_power(0), "Мятный Дворецкий: с 2 картами нельзя")
	g.players[0].hand.pop_back()
	await g.cmd_hero_power(0)
	ok(x.damage == 2, "Мятный Дворецкий: 2 урона существу")


# ================================================================= 14: Волшебник

func t_mm_spells_matter() -> void:
	mixed(0, "sandy", "cute")
	await put(0, "chalice_the_cruel", 0)
	await put(0, "erlenmeyer_the_calm", 1)
	await build(0, "spellfire_conduit", 2)
	var x = await put(1, "drooling_dude", 0)
	var hp: int = g.players[1].hp
	var p2 = hand(0, "punch_potion")
	await play(0, hand(0, "bull_sigil"))
	ok(x.damage == 2 and g.players[1].hp == hp - 1, "Чаша +2 существу соперника, Проводник огня чар: 1 урон игроку")
	ok(g.cost_of(0, p2) == 0, "Эрленмейер: второе заклинание дешевле")


func t_mm_quaffius() -> void:
	mixed(0, "sandy", "cute")
	await put(0, "quaffius_the_chemist", 0)
	var x = await put(1, "drooling_dude", 0)
	bot.answers = ["Существо", spot(1, 0), "Ещё раз", "Существо", spot(1, 0)]
	await play(0, hand(0, "punch_potion"))
	ok(x.damage == 6, "Глотиус Химик: первое заклинание сработало дважды")


func t_mm_quaffius_crystal_ball() -> void:
	mixed(0, "sandy", "cute")
	await put(0, "quaffius_the_chemist", 0)
	top(0, "math_potion")
	top(0, "math_potion")
	var potion: String = CardDB.get_def("math_potion")["name"]
	bot.answers = [potion]
	bot.asked.clear()
	await play(0, hand(0, "crystal_ball"))
	var again: Array = bot.asked.filter(func(r): return String(r.get("prompt", "")).begins_with("Глотиус"))
	ok(again.size() == 1 and String(again[0]["prompt"]).contains(CardDB.get_def("crystal_ball")["name"]),
		"Глотиус Химик: повторяет Хрустальный шар, а не сыгранное им Математическое зелье")


func t_mm_punch_potion_self() -> void:
	mixed(0, "sandy", "cute")
	var hp: int = g.players[0].hp
	bot.answers = ["Игрок: " + g.players[0].name]
	await play(0, hand(0, "punch_potion"))
	ok(g.players[0].hp == hp - 3, "Зелье удара: можно выбрать себя")
	var req := {"kind": "option", "player": 0, "prompt": "Зелье удара: кому 3 урона?",
		"options": ["Игрок: " + g.players[1].name, "Игрок: " + g.players[0].name, "Существо"]}
	ok(AIHelper.without_own_players(g, req)["options"] == ["Игрок: " + g.players[1].name, "Существо"],
		"Зелье удара: ИИ не видит себя среди целей")


func t_mm_potions() -> void:
	mixed(0, "sandy", "cute")
	await play(0, hand(0, "cheat_sheet"))
	var a = hand(0, "punch_potion")
	var b = hand(0, "heart_potion")
	ok(g.cost_of(0, a) == 0 and g.cost_of(0, b) == 0, "Шпаргалка: «Зелья» на 1 дешевле")
	g.players[0].discard.append(mk("math_potion"))
	g.players[0].discard.append(mk("yolked_potion"))
	await put(0, "bottlebeard_the_cool", 0)
	ok(g.players[0].hand.filter(func(c): return g.is_potion(c)).size() == 4, "Бутылобород: 2 «Зелья» из сброса на руку")


func t_mm_discard_counts() -> void:
	mixed(0, "sandy", "cute")
	for i in 4:
		g.players[0].discard.append(mk("punch_potion"))
	var x = await put(1, "drooling_dude", 0)
	await play(0, hand(0, "infernal_spade"))
	ok(x.damage == 4, "Адская лопата: 1 урон за заклинание в сбросе")
	var v = await put(0, "eye_viner", 0)
	ok(g.tokens(v, "atk_tok") == 3, "Глазолоза: 3+ заклинаний в сбросе — 3 жетона атаки")
	bot.answers = [spot(0, 0)]
	await play(0, hand(0, "sword_horn"))
	ok(g.tokens(v, "atk_tok") == 3 + 1 + 2, "Рог-меч: 1 + по жетону за каждые 2 заклинания в сбросе")


func t_mm_heal_cards() -> void:
	mixed(0, "sandy", "cute")
	var x = await put(0, "drooling_dude", 0)
	x.damage = 3
	bot.answers = [spot(0, 0)]
	await play(0, hand(0, "yolked_potion"))
	ok(x.damage == 1 and g.tokens(x, "atk_tok") == 2, "Желтковое зелье: снять 2, 2 жетона атаки")
	g.players[0].hp = 22
	var n: int = g.players[0].hand.size()
	bot.answers = ["Игрок: Финн"]
	await play(0, hand(0, "heart_potion"))
	ok(g.players[0].hp == 25 and g.players[0].hand.size() == n + 1, "Сердечное зелье: максимум жизней — карта")
	await put(0, "axolotl", 1)
	g.players[0].hp = 20
	bot.answers = ["Финн"]
	await g.cmd_floop(0, "creature", 1)
	ok(g.players[0].hp == 23, "Аксолотль: 3 жизни")


func t_mm_vial_phialis() -> void:
	mixed(0, "sandy", "cute")
	var mine = await put(0, "drooling_dude", 0)
	mine.damage = 4
	var x = await put(1, "drooling_dude", 0)
	await play(0, hand(0, "vial_of_vengeance"))
	ok(x.damage == 4 and g.players[0].hand.has(mine) and mine.damage == 0, "Фиал мести: урон перенесён, своё существо на руку")
	hand(0, "punch_potion")
	g.players[0].hp = 10
	bot.answers = ["Показать все: 1", "Финн"]
	await put(0, "phialis_the_caretaker", 1)
	ok(g.players[0].hp == 12, "Фиалис: 2 жизни за показанное заклинание")


## Игрок: Фиалис показывает не обязательно все заклинания — их можно выбрать.
func t_mm_phialis_pick() -> void:
	var a = hand(0, "punch_potion")
	hand(0, "punch_potion")
	hand(0, "cow")
	g.players[0].hp = 10
	bot.answers = ["Выбрать", a.uid, null, "Финн"]
	await put(0, "phialis_the_caretaker", 1)
	ok(g.players[0].hp == 12, "Фиалис: показано одно выбранное заклинание из двух — 2 жизни")
	var req: Dictionary = bot.asked.filter(func(r): return r["kind"] == "hand_card")[0]
	ok(req["options"].size() == 2, "Фиалис: на выбор только заклинания с руки")


func t_mm_misc() -> void:
	mixed(0, "sandy", "cute")
	g.players[0].discard.append(mk("punch_potion"))
	await put(0, "canopic_the_ceremonial", 0)
	ok(g.players[0].deck.back().id == "punch_potion", "Канопа: заклинание из сброса на верх колоды")
	await play(0, hand(0, "phoenix_talisman"))
	var c = await put(0, "cow", 1)
	await g.destroy_creature(0, 1)
	ok(g.players[0].hand.has(c), "Талисман феникса: уничтоженное существо вернулось на руку")
	var t = top(0, "cow")
	bot.answers = ["Корова", {"p": 0, "lane": 2, "row": "creature"}]
	await play(0, hand(0, "crystal_ball"))
	ok(g.where(t.uid)["zone"] == "creature", "Хрустальный шар: угадал — сыграл бесплатно")
	await put(1, "cow", 0)
	g.players[1].creatures[0].flags["burn"] = 2
	await g.freeze(1, 3)
	var y = await put(1, "drooling_dude", 2)
	bot.answers = [spot(1, 2)]
	await play(0, hand(0, "bladespire_maelstrom"))
	ok(y.damage == 6 or g.players[1].creatures[2] == null, "Водоворот клинков: 3 жетона — 6 урона")


func t_mm_storms() -> void:
	mixed(0, "sandy", "cute")
	var x = await put(1, "drooling_dude", 0)
	for i in 3:
		top(0, "punch_potion")
	await play(0, hand(0, "spellstorm"))
	ok(x.damage == 2 and g.players[0].actions == 3, "Буря заклинаний: 2 урона и +1 действие за каждое сброшенное заклинание")
	for i in 3:
		top(0, "punch_potion")
	var y = await put(1, "drooling_dude", 1)
	bot.answers = [spot(1, 1)]
	await put(0, "spillith_the_crippler", 0)
	ok(y.damage == 6 or g.players[1].creatures[1] == null, "Пролитиус: 2 урона за каждое сброшенное заклинание")
	g.players[0].hand = [mk("cow")]
	await play(0, hand(0, "math_potion"))
	ok(g.players[0].hand.size() == 3, "Математическое зелье: 3 карты, одна обратно")


func t_mm_brightheart() -> void:
	mixed(0, "sandy", "cute")
	await build(0, "brightheart_nexus", 0)
	await put(1, "cow", 1)
	g.players[0].hp = 20
	bot.answers = [spot(1, 1), "Финн"]
	await play(0, hand(0, "bull_sigil"))
	ok(g.players[0].hp == 21, "Узел светлого сердца: нет существ в зоне — 1 жизнь")


func t_mm_hero() -> void:
	g.players[0].hero_card = "magic_man"
	hand(0, "cow")
	ok(not g.can_hero_power(0), "Волшебник: без заклинания нельзя")
	hand(0, "punch_potion")
	var n: int = g.players[0].hand.size()
	await g.cmd_hero_power(0)
	ok(g.players[0].hand.size() == n and not g.can_hero_power(0), "Волшебник: сбросил заклинание, взял карту, раз за ход")
	g.players[0].hero_card = "magic_man_classic"
	var x = await put(1, "drooling_dude", 0)
	mixed(0, "sandy", "cute")
	g.players[0].turn = {}
	await play(0, hand(0, "spellstorm"))
	ok(x.damage >= 4, "Волшебник (Набор героев): карта за 2 — ещё 2 урона")


# ================================================================= 09: Во имя славы

func t_fg_vs_land_spells() -> void:
	var pairs := {"confectionary_ring": ["cute", "corn"], "ring_of_third_eye": ["plain", "corn"], "husker_amulet": ["corn", "cute"],
		"scroll_of_bad_breath": ["swamp", "cute"], "lucky_penny": ["sandy", "plain"], "popcorn_power": ["corn", "plain"],
		"magic_lamp": ["swamp", "sandy"], "pink_candy": ["plain", "sandy"], "scroll_of_fresh_breath": ["cute", "swamp"],
		"snake_eyes": ["sandy", "swamp"]}
	for id in pairs:
		_fresh()
		lands(0, pairs[id][0])
		lands(1, pairs[id][1])
		var me = await put(0, "drooling_dude", 0)    # 3 ATK
		var x = await put(1, "phyllis", 0)           # 2/7
		await play(0, hand(0, id))
		await g.cmd_attack(0, 0)
		ok(x.damage == 5, "%s: +2 против существа на земле «%s» (got %d)" % [CardDB.get_def(id)["name"], pairs[id][1], x.damage])
		ok(me != null, "…")


func t_fg_damage_spells() -> void:
	lands(0, "corn")
	var x = await put(1, "drooling_dude", 0)
	var gb = hand(0, "grape_butt")
	ok(not g.can_play(0, gb.uid), "Виноградный зад: без некукурузной карты нельзя")
	await play(0, hand(0, "full_metal_racket"))
	ok(x.damage == 2, "Цельнометаллический гвалт: 2 урона")
	await play(0, gb)
	ok(x.damage == 7, "Виноградный зад: 5 урона")


func t_fg_egg_braces() -> void:
	var c = top(0, "cow")
	var k = top(0, "field_stalker")
	bot.answers = [k.uid]
	await play(0, hand(0, "incredible_egg"))
	ok(g.players[0].hand.has(k) and g.players[0].discard.has(c), "Невероятное яйцо: кукурузную на руку, остальное в сброс")
	for i in 10:
		g.players[0].discard.append(mk("cow"))
	g.players[0].hp = 10
	lands(0, "swamp")
	await play(0, hand(0, "ogre_braces"))
	ok(g.players[0].hp == 12, "Подтяжки огра: 1 жизнь за 5 карт сброса")


func t_fg_ready_spells() -> void:
	lands(0, "plain")
	var a = await put(0, "cow", 0)
	var b = await put(0, "field_stalker", 1)
	var c = await put(0, "corn_ronin", 2)
	for x in [a, b, c]:
		x.exhausted = true
	await play(0, hand(0, "kung_fu_power"))
	ok(not a.exhausted and not b.exhausted and c.exhausted, "Сила кунг-фу: по одному существу каждого типа")
	a.exhausted = true
	a.flooped = true
	await play(0, hand(0, "puma_paw"))
	ok(not a.exhausted and a.temp_atk == 2, "Лапа пумы: подготовить флюпнутое, +2")
	g.players[0].actions = 2
	b.moved_this_turn = true
	b.exhausted = true
	await play(0, hand(0, "socks_of_fortitude"))
	ok(not b.exhausted and b.temp_atk == 2, "Носки стойкости: сменившие зону готовы, +2")


func t_fg_board_spells() -> void:
	lands(0, "rainbow")
	var x = await put(1, "drooling_dude", 0)
	await play(0, hand(0, "master_of_disguise"))
	ok(g.atk_of(1, 0) == 2, "Мастер маскировки: −1 существам соперника")
	g.players[0].actions = 2
	var a = await put(0, "cow", 0)
	await play(0, hand(0, "ring_of_damage"))
	ok(g.atk_of(0, 0) == 3, "Кольцо урона: +2 своим")
	lands(0, "sandy")
	g.players[0].actions = 2
	bot.answers = [spot(1, 0)]
	await play(0, hand(0, "portal_of_unsummoning"))
	ok(g.players[1].hand.has(x), "Портал отзыва: существо на руку владельца")
	var y = await put(1, "drooling_dude", 2)
	g.players[0].actions = 2
	bot.answers = [{"p": 1, "lane": 3, "row": "creature"}]
	await play(0, hand(0, "portal_to_nowhere"))
	ok(g.players[1].creatures[3] == y, "Портал в никуда: соперник сдвинут в соседнюю зону")
	g.players[0].actions = 2
	await play(0, hand(0, "psychic_tempest"))
	ok(g.players[0].hand.has(a), "Психическая буря: свои существа на руку")


func t_fg_swamp_spells() -> void:
	lands(0, "swamp")
	g.players[0].discard.append(mk("cow"))
	g.players[0].discard.append(mk("drooling_dude"))
	await play(0, hand(0, "raise_the_dead"))
	ok(g.players[0].creatures.any(func(c): return c != null), "Восстание мертвецов: существо из сброса в игру")
	lands(0, "corn")
	var a = await put(0, "cow", 2)
	g.players[0].lands[2]["type"] = "swamp"
	await play(0, hand(0, "witch_way"))
	ok(a.temp_atk == 2, "Ведьмин путь: на болоте +2")


func t_fg_misc_spells() -> void:
	lands(0, "plain")
	var a = await put(0, "cow", 0)
	var b = await put(0, "evil_eye", 3)
	await play(0, hand(0, "spell_warp"))
	ok(g.players[0].creatures[3] == a and g.players[0].creatures[0] == b, "Искажение чар: поменял местами")
	bot.answers = [{"p": 0, "lane": 0, "row": "land"}, "Лавовая равнина", null]
	lands(0, "rainbow")
	await play(0, hand(0, "musical_chair"))
	ok(g.players[0].lands[0]["type"] == "lava", "Музыкальный стул: земля заменена")
	lands(0, "plain")
	var s = await build(0, "schoolhouse", 0)
	bot.answers = [{"p": 0, "lane": 2, "row": "building"}]
	bot.skip_optional = true
	await play(0, hand(0, "tax_reduction"))
	ok(g.players[0].buildings[2] == s, "Снижение налогов: строение переехало")
	bot.skip_optional = false
	lands(0, "rainbow")
	for i in 7:
		hand(1, "cow")
	var hp: int = g.players[1].hp
	g.players[0].actions = 2
	await play(0, hand(0, "witch_slap"))
	ok(g.players[1].hand.size() == 5 and g.players[1].hp == hp - 2, "Ведьмина пощёчина: сброс до 5, урон за каждую")


func t_fg_buildings_a() -> void:
	await build(0, "elf_hut", 0)
	await put(0, "cow", 0)
	await put(1, "cow", 0)
	var n: int = g.players[0].hand.size()
	await g.cmd_activate(0, "building", 0)
	ok(g.players[0].hand.size() == n + 2, "Хижина эльфа: по карте за существо в зоне")
	await build(0, "fountain_of_tears", 1)
	var x = await put(0, "drooling_dude", 1)
	x.damage = 3
	ok(g.atk_of(0, 1) == 6, "Фонтан слёз: ровно 3 урона — +3")
	for i in 10:
		g.players[0].discard.append(mk("cow"))
	await build(0, "fright_tower", 0)
	bot.answers = [spot(0, 0)]
	await g.cmd_activate(0, "building", 0)
	ok(g.atk_of(0, 0) == 3, "Башня страха: +1 за каждые 5 карт сброса")


func t_fg_buildings_b() -> void:
	var ig = await build(0, "igloo_of_sanctuary", 1)
	var a = await put(0, "cow", 0)
	ok(not g.can_floop(0, "building", 1), "Иглу-убежище: без переместившегося существа нельзя")
	await g.move_creature(0, 0, 1)
	await g.cmd_floop(0, "building", 1)
	ok(a.temp_atk == 3 and ig.flooped, "Иглу-убежище: +3 переместившемуся")
	await build(0, "nice_windmill", 2)
	var b = await put(0, "drooling_dude", 2)
	b.damage = 3
	bot.answers = ["Снять 2 урона"]
	await g.cmd_activate(0, "building", 2)
	ok(b.damage == 1, "Добрая мельница: снять 2 урона")
	await build(0, "sand_pyramid", 3)
	var c = await put(0, "cow", 3)
	var d = await put(1, "cow", 3)
	g.players[0].actions = 2
	await g.cmd_activate(0, "building", 3)
	ok(g.players[0].hand.has(c) and g.players[1].hand.has(d), "Песчаная пирамида: все существа зоны на руку")


func t_fg_buildings_c() -> void:
	await build(0, "shadowy_pyramid", 0)
	var n: int = g.players[0].hand.size()
	await g.cmd_floop(0, "building", 0)
	ok(g.players[0].hand.size() == n + 1, "Тёмная пирамида: карта без сброса, если нет существа в зоне")
	await build(0, "silo_of_justice", 1)
	var x = await put(1, "drooling_dude", 1)
	var hp: int = g.players[1].hp
	await g.cmd_activate(0, "building", 1)
	ok(x.damage == 1 and g.players[1].hp == hp - 1, "Амбар правосудия: 1 урон существу, 1 жизнь хозяину")
	await build(0, "temple_of_the_sun", 2)
	lands(0, "sandy")
	var s = hand(0, "sand_knights")
	bot.answers = ["Вернуть на руку"]
	await play(0, s, 2)
	ok(g.players[0].hand.has(s), "Храм солнца: песчаное существо вернулось на руку")
	await build(0, "yellow_lighthouse", 3)
	await put(1, "cow", 3)
	var n1: int = g.players[1].hand.size()
	await g._start_turn(0)
	ok(g.players[1].hand.size() == n1 + 1, "Жёлтый маяк: у кого существо в зоне — берёт карту")


func t_fg_apple_paladin_ogre() -> void:
	lands(0, "corn")
	await put(0, "apple_bully", 0)
	g.turn_player = 1
	await g.flip_land(0, 0, true)
	ok(not g.players[0].lands[0]["flipped"], "Яблочный задира: соперник не переворачивает его землю")
	g.turn_player = 0
	await put(0, "black_paladin", 1)
	hand(1, "cow")
	await g.force_discard(1, 1)
	ok(g.atk_of(0, 1) == 2, "Чёрный паладин: +1 за сброшенную карту")
	await put(0, "blue_ogre", 2)
	await g._draw(0)
	await g._draw(0)
	ok(g.atk_of(0, 2) == 3, "Синий огр: +1 за каждую взятую карту")


func t_fg_gnomes() -> void:
	var ids := {"blue_gnome": "swamp", "fancy_pants_gnome": "corn", "green_gnome": "plain", "life_beater_gnome": "sandy", "yellow_gnome": "cute"}
	for id in ids:
		_fresh()
		lands(1, ids[id])
		g.players[1].lands[1]["type"] = "lava"
		var x = await put(1, "drooling_dude", 0)
		var y = await put(1, "drooling_dude", 1)
		await put(0, id, 0)
		await g.cmd_floop(0, "creature", 0)
		ok(x.damage == 1 and y.damage == 0, "%s: 1 урон существам на «%s»" % [CardDB.get_def(id)["name"], ids[id]])


func t_fg_slimeys() -> void:
	mixed(0, "plain", "sandy")
	g.players[0].lands[2]["type"] = "corn"
	var n: int = g.players[0].hand.size()
	await put(0, "lime_slimey", 0)
	ok(g.players[0].hand.size() == n + 2, "Лаймовый слизень: 3 типа земель — 2 карты")
	await put(0, "yellow_slimey", 1)
	ok(g.atk_of(0, 1) == 3, "Жёлтый слизень: +3")
	var hp: int = g.players[1].hp
	await put(0, "orange_slimey", 2)
	ok(g.players[1].hp == hp - 3, "Оранжевый слизень: 3 урона сопернику")
	var x = await put(0, "drooling_dude", 3)
	x.damage = 5
	await put(0, "strawberry_slimey", 0)
	ok(x.damage == 1, "Клубничный слизень: снять 4 урона")
	var y = await put(1, "cow", 1)
	bot.answers = [spot(1, 1)]
	await put(0, "blue_slimey", 1)
	ok(g.players[1].hand.has(y), "Синий слизень: существо зоны на руку")


func t_fg_defenders_attackers() -> void:
	var defs := {"davey_bones": "sandy", "ghost_hag": "plain", "ghost_tree": "corn", "ghost": "swamp"}
	for id in defs:
		_fresh()
		lands(0, defs[id])
		var a = await put(0, "drooling_dude", 0)
		await put(1, id, 0)
		await g.cmd_attack(0, 0)
		ok(a.damage == 3, "%s: +2 при защите от существа на «%s»" % [CardDB.get_def(id)["name"], defs[id]])
	var atks := {"rocktopus": "sandy", "sea_hag": "swamp", "timmy_magic_eyes": "plain", "well_dressed_wolf": "corn"}
	for id in atks:
		_fresh()
		lands(1, atks[id])
		await put(0, id, 0)
		var x = await put(1, "drooling_dude", 0)
		await g.cmd_attack(0, 0)
		ok(x.damage == 4, "%s: +1 при нападении на существо на «%s»" % [CardDB.get_def(id)["name"], atks[id]])


func t_fg_type_def() -> void:
	mixed(0, "plain", "sandy")
	for id in ["cotton_devil", "little_freezy", "polterclops", "swamp_horn"]:
		await put(0, id, 0)
		ok(g.def_of(0, 0) == 1 + 2, "%s: +1 к защите за тип земель" % CardDB.get_def(id)["name"])
	await put(0, "cactus_thug", 1)
	await put(0, "field_stalker", 2)
	ok(g.atk_of(0, 2) == 2, "Кактус-громила: соседнее кукурузное +1")
	await put(0, "cowsper", 3)
	ok(g.def_of(0, 2) == 11, "Коровидение: соседнее кукурузное +1 к защите")


func t_fg_taco_bat_ninja() -> void:
	lands(1, "plain")
	g.players[1].lands[0]["type"] = "corn"
	var a = await put(1, "drooling_dude", 0)
	var b = await put(1, "drooling_dude", 1)
	lands(0, "corn")
	await put(0, "captain_taco", 2)
	ok(a.damage == 0 and b.damage == 1, "Капитан Тако: 1 урон существам не на кукурузе")
	mixed(0, "corn", "plain")
	await put(0, "corn_bat", 1)
	bot.answers = [spot(1, 1)]
	await g.cmd_activate(0, "creature", 1)
	ok(b.damage == 3, "Кукурузная летучая мышь: урон = число типов земель")
	bot.answers = [spot(1, 0)]
	await put(0, "gold_ninja", 3)
	ok(a.damage == 2, "Золотой ниндзя: урон = число типов земель")


func t_fg_leave_effects() -> void:
	lands(0, "cute")
	var d = await put(0, "diamond_dan", 0)
	await g.destroy_creature(0, 0)
	ok(g.players[0].hand.has(d), "Алмазный Дэн: ушёл с доброй земли — на руку")
	lands(0, "corn")
	await put(0, "ethan_allfire", 1)
	var n: int = g.players[0].hand.size()
	await g.destroy_creature(0, 1)
	ok(g.players[0].hand.size() == n + 4, "Итан Всеогонь: по карте за кукурузное поле")
	var bottom = mk("cow")
	g.players[0].deck.push_front(bottom)
	await put(0, "ghost_chest_burster", 2)
	await g.destroy_creature(0, 2)
	ok(g.players[0].hand.has(bottom), "Призрачный мимимимик: взял нижнюю карту колоды")
	var x = await put(1, "drooling_dude", 3)
	await put(0, "green_snakey", 3)
	await g.destroy_creature(0, 3)
	ok(x.damage == 1, "Зелёная змейка: уходя, 1 урон существу в зоне")
	await put(0, "lt_mushroom", 0)
	for i in 4:
		hand(0, "cow")
	g.turn_player = 1
	await g.destroy_creature(0, 0)
	ok(g.players[1].hand.size() <= 1, "Лейтенант Грибок: ушёл в ход соперника — тот сбрасывает 3")


func t_fg_djinni_eye_fish() -> void:
	await put(0, "djinni_ghost", 0)
	await g.cmd_floop(0, "creature", 0)
	ok(g.cost_of(0, hand(0, "drooling_dude")) == 2 and int(g.turn_value(0, "spell_discount")) == 2, "Призрак-джинн: следующее заклинание на 2 дешевле")
	var t = top(0, "cow")
	bot.answers = ["Под низ колоды"]
	await put(0, "eye_guy", 1)
	await g._start_turn(0)
	ok(g.players[0].deck.front() == t or g.players[0].deck.back() != t, "Глазастик: верхнюю карту под низ")
	lands(0, "plain")
	var hp: int = g.players[1].hp
	await put(0, "fisher_fish", 2)
	ok(g.players[1].hp == hp - 2, "Рыба-рыболов: на синей равнине — 2 урона сопернику")


func t_fg_ghost_ninja_stump() -> void:
	await put(0, "ghost_ninja", 0)
	await g.cmd_attack(0, 0)
	g.turn_player = 1
	g.turn_number += 1
	mixed(1, "corn", "corn")
	var sp = hand(1, "cross_pollination")
	ok(not g.spell_castable(1, sp), "Призрачный ниндзя: в свой ход соперник не играет заклинания")
	g.turn_number += 2
	ok(g.spell_castable(1, sp), "…а потом снова может")
	g.turn_player = 0
	await put(0, "golden_axe_stump", 1)
	var hp: int = g.players[1].hp
	await g._draw(1)
	ok(g.players[1].hp == hp - 1, "Пень с золотым топором: соперник взял карту — 1 урон")


func t_fg_floopers() -> void:
	mixed(0, "corn", "sandy")
	g.players[0].lands[0]["type"] = "corn"
	await put(0, "giant_mummy_hand", 1)
	var x = await put(1, "drooling_dude", 0)
	bot.answers = [spot(1, 0)]
	await g.cmd_floop(0, "creature", 1)
	ok(x.damage == 2, "Гигантская рука мумии: урон за соседние кукурузные поля")
	await put(0, "golden_jackal", 3)
	hand(0, "sand_knights")
	await g.cmd_floop(0, "creature", 3)
	ok(x.damage == 3, "Золотой шакал: сбросил песчаную — 1 урон каждому")
	await put(0, "blue_merlock", 2)
	hand(0, "cow")
	var n: int = g.players[0].hand.size()
	await g.cmd_floop(0, "creature", 2)
	ok(g.players[0].hand.size() == n, "Синий мерлок: взять и сбросить")


func t_fg_more() -> void:
	var o = await put(0, "green_party_ogre", 0)
	o.damage = 2
	await put(0, "cow", 1)
	await g.destroy_creature(0, 1)
	ok(o.damage == 1, "Зелёный огр-тусовщик: своё существо ушло — снять 1 урон")
	var w = await put(0, "cow", 2)
	w.damage = 4
	bot.answers = [spot(0, 2)]
	await put(0, "lady_beetle", 3)
	await g._start_turn(0)
	ok(g.players[0].hand.has(w), "Божья коровка: вернула раненое существо")
	g.players[0].hand.clear()
	var b = hand(0, "schoolhouse")
	await put(0, "log_knight", 1)
	await g.cmd_floop(0, "creature", 1)
	ok(g.players[0].buildings[1] == b, "Бревенчатый рыцарь: строение с руки в игру")


func t_fg_more2() -> void:
	await put(0, "paladim", 0)
	var a = await put(0, "cow", 1)
	a.moved_this_turn = true
	ok(g.atk_of(0, 1) == 4, "Паладим: сменившие зону +3")
	await put(0, "pentacutie", 2)
	var z = hand(1, "evil_eye")
	g.turn_player = 1
	ok(not g.can_play(1, z.uid), "Пентамилашка: соперник не играет карты за 0")
	g.turn_player = 0
	var x = await put(1, "drooling_dude", 0)
	await put(0, "pickler", 3)
	bot.answers = [spot(1, 0)]
	await g.cmd_activate(0, "creature", 3)
	ok(x.damage == 3 and g.players[0].creatures[3] == null, "Огурчик: уничтожить себя — 3 урона")
	lands(0, "swamp")
	await put(0, "pirate_bear", 3)
	ok(g.atk_of(0, 3) == 3, "Медведь-пират: на болоте атака ×3")


func t_fg_more3() -> void:
	await put(0, "quadurai", 0)
	for i in 4:
		hand(1, "cow")
	var hp: int = g.players[1].hp
	await g._start_turn(0)
	ok(g.players[1].hp == hp - 2, "Квадурай: 4+ карты на руке — 2 урона")
	var s = await put(0, "sack_of_pain", 1)
	s.damage = 6
	ok(g.atk_of(0, 1) == 8, "Мешок боли: ровно 6 урона — +6")
	lands(0, "cute")
	await put(0, "sand_jackal", 2)
	var x = await put(1, "cow", 2)
	x.damage = 3
	g.players[0].hp = 10
	await g.cmd_attack(0, 2)
	ok(g.players[0].hp == 13, "Песчаный шакал: на доброй земле победа — 3 жизни")
	for i in 3:
		hand(0, "cow")
		hand(1, "cow")
	var n0: int = g.players[0].hand.size()
	await put(0, "smoldering_elder", 3)
	ok(g.players[0].hand.size() == n0 - 2, "Тлеющий старейшина: каждый сбрасывает 2")


func t_fg_more4() -> void:
	lands(0, "plain")
	await put(0, "sun_king", 0)
	ok(g.corn_count(0) == 1, "Король-солнце: считается кукурузным полем")
	g.players[1].discard.append(mk("cow", 1))
	g.players[1].discard.append(mk("cow", 1))
	g.players[1].discard.append(mk("phyllis", 1))
	await put(0, "the_sludger", 1)
	bot.answers = ["Корова"]
	await g.cmd_floop(0, "creature", 1)
	ok(g.players[1].discard.size() == 1 and g.players[1].removed.size() == 2, "Тинник: все «Коровы» из сброса убраны из игры")
	var x = await put(1, "drooling_dude", 2)
	var w = await put(0, "travelin_wizard", 2)
	ok(g.players[1].creatures[2] == w and g.players[0].creatures[2] == x, "Странствующий волшебник: меняются сторонами")
	g.players[0].turn["spells"] = 2
	ok(g.cost_of(0, hand(0, "blueberry_pieclops")) == 2, "Черничный пироклоп: −1 за заклинание в этот ход")


# ================================================================= 18: Земля легенд

func t_ll_spells_a() -> void:
	lands(0, "swamp")
	var x = await put(1, "drooling_dude", 0)
	g.players[0].hp = 10
	await play(0, hand(0, "absorb_aether"))
	ok(g.players[1].creatures[0] == null and g.players[0].hp == 19, "Поглощение эфира: трижды — по разу за каждого игрока с пустой рукой")
	ok(x.owner == 1, "…")
	lands(0, "lava")
	var a = await put(1, "cow", 1)
	var b = await put(1, "cow", 2)
	g.players[0].actions = 2
	bot.answers = [spot(1, 1)]
	await play(0, hand(0, "ashcloud"))
	ok(a.damage == 2 and b.damage == 2, "Пепельное облако: цель и соседние существа соперника")


func t_ll_spells_b() -> void:
	lands(0, "plain")
	var x = await put(0, "cow", 0)
	hand(0, "cow")
	hand(0, "cow")
	await play(0, hand(0, "brainblades"))
	ok(g.tokens(x, "atk_tok") == 3, "Мозгоклинки: 1 + по жетону за каждую другую карту на руке")
	lands(0, "corn")
	await put(0, "cow", 1)
	g.players[0].actions = 2
	var hp: int = g.players[1].hp
	await play(0, hand(0, "buttering_ram"))
	ok(g.players[1].hp == hp - 4, "Масляный таран: 2 урона за каждое повёрнутое существо")


func t_ll_chill_conflag() -> void:
	lands(0, "ice")
	var x = await put(1, "drooling_dude", 0)
	await g.add_atk_tokens(x, 2)
	await g.freeze(1, 0)
	await play(0, hand(0, "chillwave"))
	ok(x.damage == 4, "Холодная волна: урон за жетоны, вдвое на замороженной земле")
	lands(0, "lava")
	var y = await put(1, "drooling_dude", 1)
	await g.burn_creature(0, 1, 1, 3)
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "conflagration"))
	ok(y.damage == 6 and g.players[0].hand.size() == n + 1, "Пожарище: урон за жетоны огня и карта")


func t_ll_chillwave_all() -> void:
	lands(0, "ice")
	var a = await put(1, "drooling_dude", 0)
	var b = await put(1, "drooling_dude", 1)
	var c = await put(1, "drooling_dude", 2)
	var d = await put(1, "drooling_dude", 3)
	var mine = await put(0, "drooling_dude", 0)
	await g.add_atk_tokens(a, 1)
	await g.burn_creature(0, 1, 0, 1)
	await g.add_atk_tokens(b, 1)
	await g.burn_creature(0, 1, 1, 1)
	await g.add_atk_tokens(d, 3)
	await g.add_atk_tokens(mine, 2)
	await g.freeze(1, 0)
	await g.freeze(1, 2)
	await play(0, hand(0, "chillwave"))
	# the ignition itself dealt 1 damage to a and b before the spell
	ok(a.damage == 1 + 4, "Холодная волна: жетон огня и жетон атаки на замороженной земле, 2 жетона вдвое")
	ok(b.damage == 1 + 2, "Холодная волна: обычная земля, урон по числу жетонов")
	ok(c.damage == 0, "Холодная волна: без жетонов урона нет, даже на замороженной земле")
	ok(d.damage == 3, "Холодная волна: 3 жетона атаки на обычной земле, 3 урона")
	ok(mine.damage == 0, "Холодная волна: свои существа не страдают")


func t_ll_cobnoblify() -> void:
	lands(0, "rainbow")
	var a = await put(0, "drooling_dude", 0)
	await play(0, hand(0, "cobnoblify"))
	var c = hand(0, "cow")
	await play(0, c, 0)
	ok(c.under.has(a) and g.atk_of(0, 0) == 1 + 3, "Початкогоблинизация: заменённое существо съедено")


func t_ll_buttercream_duke() -> void:
	lands(0, "corn")
	lands(1, "plain")
	g.players[1].lands[0]["type"] = "sandy"
	var x = await put(1, "drooling_dude", 0)
	var y = await put(1, "drooling_dude", 1)
	bot.answers = ["Песчаная земля"]
	await play(0, hand(0, "cranial_buttercream"))
	ok(x.damage == 0 and y.damage == 2, "Черепной крем: 2 урона всем не на выбранном типе")
	lands(0, "sandy")
	await put(0, "drooling_dude", 2)
	var z = await put(1, "cow", 2)
	await play(0, hand(0, "desert_duke_out"))
	ok(g.players[1].creatures[2] == null and z.owner == 1, "Пустынная разборка: дерутся, пока одно не погибнет")


func t_ll_energy_eye() -> void:
	lands(0, "corn")
	await play(0, hand(0, "energy_potion"))
	g.turn_player = 0
	await g._start_turn(0)
	ok(g.players[0].actions == 4, "Зелье энергии: +2 действия в следующий ход")
	lands(0, "plain")
	top(0, "cow")
	top(0, "evil_eye")
	top(0, "field_stalker")
	top(0, "sand_knights")
	top(0, "corn_ronin")
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "eye_see_all"))
	ok(g.players[0].hand.size() == n + 2, "Всевидящее око: по карте каждого типа (corn, sandy), радужные в сброс")


func t_ll_phoenix_pyre() -> void:
	lands(0, "lava")
	var d1 = mk("drooling_dude")
	var d2 = mk("cow")
	g.players[0].discard.append(d1)
	g.players[0].discard.append(d2)
	g.players[0].actions = 2
	bot.answers = [d1.uid, {"p": 0, "lane": 0, "row": "creature"}, {"p": 0, "lane": 1, "row": "creature"}]
	await play(0, hand(0, "form_of_the_phoenix"))
	ok(g.creature_count(0) == 2, "Облик феникса: 2 существа из сброса в игру")
	await g._end_turn(0)
	ok(g.creature_count(0) == 0, "Облик феникса: в конце хода они уничтожены")
	_fresh()
	lands(0, "lava")
	g.players[0].discard.append(mk("drooling_dude"))
	await play(0, hand(0, "pyre_dance"))
	ok(g.hp_of(0, 0) == 1, "Танец костра: в игру с 1 оставшейся защитой")


func t_ll_potions() -> void:
	lands(0, "rainbow")
	var a = await put(0, "drooling_dude", 0)
	var b = await put(1, "drooling_dude", 0)
	a.damage = 4
	b.damage = 4
	await play(0, hand(0, "friendship_potion"))
	ok(a.damage == 1 and b.damage == 1, "Зелье дружбы: снять 3 со своего и 3 с чужого")
	lands(0, "ice")
	bot.answers = [spot(1, 0), {"p": 1, "lane": 2}]
	await play(0, hand(0, "frostfire_potion"))
	ok(g.burning(b) and g.tokens(a, "atk_tok") == 1 and g.is_frozen(1, 2), "Зелье морозного пламени: огонь, жетон атаки, мороз")
	lands(0, "plain")
	var s = await build(0, "schoolhouse", 1)
	s.exhausted = true
	bot.answers = [{"p": 0, "lane": 3, "row": "building"}]
	await play(0, hand(0, "relocation_potion"))
	ok(not s.exhausted and g.players[0].buildings[3] == s, "Зелье переезда: строение готово и переехало")


func t_ll_heat_icy() -> void:
	lands(0, "sandy")
	var a = await put(0, "drooling_dude", 0)
	var b = await put(1, "drooling_dude", 0)
	bot.answers = [spot(1, 0), spot(0, 0)]
	await play(0, hand(0, "heat_stroke"))
	ok(a.damage == 4 and b.damage == 4, "Тепловой удар: каждый выбирает разное существо")
	lands(0, "ice")
	await g.freeze(1, 0)
	await play(0, hand(0, "icy_hot"))
	ok(g.burning(b) and not g.burning(a), "Ледяной жар: горят существа на замороженных землях")


func t_ll_juiced_plate() -> void:
	lands(0, "cute")
	var a = await put(0, "drooling_dude", 0)
	a.damage = 3
	for i in 3:
		g.players[0].discard.append(mk("hot_shot"))
	await play(0, hand(0, "juiced_lightning"))
	ok(a.damage == 1 and g.tokens(a, "atk_tok") == 1, "Заряженная молния: снять 2 и жетон атаки")
	lands(0, "lava")
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "pyroheart_plate"))
	ok(a.damage == 0 and g.burning(a) and g.players[0].hand.size() == n + 1, "Доспех огненного сердца: поджечь, снять урон, карта")


func t_ll_shock_swamp_wand() -> void:
	g.players[0].discard.append(mk("cow"))
	g.players[0].hp = 20
	bot.skip_optional = false
	await play(0, hand(0, "shock_box"))
	ok(g.players[0].hp >= 21, "Шок-коробка: карта замешана, жизнь")
	lands(0, "swamp")
	var x = await put(1, "cow", 0)
	x.damage = 3
	hand(1, "cow")
	g.players[0].actions = 2
	await play(0, hand(0, "swamp_gas"))
	ok(g.players[1].hand.is_empty(), "Болотный газ: уничтожил — владелец сбрасывает карту")
	g.players[0].actions = 2
	var y = await put(1, "drooling_dude", 1)
	hand(1, "full_metal_racket")
	bot.answers = ["Сыграть бесплатно", spot(1, 1)]
	await play(0, hand(0, "wand_of_hexcraft"))
	ok(y.damage == 2, "Жезл колдовства: сброшенное заклинание сыграно бесплатно")


func t_ll_buildings_a() -> void:
	hand(1, "cow")
	var keep = hand(0, "cob_keep")
	ok(g.cost_of(0, keep) == 0, "Початочная крепость: бесплатна, если у кого-то ≤1 карты")
	await build(0, "cob_keep", 0)
	await put(0, "cow", 0)
	ok(g.atk_of(0, 0) == 3 and g.def_of(0, 0) == 7, "Початочная крепость: +2/+2")
	await build(0, "combatarium", 1)
	var x = await put(0, "cow", 1)
	x.exhausted = true
	await g.cmd_floop(0, "building", 1)
	ok(not x.exhausted and x.damage == 1, "Боевая арена: подготовить и 1 урон")
	await build(0, "fortitude_fountain", 2)
	ok(g.players[0].max_hp == 30, "Фонтан стойкости: максимум жизней +5")
	await g.destroy_building(0, 2)
	ok(g.players[0].max_hp == 25, "…и обратно")


func t_ll_buildings_b() -> void:
	await build(0, "geyser_cannon", 0)
	await put(0, "drooling_dude", 0)
	ok(g.atk_of(0, 0) == 6, "Гейзерная пушка: пустая рука — атака ×2")
	await build(0, "honeycomb_haven", 1)
	await put(0, "drooling_dude", 1)
	g.players[0].hp = 10
	await g.cmd_attack(0, 1)
	ok(g.players[0].hp == 13, "Медовое убежище: урон сопернику — столько же жизней")
	await build(1, "skullshade_shanty", 2)
	var a = await put(0, "drooling_dude", 2)
	await g.cmd_attack(0, 2)
	ok(a.damage == 3, "Хижина черепной тени: обидчик получает тот же урон")
	await build(0, "hot_box", 3)
	var z = await put(1, "cow", 3)
	var hp: int = g.players[1].hp
	await g.destroy_creature(1, 3)
	ok(g.players[1].hp == hp - 2 and z.owner == 1, "Пекло: существо соперника ушло — 2 урона владельцу")


func t_ll_buildings_c() -> void:
	var x = await put(1, "drooling_dude", 0)
	await build(0, "lavafall_retreat", 0)
	ok(g.burning(x), "Приют лавопада: входя, поджигает существо в зоне")
	var y = await put(0, "cow", 0)
	ok(g.burning(y), "Приют лавопада: каждое входящее существо горит")
	await build(0, "magma_canals", 1)
	await put(1, "cow", 2)
	await g.burn_creature(0, 1, 2, 2)
	var z = await put(1, "drooling_dude", 1)
	await g.cmd_floop(0, "building", 1)
	ok(z.damage == 4, "Магмовые каналы: урон за жетоны огня в других зонах (2+1+1)")
	await build(0, "ziggurat_of_the_darned", 3)
	await put(1, "drooling_dude", 3)
	ok(g.atk_of(1, 3) == 1, "Зиккурат проклятых: −2 к атаке")


func t_ll_buildings_d() -> void:
	await build(0, "sky_burial_tower", 0)
	await g.cmd_floop(0, "building", 0)
	ok(g.players[0].actions == 3, "Башня небесного погребения: у соперника ≤1 карты — действие")
	await build(0, "snowmaker_station", 1)
	await g.freeze(1, 0)
	bot.answers = [{"p": 1, "lane": 1}]
	var n: int = g.players[0].hand.size()
	await g.cmd_floop(0, "building", 1)
	ok(not g.is_frozen(1, 0) and g.is_frozen(1, 1) and g.players[0].hand.size() == n + 1, "Станция снегоделов: мороз перенесён, карта")
	var w = await build(0, "wandering_workshop", 2)
	var c = await put(0, "cow", 2)
	bot.answers = [spot(0, 2), {"p": 0, "lane": 3, "row": "building"}]
	await g.cmd_floop(0, "building", 2)
	ok(g.tokens(c, "atk_tok") == 1 and g.players[0].buildings[3] == w, "Бродячая мастерская: жетон атаки и переезд")


func t_ll_eyesneks() -> void:
	await put(0, "dazzling_eyesnek", 0)
	var x = await put(1, "drooling_dude", 0)
	bot.answers = [spot(1, 0)]
	await put(0, "sunscorch_eyesnek", 1)
	ok(x.damage == 2, "Солнцепёчный глазмей: урон за каждого глазмея")
	await put(0, "molten_eyesnek", 2)
	ok(g.tokens(g.players[0].creatures[0], "atk_tok") == 1, "Расплавленный глазмей: жетон атаки каждому глазмею")
	await put(0, "stalk_eyesnek", 3)
	ok(g.players[0].creatures[0].temp_atk == 4, "Стебельчатый глазмей: +1 за каждого глазмея")
	var hp: int = g.players[1].hp
	g.players[0].hp = 10
	await put(0, "bog_eyesnek", 1)
	ok(g.players[1].hp == hp - 4 and g.players[0].hp == 14, "Болотный глазмей: урон и жизни за глазмеев")
	var n: int = g.players[0].hand.size()
	await put(0, "cerulean_eyesnek", 2)
	ok(g.players[0].hand.size() == n + 4, "Лазурный глазмей: карта за каждого своего глазмея")
	var f = g.players[0].creatures[0]
	f.damage = 5
	await put(0, "hillside_eyesnek", 3)
	ok(f.damage == 1, "Холмовой глазмей: снять урон за глазмеев")
	await put(0, "snowblind_eyesnek", 1)
	ok(g.frozen_count() == 4, "Снегослепой глазмей: заморозить по земле за глазмея")


func t_ll_creatures_a() -> void:
	top(0, "cow")
	g.players[0].discard.append(mk("drooling_dude"))
	await put(0, "ancient_magic_pharaoh_dragon", 0)
	ok(g.players[0].deck.size() == 1 and g.players[0].deck[0].id == "drooling_dude", "Дракон-фараон: колода и сброс поменялись")
	var x = await put(1, "drooling_dude", 0)
	await put(0, "basalt_behemoth", 1)
	await g.cmd_floop(0, "creature", 1)
	ok(g.burning(x) and x.damage == 2, "Базальтовый бегемот: поджечь и урон за жетоны огня")
	var boa = await put(0, "bayou_boa", 2)
	boa.damage = 3
	await g.cmd_activate(0, "creature", 2)
	ok(g.tokens(boa, "atk_tok") == 2 and boa.damage == 1, "Удав из протоки: уничтожить своё — 2 жетона атаки, снять 2")


func t_ll_creatures_b() -> void:
	mixed(0, "sandy", "plain")
	await put(0, "kind_ling", 0)
	await put(0, "field_stalker", 1)
	await put(0, "dualcast_adept", 2)
	await put(1, "drooling_dude", 3)
	bot.answers = [spot(1, 3)]
	await put(0, "beach_worm", 3)
	ok(g.players[1].creatures[3] == null, "Пляжный червь: 4 типа существ — уничтожил")
	_fresh()
	top(0, "punch_potion")
	await put(1, "drooling_dude", 0)
	bot.answers = ["Существо", spot(1, 0)]
	await put(0, "brew_haha", 0)
	ok(g.players[1].creatures[0].damage == 3, "Варево-хаха: «Зелье» из колоды сыграно")


func t_ll_courtly_doc() -> void:
	lands(0, "cute")
	var a = await put(0, "drooling_dude", 0)
	var b = await put(1, "drooling_dude", 0)
	g.players[0].actions = 5
	var big = hand(0, "courtly_armourdillo")
	ok(big != null, "…")
	_fresh()
	var x = await put(0, "drooling_dude", 0)
	var y = await put(1, "drooling_dude", 0)
	var c = mk("courtly_armourdillo")
	c.flags["from_hand"] = true
	await g._put_creature(0, c, 1, true)
	ok(x.damage == 8 and y.damage == 8, "Придворный броненосец: с руки 8 урона всем другим")
	await put(0, "dr_pieclops", 2)
	g.players[0].hp = 20
	mixed(0, "rainbow", "rainbow")
	await play(0, hand(0, "full_metal_racket"))
	ok(g.players[0].hp == 22, "Доктор Пироклоп: заклинание — 2 жизни")
	ok(a != null and b != null, "…")


func t_ll_low_hand() -> void:
	var c = await put(0, "cinder_construct", 0)
	await g.damage_creature(0, 0, 3, {"kind": "effect", "p": 1})
	ok(c.damage == 2, "Шлаковый голем: урон вдвое меньше (с округлением вверх)")
	await put(0, "erupting_colossus", 1)
	var x = await put(1, "drooling_dude", 0)
	await g.damage_creature(1, 0, 2, {"kind": "effect", "p": 0})
	ok(x.damage == 4, "Извергающийся колосс: урон удвоен")
	var z = await put(0, "cow", 3)
	var w = await put(1, "cow", 3)
	z.exhausted = false
	await g.cmd_attack(0, 3)
	ok(w.damage == g.atk_of(0, 3) * 2, "Извергающийся колосс: в бою урон удвоен")
	# Поезд: герои с характеристиками, у игрока 1 карта в руке.
	g.train.set_stats(0, {"atk": 1, "vs_atk": 1, "crit": 0, "regen": 1})
	g.train.set_stats(1, {"armor": 1})
	g.players[0].hand.clear()
	var z2 = await put(0, "cow", 2)
	var w2 = await put(1, "dazzling_eyesnek", 2)
	z2.exhausted = false
	await g.cmd_attack(0, 2)
	ok(w2.damage == (g.atk_of(0, 2) + 1) * 2, "Извергающийся колосс в поезде: урон удвоен (%d, атака %d)" % [w2.damage, g.atk_of(0, 2)])
	var y = await put(1, "cow", 2)
	await put(0, "firestorm_of_phoenixes", 2)
	ok(g.burning(x) and g.burning(y), "Огненная буря фениксов: поджечь каждое существо соперника")


func t_ll_cobnoblins() -> void:
	await put(0, "gentle_cobnoblin", 0)
	ok(not g.can_attack(0, 0), "Кроткий початкогоблин: не нападает")
	_fresh()
	var x = await put(1, "drooling_dude", 0)
	await put(0, "hostile_cobnoblin", 0)
	await g._put_creature(0, mk("drooling_dude"), 0)
	ok(x.damage == 3, "Враждебный початкогоблин: заменяющий сначала бьёт существо соперника")
	_fresh()
	var k = await put(0, "kernel_king_cobnoblin", 0)
	var n = await g._put_creature(0, mk("cow"), 0)
	ok(g.players[0].creatures.has(k) and g.players[0].creatures[0] != k, "Король зёрен: не заменяется, а переходит в пустую зону")
	ok(n == null, "…")
	_fresh()
	k = await put(0, "kernel_king_cobnoblin", 0)
	k.flags["gobble_turn"] = g.turn_number
	var cow = mk("cow")
	bot.answers = ["Хрум"]
	await g._put_creature(0, cow, 0)
	ok(g.players[0].creatures[0] == cow and cow.under.has(k), "Игрок: Король зёрен с Хрумом — можно выбрать Хрум, он уходит под новое существо")
	_fresh()
	k = await put(0, "kernel_king_cobnoblin", 0)
	k.flags["gobble_turn"] = g.turn_number
	bot.answers = ["Перейти в пустую зону"]
	await g._put_creature(0, mk("cow"), 0)
	ok(g.players[0].creatures.has(k) and g.players[0].creatures[0] != k, "Король зёрен с Хрумом: можно и перейти в пустую зону")


func t_ll_rabbit() -> void:
	var host = await put(0, "drooling_dude", 0)
	var r = mk("holographic_rabbit")
	await g._put_creature(0, r, 0)
	ok(g.players[0].creatures[0] == host and host.under.has(r), "Голографический кролик: делит землю")
	await g.damage_creature(0, 0, 3, {"kind": "effect", "p": 1})
	ok(host.damage == 0 and r.damage == 3, "Голографический кролик: урон уходит на него")
	await g.damage_creature(0, 0, 2, {"kind": "effect", "p": 1})
	ok(g.players[0].discard.has(r) and not host.under.has(r), "Голографический кролик: уничтожен")
	r = mk("holographic_rabbit")
	await g._put_creature(0, r, 0)
	await g.damage_creature(0, 0, 1, {"kind": "effect", "p": 1})
	await g.destroy_creature(0, 0)
	ok(g.players[0].creatures[0] == r and r.damage == 1 and not r.flags.has("guard"),
		"Голографический кролик: существо ушло — кролик остаётся на земле обычным существом")
	await g.damage_creature(0, 0, 1, {"kind": "effect", "p": 1})
	ok(r.damage == 2, "Голографический кролик: один на земле получает урон сам")
	var host2 = await put(0, "drooling_dude", 1)
	var r2 = mk("holographic_rabbit")
	await g._put_creature(0, r2, 1)
	var cow = await put(0, "cow", 1)
	ok(g.players[0].creatures[1] == cow and cow.under.has(r2) and g.players[0].discard.has(host2),
		"Голографический кролик: существо заменили — кролик делит землю с новым")


func t_ll_misc_a() -> void:
	var t = await put(0, "flameingo_flame_tamer", 0)
	var x = await put(1, "drooling_dude", 0)
	await g.burn_creature(0, 1, 0)
	g.turn_player = 1
	await g.damage_creature(0, 0, 3, {"kind": "combat", "p": 1, "card": x})
	ok(t.damage == 1, "Пламинго-укротитель: первые 2 урона от горящих предотвращены")
	g.turn_player = 0
	g.players[0].discard.append(mk("president_sweetcorn"))
	await put(0, "foulwater_reviver", 1)
	await g.cmd_floop(0, "creature", 1)
	ok(g.players[0].creatures.any(func(c): return c != null and c.id == "president_sweetcorn"), "Оживитель гнилых вод: существо за 1 из сброса")


func t_ll_misc_b() -> void:
	lands(0, "rainbow")
	await put(0, "ghost_sorceress", 0)
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "full_metal_racket"))
	ok(g.players[0].hand.size() == n + 1, "Призрачная колдунья: 2 карты, 1 сброс")
	var a = await put(0, "cow", 1)
	await g.burn_creature(1, 0, 1)
	var b = await put(0, "cow", 2)
	await put(0, "hexbreeze_drifter", 3)
	bot.answers = [spot(0, 2)]
	await g.cmd_floop(0, "creature", 3)
	ok(not g.burning(a) and g.burning(b), "Бродяга колдовского бриза: жетон перенесён")


func t_ll_misc_c() -> void:
	await put(0, "cow", 0)
	await put(0, "phyllis", 1)
	await put(0, "pony", 2)
	var hb = await put(0, "honey_badger", 3)
	ok(g.tokens(hb, "atk_tok") == 4 and g.def_of(0, 3) == 8, "Медоед: 4 жетона атаки и +1 к защите за каждый")
	_fresh()
	await put(0, "iceshadow_avalancheetah", 0)
	var x = await put(1, "drooling_dude", 0)
	hand(1, "cow")
	bot.answers = [spot(1, 0)]
	await g.force_discard(1, 1)
	ok(x.damage == 2, "Ледяная Тень: соперник сбросил — 2 урона")
	await put(0, "kind_ling", 1)
	await put(0, "giant_red_salamander", 2)
	ok(g.atk_of(0, 2) == 5, "Добрый огонёк: другие лавовые +1")


func t_ll_misc_d() -> void:
	await put(0, "cow", 0)
	await put(0, "field_stalker", 1)
	var o = await put(0, "motley_otters", 2)
	ok(g.tokens(o, "atk_tok") == 1, "Пёстрые выдры: жетон за каждый тип своих существ, радужные не в счёт")
	var m = await put(0, "mouth_beater", 3)
	hand(0, "cow")
	hand(0, "cow")
	ok(g.atk_of(0, 3) == 2, "Болтун-драчун: +1 за карту на руке")
	var x = await put(1, "cow", 3)
	x.damage = 4
	var n: int = g.players[0].hand.size()
	await g.cmd_attack(0, 3)
	ok(g.players[0].hand.size() == n + 1 and m != null, "Болтун-драчун: победил — карта")


func t_ll_misc_e() -> void:
	await put(0, "onyx_merlock", 0)
	var d: int = g.players[1].deck.size()
	await g._end_turn(0)
	ok(g.players[1].deck.size() == d - 2, "Ониксовый мерлок: 2 карты колоды соперника в сброс")
	_fresh()
	await put(0, "persuasive_armourdillo", 0)
	await g.cmd_floop(0, "creature", 0)
	ok(g.cost_of(0, hand(0, "titanbane_amulet")) == 0, "Убедительный броненосец: следующее заклинание бесплатно")
	await put(0, "psychedelic_rock_gecko", 1)
	var dd: int = g.players[0].deck.size()
	await put(1, "cow", 1)
	ok(g.players[0].deck.size() == dd - 1, "Психоделический геккон: другое существо вошло — сброс верхней карты")


func t_ll_misc_f() -> void:
	var pg = await put(0, "puffy_penguin", 0)
	var c = await put(0, "cow", 1)
	pg.damage = 2
	await g.heal_creature(0, 0, 1)
	ok(g.tokens(c, "atk_tok") == 1 and g.tokens(pg, "atk_tok") == 1, "Пухлый пингвин: лечение — жетон атаки каждому своему")
	await put(0, "pyrovent_sentinel", 2)
	var x = await put(1, "drooling_dude", 0)
	await g.destroy_creature(0, 2)
	ok(x.damage == 3, "Страж пиропара: уходя, 3 урона")
	var sc = await put(0, "scorchpion", 3)
	await g.cmd_floop(0, "creature", 3)
	ok(g.burning(sc), "Жгучий скорпион: поджигает себя")


func t_ll_misc_g() -> void:
	await put(0, "smoldering_phantom", 0)
	var c = await put(0, "cow", 1)
	c.exhausted = true
	g.players[0].turn["spells"] = 1
	g.players[0].turn["spells"] = 2
	await g._notify("on_played_", [0, mk("hot_shot")])
	ok(not c.exhausted, "Тлеющий фантом: второе заклинание — подготовить существо")
	await put(0, "snowbound_avalancheetah", 2)
	g.players[0].turn["played_lands"] = ["corn", "plain"]
	bot.answers = [{"p": 1, "lane": 1}]
	await g._end_turn(0)
	ok(g.is_frozen(1, 1), "Снежный Плен: 2 неледяные карты — заморозить землю")


func t_ll_misc_h() -> void:
	await g.freeze(1, 0)
	hand(1, "cow")
	await put(0, "winter_weaver", 0)
	var n: int = g.players[0].hand.size()
	await g.cmd_floop(0, "creature", 0)
	ok(g.players[0].hand.size() == n + 1 and g.players[1].hand.is_empty(), "Зимняя ткачиха: карта, сброс у игрока с морозом")
	lands(0, "plain")
	var s = hand(0, "woadic_blazetrail_sprinter")
	g.players[0].actions = 2
	ok(g.play_lanes(0, s.uid) == [3], "Огнеходный спринтер: только в крайнюю правую зону")
	await play(0, s, 3)
	await g.cmd_floop(0, "creature", 3)
	ok(g.players[0].creatures[2] == s and g.tokens(s, "atk_tok") == 1, "Огнеходный спринтер: шаг влево и жетон атаки")


func t_ll_living_desert() -> void:
	var d = await put(1, "living_desert", 3)
	await put(0, "drooling_dude", 0)
	bot.answers = [spot(1, 3)]
	var hp: int = g.players[1].hp
	await g.cmd_attack(0, 0)
	ok(g.players[1].hp == hp and d.damage == 3, "Живая пустыня: принимает нападение")
	g.turn_player = 1
	var c = hand(1, "cow")
	ok(not g.can_play(1, c.uid), "Живая пустыня: хозяин не играет существ")


# ================================================================= 10: Промо

func t_promo_cards() -> void:
	lands(0, "rainbow")
	await build(0, "sundae_school", 0)
	await put(0, "cow", 0)
	g.players[0].hp = 24
	ok(g.atk_of(0, 0) == 3, "Воскресная пломбирная школа: чётные жизни — +2")
	g.players[0].hp = 23
	ok(g.atk_of(0, 0) == 1, "…нечётные — нет")
	await build(0, "the_pigsty", 1)
	await put(0, "cow", 1)
	ok(g.def_of(0, 1) == 7, "Свинарник: +2 к защите")
	await g._put_creature(0, mk("the_pigs"), 1)
	ok(g.def_of(0, 1) == int(CardDB.get_def("the_pigs")["def"]) + 5, "Свинарник: свинье +5")
	await put(0, "cyclops", 2)
	ok(g.def_of(0, 2) == 1 + 2 + 54, "Циклоп: +1 за каждый открытый глаз других существ, у Свиней 54")


func t_promo_meats_drifter() -> void:
	g.players[1].removed.append(mk("cow", 1))
	g.players[1].removed.append(mk("cow", 1))
	lands(0, "swamp")
	g.players[0].hp = 20
	bot.answers = ["Финн"]
	await play(0, hand(0, "sweet_delicious_meats"))
	ok(g.players[0].hp == 22, "Сладкое вкусное мясо: жизнь за каждую карту вне игры")
	var d = await put(0, "blue_plains_drifter", 0)
	var c = await put(0, "cow", 2)
	await g.cmd_activate(0, "creature", 0)
	ok(g.players[0].creatures[2] == d and d.temp_atk == 1 and c.temp_atk == 1, "Бродяга синих равнин: поменялся, оба +1")
	ok(not g.can_activate(0, "creature", 2), "…раз за ход")


func t_promo_drake_unicorns_pigs() -> void:
	for i in 3:
		top(1, "cow")
	top(1, "hot_shot")
	top(1, "cow")
	bot.answers = ["Джейк"]
	var dr = await put(0, "time_drake", 0)
	ok(g.tokens(dr, "atk_tok") == 4, "Дракон времени: существа сверху в сброс, жетон за каждое")
	g.players[1].deck.push_front(mk("cow", 1))
	g.players[1].deck.push_front(mk("hot_shot", 1))
	bot.answers = ["Джейк"]
	var u = await put(0, "probably_too_many_unicorns", 1)
	ok(g.players[1].discard.size() >= 5, "Слишком много единорогов: существа снизу в сброс")
	var x = await put(1, "drooling_dude", 1)
	u.damage = 8
	x.exhausted = false
	g.turn_player = 1
	await g.cmd_attack(1, 1)
	ok(g.players[0].deck.front() == u, "Слишком много единорогов: побеждён — под низ колоды")
	g.turn_player = 0
	var y = await put(1, "drooling_dude", 2)
	bot.answers = [spot(1, 2)]
	await put(0, "the_pigs", 2)
	ok(y.damage == 1, "Свиньи: входя, 1 урон")
	lands(1, "corn")
	g.phase = "main"
	await put(0, "the_pig_promo", 3)
	await g.cmd_floop(0, "creature", 3)
	ok(g.players[1].lands[3]["flipped"], "Свинья (промо): переворачивает кукурузное поле")


# ================================================================= 11: Kickstarter 1

func t_ks1_spells() -> void:
	lands(0, "rainbow")
	var a = await put(0, "cow", 0)
	await play(0, hand(0, "ancient_comet"))
	ok(a.damage == 2 or a.temp_atk == 2, "Древняя комета: орёл — урон, решка — +2")
	g.players[0].actions = 2
	g.players[0].hp = 10
	bot.answers = ["Отдать сопернику"]
	var bb = hand(0, "beach_ball")
	await play(0, bb)
	ok(g.players[0].hp == 14 and g.players[1].hand.has(bb), "Пляжный мяч: +4 жизни, мяч у соперника")
	lands(0, "corn")
	g.players[0].discard.append(mk("infinite_pies"))
	var ip = hand(0, "infinite_pies")
	ok(g.cost_of(0, ip) == 0, "Бесконечные пироги: бесплатно, если такая же в сбросе")
	var hp: int = g.players[1].hp
	await play(0, ip)
	ok(g.players[1].hp == hp - 2, "Бесконечные пироги: 2 урона сопернику")


func t_ks1_beach_ball_stolen() -> void:
	lands(0, "rainbow")
	bot.answers = ["Отдать сопернику"]
	var bb = mk("beach_ball", 1)          # the opponent's card in p0's hand (stolen)
	g.players[0].hand.append(bb)
	await play(0, bb)
	ok(g.players[1].hand.has(bb) and not g.players[0].hand.has(bb), "Пляжный мяч: украденный мяч уходит сопернику, а не обратно")


func t_heal_full_targets() -> void:
	mixed(0, "cute", "sandy")
	var full = await put(0, "cow", 0)
	var candy = hand(0, "blue_candy")
	ok(g.can_play(0, candy.uid), "Синяя сахарная вата: можно сыграть на целое существо")
	await play(0, candy)
	ok(full.damage == 0 and g.players[0].discard.has(candy), "Синяя сахарная вата: целое существо не получает лишнего")


func t_ai_heals_own_side() -> void:
	mixed(0, "cute", "sandy")
	var mine = await put(0, "cow", 0)
	var theirs = await put(1, "cow", 0)
	mine.damage = 2
	theirs.damage = 3
	var duet := {"kind": "creature", "player": 0, "prompt": "Омар-спасатель: с какого другого существа снять 1 урон?",
		"options": [spot(1, 0), spot(0, 0)]}
	ok(AIHelper.choose(g, duet) == spot(0, 0), "ИИ: «снять урон» со своего существа, не с чужого")
	g.players[1].hp = 15
	var potion := {"kind": "option", "player": 0, "prompt": "Сердечное зелье: кого лечить на 5?",
		"options": ["Игрок: " + g.players[0].name, "Игрок: " + g.players[1].name, "Существо"]}
	ok(AIHelper.obvious(g, potion) == ["Существо"], "ИИ: лечит своё раненое существо, а не соперника")
	mine.damage = 0
	ok(AIHelper.obvious(g, potion) == ["Игрок: " + g.players[0].name], "ИИ: лечит себя, даже целого, но не соперника")
	var forced := {"kind": "creature", "player": 0, "prompt": "Дуэт: с чужого существа снять 1 урон",
		"options": [spot(1, 0), spot(1, 1)]}
	await put(1, "cow", 1)
	ok(AIHelper.choose(g, forced) == spot(1, 1), "ИИ: обязательное лечение чужого идёт на целое существо")


func t_ks1_last_will_tools() -> void:
	lands(0, "plain")
	var x = await put(1, "cow", 0)
	await play(0, hand(0, "last_will_and_detriment"))
	var hp: int = g.players[1].hp
	await g.destroy_creature(1, 0)
	ok(g.players[1].hp == hp - 4, "Последняя воля и вред: существо уничтожено — 4 урона")
	lands(0, "cute")
	await play(0, hand(0, "tools_of_the_trade"))
	await put(1, "cow", 1)
	g.players[0].hp = 10
	await g.destroy_creature(1, 1)
	ok(g.players[0].hp == 12, "Орудия ремесла: +2 жизни за уничтоженное существо соперника")
	ok(x.owner == 1, "…")


func t_ks1_party_whims() -> void:
	lands(0, "sandy")
	var a = await put(0, "cow", 0)
	var b = await put(0, "cow", 1)
	await play(0, hand(0, "party_energy"))
	ok(g.players[0].creatures[0] != a and g.players[0].creatures[1] != b and a.temp_atk == 2, "Энергия вечеринки: все в новые зоны, +2")
	lands(0, "rainbow")
	g.players[0].discard.append(mk("drooling_dude"))
	g.players[0].actions = 2
	await play(0, hand(0, "whims_of_fate"))
	ok(true, "Прихоти судьбы: монетка без ошибок")


func t_ks1_buildings() -> void:
	var bk = await build(0, "berserk_bakery", 0)
	var x = await put(1, "drooling_dude", 0)
	hand(0, "cow")
	await g.cmd_activate(0, "building", 0)
	ok(bk.damage == 1 and not g.can_activate(0, "building", 0), "Буйная пекарня: жетон урона, раз за ход")
	await g.cmd_floop(0, "building", 0)
	ok(x.damage == 1, "Буйная пекарня: урон за жетоны")
	await build(0, "bongo_bounce_house", 1)
	await g.damage_player(0, 3, null, {"kind": "effect", "p": 1})
	ok(g.players[0].hp == 25, "Надувной замок Бонго: урон по нему, а не по тебе")
	await g.damage_player(0, 3, null, {"kind": "effect", "p": 1})
	ok(g.players[0].buildings[1] == null, "Надувной замок Бонго: приняв 5, разрушен")
	await build(0, "creepy_crypt", 2)
	await put(0, "cow", 2)
	var hp: int = g.players[1].hp
	await g.destroy_creature(0, 2)
	ok(g.players[1].hp == hp - 2, "Жуткий склеп: своё существо ушло — 2 урона сопернику")
	await build(0, "dressage_dance_hall", 3)
	ok(g.land_count(0, "plain") == 5, "Манежный танцзал: копия своей земли")


func t_ks1_monolith_oasis_tower() -> void:
	await build(0, "monolith_of_doom", 0)
	await put(0, "cow", 0)
	await put(1, "cow", 1)
	await g.destroy_creature(0, 0)
	ok(g.creature_count(1) == 0 and g.players[0].buildings[0] == null, "Монолит рока: гибнут все и монолит")
	await build(0, "party_oasis", 1)
	var a = await put(0, "cow", 1)
	var b = await put(0, "evil_eye", 3)
	bot.answers = [{"p": 0, "lane": 0, "row": "creature"}, spot(0, 3)]
	await g.cmd_floop(0, "building", 1)
	ok(g.players[0].creatures[0] == a and g.players[0].creatures[1] == b, "Оазис вечеринок: одно ушло, другое пришло")
	await build(0, "terrible_tower", 2)
	await put(0, "cow", 2)
	top(0, "cow")
	top(0, "evil_eye")
	var deck_n: int = g.players[0].deck.size()
	await g.cmd_floop(0, "building", 2)
	ok(g.players[0].deck.size() == deck_n - 2, "Ужасная башня: 2 верхние карты сыграны")


func t_ks1_creatures() -> void:
	g.players[0].lands[0]["flipped"] = true
	g.players[0].hp = 10
	await put(0, "ancient_healer", 0)
	ok(not g.players[0].lands[0]["flipped"] and g.players[0].hp == 14, "Древний целитель: земля лицом вверх, +4 жизни")
	var host = await put(0, "drooling_dude", 1)
	await g._put_creature(0, mk("crust_crusher"), 1)
	await g.damage_creature(0, 1, 3, {"kind": "effect", "p": 1})
	ok(host.damage == 0, "Корочкодав: урон идёт на него")
	await put(0, "dark_o_mint", 2)
	hand(1, "cow")
	hand(1, "cow")
	await g.destroy_creature(0, 2)
	ok(g.players[1].hand.is_empty(), "Тёмномят: уничтожен — соперник сбрасывает 2")
	top(0, "cow")
	bot.answers = ["Взять"]
	var n: int = g.players[0].hand.size()
	await put(0, "happy_ghost_lucky", 3)
	ok(g.players[0].hand.size() == n + 1, "Лаки: радужная сверху — на руку")


# ================================================================= 15: Kickstarter 2

func t_ks2_spells_a() -> void:
	lands(0, "swamp")
	await put(0, "cow", 0)
	await put(1, "cow", 0)
	hand(0, "drooling_dude")
	bot.answers = [{"p": 0, "lane": 0, "row": "creature"}]
	await play(0, hand(0, "bayou_surge"))
	ok(g.players[1].creatures[0] == null and g.players[0].creatures[0] != null, "Прилив в протоке: все уничтожены, своё существо с руки")
	for i in 5:
		g.players[0].discard.append(mk("cow"))
	g.players[0].actions = 2
	var bc = hand(0, "bog_cyclone")
	await play(0, bc)
	ok(g.players[0].removed.has(bc), "Болотный циклон: убран из игры")
	lands(0, "cute")
	await put(1, "drooling_dude", 1)
	await put(1, "cow", 2)
	g.players[0].actions = 2
	await play(0, hand(0, "cull_uh_bye"))
	ok(g.players[1].creatures[1] == null or g.atk_of(1, 1) < 4, "Баю-бай-бай: существа с атакой 4+ уничтожены")


func t_ks2_spells_b() -> void:
	lands(0, "rainbow")
	g.players[0].hp = 5
	g.players[1].hp = 5
	g.players[0].actions = 2
	await play(0, hand(0, "divine_right"))
	ok(g.players[0].hp == 20 and g.players[1].hp == 20, "Божественное право: каждый +15")
	var n0: int = g.players[0].hand.size()
	var n1: int = g.players[1].hand.size()
	await play(0, hand(0, "royal_prosperity"))
	ok(g.players[0].hand.size() == n0 + 2 and g.players[1].hand.size() == n1 + 2, "Королевское процветание: каждый берёт 2")
	lands(0, "swamp")
	await build(0, "schoolhouse", 0)
	await put(0, "drooling_dude", 1)
	var x = await put(1, "drooling_dude", 2)
	bot.answers = [spot(1, 2)]
	await play(0, hand(0, "delta_domination"))
	ok(x.damage == 3, "Дельта-господство: урон = общая стоимость своих карт")


func t_ks2_letters() -> void:
	lands(0, "corn")
	var a = await put(1, "cow", 0)
	var b = await put(1, "drooling_dude", 1)
	bot.answers = ["К"]
	await play(0, hand(0, "curse_words"))
	ok(a.damage == 0 and b.damage == 4, "Бранные слова: уцелели существа на выбранную букву")
	top(0, "cow")
	top(0, "drooling_dude")
	bot.answers = ["К"]
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "careful_shuffle"))
	ok(g.players[0].hand.size() == n + 1, "Аккуратная тасовка: карта на букву на руку, остальные в сброс")


func t_ks2_xray_discovery() -> void:
	lands(0, "plain")
	top(0, "drooling_dude")
	var cow = top(0, "cow")
	var eye = top(0, "evil_eye")
	await play(0, hand(0, "x_ray_specs"))
	ok(g.xray_top(0) == eye and g.players[0].actions == 2, "Рентгеновские очки: верх колоды открыт, сразу играть не надо")
	await play(0, hand(0, "cow"), 2)
	await play(0, eye, 0)
	ok(g.players[0].creatures[0] == eye and g.players[0].actions == 2, "Рентгеновские очки: позже в ходу, первая без доплаты")
	ok(g.xray_top(0) == cow and g.cost_of(0, cow) == 1 and g.legal_commands(0).has({"cmd": "play", "uid": cow.uid, "lane": 1}),
		"Рентгеновские очки: вторая на 1 дороже")
	await play(0, cow, 1)
	ok(g.players[0].creatures[1] == cow and g.players[0].actions == 1, "Рентгеновские очки: вторую сыграл за 1")
	ok(not g.can_play(0, g.xray_top(0).uid), "Рентгеновские очки: третья стоит 2 + 2")
	g.players[0].turn = {}
	ok(g.xray_top(0) == null, "Рентгеновские очки: в следующем ходу колода закрыта")
	lands(0, "rainbow")
	g.players[0].discard.append(mk("hot_shot"))
	await play(0, hand(0, "brilliant_discovery"))
	ok(g.players[0].hero_state.get("notes", []).size() >= 1, "Блестящее открытие: заклинание в заметки")


## Счастливый призрак Лаки входит в зону Призрачной сторожки: игрок выбирает, что сначала.
func t_enter_effects_order() -> void:
	await build(0, "wraithwood_lodge", 0)
	hand(0, "cow")
	top(0, "x_ray_specs")
	var eye = top(0, "evil_eye")
	bot.answers = ["Призрачная сторожка, зона 1"]
	await put(0, "happy_ghost_lucky", 0)
	var ask: Dictionary = bot.asked[0]
	ok(String(ask.get("prompt", "")).contains("какой эффект сначала") and ask["options"].size() == 2,
		"вход в игру: два эффекта, игрок выбирает порядок")
	ok(g.players[0].hand == [eye], "вход в игру: сначала сторожка, потом Лаки смотрит новую верхнюю карту")
	bot.asked.clear()
	await put(0, "happy_ghost_lucky", 1)
	ok(not bot.asked.any(func(r): return String(r.get("prompt", "")).contains("сначала")), "вход в игру: один эффект без вопроса")


func t_ks2_buildings() -> void:
	await build(0, "sovereigns_sanctuary", 0)
	var a = await put(0, "drooling_dude", 0)
	var b = await put(1, "drooling_dude", 0)
	a.damage = 4
	b.damage = 4
	await g.cmd_floop(0, "building", 0)
	ok(a.damage == 1 and b.damage == 1, "Святилище государя: снять 3 с каждого в зоне")
	await build(0, "the_icebox", 1)
	await g.freeze(1, 1)
	hand(1, "cow")
	g.turn_player = 1
	g.players[0].hp = 20
	var hp: int = g.players[1].hp
	await g.cmd_thaw(1, 1)
	ok(g.players[1].hp == hp - 1 and g.players[0].hp == 21, "Ледник: растопил сбросом — 1 урон, +1 жизнь")


func t_ks2_creatures_a() -> void:
	var ab = hand(0, "abnegator")
	await g.discard_card(0, ab)
	ok(g.players[0].actions == 3, "АбнеГатор: сброшен в свой ход — +1 действие")
	bot.answers = ["Джейк"]
	await put(0, "blizzard_born", 0)
	ok(g.frozen_count() == 8, "Рождённый вьюгой: замерзают земли (жетонов мороза больше четырёх)")
	ok(g.creature_lane_ok(0, 1), "Рождённый вьюгой: можно играть на замороженные")
	bot.answers = ["К"]
	await put(0, "chancellors_commended", 1)
	await put(0, "cow", 2)
	ok(g.atk_of(0, 2) == 4, "Отмеченный канцлером: существа на букву +3")


func t_ks2_creatures_b() -> void:
	var dd = await put(0, "dynastic_defector", 0)
	bot.answers = ["Сыграть к сопернику", {"p": 1, "lane": 1}]
	await g.destroy_creature(0, 0)
	ok(g.players[1].creatures[1] == dd, "Династический перебежчик: сыгран к сопернику")
	await put(0, "icewarden", 1)
	var x = await put(1, "drooling_dude", 2)
	await g.freeze(1, 2)
	await g.damage_creature(1, 2, 2, {"kind": "effect", "p": 0})
	ok(x.damage == 4, "Ледяной страж: двойной урон на замороженной земле")
	var nb = await put(0, "neonate_bladesmith", 2)
	await put(0, "cow", 3)
	ok(g.tokens(nb, "atk_tok") == 1, "Юный кузнец: слабое существо вошло — жетон атаки")


func t_ks2_creatures_c() -> void:
	g.players[0].discard.append(mk("cow"))
	g.players[0].discard.append(mk("evil_eye"))
	g.players[0].discard.append(mk("cow"))
	await put(0, "platypus", 0)
	ok(g.atk_of(0, 0) == 2, "Утконос: +1 за каждую разную карту за 0 в сбросе")
	await put(0, "neuromancer", 1)
	bot.answers = [g.players[0].discard[0].uid, {"p": 0, "lane": 2, "row": "creature"}]
	await g.cmd_floop(0, "creature", 1)
	var played = g.players[0].creatures[2]
	ok(played != null, "Нейромант: сыграл карту за 0 из сброса")
	await g._end_turn(0)
	ok(g.players[0].removed.has(played), "Нейромант: в конце хода она убрана из игры")


func t_ks2_creatures_d() -> void:
	var t = top(0, "cow")
	bot.answers = ["Корова"]
	await put(0, "propagator", 0)
	ok(g.players[0].discard.has(t) and g.players[0].actions == 4, "ПропаГатор: угадал — сброс и 2 действия")
	await put(0, "protector_of_the_realm", 1)
	ok(not g.can_activate(0, "creature", 1), "Защитник королевства: проклятий нет — не применить")
	var q = await put(0, "quality_controller", 2)
	await g.destroy_creature(0, 2)
	ok(g.players[0].hero_state.get("notes", []).has(q), "Контролёр качества: ушёл в заметки")
	await put(0, "toddler_scholar", 3)
	var n: int = g.players[0].hand.size()
	await g.cmd_attack(0, 3)
	ok(g.players[0].hand.size() == n + 1, "Грамотей-карапуз: карта за каждый урон игроку")


func t_ks2_creatures_e() -> void:
	var pig = hand(0, "the_pigs")
	await put(0, "the_big_pig", 0)
	bot.answers = ["Ввести с руки", {"p": 0, "lane": 1, "row": "creature"}]
	await g._start_turn(0)
	ok(g.where(pig.uid)["zone"] == "creature", "Большая свинья: ввела свинью с руки")
	var u = await put(0, "urfwurm", 2)
	u.damage = 5
	var c1 = hand(0, "president_sweetcorn")
	g.players[0].hand = [c1]
	var x = await put(1, "drooling_dude", 2)
	g.turn_player = 1
	await g.cmd_attack(1, 2)
	ok(g.players[0].creatures[2] == c1, "Урфвурм: побеждён — на его землю бесплатно существо за 1")
	ok(u != null and x != null, "…")


# ================================================================= новые герои

func t_heroes_new_a() -> void:
	g.players[0].hero_card = "ice_queen"
	await put(0, "cow", 0)
	ok(g.atk_of(0, 0) == 1, "Снежная Королева: в свой ход нет бонуса")
	g.turn_player = 1
	ok(g.atk_of(0, 0) == 2, "Снежная Королева: в ход соперника +1 существам без урона")
	g.turn_player = 0
	g.players[0].hero_card = "the_snail"
	g.players[0].hp = 4
	var n: int = g.players[0].hand.size()
	await g._start_turn(0)
	ok(g.players[0].hand.size() == n + 3, "Улитка: 5 жизней или меньше — две лишние карты")
	g.players[0].hero_card = "starchy"
	g.players[1].discard.append(mk("cow", 1))
	n = g.players[0].hand.size()
	await g.cmd_hero_power(0)
	ok(g.players[1].removed.size() == 1 and g.players[0].hand.size() == n + 1, "Крахмалик: существо из сброса убрано, карта")


func t_heroes_new_b() -> void:
	g.players[0].hero_card = "me_mow"
	var x = await put(1, "drooling_dude", 0)
	var d: int = g.players[1].deck.size()
	await g.damage_creature(1, 0, 1, {"kind": "effect", "p": 0})
	ok(g.players[1].deck.size() == d - 1 and g.players[1].removed.size() == 1, "Мяу-Мяу: ровно 1 урон — нижняя карта колоды убрана")
	g.players[0].hero_card = "cinnamon_bun"
	g.players[0].turn = {}
	await put(0, "drooling_dude", 0)
	g.players[0].hp = 10
	await g.cmd_hero_power(0)
	ok(g.players[0].hp == 12, "Коричный Пончик: 2 урона своему — 2 жизни")
	g.players[0].hero_card = "death"
	g.players[0].turn = {}
	var hp: int = g.players[1].hp
	await g.cmd_hero_power(0)
	ok(g.players[1].hp == hp - 4 and g.players[0].lands.any(func(l): return l["flipped"]), "Смерть: перевернул землю — 4 урона")
	ok(x != null, "…")


func t_heroes_new_c() -> void:
	g.players[0].hero_card = "james_baxter"
	var n0: int = g.players[0].hand.size()
	bot.answers = ["Взять карту"]
	await g.cmd_hero_power(0)
	ok(g.players[0].hand.size() == n0 + 1 and g.players[1].hand.size() == 1, "Джеймс Бакстер: оба берут карту")
	g.players[0].hero_card = "neptr"
	g.players[0].turn = {}
	top(0, "cow")
	var n: int = g.players[0].hand.size()
	await g.cmd_hero_power(0)
	ok(g.players[0].hand.size() == n + 1, "НЕПТР: сброшено существо — на руку")
	g.players[0].hero_card = "party_god"
	var c = await put(0, "cow", 0)
	await g.move_creature(0, 0, 1)
	ok(c.temp_atk == 1, "Бог Вечеринок: сменил зону — +1")


func t_heroes_new_d() -> void:
	g.players[0].hero_card = "peppermint_butler_ks1"
	await put(0, "cow", 0)
	var x = await put(1, "drooling_dude", 0)
	await g.destroy_creature(0, 0)
	ok(x.damage == 2, "Мятный Дворецкий (KS1): своё существо ушло — 2 урона")
	g.players[0].hero_card = "lich_ks1"
	g.players[0].turn = {}
	await put(0, "cow", 1)
	await g.cmd_hero_power(0)
	ok(g.players[0].actions == 3 and g.creature_count(0) == 0, "Лич (KS1): уничтожил своё — действие")
	g.players[0].hero_card = "baby_finn_and_jake"
	await put(0, "cow", 2)
	await g._enter_battle(0)
	ok(g.atk_of(0, 2) == 4, "Малыши Финн и Джейк: в фазе сражения +3")


func t_heroes_new_e() -> void:
	g.players[0].hero_card = "banana_man"
	var b = mk("cow")
	g.players[0].deck.push_front(b)
	bot.answers = ["Наверх колоды"]
	await g.cmd_hero_power(0)
	ok(g.players[0].deck.back() == b, "Банановый человек: нижняя карта наверх")
	g.players[0].hero_card = "mr_fox"
	g.players[0].turn = {}
	top(0, "cow")
	bot.answers = ["Взять на руку"]
	var n: int = g.players[0].hand.size()
	await g.cmd_hero_power(0)
	ok(g.players[0].hand.size() == n + 1, "Мистер Лис: карта за 0 на руку")
	g.players[0].hero_card = "hot_dog_princess"
	var c = await put(0, "drooling_dude", 0)
	c.damage = 5
	await g._start_turn(0)
	ok(g.tokens(c, "atk_tok") == 1, "Принцесса Хот-Дог: 5+ урона — жетон атаки")


func t_heroes_new_f() -> void:
	g.players[0].hero_card = "betty"
	g.players[0].deck = g.players[0].deck.filter(func(x): return x.kind() != "spell")
	for id in ["hot_shot", "broils_coils", "hot_shot", "molten_potion"]:
		g.players[0].deck.append(mk(id))
	var deck_n: int = g.players[0].deck.size()
	await g._hero_event(0, "setup")
	var note_ids: Array = g.players[0].hero_state["notes"].map(func(x): return x.id)
	ok(note_ids.size() == 5 and not note_ids.has("hot_shot") and note_ids.has("broils_coils") and note_ids.has("molten_potion"), "Бетти: 5 разных заклинаний за 1, сначала из колоды")
	ok(g.players[0].deck.size() == deck_n, "Бетти: колода не уменьшается, заметки сверх неё")
	await put(1, "drooling_dude", 0)
	lands(0, "lava")
	await g.cmd_hero_power(0)
	ok(g.players[0].actions == 1, "Бетти: −1 действие, случайная заметка сыграна")
	g.players[0].hero_card = "choose_goose"
	g.players[0].hero_state["letter"] = "К"
	var c = hand(0, "chillwave")
	ok(g.cost_of(0, c) == 0, "Гусь-выбирусь: карта на выбранную букву дешевле")


func t_heroes_new_g() -> void:
	g.players[0].hero_card = "ghost_princess"
	for i in 4:
		g.players[0].discard.append(mk("cow"))
	g.players[0].hp = 10
	bot.answers = ["Нет"]
	await g.cmd_hero_power(0)
	ok(g.players[0].hp == 16 and g.players[0].discard.is_empty(), "Принцесса-призрак: 3 карты, по 2 жизни за существо, сброс в колоду")
	g.players[0].hero_card = "grob_gob_glob_grod"
	for l in 4:
		await put(0, "drooling_dude", l)
	ok(g.atk_of(0, 0) == 6, "Гроб Гоб Глоб Грод: 4 существа на 8+ — +3")


func t_heroes_new_h() -> void:
	g.players[0].hero_card = "muscle_princess"
	await put(0, "cow", 0)
	var x = await put(1, "cow", 0)
	bot.answers = [spot(0, 0), spot(1, 0), {"p": 1, "lane": 3, "row": "creature"}]
	await g.cmd_hero_power(0)
	ok(g.players[1].creatures[3] == x and g.tokens(g.players[0].creatures[0], "atk_tok") == 1, "Принцесса Мускулов: жетон и перемещение")
	g.players[0].hero_card = "simon_petrikov"
	await g.freeze(0, 1)
	var n: int = g.players[0].hand.size()
	await g.thaw(0, 1)
	await g.freeze(0, 1)
	await g.thaw(0, 1)
	ok(g.players[0].hand.size() == n + 1, "Саймон Петриков: первый снятый за ход жетон мороза — карта")


func t_heroes_new_i() -> void:
	g.players[0].hero_card = "the_stag"
	await put(0, "drooling_dude", 0)
	var x = await put(1, "cow", 0)
	for i in 3:
		hand(0, "cow")
	await g.cmd_hero_power(0)
	ok(g.players[1].removed.has(x), "Олень: убрал существо слабее по защите")
	g.players[0].hero_card = "turtle_princess"
	var t = await put(0, "cow", 2)
	await g.add_atk_tokens(t, 2)
	bot.answers = ["Убрать 2"]
	await g.damage_creature(0, 2, 3, {"kind": "effect", "p": 1})
	ok(t.damage == 1 and g.tokens(t, "atk_tok") == 0, "Принцесса Черепах: жетоны атаки предотвращают урон")
	g.players[0].hero_card = "billy"
	g.players[1].deck.clear()
	await g._check_win()
	ok(g.phase == "over" and g.winner == 0, "Билли: у соперника кончилась колода — победа")


func t_heroes_new_j() -> void:
	g.players[0].hero_card = "kickstarter_backer"
	top(0, "ancient_comet")
	lands(0, "corn")
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "infinite_pies"))
	ok(g.players[0].hand.size() == n + 1, "Спонсор 10-летия: сверху карта Kickstarter — на руку")
	g.players[0].hero_card = "flame_princess_promo"
	var x = await put(1, "cow", 0)
	await g.cmd_hero_power(0)
	ok(g.burning(x), "Огненная Принцесса (промо): поджигает существ соперника")



# ================================================================= Король вампиров

const VK_ASK := "Король вампиров"


func _vk_asked() -> Array:
	return bot.asked.filter(func(r): return String(r.get("prompt", "")).begins_with(VK_ASK))


func t_vampire_king_card() -> void:
	ok(CardDB.hero_card_ids().has("vampire_king"), "Король вампиров: есть среди карт героев")
	var d: Dictionary = CardDB.hero_card("vampire_king")
	ok(d.get("name", "") == "Король вампиров" and String(d.get("text", "")).begins_with("Когда ты должен снять урон"),
		"Король вампиров: имя и способность")
	ok(ResourceLoader.exists(CardDB.sharp_path(String(d["image"]))), "Король вампиров: чёткая картинка есть")
	ok(not d.has("power"), "Король вампиров: способность без кнопки")


func t_vampire_king_redirect() -> void:
	g.players[0].hero_card = "vampire_king"
	lands(0, "cute")
	var mine = await put(0, "cow", 0)
	mine.damage = 2
	var foe = await put(1, "cow", 1)
	bot.answers = [spot(0, 0), spot(1, 1)]
	await play(0, hand(0, "champions_emblem"))
	var asks := _vk_asked()
	ok(asks.size() == 1 and asks[0]["optional"] == true, "Король вампиров: спрашивает, можно отказаться")
	ok(asks.size() == 1 and String(asks[0]["prompt"]).contains("2 урона"), "Король вампиров: в вопросе урон, который сняли бы, 2 а не 3")
	ok(mine.damage == 2 and foe.damage == 2, "Король вампиров: урон остался, 2 урона другому существу (got %d, %d)" % [mine.damage, foe.damage])
	ok(g.players[0].actions == 2, "Эмблема чемпиона: урон остался, действие вернулось")


func t_vampire_king_decline() -> void:
	g.players[0].hero_card = "vampire_king"
	lands(0, "cute")
	var mine = await put(0, "cow", 0)
	mine.damage = 4
	var foe = await put(1, "cow", 1)
	bot.answers = [spot(0, 0), null]
	await play(0, hand(0, "champions_emblem"))
	ok(_vk_asked().size() == 1, "Король вампиров: вопрос был")
	ok(mine.damage == 1 and foe.damage == 0, "Король вампиров: отказ, урон снимается как обычно")


func t_vampire_king_no_damage() -> void:
	g.players[0].hero_card = "vampire_king"
	var mine = await put(0, "cow", 0)
	await put(1, "cow", 1)
	ok(await g.heal_creature(0, 0, 3) == 0, "снять урон с целого существа: 0")
	ok(_vk_asked().is_empty() and mine.damage == 0, "Король вампиров: нечего снимать, не спрашивает")


func t_vampire_king_kills() -> void:
	g.players[0].hero_card = "vampire_king"
	var mine = await put(0, "cow", 0)
	mine.damage = 3
	var foe = await put(1, "cow", 2)
	foe.damage = 3
	bot.answers = [spot(1, 2)]
	var got: int = await g.heal_creature(0, 0, 5)
	ok(got == 0 and mine.damage == 3, "Король вампиров: heal_creature вернул 0, урон на месте")
	ok(foe.damage == 6, "Король вампиров: нанесено 3, сколько было бы снято")
	await g._check_state()
	ok(g.players[1].creatures[2] == null, "Король вампиров: существо с уроном не меньше защиты уничтожено")


func t_vampire_king_any_creature() -> void:
	g.players[0].hero_card = "vampire_king"
	var a = await put(0, "cow", 0)
	a.damage = 1
	var b = await put(0, "cow", 3)
	await put(1, "cow", 1)
	bot.answers = [spot(0, 3)]
	await g.heal_creature(0, 0, 1)
	var opts: Array = _vk_asked()[0]["options"]
	ok(opts.size() == 3, "Король вампиров: на выбор все существа обеих сторон (got %d)" % opts.size())
	ok(b.damage == 1 and a.damage == 1, "Король вампиров: можно нанести урон своему существу")
	bot.asked.clear()
	bot.answers = [spot(0, 0)]
	await g.heal_creature(0, 0, 1)
	ok(a.damage == 2, "Король вампиров: можно нанести урон тому же существу")


func t_vampire_king_whose_heal() -> void:
	g.players[0].hero_card = "vampire_king"
	var theirs = await put(1, "cow", 0)
	theirs.damage = 2
	var mine = await put(0, "cow", 1)
	mine.damage = 2
	# The opponent heals: not his choice.
	await g.heal_creature(1, 0, 1)
	ok(_vk_asked().is_empty() and theirs.damage == 1, "Король вампиров: соперник снимает урон, не срабатывает")
	await g.heal_creature(0, 1, 1, 1)
	ok(_vk_asked().is_empty() and mine.damage == 1, "Король вампиров: урон с моего существа снимает соперник, не срабатывает")
	# Зелье дружбы: he heals the foe's creature too, that may go elsewhere.
	theirs.damage = 3
	mine.damage = 3
	# Only one creature on each side: the spell picks them itself, only the hero asks.
	bot.answers = [null, spot(1, 0)]
	await play(0, hand(0, "friendship_potion"))
	ok(_vk_asked().size() == 2, "Зелье дружбы: Король вампиров спрашивает на каждое снятие")
	ok(g.players[0].creatures[1] == mine and mine.damage == 0, "Зелье дружбы: со своего снял")
	ok(g.players[1].creatures[0] == null and g.players[1].discard.has(theirs), "Зелье дружбы: урон с чужого не снят, ещё 3 тому же, оно погибло")
	g.players[0].hero_card = "jake"
	theirs = await put(1, "cow", 0)
	theirs.damage = 1
	await g.heal_creature(1, 0, 1, 0)
	ok(_vk_asked().size() == 2 and theirs.damage == 0, "без Короля вампиров урон просто снимается")


func t_vampire_king_moves() -> void:
	g.players[0].hero_card = "vampire_king"
	var angel = await put(0, "bog_ban_she_angel", 0)
	angel.damage = 3
	var foe = await put(1, "cow", 1)
	bot.answers = [spot(1, 1)]
	await g.cmd_activate(0, "creature", 0)
	ok(_vk_asked().is_empty(), "Болотный ангел-банши: перенос урона не снятие, Король вампиров молчит")
	ok(angel.damage == 0 and foe.damage == 3, "Болотный ангел-банши: урон перенесён")


func t_vampire_king_herbal() -> void:
	g.players[0].hero_card = "vampire_king"
	var mine = await put(0, "cow", 0)
	mine.damage = 3
	var foe = await put(1, "cow", 2)
	g.players[0].turn["herbal"] = true
	bot.answers = [spot(1, 2)]
	await g._herbal(0, 0, mine, 2)
	ok(mine.damage == 3 and foe.damage == 2, "Травяные метатели: Король вампиров и тут")


func t_vampire_king_bale_out() -> void:
	g.players[0].hero_card = "vampire_king"
	var mine = await put(0, "cow", 0)
	var foe = await put(1, "cow", 1)
	mine.flags["bale_out"] = g.turn_number
	mine.damage = 5
	g.phase = "attack"
	bot.answers = [null]
	await g._check_state()
	ok(g.players[0].creatures[0] == mine and mine.damage == 0, "Тюк спасения: отказ, существо остаётся")
	mine.flags["bale_out"] = g.turn_number
	mine.damage = 6
	bot.answers = [spot(1, 1)]
	await g._check_state()
	ok(g.players[1].creatures[1] == null and g.players[1].discard.has(foe), "Тюк спасения: Король вампиров, 6 урона другому существу")
	ok(g.players[0].creatures[0] == null and g.players[0].discard.has(mine), "Тюк спасения: урон не снят, существо покидает игру")


func t_vampire_king_elephant() -> void:
	g.players[0].hero_card = "vampire_king"
	lands(0, "cute")
	var mine = await put(0, "cow", 0)
	mine.damage = 2
	var ele = await put(1, "endearing_elephant", 1)
	var hp: int = g.players[0].hp
	bot.answers = [spot(0, 0), spot(1, 1)]
	await play(0, hand(0, "champions_emblem"))
	ok(ele.damage == 2 and g.players[0].hp == hp, "Очаровательный слон: выбор Короля вампиров не заклинание")


func t_vampire_king_doubles() -> void:
	_fresh4()
	for ps in g.players:
		ps.hero_card = ""
	g.players[0].hero_card = "vampire_king"
	lands(0, "cute")
	var mate = await put(2, "cow", 0)
	mate.damage = 2
	await put(1, "cow", 1)
	await put(3, "cow", 2)
	bot.answers = [spot(2, 0), spot(3, 2)]
	await play(0, hand(0, "champions_emblem"))
	var asks := _vk_asked()
	ok(asks.size() == 1 and asks[0]["options"].size() == 3, "2 на 2: на выбор существа всех мест")
	ok(mate.damage == 2 and g.players[3].creatures[2].damage == 2, "2 на 2: урон союзника остался, 2 урона сопернику")
	g.players[2].hero_card = "vampire_king"
	g.players[0].hero_card = ""
	bot.asked.clear()
	await g.heal_creature(2, 0, 2, 0)
	ok(_vk_asked().is_empty() and mate.damage == 0, "2 на 2: снимает урон не Король вампиров, не срабатывает")


func t_vampire_king_three() -> void:
	_fresh(["finn", "jake", "pb"])
	for ps in g.players:
		ps.hero_card = ""
	g.players[0].hero_card = "vampire_king"
	var mine = await put(0, "cow", 0)
	mine.damage = 2
	await put(1, "cow", 1)
	await put(2, "cow", 2)
	bot.answers = [spot(2, 2)]
	await g.heal_creature(0, 0, 2)
	ok(_vk_asked()[0]["options"].size() == 3 and g.players[2].creatures[2].damage == 2, "на троих: урон любому из трёх игроков")
	await g._drop_out(2)
	bot.asked.clear()
	bot.answers = [null]
	await g.heal_creature(0, 0, 2)
	var asks := _vk_asked()
	ok(asks.size() == 1 and asks[0]["options"].all(func(o): return int(o["p"]) != 2), "на троих: выбывшего игрока нет в выборе")
	# The hero's own player dropped out: nothing to ask.
	g.players[2].hero_card = "vampire_king"
	bot.asked.clear()
	await g.heal_instead(2, mine, 0, 0, 1)
	ok(_vk_asked().is_empty(), "на троих: выбывший Король вампиров не срабатывает")


func t_vampire_king_ai() -> void:
	g.players[0].hero_card = "vampire_king"
	var mine = await put(0, "cow", 0)
	mine.damage = 2
	var req := {"kind": "creature", "player": 0, "optional": true,
		"prompt": "Король вампиров: нанести 2 урона существу вместо того, чтобы снять его с «Корова»?",
		"options": g.creature_opts(0, g.sides())}
	ok(AIHelper.obvious(g, req) == [null], "ИИ: врагов нет, урон снимает")
	var foe = await put(1, "cow", 2)
	foe.damage = 3
	await put(1, "cow", 3)
	req["options"] = g.creature_opts(0, g.sides())
	var pick: Array = AIHelper.obvious(g, req)
	ok(pick.size() == 1 and pick[0] != null and int(pick[0]["p"]) == 1 and int(pick[0]["lane"]) == 2,
		"ИИ: бьёт существо соперника, которое добьёт")

# ================================================================= 07: Парный турнир

## A 2 на 2 game: seats 0 and 2 against 1 and 3.
func _fresh4() -> void:
	_fresh(["finn", "jake", "pb", "bmo"])
	g.turn_number = 5


func t_dt_teamwork_slot() -> void:
	mixed(0, "sandy", "cute")
	var a = hand(0, "assistance")
	await play(0, a)
	ok(g.players[0].teamwork == a and g.where(a.uid)["zone"] == "teamwork", "Командная карта: лежит у земель")
	var b = hand(0, "fellowship")
	ok(not g.can_play(0, b.uid), "Командная карта: одна за ход")
	g.players[0].turn.erase("teamwork_played")
	await play(0, b)
	ok(g.players[0].teamwork == b and g.players[0].discard.has(a), "Командная карта: новая отправляет старую в сброс")


func t_dt_teamwork_2v2() -> void:
	_fresh4()
	mixed(0, "sandy", "cute")
	await play(0, hand(0, "assistance"))
	g.players[0].actions = 2
	await play(0, hand(0, "drooling_dude"), 0)
	var n: int = g.players[2].hand.size()
	bot.answers = ["Взять карту"]
	await g._enter_battle(0)
	ok(g.players[2].hand.size() == n + 1, "Помощь: существо за 2 — союзник берёт карту")


func t_dt_solidarity_coordination() -> void:
	_fresh4()
	g.players[2].teamwork = mk("solidarity", 2)
	var a = await put(0, "drooling_dude", 0)
	var a2: Array = g.across(0, 0)
	var x = await put(a2[0], "phyllis", a2[1])
	await g.cmd_attack(0, 0)
	ok(x.damage == 4, "Солидарность: первое существо, напавшее на существо, +1")
	g.players[0].teamwork = mk("coordination", 0)
	await g.freeze(0, 1)
	await g.freeze(0, 2)
	ok(not g.creature_lane_ok(0, 1), "Координация: без своего существа на морозе нельзя")
	await g.freeze(0, 0)
	ok(g.creature_lane_ok(0, 1), "Координация: своё существо на замороженной земле — можно")
	ok(a != null, "…")


func t_dt_instigator_any_foe() -> void:
	_fresh4()
	var a: Array = g.across(0, 0)
	var other: int = 1 if a[0] == 3 else 3
	var x = await put(other, "cow", 1)
	bot.answers = [spot(other, 1)]
	await put(0, "instigator", 0)
	ok(g.players[a[0]].creatures[a[1]] == x and g.players[other].creatures[1] == null,
		"ПровокАтор 2 на 2: существо можно взять у любого соперника")


func t_dt_camaraderie_fellowship() -> void:
	_fresh4()
	g.players[1].teamwork = mk("camaraderie", 1)
	await put(0, "cow", 0)
	var hp: int = g.players[0].hp
	await g.cmd_attack(0, 0)
	ok(g.players[0].hp == hp - 1, "Товарищество: урон команде — 1 урон команде соперников")
	_fresh4()
	g.players[0].teamwork = mk("fellowship", 0)
	await put(0, "cow", 0)
	var t2: Array = g.across(2, 0)
	var y = await put(t2[0], "drooling_dude", t2[1])
	bot.answers = [{"p": t2[0], "lane": t2[1]}]
	await g.cmd_attack(0, 0)
	ok(y.damage == 1, "Братство: союзник наносит 1 урон в своих зонах")


func t_dt_spells_a() -> void:
	lands(0, "sandy")
	var c = await put(0, "drooling_dude", 0)
	c.damage = 5
	await play(0, hand(0, "bail_out"))
	ok(g.players[0].creatures.has(c) and c.damage == 0, "Выручка: на руку и снова в игру")
	lands(0, "corn")
	var b = await put(0, "cow", 1)
	b.damage = 3
	bot.answers = [spot(0, 1)]
	await play(0, hand(0, "bale_out"))
	await put(1, "drooling_dude", 1)
	g.phase = "main"
	await g.cmd_attack(0, 1)
	ok(g.players[0].creatures[1] == b and b.damage == 0, "Тюк спасения: не погиб, урон снят")
	lands(0, "ice")
	var x = await put(1, "drooling_dude", 2)
	await g.freeze(1, 2)
	g.phase = "main"
	g.players[0].actions = 2
	await play(0, hand(0, "bomb_pop"))
	ok(g.players[1].creatures[2] == null and x.owner == 1, "Эскимо-бомба: уничтожает существо на замороженной земле")


func t_dt_spells_b() -> void:
	lands(0, "rainbow")
	await put(1, "cow", 0)
	await play(0, hand(0, "clone"))
	ok(g.cost_of(0, hand(0, "cow")) == 0, "Клон: такое же существо в игре — бесплатно")
	var a = await put(0, "drooling_dude", 1)
	var x = await put(1, "drooling_dude", 1)
	lands(0, "cute")
	await play(0, hand(0, "cuddle_puddle"))
	ok(x.damage == 4 and a.damage == 3, "Лужица обнимашек: все бьют существо напротив, свои +1")
	lands(0, "rainbow")
	g.players[0].actions = 2
	var hp0: int = g.players[0].hp
	var hp1: int = g.players[1].hp
	await play(0, hand(0, "firm_handshake"))
	ok(g.players[0].hp == hp0 - 5 and g.players[1].hp == hp1 - 5, "Крепкое рукопожатие: 5 себе и сопернику")


func t_dt_spells_c() -> void:
	lands(0, "cute")
	var a = await put(0, "cow", 0)
	var x = await put(1, "drooling_dude", 0)
	await play(0, hand(0, "hug_it_out"))
	ok(g.players[0].creatures[0] == null and g.players[1].creatures[0] == null, "Обнимемся!: оба существа уничтожены")
	lands(0, "corn")
	var y = await put(1, "drooling_dude", 1)
	y.damage = 6
	var hp: int = g.players[0].hp
	await play(0, hand(0, "infinite_haymaker"))
	ok(g.players[0].hp == hp - 3 and g.players[1].creatures[1] == null, "Бесконечный хук: урон себе = оставшаяся защита")
	ok(a != null and x != null, "…")


func t_dt_spells_d() -> void:
	lands(0, "ice")
	bot.answers = [{"p": 0, "lane": 0}, {"p": 1, "lane": 0}]
	await play(0, hand(0, "ice_sing"))
	ok(g.is_frozen(0, 0) and g.is_frozen(1, 0), "Ледяная песнь: по земле каждого")
	var a = await put(0, "drooling_dude", 1)
	a.damage = 3
	await play(0, hand(0, "frozen_lemon_aid"))
	ok(a.damage == 2, "Замороженный лимонад: по 1 урону с каждого существа, одно существо только раз")
	lands(0, "plain")
	var b = await put(0, "drooling_dude", 2)
	b.damage = 4
	var x = await put(1, "drooling_dude", 2)
	g.players[0].actions = 2
	await play(0, hand(0, "redirect_danger"))
	ok(b.damage == 1 and x.damage == 3, "Перенаправь опасность: 3 урона перенесены")


func t_dt_spells_e() -> void:
	lands(0, "sandy")
	var x = await put(1, "drooling_dude", 0)
	var n: int = g.players[1].hand.size()
	await play(0, hand(0, "scorching_serve"))
	ok(g.players[1].creatures[0] == null and g.players[1].hand.size() == n + 2, "Обжигающая подача: уничтожено, соперник берёт карты = стоимость")
	lands(0, "swamp")
	var y = await put(1, "drooling_dude", 1)
	await play(0, hand(0, "staff_of_frailty"))
	ok(g.hp_of(1, 1) == 1, "Посох немощи: осталась 1 защита")
	g.players[0].actions = 2
	await play(0, hand(0, "water_logged"))
	ok(g.atk_of(1, 1) == 1, "Подмокшие: −2 к атаке существам соперника")
	ok(x != null and y != null, "…")


func t_dt_spells_f() -> void:
	lands(0, "cute")
	var a = await put(0, "drooling_dude", 0)
	await play(0, hand(0, "stuffed"))
	ok(a.damage == 3 and g.atk_of(0, 0) == 6, "Объелся: урон = атака, затем атака ×2")
	var b = await put(0, "cow", 1)
	b.damage = 2
	a.damage = 6
	bot.answers = ["8"]
	g.players[0].actions = 2
	await play(0, hand(0, "patchwork"))
	ok(a.damage + b.damage == 8, "Лоскутки: урон перераспределён (всего 8)")
	lands(0, "rainbow")
	var c = await put(1, "cow", 2)
	await play(0, hand(0, "tandem_bike"))
	ok(g.players[1].hand.has(c), "Тандем: каждый возвращает своё существо")


func t_dt_spells_g() -> void:
	lands(0, "rainbow")
	top(0, "cow")
	top(0, "cow")
	var hp: int = g.players[1].hp
	await play(0, hand(0, "matchy_matchy"))
	ok(g.players[1].hp == hp, "Одинаковые: стоимость 0+0 — урона нет")
	var m = await put(0, "cow", 0)
	await play(0, hand(0, "royal_revelry"))
	hp = g.players[1].hp
	await g.cmd_attack(0, 0)
	ok(g.players[1].hp == hp - 1 - 2, "Королевский кутёж: ещё 2 урона")
	g.phase = "main"
	g.players[0].actions = 2
	await play(0, hand(0, "extreme_high_five"))
	ok(m != null, "Мегапятюня: без ошибок")


func t_dt_spells_h() -> void:
	lands(0, "rainbow")
	hand(1, "cow")
	hand(0, "drooling_dude")
	await play(0, hand(0, "jinx"))
	ok(g.players[1].hand.is_empty() or g.players[1].hand.size() == 1, "Сглаз: без ошибок")
	top(1, "cow")
	top(0, "evil_eye")
	var n1: int = g.players[1].hand.size()
	await play(0, hand(0, "twinsies"))
	ok(g.players[1].hand.size() == n1 + 1, "Близняшки: стоимости совпали — соперник берёт карту")
	bot.answers = [{"p": 0, "lane": 0}]
	await put(1, "field_stalker", 0)
	lands(0, "corn")
	var n: int = g.players[0].hand.size()
	await play(0, hand(0, "family_gathering"))
	ok(g.players[0].hand.size() == n + 1, "Семейный сбор: по карте за существо того же типа")


func t_knit_kitty_buildings() -> void:
	# «На Вязаного котика действуют строения на соседних землях»: not only the stat buildings.
	await build(0, "bean_ball_bomba", 1)
	var k = await put(0, "knit_kitty", 0)
	k.damage = 6
	ok(g.can_floop(0, "building", 1), "Бомба из бобов: Вязаный котик из соседней зоны подходит")
	await g.cmd_floop(0, "building", 1)
	ok(k.damage == 4, "Бомба из бобов: с котика соседней зоны снято до 4 урона (got %d)" % k.damage)
	var far = await put(0, "knit_kitty", 3)
	far.damage = 6
	k.damage = 4
	await g.cmd_floop(0, "building", 1)
	ok(far.damage == 6, "Бомба из бобов: котик через зону строением не затрагивается")
	# A creature on the building's own lane too: the player picks.
	_fresh()
	await build(0, "bean_ball_bomba", 1)
	var own = await put(0, "drooling_dude", 1)
	var kit = await put(0, "knit_kitty", 0)
	own.damage = 6
	kit.damage = 6
	bot.answers = [spot(0, 0)]
	await g.cmd_floop(0, "building", 1)
	ok(kit.damage == 4 and own.damage == 6, "Бомба из бобов: при двух подходящих существах выбирает игрок")
	# A plain creature next door gets nothing.
	_fresh()
	await build(0, "bean_ball_bomba", 1)
	await put(0, "drooling_dude", 0)
	ok(not g.can_floop(0, "building", 1), "Бомба из бобов: обычное существо соседней зоны не подходит")
	# Курвейер and the other lane buildings follow the same way.
	_fresh()
	await build(0, "auto_plucker", 2)
	var kp = await put(0, "knit_kitty", 3)
	kp.damage = 3
	bot.answers = ["Восстановить 1"]
	await g.cmd_floop(0, "building", 2)
	ok(kp.damage == 2, "Курвейер: лечит Вязаного котика соседней зоны")
	_fresh()
	await build(0, "nice_windmill", 1)
	var kw = await put(0, "knit_kitty", 2)
	kw.damage = 3
	bot.answers = ["Снять 2 урона"]
	await g.cmd_activate(0, "building", 1)
	ok(kw.damage == 1, "Добрая мельница: лечит Вязаного котика соседней зоны")
	# Not only the creature abilities: triggers, protection and stats of the other buildings.
	_fresh()
	await build(0, "sovereigns_sanctuary", 1)
	var ks = await put(0, "knit_kitty", 0)
	ks.damage = 5
	await g.cmd_floop(0, "building", 1)
	ok(ks.damage == 2, "Престол владык: снимает урон с Вязаного котика соседней зоны")
	_fresh()
	await build(0, "creepy_crypt", 1)
	await put(0, "knit_kitty", 0)
	var hp: int = g.players[1].hp
	await g.destroy_creature(0, 0)
	ok(g.players[1].hp == hp - 2, "Жуткий склеп: срабатывает, когда котик соседней зоны покидает игру")
	_fresh()
	await build(0, "geyser_cannon", 1)
	var kg = await put(0, "knit_kitty", 0)
	ok(g.atk_of(0, 0) == 6, "Гейзерная пушка: удваивает атаку котика соседней зоны (got %d)" % g.atk_of(0, 0))
	_fresh()
	await build(0, "charming_city", 1)
	var kc = await put(0, "knit_kitty", 0)
	ok(g.is_type(kc, "rainbow", 0, 0), "Очаровательный город: котик соседней зоны становится радужным")
	_fresh()
	await build(0, "cloud_tower", 1)
	await put(0, "knit_kitty", 0)
	g.cmd_source = "gnome_snot"
	ok(g.cloud_hidden(1, 0, 0), "Облачная башня: прячет котика соседней зоны от заклинаний соперника")
	g.cmd_source = ""
	_fresh()
	await build(0, "funeral_home", 1)
	var kf = await put(0, "knit_kitty", 0)
	var fc = hand(1, "cow")
	await g.discard_card(1, fc)
	ok(g.atk_of(0, 0) == 4 and kf.temp_atk == 1, "Похоронное бюро: котик соседней зоны получает +1 к атаке")


func t_dt_buildings_a() -> void:
	await build(0, "bayou_fountain", 0)
	var a = await put(0, "cow", 0)
	hand(0, "cow")
	await g.cmd_activate(0, "building", 0)
	ok(a.temp_atk == 1, "Фонтан в протоке: сбрось — +1")
	await build(0, "bean_ball_bomba", 1)
	var b = await put(0, "drooling_dude", 1)
	b.damage = 6
	await g.cmd_floop(0, "building", 1)
	ok(b.damage == 4, "Бомба из бобов: урон ровно 4")
	await build(0, "bog_palace", 2)
	await put(0, "cow", 2)
	ok(g.atk_of(0, 2) == 4, "Болотный дворец: +3")
	await build(0, "husker_garrison", 3)
	await put(0, "field_stalker", 3)
	ok(g.atk_of(0, 3) == 2 and g.def_of(0, 3) == 11, "Гарнизон кожурыцарей: +1/+1 за кукурузное существо")


func t_dt_buildings_b() -> void:
	await build(0, "cloud_tower", 0)
	var a = await put(0, "cow", 1)
	await g.cmd_floop(0, "building", 0)
	ok(g.players[0].creatures[0] == a, "Облачная башня: переместила существо в свою зону")
	g.turn_player = 1
	g.cmd_source = "hot_shot"
	ok(g.creature_opts(1, [0]).is_empty(), "Облачная башня: заклинания соперника её не выбирают")
	g.cmd_source = ""
	g.turn_player = 0
	await build(0, "domed_stronghold", 2)
	var b = await put(0, "drooling_dude", 2)
	ok(g.def_of(0, 2) == 11, "Купольная твердыня: +2 к защите")
	g.cmd_source = "hot_shot"
	await g.damage_creature(0, 2, 3, {"kind": "effect", "p": 1})
	g.cmd_source = ""
	ok(b.damage == 0, "Купольная твердыня: заклинания соперника не наносят урона")


func t_dt_buildings_c() -> void:
	await build(0, "crab_skull_island", 0)
	top(0, "hot_shot")
	top(0, "cow")
	await g.cmd_floop(0, "building", 0)
	ok(g.players[0].creatures[0] != null, "Остров крабьего черепа: существо с колоды в зону")
	await build(0, "haybarn", 1)
	g.players[0].discard.append(mk("feedman"))
	await g.cmd_floop(0, "building", 1)
	ok(g.players[0].creatures[1] != null and g.players[0].creatures[1].id == "feedman", "Сеновал: Кормилец из сброса")
	await g.destroy_building(0, 1)
	ok(g.players[0].creatures[1] == null, "Сеновал: ушёл — Кормилец уничтожен")


func t_dt_buildings_d() -> void:
	await build(0, "ice_base", 0)
	ok(g.is_frozen(0, 0) and g.is_frozen(1, 0) and g.creature_lane_ok(0, 0), "Ледяная база: мороз, но играть в зону можно")
	await build(0, "pillow_fortress", 1)
	var a = await put(0, "drooling_dude", 1)
	var b = await put(0, "drooling_dude", 2)
	a.damage = 3
	b.damage = 3
	bot.answers = ["Снять 2 урона", spot(0, 2)]
	await g.cmd_floop(0, "building", 1)
	ok(a.damage == 1 and b.damage == 1, "Подушечная крепость: снять 2 с двух существ")
	await build(0, "sand_castle", 2)
	await g.cmd_activate(0, "building", 2)
	ok(g.players[0].creatures.has(b) and b.damage == 0, "Песчаный замок: на руку и снова в игру")
	await build(0, "snow_bank", 3)
	await g.freeze(1, 3)
	var hp: int = g.players[1].hp
	await g.cmd_floop(0, "building", 3)
	ok(g.players[1].hp == hp - 3 and not g.is_frozen(1, 3), "Снежный банк: снял мороз — 3 урона")


func t_dt_damaged4() -> void:
	var c = await put(0, "cutie_koala", 0)
	c.damage = 4
	ok(g.atk_of(0, 0) == 3, "Коала-милашка: 4+ урона — +2")
	var o = await put(0, "overstuffed_orangutan", 1)
	o.damage = 4
	ok(g.atk_of(0, 1) == 4, "Перекормленный орангутан: атака ×2")
	var gr = await put(0, "giddy_giraffe", 2)
	gr.damage = 4
	await put(1, "drooling_dude", 2)
	var hp: int = g.players[1].hp
	await g.cmd_attack(0, 2)
	ok(g.players[1].hp == hp - 1, "Весёлый жираф: нападает на соперника")
	var s = await put(0, "sewn_sloth", 3)
	s.damage = 4
	ok(g.atk_of(0, 2) == 1 + 2, "Шитый ленивец: соседям +2 при 4+ уроне")


func t_dt_damaged4_b() -> void:
	var b = await put(0, "adorabunny", 0)
	b.damage = 4
	var hp: int = g.players[1].hp
	await g._start_turn(0)
	ok(g.players[1].hp == hp - 3, "Милокрольчик: 3 урона сопернику")
	var l = await put(0, "loveable_lamb", 1)
	l.damage = 4
	var x = await put(1, "drooling_dude", 1)
	await g._start_turn(0)
	ok(x.damage == 2, "Милый ягнёнок: 2 урона существу напротив")
	var sq = await put(0, "stitched_squirrel", 2)
	sq.damage = 4
	await build(1, "schoolhouse", 2)
	await g._start_turn(0)
	ok(g.players[1].buildings[2] == null, "Сшитая белка: разрушила строение напротив")
	var f = await put(0, "fluffy_fox", 3)
	f.damage = 4
	var y = await put(1, "cow", 3)
	await g.damage_creature(0, 3, 1, {"kind": "combat", "p": 1, "card": y})
	ok(f.damage == 4, "Пушистый лис: игнорирует первые 2 урона от существ")


func t_dt_movers() -> void:
	var bio = await put(0, "biomancer", 0)
	bio.damage = 3
	var chrono = await put(0, "chronomancer", 1)
	await g.move_creature(0, 1, 2)
	ok(bio.damage == 1 and g.players[0].actions == 3, "Биомант лечится, Хрономант даёт действие при смене зоны")
	await put(0, "robomancer", 3)
	ok(g.atk_of(0, 3) == 3, "Робомант: +1 за смену зоны в этот ход")
	ok(chrono != null, "…")


func t_dt_creatures_a() -> void:
	await put(0, "brigadier_banana_split", 0)
	var x = await put(1, "drooling_dude", 2)
	await g.freeze(1, 2)
	await g.cmd_attack(0, 0)
	ok(x.damage == 2, "Бригадир Банана-сплит: 2 урона существу на морозе")
	g.phase = "main"
	await put(0, "four_star_fudge", 1)
	var n: int = g.players[0].hand.size()
	await g.freeze(1, 3)
	ok(g.players[0].hand.size() == n + 1, "Помадка «Четыре звезды»: заморозилась земля — карта")
	await put(0, "frozen_bananancy", 2)
	await g.freeze(0, 2)
	var hp: int = g.players[1].hp
	await g._enter_battle(0)
	ok(g.players[1].hp <= hp - 2, "Замороженная БанаНэнси: 2 урона сопернику")


func t_dt_creatures_b() -> void:
	await put(0, "feedman", 0)
	ok(g.cost_of(0, hand(0, "drooling_dude")) == 1, "Кормилец: следующее существо дешевле")
	await put(0, "fumigator", 1)
	var x = await put(1, "cow", 0)
	await g.cmd_floop(0, "creature", 1)
	ok(x.damage == 1 and g.players[0].actions == 1, "ФумиГатор: 1 урон всем за действие")
	var w = await put(0, "granary_weevil", 2)
	var y = await put(1, "cow", 2)
	await g.cmd_activate(0, "creature", 2)
	ok(g.players[1].creatures[0] == null and g.players[1].creatures[2] == null, "Амбарный долгоносик: все с тем же названием уничтожены")
	ok(w != null and y != null, "…")


func t_dt_creatures_c() -> void:
	await put(0, "green_zebracorn", 0)
	var hp: int = g.players[1].hp
	await g.cmd_attack(0, 0)
	ok(g.players[1].hp == hp - 1 - 1, "Зелёный ЗеброРог: сразу 1 урон сопернику")
	g.phase = "main"
	await put(1, "cow", 0)
	await put(1, "cow", 2)
	await put(0, "spiked_zebracorn", 1)
	await g.cmd_attack(0, 1)
	ok(g.players[1].creatures[0].damage == 1 and g.players[1].creatures[2].damage == 1, "Шипастый ЗеброРог: 1 урон в соседних зонах")
	await g.freeze(1, 3)
	g.phase = "main"
	ok(g.cost_of(0, hand(0, "ice_cream_captain")) == 3, "Капитан Пломбир: −1 за игрока с замороженной землёй")


func t_dt_creatures_d() -> void:
	var x = await put(1, "cow", 2)
	await put(0, "instigator", 0)
	ok(g.players[1].creatures[0] == x, "ПровокАтор: перетащил существо соперника в свою зону")
	lands(0, "ice")
	await put(0, "irrigator", 1)
	ok(g.atk_of(0, 1) == 3, "ИрригАтор: на ледяной земле +2")
	lands(0, "corn")
	await put(0, "king_baby", 2)
	var y = await put(1, "drooling_dude", 3)
	bot.answers = [spot(1, 3)]
	await g.cmd_floop(0, "creature", 2)
	ok(y.damage == 4, "Король-младенец: урон за кукурузные поля")
	_fresh()
	await build(0, "blood_fortress", 1)
	await put(0, "knit_kitty", 0)
	ok(g.atk_of(0, 0) == 4, "Вязаный котик: на него действует строение соседней зоны")


func t_dt_creatures_e() -> void:
	var a = await put(0, "drooling_dude", 0)
	a.damage = 3
	await put(0, "lifeguard_lobster", 1)
	bot.answers = [spot(0, 0)]
	await put(0, "cow", 2)
	ok(a.damage == 2, "Омар-спасатель: вошло существо — снять 1 урон")
	lands(1, "swamp")
	await put(0, "longboard_lobster", 3)
	ok(g.atk_of(0, 3) == 1 + 4, "Омар-лонгбордист: +1 за болото в игре")
	await put(0, "mint_chocouflage", 2)
	await g.damage_creature(0, 2, 2, {"kind": "effect", "p": 1})
	ok(g.players[0].creatures[2].damage == 0, "Мятный шокомуфляж: без существа напротив урон от соперника не проходит")


func t_dt_creatures_f() -> void:
	await put(0, "mocha_launcher", 0)
	var x = await put(1, "cow", 1)
	x.damage = 4
	bot.answers = [spot(1, 1)]
	await g.cmd_floop(0, "creature", 0)
	ok(g.players[1].creatures[1] == null and g.is_frozen(1, 1), "Мокко-пушка: уничтожила — заморозила землю")
	var nav = await put(0, "navigator", 1)
	g.players[0].hand = [mk("drooling_dude")]
	await g.cmd_activate(0, "creature", 1)
	ok(nav.temp_atk == 2, "НавиГатор: +атака = стоимость сброшенной")
	var pup = await put(0, "patched_puppy", 2)
	await g.cmd_activate(0, "creature", 2)
	ok(pup.damage == 3 and pup.temp_atk == 2, "Заштопанный щенок: 3 урона себе — +2")


func t_dt_creatures_g() -> void:
	var nec = await put(0, "necromancer", 0)
	await put(0, "cow", 2)
	bot.answers = ["Переместить"]
	await g.destroy_creature(0, 2)
	ok(g.players[0].creatures[2] == nec, "Некромант: перешёл на опустевшую землю")
	var x = await put(1, "drooling_dude", 1)
	bot.answers = [spot(1, 1)]
	await put(0, "pyromancer", 1)
	ok(x.damage == 2, "Пиромант: на пустую землю — 2 урона в зоне")
	await put(0, "patriot_popsicle", 3)
	ok(g.is_frozen(0, 3) or g.is_frozen(1, 3), "Эскимо-патриот: заморозил землю в зоне")


func t_dt_crabs() -> void:
	var rc = await put(0, "repelling_rock_crab", 0)
	var x = await put(1, "drooling_dude", 0)
	g.turn_player = 1
	await g.cmd_attack(1, 0)
	ok(x.damage == 1 + 3 or g.players[1].creatures[0] == null, "Отражающий скальный краб: отражает урон")
	g.turn_player = 0
	g.phase = "main"
	ok(rc != null, "…")
	hand(0, "president_sweetcorn")
	await put(0, "sailing_sand_crab", 1)
	ok(g.players[0].creatures.any(func(c): return c != null and c.id == "president_sweetcorn"), "Песчаный краб-мореход: существо за 1 бесплатно")
	await put(0, "slashy_sand_crab", 2)
	var y = await put(1, "drooling_dude", 2)
	await put(0, "cow", 3)
	ok(y.damage == 2, "Режущий песчаный краб: сыграно рядом — 2 урона напротив")


func t_dt_misc() -> void:
	var t = await put(0, "softie_recruit", 0)
	ok(g.players[0].actions == 3, "Мягкий новобранец: нет соперника напротив — действие")
	for i in 10:
		g.players[0].discard.append(mk("cow"))
	await put(0, "subjugator", 1)
	await put(1, "drooling_dude", 1)
	ok(g.def_of(1, 1) == 7, "ПокорГатор: −1 к защите напротив за 5 карт сброса")
	await put(0, "cow", 2)
	await g.destroy_creature(0, 2)
	var n: int = g.players[0].hand.size()
	await put(0, "tailgator", 2)
	ok(g.players[0].hand.size() == n + 1, "ХвостоГатор: карта за существо, ушедшее в сброс")
	await put(0, "the_barrel", 3)
	await put(1, "the_barrel", 3)
	ok(g.atk_of(0, 3) == 2 and g.def_of(0, 3) == 6, "Бочка: +1/+1 за другую Бочку")
	ok(t != null, "…")


func t_dt_teamwork_users() -> void:
	g.players[0].teamwork = mk("assistance", 0)
	await put(0, "trained_zebracorn_husker", 0)
	ok(g.atk_of(0, 0) == 4, "Обученный кожурыцарь-зебророг: +1 за командную карту")
	await put(0, "the_cooper", 1)
	bot.answers = [spot(0, 1)]
	await g.cmd_floop(0, "creature", 1)
	ok(g.players[0].creatures[1].temp_atk == 1, "Бондарь: + стоимость командных карт")
	top(0, "cow")
	top(0, "fellowship")
	top(0, "cow")
	await put(0, "investigator", 2)
	await g.cmd_floop(0, "creature", 2)
	ok(g.players[0].teamwork.id == "fellowship", "ИсследоГатор: открыл и сыграл командную карту")
	top(0, "solidarity")
	top(0, "cow")
	bot.answers = ["Искать"]
	await put(0, "hydromancer", 3)
	ok(g.players[0].teamwork.id == "solidarity", "Гидромант: нашёл и сыграл командную карту")


func t_dt_freezers() -> void:
	await put(0, "ice_cream_sammy", 0)
	bot.answers = [{"p": 0, "lane": 2, "row": "creature"}]
	await g.cmd_floop(0, "creature", 0)
	ok(g.is_frozen(0, 2) and g.is_frozen(1, 2), "Мороженщик Сэмми: заморозил обе земли зоны")
	await put(0, "smooth_eli", 1)
	bot.answers = [{"p": 0, "lane": 2}, {"p": 1, "lane": 0}]
	await g.cmd_floop(0, "creature", 1)
	ok(not g.is_frozen(0, 2) and g.is_frozen(1, 0), "Гладкий Илай: перенёс жетон мороза")
	await put(0, "ultra_dog", 3)
	await put(1, "cow", 3)
	bot.answers = [spot(1, 3)]
	await g.cmd_floop(0, "creature", 3)
	ok(g.is_frozen(1, 3), "Ультрапёс: заморозил землю с существом")


func t_dt_elephant() -> void:
	await put(1, "endearing_elephant", 0)
	lands(0, "lava")
	var hp: int = g.players[0].hp
	bot.answers = [spot(1, 0)]
	var hs = hand(0, "hot_shot")
	await g.run_command(0, {"cmd": "play", "uid": hs.uid, "lane": -1})
	ok(g.players[0].hp == hp - 2, "Очаровательный слон: выбран заклинанием соперника — 2 урона")


# ================================================================= «Выбранный»: без цели нельзя

## Records the events the engine sends to the board.
class Events:
	var seen: Array = []
	func play(ev: Dictionary) -> void:
		seen.append(ev)


## Spells, floops and paid abilities that choose a player or the card itself: a target is always there.
const ALWAYS_TARGET := ["abraca_amadeus", "mace_stump", "strength_crystal", "skeletal_hand", "blood_bath",
	"bums_away", "frosty_frolic", "cottonpult", "convey_wisdom", "firm_handshake", "matchy_matchy", "twinsies",
	"king_baby", "mocha_launcher", "the_cooper", "witch_slap", "giant_mummy_hand", "sweet_delicious_meats",
	"flameingo_flameweaver", "gossamer_beam", "mire_madness", "heart_potion", "punch_potion", "axolotl",
	"buttering_ram", "shock_box"]


func t_chosen_has_check() -> void:
	var rx := RegEx.create_from_string("(?i)выбранн")
	var missing := []
	CardDB.ensure_loaded()
	for id: String in CardDB._defs.keys():
		var d: Dictionary = CardDB.get_def(id)
		if rx.search(String(d.get("text", ""))) == null or ALWAYS_TARGET.has(id):
			continue
		var hook := ""
		if d.get("floop", false):
			hook = "floop_ok_"
		elif d.has("activated"):
			hook = "act_ok_"
		elif d["kind"] == "spell":
			hook = "playable_"
		if hook != "" and not g.has_hook(hook + id):
			missing.append(id)
	ok(missing.is_empty(), "«выбранный»: у каждого заклинания и способности с выбором цели есть проверка цели %s" % [missing])


func t_chosen_no_target() -> void:
	var castable := func(id: String) -> bool: return g.spell_castable(0, mk(id))
	for id in ["ham_fist", "frostfire_potion", "bladespire_maelstrom", "friendship_potion", "enchanted_celebration"]:
		ok(not castable.call(id), "«выбранный»: «%s» без существ не играется" % CardDB.get_def(id)["name"])
	g.players[1].discard.append(mk("cow", 1))
	ok(not castable.call("blood_transfusion"), "Переливание крови: без существа в игре не играется")
	var x = await put(0, "cow", 1)
	ok(castable.call("ham_fist") and castable.call("blood_transfusion"), "Окорок-кулак, Переливание крови: со своим существом играются")
	ok(not castable.call("friendship_potion"), "Зелье дружбы: нужно и своё, и чужое существо")
	await put(1, "cow", 1)
	ok(castable.call("friendship_potion"), "Зелье дружбы: своё и чужое есть — играется")
	ok(castable.call("enchanted_celebration") and x != null, "Волшебное празднество: есть куда передвинуть — играется")
	for s in 2:
		for l in 4:
			g.players[s].lands[l]["frozen"] = true
	ok(castable.call("snow_way") and castable.call("freeze_ray") and castable.call("slushie_salvo"),
		"Игрок: замороженную землю можно заморозить снова — Лыжню!, УЗИ, Залп слаша играются и при всех замёрзших землях")


## Игрок: Панк-кот и Синюшная кровь — «каждое существо», чужое тоже; кровь даёт +2 только уже сменившим зону.
func t_chosen_punk_cat_woad_blood() -> void:
	await put(0, "punk_cat", 0)
	var x = await put(1, "drooling_dude", 1)
	await g.move_creature(1, 1, 2)
	ok(g.atk_of(1, 2) == 3 + 2, "Панк-кот: +2 и существу соперника, сменившему зону")
	var y = await put(0, "phyllis", 1)
	await play(0, hand(0, "woad_blood"))
	ok(g.atk_of(1, 2) == 3 + 2 + 2, "Синюшная кровь: +2 существу соперника, сменившему зону")
	await g.move_creature(0, 1, 3)
	ok(g.atk_of(0, 3) == 2 + 2, "Синюшная кровь: сменившее зону после неё не получает +2 (только Панк-кот)")
	ok(x != null and y != null, "…")


## Игрок: Свинья рядом с синей равниной и перевёрнутым кукурузным полем не флюпается — и через Школу тоже.
func t_chosen_pig_school() -> void:
	g.players[0].lands[1]["type"] = "plain"
	g.players[1].lands[1]["type"] = "corn"
	g.players[1].lands[1]["flipped"] = true
	var x = await put(0, "woadic_marauder", 1)
	await build(0, "schoolhouse", 1)
	g.players[0].discard.append(mk("the_pig"))
	await g.cmd_floop(0, "building", 1)
	ok(x.granted_floop == "the_pig" and not g.can_floop(0, "creature", 1), "Школа: флюп Свиньи без кукурузного поля применить нельзя")
	g.players[1].lands[1]["flipped"] = false
	ok(g.can_floop(0, "creature", 1), "Школа: с открытым кукурузным полем в зоне — можно")
	await put(0, "the_pig", 2)
	g.players[0].lands[2]["type"] = "corn"
	g.players[0].lands[2]["flipped"] = true
	g.players[1].lands[2]["type"] = "plain"
	ok(not g.can_floop(0, "creature", 2), "Свинья: перевёрнутое кукурузное поле — не цель")


## Игрок: Смерч штормового клинка возвращает каждое существо на руку его владельца.
func t_galeblade_owner_hand() -> void:
	lands(0, "plain")
	var a = await put(0, "future_scholar", 0)
	var b = await put(1, "future_scholar", 2)
	var stolen = await put(0, "cow", 1, 1)
	bot.answers = [spot(0, 1), spot(1, 2)]
	await play(0, hand(0, "galeblade_tornado"))
	ok(g.players[1].hand.has(stolen) and g.players[1].hand.has(b) and not g.players[0].hand.has(b),
		"Смерч штормового клинка: чужие существа уходят на руку владельца")
	ok(g.players[0].creatures[0] == a, "…")


## Игрок: радужная карта не даёт типа земель (Призмо, Призматархия, Всевидящее око).
func t_rainbow_no_type() -> void:
	g._record_play(0, mk("cow"))           # радужная
	g._record_play(0, mk("archer_dan"))    # кукурузная
	ok(g.played_types(0) == 1, "Призмо: радужная и кукурузная карты — это не 2 разных типа земель")
	g._record_play(0, mk("woadic_marauder"))
	ok(g.played_types(0) == 2, "Призмо: кукурузная и равнинная — 2 типа")
	await put(0, "cow", 0)
	await put(0, "archer_dan", 1)
	var pr = mk("prismatarchia")
	ok(g.cost_of(0, pr) == 3, "Призматархия: радужное существо не считается (стоит %d)" % g.cost_of(0, pr))
	g.players[0].deck.clear()
	top(0, "archer_dan")
	top(0, "cow")
	await g.run_hook("spell_eye_see_all", [mk("eye_see_all"), 0])
	var ids: Array = g.players[0].hand.map(func(c): return c.id)
	ok(ids == ["archer_dan"], "Всевидящее око: радужную карту не берёт (на руке %s)" % [ids])


func t_abracadaniel_reveals() -> void:
	var ev := Events.new()
	g.animator = ev
	g.players[0].hero_card = "abracadaniel"
	top(0, "archer_dan")
	await g.cmd_hero_power(0)
	ok(ev.seen.any(func(e): return e["type"] == "reveal"), "Абракадэниел: верхнюю карту видят оба игрока, даже не радужную")
	ok(g.players[0].deck.back().id == "archer_dan", "Абракадэниел: не радужная карта остаётся сверху")


## Реплей игрока: Крошечный слон считается и радужным, значит Грамотей-младенец получает +3.
func t_fc_infant_scholar_counts_tiny_elephant() -> void:
	lands(0, "plain")
	var s = await put(0, "infant_scholar", 3)
	ok(g.atk_of(0, 3) == 1, "Грамотей-младенец: без радужных карт 1 атаки (got %d)" % g.atk_of(0, 3))
	var e = hand(0, "tiny_elephant")
	await play(0, e, 1)
	ok(g.players[0].creatures[1] == e and g.is_type(e, "rainbow", 0, 1), "Крошечный слон сыгран и считается радужным")
	ok(g.atk_of(0, 3) == 4, "Грамотей-младенец: Крошечный слон даёт +3 к атаке (got %d)" % g.atk_of(0, 3))
	await g._end_turn_cleanup(0)
	g.turn_player = 1
	ok(g.atk_of(0, 3) == 1, "Грамотей-младенец: бонус только в ход игрока")
	# Сыгранная бесплатно радужная карта тоже считается.
	g.turn_player = 0
	g.players[0].turn.erase("rainbow_played")
	ok(g.atk_of(0, 3) == 1, "Грамотей-младенец: новый ход без радужных карт")
	var f = hand(0, "tiny_elephant")
	await g.play_free(0, f)
	ok(g.atk_of(0, 3) == 4, "Грамотей-младенец: бесплатно сыгранный Крошечный слон тоже даёт +3 (got %d)" % g.atk_of(0, 3))
	var n = hand(0, "corn_ronin")
	g.players[0].turn.erase("rainbow_played")
	await g.play_free(0, n)
	ok(g.atk_of(0, 3) == 1, "Грамотей-младенец: обычная карта бонуса не даёт")


func t_fc_woadic_weirdo_in_play() -> void:
	lands(0, "plain")
	await put(0, "woadic_weirdo", 0)
	await put(0, "woadic_matriarch", 1)
	var c = hand(0, "corn_ronin")
	await g.cmd_floop(0, "creature", 0)
	ok(g.play_land(c) == "rainbow", "Синюшный чудила: показанная карта стала Радужной")
	await play(0, c, 2)
	ok(g.players[0].creatures[2] == c and g.is_type(c, "rainbow", 0, 2), "Синюшный чудила: сыгранная карта Радужная до конца хода")
	ok(not g.is_type(c, "corn", 0, 2), "Синюшный чудила: у Радужной нет типа земель")
	ok(g.atk_of(0, 1) == 2, "Синюшная матриарх: считает существо от Синюшного чудилы")
	await g._end_turn_cleanup(0)
	ok(g.is_type(c, "corn", 0, 2) and g.atk_of(0, 1) == 1, "Синюшный чудила: после хода снова кукурузное")


## Игрок: карте за 0 нужна открытая земля своего типа, перевёрнутая не считается.
func t_zero_cost_needs_land() -> void:
	lands(0, "plain")
	var dog = hand(0, "fire_dog")
	ok(not g.can_play(0, dog.uid), "Огненный пёс: без Лавовых равнин сыграть нельзя")
	g.players[0].lands[0]["type"] = "lava"
	g.players[0].lands[0]["flipped"] = true
	ok(not g.can_play(0, dog.uid), "Огненный пёс: перевёрнутые Лавовые равнины не считаются")
	g.players[0].lands[0]["flipped"] = false
	ok(g.can_play(0, dog.uid), "Огненный пёс: с открытыми Лавовыми равнинами можно")
	for l in 4:
		g.players[0].lands[l]["flipped"] = true
	ok(g.can_play(0, hand(0, "big_foot").uid), "Бигфут: радужной карте за 0 земли не нужны")


func t_self_pay_floop() -> void:
	# Rulebook: Док Смерть may destroy any creature you control to pay, itself too.
	var doc = await put(0, "dr_death", 1)
	var foe = await put(1, "evil_eye", g.across(0, 1)[1])
	ok(g.can_floop(0, "creature", 1), "Док Смерть: флюп доступен, когда своё существо только он")
	bot.answers = [func(req): return req["options"].filter(func(o): return o["lane"] == 1)[0]]
	await g.cmd_floop(0, "creature", 1)
	ok(g.players[0].creatures[1] == null and g.players[0].discard.has(doc), "Док Смерть: уничтожил себя")
	ok(not g.players[1].creatures.has(foe), "Док Смерть: существо соперника в зоне тоже уничтожено")
	_fresh()
	var hit = await put(0, "industrial_assassin", 2)
	var n: int = g.players[0].hand.size()
	bot.answers = [func(req): return req["options"].filter(func(o): return o["lane"] == 2)[0]]
	await g.cmd_floop(0, "creature", 2)
	ok(g.players[0].creatures[2] == null and g.players[0].discard.has(hit), "Промышленный убийца: уничтожил себя")
	ok(g.players[0].hand.size() == n + 1, "Промышленный убийца: карта взята")


func t_necromancer_fights_after_move() -> void:
	# Bug report: «атаковать всеми» went left to right once, so Некромант that moved onto
	# a lane already passed (its creature died in the fight) did not attack this turn.
	var weak = await put(0, "cow", 0)
	var nec = await put(0, "necromancer", 3)
	var a: Array = g.across(0, 0)
	await put(a[0], "evil_eye", a[1])
	g.players[a[0]].creatures[a[1]].damage = 0
	weak.damage = g.def_of(0, 0) - 1
	bot.answers = ["Переместить"]
	await g.cmd_end_turn(0)
	ok(g.where(nec.uid)["lane"] == 0, "Некромант перешёл на опустевшую землю")
	ok(nec.exhausted, "Некромант атаковал после перехода")
