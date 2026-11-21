extends SceneTree
## Targeted rules checks for the trickier card mechanics, headless:
##   godot --headless --path . -s res://tests/rules_test.gd

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")


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
var g
var bot: Scripted


func _initialize() -> void:
	var tests := [
		"t_freeze", "t_lumberjack", "t_camel", "t_possum", "t_spirit_tower",
		"t_falling_star", "t_learning_center", "t_palace", "t_shark_palace", "t_enchantress", "t_pyramidia", "t_silo_freedom", "t_coffin",
		"t_cave", "t_pied_piper", "t_parrotrooper", "t_parrotrooper_foe", "t_parrotrooper_full",
		"t_parrotrooper_cards", "t_sandmagus", "t_masher", "t_steakchop",
		"t_charming_city", "t_wombat", "t_blood_castle", "t_hero_finn", "t_field_reaper", "t_shark", "t_corn_dog_husker_worm", "t_hero_jake", "t_hero_pb", "t_hero_lsp", "t_hero_bmo", "t_hero_rainicorn",
		"t_hero_ice_king", "t_hero_marceline", "t_hero_lemongrab", "t_hero_gunter", "t_hero_fionna",
		"t_hero_cake", "t_hero_tree_trunks", "t_hero_lich", "t_hero_monica", "t_hero_jake_2x2",
		"t_hero_charlie", "t_hero_ricardio", "t_hero_prismo", "t_hero_susan", "t_hero_cosmic_owl",
		"t_hero_huntress", "t_hero_magic_man", "t_hero_abracadaniel", "t_building_cost", "t_hero_grand_prix", "t_undo",
	]
	for t in tests:
		await _fresh()
		await call(t)
	print("rules tests: %d checks failed" % failures)
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
	if cond:
		print("ok   ", what)
	else:
		failures += 1
		printerr("FAIL ", what)


## Makes a card from nothing (it joins the owner's pile accounting).
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


# ---------------------------------------------------------------- tests

func t_freeze() -> void:
	var c = hand(0, "evil_eye")
	await g.freeze(0, 1)
	ok(not g.can_play(0, c.uid, 1), "creatures can't enter a frozen land")
	ok(g.can_play(0, c.uid, 2), "…but can enter a normal one")
	var d = hand(0, "frosted_deanimator")
	g.players[0].lands[1]["type"] = "ice"
	ok(g.can_play(0, d.uid, 1), "Морозный деаниматор may enter frozen lands")
	var b = hand(0, "schoolhouse")
	ok(g.can_play(0, b.uid, 1), "buildings may be built on a frozen land")
	ok(g.can_thaw(0, 1), "a frozen land can be thawed")
	var before: int = g.players[0].hand.size()
	await g.cmd_thaw(0, 1)
	ok(not g.is_frozen(0, 1), "thawing removes the frost token")
	ok(g.players[0].hand.size() == before - 1 and g.players[0].actions == 2, "thawing discards a card, not an action")
	# no card to discard: no thaw
	g.players[0].hand.clear()
	await g.freeze(0, 1)
	ok(not g.can_thaw(0, 1), "thawing needs a card to discard")
	# no limit on frost tokens
	await g.freeze(0, 0)
	await g.freeze(0, 2)
	await g.freeze(1, 0)
	ok(g.frozen_count() == 4, "four frost tokens are in play")
	await g.freeze(1, 1)
	ok(g.is_frozen(1, 1) and g.frozen_count() == 5, "a fifth frost token is fine")



func t_lumberjack() -> void:
	await put(0, "burly_lumberjack", 2)
	await build(0, "celestial_castle", 2)
	var f = hand(0, "blood_fortress")
	g.players[0].actions = 2
	ok(g.can_play(0, f.uid, 2), "Крепкий лесоруб allows a second building")
	await g.cmd_play(0, f.uid, 2)
	ok(g.players[0].buildings[2] != null and g.players[0].extra_buildings[2].size() == 1, "second building is added, not replaced")
	ok(g.atk_of(0, 2) == 3 and g.def_of(0, 2) == 12, "both buildings work (ATK %d, DEF %d)" % [g.atk_of(0, 2), g.def_of(0, 2)])


func t_camel() -> void:
	var camel = await put(0, "carmel_camel", 0)
	await put(0, "evil_eye", 1)
	bot.answers = ["Под Карамельный верблюд"]
	await g.destroy_creature(0, 1)
	ok(camel.under.size() == 1, "a dying creature can go under Карамельный верблюд")
	ok(g.atk_of(0, 0) == 1 and g.def_of(0, 0) == 5, "Карамельный верблюд +1/+1 per card")
	var before: int = g.players[0].discard.size()
	await g.destroy_creature(0, 0)
	ok(g.players[0].discard.size() == before + 2, "Карамельный верблюд leaves: it and the card under it go to the discard")



func t_possum() -> void:
	var possum = hand(0, "impossible_possum")
	var other = hand(0, "evil_eye")
	bot.answers = [other.uid]
	await g.discard_card(0, possum)
	ok(g.players[0].hand.has(possum) and g.players[0].discard.has(other), "Невозможный опоссум comes back for a discard")


func t_spirit_tower() -> void:
	await build(0, "spirit_tower", 1)
	var foe = await put(1, "drooling_dude", 1)
	ok(g.can_floop(0, "building", 1), "Башня духа can be flooped")
	await g.cmd_floop(0, "building", 1)
	ok(g.players[0].creatures[1] == foe and not foe.exhausted, "the enemy creature crosses over, ready")
	await g._end_turn_cleanup(0)
	ok(g.players[1].creatures[1] == foe, "…and goes home at the end of the turn")



func t_falling_star() -> void:
	await put(0, "evil_eye", 0)
	await put(1, "drooling_dude", 0)
	g.players[1].turn["falling_star"] = true
	await g.cmd_attack(0, 0)
	ok(g.players[1].creatures[0].damage == 0, "Падающая звезда stops damage from enemy creatures")



func t_learning_center() -> void:
	await put(0, "evil_eye", 1)
	await build(0, "blood_fortress", 0)
	await build(0, "learning_center", 1)
	ok(g.atk_of(0, 1) == 2, "Учебный центр copies the neighbouring Кровавая крепость")




func t_palace() -> void:
	await build(1, "palace_of_bone", 1)
	var hp_before: int = g.players[1].hp
	var c = hand(0, "cornataur")
	g.players[0].lands = g.players[0].lands.map(func(l):
		l["type"] = "corn"
		return l)
	await g.cmd_play(0, c.uid, 1)
	ok(g.players[1].hp == hp_before, "Костяной дворец cancels the enemy's enter effect")


## Костяной дворец: a creature entering its lane triggers nothing, neither its own
## enter effect nor the watchers like Акула.
func t_shark_palace() -> void:
	await build(1, "palace_of_bone", 1)
	await put(0, "shark", 1)
	ok(g.atk_of(0, 1) == 2, "Акула in the palace's lane gets no +1 for her own entry (got %d)" % g.atk_of(0, 1))
	await _fresh()
	await build(1, "palace_of_bone", 1)
	await put(0, "shark", 0)
	var foe = await put(1, "drooling_dude", 1)
	var dmg_before: int = foe.damage
	var snake = await put(0, "sandsnake", 1)
	ok(snake.temp_atk == 0 and g.atk_of(0, 0) == 3, "a Sandy creature entering the palace's lane gets no Акула bonus (got %d, %d)" % [snake.temp_atk, g.atk_of(0, 0)])
	ok(foe.damage == dmg_before, "…and the palace cancels that creature's own enter effect")


func t_enchantress() -> void:
	await put(1, "woadic_enchantress", 2)
	await put(0, "the_pig", 2)
	ok(not g.can_floop(0, "creature", 2), "Синюшная чародейка stops floops on her lane")


func t_pyramidia() -> void:
	await put(0, "evil_eye", 1)
	await build(0, "pyramidia", 1)
	await g.cmd_floop(0, "building", 1)
	g.players[0].actions = 0
	var c = hand(0, "phyllis")
	ok(g.can_play(0, c.uid, 1) and not g.can_play(0, c.uid, 2), "Пирамидия's action only plays a creature on its lane")


func t_silo_freedom() -> void:
	await build(0, "silo_of_freedom", 0)
	hand(0, "evil_eye")
	bot.answers = ["Кукурузное поле"]
	await g.cmd_activate(0, "building", 0)
	ok(g.land_type(0, 0) == "corn" and g.land_count(0, "corn") == 1, "Амбар свободы changes the land type")
	g.turn_player = 1
	await g._start_turn(0)
	ok(g.land_type(0, 0) == "plain", "…until the start of its owner's next turn")


func t_coffin() -> void:
	g.players[0].lands = g.players[0].lands.map(func(l):
		l["type"] = "sandy"
		return l)
	var coffin = hand(0, "unempty_coffin")
	var golem = hand(0, "lost_golem")
	await g.cmd_play(0, coffin.uid, -1)
	ok(g.cost_of(0, golem) == 1, "Непустой гроб: next creature costs 2 less")
	await g.cmd_play(0, golem.uid, 0)
	ok(int(g.turn_value(0, "creature_discount")) == 0, "…and the discount is used up")


func t_cave() -> void:
	await build(1, "cave_of_solitude", 0)
	await put(1, "evil_eye", 0)
	hand(1, "phyllis")
	g.turn_player = 1
	g.players[1].actions = 2
	await g.cmd_activate(1, "building", 0)
	g.turn_player = 0
	await put(0, "drooling_dude", 0)
	ok(not g.can_attack(0, 0), "Пещера одиночества: can't be attacked")
	ok(g.creature_opts(0, [1]).is_empty(), "…or chosen by the opponent")


func t_pied_piper() -> void:
	await put(0, "pied_piper", 0)
	var sub = await put(0, "drooling_dude", 1)
	sub.exhausted = true
	sub.flooped = true
	await put(1, "nice_ice_baby", 0)
	bot.answers = [{"p": 0, "lane": 1}]
	await g.cmd_attack(0, 0)
	ok(g.players[1].creatures[0] == null and sub.damage == 1, "Крысолов sends a flooped creature to fight instead")




func t_parrotrooper() -> void:
	var c = hand(0, "static_parrotrooper")
	await put(0, "evil_eye", 1)
	bot.answers = [{"p": 0, "lane": 3, "row": "creature"}]
	await g.cmd_play(0, c.uid, 0)
	ok(g.players[0].creatures[3] == c, "поп-десант drops onto an empty land")
	var r = hand(0, "evil_eye")
	ok(not g.can_play(0, r.uid, 3), "…and can't be replaced")


func t_parrotrooper_foe() -> void:
	# Official rules: a parrotrooper may land on ANY empty land, the opponent's too.
	# Whoever controls it carries the drawback, the owner keeps the card.
	var c = hand(0, "static_parrotrooper")
	await put(0, "evil_eye", 1)
	await put(1, "evil_eye", 0)
	bot.answers = [{"p": 1, "lane": 2, "row": "creature"}]
	await g.cmd_play(0, c.uid, 0)
	var req: Dictionary = bot.asked[0]
	var mine := 0
	var foes := 0
	for o in req["options"]:
		mine += 1 if o["p"] == 0 else 0
		foes += 1 if o["p"] == 1 else 0
	ok(mine == 2 and foes == 3, "поп-десант is offered every empty land: own 2 and opponent's 3 (got %d, %d)" % [mine, foes])
	# The AI hands a поп-десант with a drawback to the opponent.
	var AiHelper = load("res://scripts/ai/ai_helper.gd")
	var pick = AiHelper.choose(g, {"kind": "lane", "player": 0, "options": req["options"], "hurts_controller": true})
	ok(pick["p"] == 1, "the AI sends a harmful поп-десант to the opponent's side")
	ok(g.players[1].creatures[2] == c and g.players[0].creatures[0] == null, "поп-десант lands on the opponent's side")
	ok(c.owner == 0 and g.where(c.uid)["p"] == 1, "…the owner stays, the opponent controls it")
	var r = hand(1, "evil_eye")
	g.turn_player = 1
	ok(not g.can_play(1, r.uid, 2), "…and the opponent can't replace it either")
	g.players[1].actions = 2
	var hp0: int = g.players[0].hp
	var hp1: int = g.players[1].hp
	await g._start_turn(1)
	ok(g.players[1].hp == hp1 - 1 and g.players[0].hp == hp0, "Статичный попугайчик hurts the hero of its controller")
	await g.destroy_creature(1, 2)
	ok(g.players[0].discard.has(c) and not g.players[1].discard.has(c), "a destroyed поп-десант goes to its owner's discard")


func t_parrotrooper_full() -> void:
	# No empty land anywhere: it stays where it was played.
	for l in 4:
		await put(1, "evil_eye", l)
	for l in [1, 2, 3]:
		await put(0, "evil_eye", l)
	var c = hand(0, "static_parrotrooper")
	g.players[0].creatures[0] = null
	var before: int = bot.asked.size()
	await g.cmd_play(0, c.uid, 0)
	ok(g.players[0].creatures[0] == c and bot.asked.size() == before, "no empty land: the поп-десант stays and nothing is asked")
	# Only the opponent's side has room: it must go there.
	for l in 4:
		g.players[1].creatures[l] = null
	await put(1, "evil_eye", 0)
	var d = hand(0, "jinxed_parrotrooper")
	g.players[0].creatures[2] = null
	await g.cmd_play(0, d.uid, 2)
	var at: Dictionary = g.where(d.uid)
	ok(at["p"] == 1 and at["lane"] != 0, "only foreign lands are free: the поп-десант goes there")


func t_parrotrooper_cards() -> void:
	# Невезучий: the controller discards. Мясной: the landing land flips. Драконий: neighbours of the controller.
	var j = hand(0, "jinxed_parrotrooper")
	bot.answers = [{"p": 1, "lane": 0, "row": "creature"}]
	await g.cmd_play(0, j.uid, 3)
	hand(1, "evil_eye")
	hand(1, "evil_eye")
	g.turn_player = 1
	var n: int = g.players[1].hand.size()
	await g._start_turn(1)
	ok(g.players[1].hand.size() == n, "Сглаженный попугайчик: its controller draws then discards a card")
	ok(g.players[1].discard.size() == 1 and g.players[0].discard.is_empty(), "…into the controller's own discard")
	g.turn_player = 0
	var h = hand(0, "husky_parrotrooper")
	g.players[0].actions = 2
	bot.answers = [{"p": 1, "lane": 2, "row": "creature"}]
	await g.cmd_play(0, h.uid, 1)
	ok(g.players[1].lands[2]["flipped"] and not g.players[0].lands[1]["flipped"], "Хаски-попугайчик flips the land it landed on")
	g.players[1].creatures[1] = null
	g.players[1].creatures[3] = null
	var d = hand(0, "dragoon_parrotrooper")
	var e = await put(1, "evil_eye", 2)
	bot.answers = [{"p": 1, "lane": 1, "row": "creature"}]
	g.players[0].actions = 2
	var atk: int = g.atk_of(1, 2)
	await g.cmd_play(0, d.uid, 0)
	ok(atk >= 1 and g.atk_of(1, 2) == atk - 1 and e != null, "Драгун-попугайчик weakens the neighbours of whoever controls it")
	# Ска-рпион: free while the opponent controls a creature you own.
	var s = hand(0, "ska_pion")
	ok(g.cost_of(0, s) == 0, "Ска-рпион costs 0 once the opponent controls your поп-десант")
	g.players[0].lands[0]["flipped"] = true
	g.players[0].lands[1]["flipped"] = true
	g.players[0].lands[2]["flipped"] = true
	g.players[0].lands[3]["flipped"] = true
	g.players[0].actions = 0
	ok(not g.can_play(0, s.uid, 0), "…but still needs a face-up land of its type")
	g.players[0].lands[0]["type"] = "sandy"
	g.players[0].lands[0]["flipped"] = false
	ok(g.can_play(0, s.uid, 0), "…and needs no actions then")


func t_sandmagus() -> void:
	var m = await put(0, "sandmagus", 0)
	var a = await put(0, "evil_eye", 1)
	bot.answers = ["Вернуть (+1 к атаке другим)"]
	g.turn_player = 0
	await g._start_turn(0)
	var atk: int = g.def_of(0, 1)
	ok(g.players[0].hand.has(m), "Песчаный маг goes back to its owner's hand")
	ok(a.temp_atk == 1, "…creatures in play get +1 ATK")
	var b = hand(0, "evil_eye")
	g.players[0].actions = 2
	await g.cmd_play(0, b.uid, 2)
	ok(b.temp_atk == 1, "…and so do creatures that enter later this turn (official clarification)")
	g.players[0].actions = 2
	await g.cmd_play(0, m.uid, 3)
	ok(m.temp_atk == 0, "…but not Песчаный маг itself (каждое другое существо)")
	await g._end_turn_cleanup(0)
	ok(b.temp_atk == 0 and a.temp_atk == 0, "…only for this turn")


func t_masher() -> void:
	# Крушитель недр / Рок-н-роллер flip a land in their own lane, either side's.
	for l in 4:
		g.players[0].lands[l]["type"] = "corn"
	var m = hand(0, "mantle_masher")
	bot.answers = [{"p": 1, "lane": 0, "row": "land"}]
	await g.cmd_play(0, m.uid, 0)
	var land_opts := 0
	for o in bot.asked[0]["options"]:
		land_opts += 1
	ok(land_opts == 2, "Крушитель недр offers the two lands of its lane (got %d)" % land_opts)
	ok(g.players[1].lands[0]["flipped"] and not g.players[0].lands[0]["flipped"], "…and flips the opponent's land when asked")
	await g.destroy_creature(0, 0)
	ok(not g.players[1].lands[0]["flipped"], "…the same land turns face up when it leaves")
	var r = hand(0, "rock_n_roller")
	g.players[0].actions = 2
	bot.answers = [{"p": 0, "lane": 3, "row": "land"}]
	await g.cmd_play(0, r.uid, 3)
	ok(g.players[0].lands[3]["flipped"], "Рок-н-роллер may flip its own land")
	var AiHelper = load("res://scripts/ai/ai_helper.gd")
	var pick = AiHelper.choose(g, {"kind": "land", "player": 0, "prompt": "переверни", "options": bot.asked[1]["options"]})
	ok(pick["p"] == 1, "the AI flips the opponent's land")


func t_steakchop() -> void:
	await put(0, "steakchop", 0)
	hand(0, "evil_eye")
	bot.answers = ["Уничтожить Антрекот-мясник"]
	g.turn_player = 0
	await g._start_turn(0)
	ok(g.players[0].creatures[0] == null, "Антрекот-мясник is destroyed when not fed")


func t_charming_city() -> void:
	var dude = await put(1, "drooling_dude", 2)
	await put(0, "tiny_elephant", 1)
	ok(g.is_type(g.players[0].creatures[1], "rainbow", 0, 1), "Крошечный слон also counts as Rainbow")
	await build(0, "charming_city", 2)
	ok(g.card_types(dude, 1, 2) == ["rainbow"], "Очаровательный город turns the whole lane Rainbow")


func t_wombat() -> void:
	for l in 4:
		await put(0, "evil_eye", l)
	g.players[0].creatures[2] = null
	var w = await put(0, "tired_wombat", 2)
	g.turn_player = 0
	await g._start_turn(0)
	var w_at: Dictionary = g.where(w.uid)
	ok(w_at["zone"] == "creature" and w_at["p"] == 1, "Усталый вомбат with no room wanders to the opponent")


func t_blood_castle() -> void:
	await build(0, "blood_castle", 1)
	await put(1, "drooling_dude", 1)
	await g.damage_creature(1, 1, 2)
	ok(g.players[1].creatures[1].damage == 3, "Кровавый замок adds 1 to damage on its lane")



func t_hero_finn() -> void:
	g.players[0].hero_card = "finn"
	var a = await put(0, "evil_eye", 0)
	var t = await put(1, "drooling_dude", 0)
	ok(g.can_floop(0, "creature", 0), "Финн: a creature without a floop gets one")
	bot.answers = [{"p": 1, "lane": 0}]
	await g.cmd_floop(0, "creature", 0)
	ok(t.damage == 1 and a.flooped, "Финн: the hero floop deals 1 damage")
	var b = await put(0, "phyllis", 1)
	b.damage = 1
	ok(not g.can_floop(0, "creature", 1), "Финн: damaged creatures do not get it")
	var sc = await put(0, "ancient_scholar", 2)
	var t2 = await put(1, "drooling_dude", 3)
	var acts: Array = g.legal_commands(0).filter(func(x): return x.get("hero", false))
	ok(acts.size() == 1 and int(acts[0]["lane"]) == 2, "Финн: a creature with its own floop also has the hero floop as a separate command")
	bot.answers = [{"p": 1, "lane": 3}]
	await g.cmd_floop(0, "creature", 2)
	ok(sc.flooped and t2.damage == 0, "Игрок: its own floop does not deal the hero's 1 damage too")
	sc.exhausted = false
	sc.flooped = false
	bot.answers = [{"p": 1, "lane": 3}]
	await g.cmd_floop(0, "creature", 2, true)
	ok(sc.flooped and t2.damage == 1, "Финн: the hero floop chosen instead deals the 1 damage")


func t_shark() -> void:
	await put(0, "shark", 0)
	ok(g.atk_of(0, 0) == 3, "Акула: +1 ATK when she enters (got %d)" % g.atk_of(0, 0))
	var snake = await put(0, "sandsnake", 1)
	ok(snake.temp_atk == 1 and g.atk_of(0, 0) == 3, "Акула: another Sandy creature entering gets +1 ATK, not the Shark (got %d, %d)" % [snake.temp_atk, g.atk_of(0, 0)])


func t_corn_dog_husker_worm() -> void:
	for l in 4:
		g.players[0].lands[l]["type"] = "corn"
	await put(0, "corn_dog", 0)
	ok(g.atk_of(0, 0) == 0 and g.def_of(0, 0) == 16, "Кукутузик: 4 поля = 0/16 (got %d/%d)" % [g.atk_of(0, 0), g.def_of(0, 0)])
	bot.answers = [{"p": 0, "lane": 2}]
	var w = await put(0, "husker_worm", 1)
	ok(g.players[0].lands[2]["flipped"] and g.atk_of(0, 1) == 5 and g.def_of(0, 1) == 4,
		"Шаи-Кукуруз: 5/4, переворачивает своё кукурузное поле")
	ok(w != null and g.atk_of(0, 0) == 1 and g.def_of(0, 0) == 15, "Кукутузик: 3 поля = 1/15 (got %d/%d)" % [g.atk_of(0, 0), g.def_of(0, 0)])


func t_field_reaper() -> void:
	var e = await put(1, "drooling_dude", 1)
	await put(0, "evil_eye", 0)
	bot.answers = [{"p": 1, "lane": 1}, {"p": 0, "lane": 2, "row": "creature"}]
	var r = await put(0, "field_reaper", 1)
	ok(g.players[0].creatures[2] == e and g.players[1].creatures[1] == null and g.players[0].creatures[1] == r,
		"Жнец: the opposing creature crosses to an empty adjacent lane on the Reaper's side")
	ok(e.exhausted and e.moved_this_turn, "Жнец: the taken creature is exhausted and has changed Lanes")
	await _fresh()
	var m = await put(1, "woadic_marauder", 1)
	var n: int = g.players[0].hand.size()
	bot.answers = [{"p": 1, "lane": 1}, {"p": 0, "lane": 2, "row": "creature"}]
	await put(0, "field_reaper", 1)
	ok(g.players[0].creatures[2] == m and g.players[0].hand.size() == n + 1, "Жнец: a taken Синюшный злопыхатель draws for its new controller (hand %d → %d)" % [n, g.players[0].hand.size()])


func t_hero_jake() -> void:
	g.players[0].hero_card = "jake"
	await put(0, "evil_eye", 1)
	await g.flip_land(0, 1, true)
	ok(g.atk_of(0, 1) == 3, "Джейк: +2 ATK on a face-down land (got %d)" % g.atk_of(0, 1))


func t_hero_pb() -> void:
	g.players[0].hero_card = "pb"
	var c = await put(0, "drooling_dude", 2)
	ok(g.can_hero_power(0), "Жвачка: the ability is available")
	await g.cmd_hero_power(0)
	ok(c.damage == 1 and g.atk_of(0, 2) == 4, "Жвачка: 1 damage and +1 ATK")
	ok(not g.can_hero_power(0), "Жвачка: once per turn")


func t_hero_lsp() -> void:
	g.players[0].hero_card = "lsp"
	await put(0, "evil_eye", 0)
	var n: int = g.players[0].hand.size()
	await put(0, "phyllis", 0)
	ok(g.players[0].hand.size() == n + 1, "Пупырка: the first replacement draws a card")
	await put(0, "cow", 0)
	ok(g.players[0].hand.size() == n + 1, "Пупырка: only the first one")


func t_hero_bmo() -> void:
	g.players[0].hero_card = "bmo"
	hand(0, "cow")
	var t = await put(1, "drooling_dude", 0)
	await g.cmd_hero_power(0)
	ok(t.damage == 1 and g.players[0].hand.is_empty(), "Бимо: discard a card, deal 1 damage")


func t_hero_rainicorn() -> void:
	g.players[0].hero_card = "rainicorn"
	g.players[0].hp = 20
	await put(0, "evil_eye", 0)
	await put(0, "cow", 1)
	await g.bounce_creature(0, 0)
	ok(g.players[0].hp == 20, "Ливнерог: one creature back is not enough")
	await g.bounce_creature(0, 1)
	ok(g.players[0].hp == 22, "Ливнерог: two creatures back give +2 HP")


func t_hero_ice_king() -> void:
	g.players[0].hero_card = "ice_king"
	await put(0, "evil_eye", 0)
	await put(0, "cow", 1)
	await g.cmd_attack(0, 0)
	ok(g.players[1].hp == 23, "Снежный король: the first attack on an empty lane gets +1 ATK")
	await g.cmd_attack(0, 1)
	ok(g.players[1].hp == 22, "Снежный король: only the first one")


func t_hero_marceline() -> void:
	g.players[0].hero_card = "marceline"
	var c = await put(0, "drooling_dude", 0)
	c.damage = 5
	ok(g.atk_of(0, 0) == 4, "Марселин: 5 damage gives +1 ATK")
	c.damage = 4
	ok(g.atk_of(0, 0) == 3, "Марселин: 4 damage gives nothing")


func t_hero_lemongrab() -> void:
	g.players[0].hero_card = "lemongrab"
	g.players[0].hp = 20
	await g.cmd_begin_attack(0)
	ok(g.players[0].hp == 21, "Лимонохват: an empty land at the fight phase gives +1 HP")


func t_hero_gunter() -> void:
	g.players[0].hero_card = "gunter"
	await put(0, "evil_eye", 2)
	await g.freeze(0, 2)
	ok(g.atk_of(0, 2) == 2, "Гантер: +1 ATK on a frozen land")


func t_hero_fionna() -> void:
	g.players[0].hero_card = "fionna"
	await put(0, "evil_eye", 0)
	ok(g.atk_of(0, 0) == 2, "Фионна: one land type gives Rainbow creatures +1 ATK")
	g.players[0].lands[3]["type"] = "corn"
	ok(g.atk_of(0, 0) == 1, "Фионна: two land types give nothing")


func t_hero_cake() -> void:
	g.players[0].hero_card = "cake"
	var c = await put(0, "drooling_dude", 1)
	c.damage = 3
	await build(0, "blood_fortress", 1)
	ok(c.damage == 1, "Кейк: a new building heals 2 from the creature on its land")
	var d = await put(0, "phyllis", 3)
	d.damage = 3
	c.damage = 3
	await build(0, "celestial_castle", 0)
	ok(c.damage == 1 and d.damage == 3, "Кейк: every creature in a lane with a building heals, others not")


func t_hero_tree_trunks() -> void:
	g.players[0].hero_card = "tree_trunks"
	hand(0, "cow")
	ok(not g.can_hero_power(0), "Тётушка Древесная: needs a pie card")
	hand(0, "pied_piper")
	ok(not g.can_hero_power(0), "Тётушка Древесная: Крысолов (Pied Piper) is no pie")
	hand(0, "pieclops")
	await g.cmd_hero_power(0)
	ok(g.players[0].actions == 3 and g.players[0].hand.size() == 2, "Тётушка Древесная: discard a pie, gain 1 action")
	hand(0, "piestorm")
	ok(not g.can_hero_power(0), "Тётушка Древесная: once per turn")


func t_hero_lich() -> void:
	g.players[0].hero_card = "lich"
	hand(1, "cow")
	ok(not g.can_hero_power(0), "Лич: no power without more cards in hand")
	hand(0, "cow")
	hand(0, "cow")
	g.players[0].hp = 20
	var hp1: int = g.players[1].hp
	await g.cmd_hero_power(0)
	ok(g.players[1].hp == hp1 - 1 and g.players[0].hp == 21, "Лич: 1 damage to the opponent, 1 HP back")
	ok(not g.can_hero_power(0), "Лич: once a turn")


func t_hero_monica() -> void:
	g.players[0].hero_card = "monica"
	var c = await put(0, "evil_eye", 0)
	c.exhausted = true
	c.flooped = true
	await g.cmd_hero_power(0)
	ok(not c.exhausted and not c.flooped, "Моникер: a flooped creature is ready again")


func t_hero_grand_prix() -> void:
	g.players[0].hero_card = "grand_prix"
	var old = await put(0, "evil_eye", 1)
	ok(not g.can_hero_power(0), "Гран-при: nothing played this turn, no power")
	var c = hand(0, "drooling_dude")
	g.players[0].actions = 5
	await g.cmd_play(0, c.uid, 0)
	var acts: int = g.players[0].actions
	bot.answers = [{"p": 0, "lane": 0}, {"p": 0, "lane": 3, "row": "creature"}]
	await g.cmd_hero_power(0)
	ok(g.players[0].creatures[0] == null and g.players[0].creatures[3] == c and c.damage == 3,
		"Гран-при: the creature played this turn comes again into another lane with 3 damage")
	ok(g.players[0].actions == acts and g.players[0].creatures[1] == old, "Гран-при: free, and only that creature")
	ok(not g.can_hero_power(0), "Гран-при: once a turn")
	# Every hero card with a power has the label of its button, or a person has no way to use it.
	for id: String in CardDB.hero_card_ids():
		if g._hooks.has("hero_power_" + id):
			ok(String(CardDB.hero_card(id).get("power", "")) != "", "hero card %s: its power has a button label" % id)


func t_hero_jake_2x2() -> void:
	g.players[0].hero_card = "jake_2x2"
	await put(0, "evil_eye", 0)
	var t = await put(1, "drooling_dude", 1)
	bot.answers = [{"p": 1, "lane": 1}]
	await g.cmd_attack(0, 0)
	ok(g.players[1].hp == 24 and t.damage == 1, "Джейк (Парный турнир): hitting the opponent gives 1 damage to a creature")


func t_hero_charlie() -> void:
	g.players[0].hero_card = "charlie"
	var c = await put(0, "evil_eye", 1)
	bot.answers = [{"p": 0, "lane": 1}, {"p": 0, "lane": 2, "row": "creature"}]
	await g.cmd_hero_power(0)
	ok(g.players[0].creatures[2] == c and not g.can_hero_power(0), "Чарли: moves a creature next door, once per turn")


func t_hero_ricardio() -> void:
	g.players[0].hero_card = "ricardio"
	var top = g.players[0].deck.back()
	await g.cmd_hero_power(0)
	ok(g.players[0].hp == 24 and g.players[0].discard.has(top), "Рикардио: -1 HP, the top card may be discarded")


func t_hero_prismo() -> void:
	g.players[0].hero_card = "prismo_classic"
	await put(0, "evil_eye", 0)
	ok(g.def_of(0, 0) == 5, "Призмо: four Blue Plains give nothing")
	for l in 4:
		g.players[0].lands[l]["type"] = ["plain", "corn", "cute", "swamp"][l]
	ok(g.def_of(0, 0) == 6, "Призмо: all lands different give +1 DEF")


func t_hero_susan() -> void:
	g.players[0].hero_card = "susan_strong"
	await put(0, "drooling_dude", 0)
	var a = await put(1, "evil_eye", 1)
	var b = await put(1, "phyllis", 2)
	await g.cmd_hero_power(0)
	ok(g.players[0].creatures[0] == null and a.damage == 2 and b.damage == 2 and g.players[0].actions == 1,
		"Сьюзан: -1 action, destroy a cost-2 creature, 2 damage to each enemy")


func t_hero_cosmic_owl() -> void:
	g.players[0].hero_card = "cosmic_owl"
	var deck: Array = g.players[0].deck
	var top := [deck[-1], deck[-2], deck[-3], deck[-4]]
	bot.answers = [top[3].uid, top[2].uid, top[1].uid]
	await g.cmd_hero_power(0)
	ok(deck[-1] == top[3] and deck[-2] == top[2] and deck[-3] == top[1] and deck[-4] == top[0],
		"Космическая Сова: the top four cards are reordered")


func t_hero_huntress() -> void:
	g.players[0].hero_card = "huntress_wizard"
	await g._hero_event(0, "setup")
	ok(String(g.players[0].hero_state.get("word", "")).length() >= 3, "Охотница-волшебница: a word is chosen")
	g.players[0].hero_state["word"] = "одноглазое"
	var t = await put(1, "drooling_dude", 2)
	var c = hand(0, "evil_eye")
	await g.cmd_play(0, c.uid, 0)
	ok(t.damage == 1, "Охотница-волшебница: a card with the word gives 1 damage")


func t_hero_magic_man() -> void:
	g.players[0].hero_card = "magic_man_classic"
	var t = await put(1, "phyllis", 0)
	var c = hand(0, "drooling_dude")
	await g.cmd_play(0, c.uid, 1)
	ok(t.damage == 2, "Волшебник: a cost-2 card gives 2 damage")


func t_hero_abracadaniel() -> void:
	g.players[0].hero_card = "abracadaniel"
	var c = mk("evil_eye", 0)
	g.players[0].deck.append(c)
	await g.cmd_hero_power(0)
	ok(g.where(c.uid)["zone"] == "creature" and g.players[0].actions == 1, "Абракадэниел: a Rainbow card on top is played")
	var d = mk("cool_dog", 0)
	g.players[0].deck.append(d)
	await g.cmd_hero_power(0)
	ok(g.players[0].deck.back() == d, "Абракадэниел: other cards stay on top")


## A building takes its cost in actions. Only a printed 0 (Фонтан милашности of Тётушка Древесная,
## Аванпост попугаев…), an improved card or a train item makes it free.
func t_undo() -> void:
	g.journal = []
	g.players[0].hero_card = "finn"
	var foe = await put(1, "drooling_dude", 0)
	var c = hand(0, "evil_eye")
	var acts: int = g.players[0].actions
	var h: int = g.state_hash()
	var point: Dictionary = g.undo_point(0)
	await g.run_command(0, {"cmd": "play", "uid": c.uid, "lane": 1})
	ok(g.players[0].creatures[1] == c and g.undo_clean(point), "Отмена: playing a creature can be taken back")
	g.undo_to(point)
	ok(g.players[0].creatures[1] == null and g.players[0].hand.has(c) and g.players[0].actions == acts
		and g.state_hash() == h and g.journal.is_empty(), "Отмена: the state and the journal are as before")
	await g.run_command(0, {"cmd": "play", "uid": c.uid, "lane": 1})
	point = g.undo_point(0)
	bot.answers = [{"p": 1, "lane": 0}]
	await g.run_command(0, {"cmd": "floop", "kind": "creature", "lane": 1})
	ok(foe.damage == 1 and g.undo_clean(point), "Отмена: Финн's floop can be taken back")
	g.undo_to(point)
	ok(foe.damage == 0 and not c.exhausted, "Отмена: the damage and the floop are gone")
	point = g.undo_point(0)
	await g.run_command(0, {"cmd": "draw"})
	ok(not g.undo_clean(point), "Отмена: a drawn card can't be taken back")


func t_building_cost() -> void:
	var school = hand(0, "schoolhouse")
	g.players[0].actions = 0
	ok(not g.can_play(0, school.uid, 0), "Строение за 1: без действий не сыграть")
	g.players[0].actions = 1
	ok(g.can_play(0, school.uid, 0), "Строение за 1: с одним действием можно")
	await g.cmd_play(0, school.uid, 0)
	ok(g.players[0].actions == 0 and g.players[0].buildings[0] == school, "Строение за 1: платит действие")
	var outpost = hand(0, "parrotmilitary_outpost")
	ok(g.can_play(0, outpost.uid, 1) and g.cost_of(0, outpost) == 0, "Аванпост попугаев: напечатан 0, бесплатно по карте")
	var school_2 = hand(0, "schoolhouse")
	ok(not g.can_play(0, school_2.uid, 1), "Вторая Школа без действий: нельзя")
	g.train.set_stats(0, {"building_cheap": 1})
	ok(g.can_play(0, school_2.uid, 1), "Предмет «строения дешевле»: Школа бесплатна")
