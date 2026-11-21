extends SceneTree
## 2 на 2 rules from the Doubles Tournament rulebook, headless:
##   godot --headless --path . -s res://tests/teams_rules_test.gd
## Seats 0 and 2 are a team against 1 and 3; turns go 0, 1, 2, 3. Lanes 0 and 1 of a
## seat face the next seat's lanes 3 and 2, lanes 2 and 3 the seat before's 1 and 0.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const AIView = preload("res://scripts/ai/ai_view.gd")


class Scripted:
	var answers: Array = []
	var asked: Array = []
	func choose(req: Dictionary):
		asked.append(req)
		if not answers.is_empty():
			var a = answers.pop_front()
			return a.call(req) if a is Callable else a
		return req["options"][0]


var failures := 0
var g
var bot: Scripted


func _initialize() -> void:
	var tests := ["t_setup", "t_turn_order", "t_rule_of_three", "t_attack_across", "t_attack_empty", "t_team_win",
		"t_spirit_tower", "t_pick_foe", "t_hit_foes", "t_each_player", "t_pyramid_across", "t_frost_tokens",
		"t_ai_view", "t_adjacent_middle", "t_knit_kitty"]
	for t in tests:
		_fresh()
		await call(t)
	print("teams rules tests: %d checks failed" % failures)
	quit(1 if failures > 0 else 0)


func _fresh() -> void:
	g = Game.new()
	bot = Scripted.new()
	g.chooser = bot
	g.setup(["finn", "jake", "bmo", "marceline"], 0, 7)
	for ps in g.players:
		ps.hero_card = ""
		ps.deck.append_array(ps.hand)
		ps.hand.clear()
	g.turn_number = 5
	g.turn_player = 0
	g.phase = "main"
	g.players[0].actions = 2


func ok(cond: bool, what: String) -> void:
	if cond:
		print("ok   ", what)
	else:
		failures += 1
		printerr("FAIL ", what)


func mk(id: String, owner := 0):
	return g._make_card(id, owner)


func put(p: int, id: String, lane: int):
	var c = mk(id, p)
	await g._put_creature(p, c, lane)
	return c


func hand(p: int, id: String):
	var c = mk(id, p)
	g.players[p].hand.append(c)
	return c


# ---------------------------------------------------------------- tests

func t_setup() -> void:
	var fresh := Game.new()
	fresh.setup(["finn", "jake", "finn", "jake"], 2, 3)
	ok(fresh.players.size() == 4 and fresh.teams(), "four picks make four seats")
	ok(fresh.players.all(func(ps): return ps.hp == 40 and ps.max_hp == 40), "a team starts with 40 hit points (the maximum)")
	ok(fresh.players.all(func(ps): return ps.hand.size() == 5), "every player draws five")
	var names := {}
	for ps in fresh.players:
		names[ps.name] = true
	ok(names.size() == 4, "the same deck twice gets two names")
	ok(fresh.foes(0) == [1, 3] and fresh.foes(1) == [2, 0], "the opponents sit left and right")
	ok(fresh.across(0, 0) == [1, 3] and fresh.across(0, 1) == [1, 2] and fresh.across(0, 2) == [3, 1] \
		and fresh.across(0, 3) == [3, 0], "two landscapes face each opponent")


func t_turn_order() -> void:
	g.turn_number = 1
	var order := [0]
	for i in 4:
		await g._end_turn(g.turn_player)
		await g._start_turn(g.turn_player)
		order.append(g.turn_player)
	ok(order == [0, 1, 2, 3, 0], "turns go round the table, the teams take turns: %s" % [order])


func t_rule_of_three() -> void:
	g.phase = "main"
	for t in [1, 2, 3]:
		g.turn_number = t
		g.turn_player = (t - 1) % 4
		var p: int = g.turn_player
		await put(p, "evil_eye", 0)
		ok(not g.can_attack(p, 0), "the %d. player can't fight in their first turn" % t)
		g.players[p].creatures[0] = null
	g.turn_number = 4
	g.turn_player = 3
	var c = await put(3, "evil_eye", 0)
	c.exhausted = false
	ok(g.can_attack(3, 0), "the fourth player fights in their first turn")


func t_attack_across() -> void:
	var a = await put(0, "evil_eye", 1)
	var d = await put(1, "evil_eye", 2)
	var other = await put(1, "evil_eye", 1)
	await g.cmd_attack(0, 1)
	ok(d.damage == 1 and a.damage == 1, "the fight is with the creature across the lane")
	ok(other.damage == 0, "the same lane number of the opponent is another lane")


func t_attack_empty() -> void:
	await put(0, "evil_eye", 3)
	await g.cmd_attack(0, 3)
	ok(g.players[3].hp == 39 and g.players[1].hp == 39, "an empty lane: the damage goes to the opposing team")
	ok(g.players[0].hp == 40 and g.players[2].hp == 40, "…not to the attacker's team")


func t_team_win() -> void:
	g.players[1].hp = 1
	await put(0, "evil_eye", 0)
	await g.cmd_attack(0, 0)
	ok(g.phase == "over" and g.winner == 0, "a team with no hit points left loses (winner = team 0)")
	ok(g.side_name(g.winner).contains(g.players[2].name), "the winners are both players of the team")


func t_spirit_tower() -> void:
	g.players[0].lands[0]["type"] = "swamp"
	g.players[0].lands[1]["type"] = "swamp"
	var t = mk("spirit_tower", 0)
	await g._put_building(0, t, 0)
	var foe = await put(1, "evil_eye", 3)
	foe.exhausted = true
	ok(g.can_floop(0, "building", 0), "Башня духа sees the creature across the lane")
	await g.cmd_floop(0, "building", 0)
	ok(g.players[0].creatures[0] == foe, "it takes the opposite creature")
	await g._end_turn_cleanup(0)
	ok(g.players[1].creatures[3] == foe, "it goes home to its own lane at the end of the turn")


func t_pick_foe() -> void:
	await put(0, "dark_angel", 0)     # Костяная палочка needs a swamp creature
	hand(1, "evil_eye")
	hand(3, "evil_eye")
	var c = hand(0, "bone_wand")
	bot.answers = [g.players[3].name]
	await g.cmd_play(0, c.uid, -1)
	ok(bot.asked.size() >= 1 and bot.asked[0]["kind"] == "option" and bot.asked[0]["options"].size() == 2,
		"a card for «the opponent» asks which one")
	ok(g.players[3].hand.is_empty() and g.players[1].hand.size() == 1, "the chosen opponent discards")


func t_hit_foes() -> void:
	var a = await put(1, "evil_eye", 0)
	var b = await put(3, "evil_eye", 2)
	var mate = await put(2, "evil_eye", 1)
	var c = hand(0, "cerebral_bloodstorm")
	await g.cmd_play(0, c.uid, -1)
	ok(a.damage == 1 and b.damage == 1, "«each opposing creature» is both opponents' creatures")
	ok(mate.damage == 0, "…not the teammate's")


func t_each_player() -> void:
	await put(0, "field_stalker", 0)
	var sizes := []
	for ps in g.players:
		sizes.append(ps.hand.size())
	await g._trigger_own(0, "start_")
	var grew := 0
	for i in 4:
		if g.players[i].hand.size() == sizes[i] + 1:
			grew += 1
	ok(grew == 4, "«each player» draws: all four")


func t_pyramid_across() -> void:
	var c = await put(0, "evil_eye", 2)
	var base: int = g.def_of(0, 2)
	var pyr = mk("celestial_fortress", 3)
	await g._put_building(3, pyr, 1)
	ok(g.def_of(0, 2) == base - 2, "a building works on the lane it is on: across from it")
	var other = mk("celestial_fortress", 1)
	await g._put_building(1, other, 2)
	ok(g.def_of(0, 2) == base - 2, "…and only there")
	ok(c != null, "")


func t_frost_tokens() -> void:
	for side in 4:
		for lane in 2:
			await g.freeze(side, lane)
	ok(g.frozen_count() == 8, "eight frozen lands in a Doubles game")
	await g.freeze(0, 3)
	ok(g.is_frozen(0, 3) and g.frozen_count() == 9, "…and more: no limit on frost tokens")


func t_ai_view() -> void:
	var foe = await put(1, "evil_eye", 2)        # across seat 0's lane 1
	var foe2 = await put(3, "nice_ice_baby", 0)  # across seat 0's lane 3
	await put(2, "evil_eye", 0)                  # the teammate's: not in seat 0's view
	var v := AIView.state_view(g, 0)
	ok(v["cr"][1][1] != null and v["cr"][1][1][0] == foe.id, "the AI sees the creature across its lane 1")
	ok(v["cr"][1][3] != null and v["cr"][1][3][0] == foe2.id, "…and across its lane 3 (the other opponent's)")
	ok(v["cr"][1][0] == null and v["cr"][1][2] == null, "…and nothing across the empty ones")
	ok(v["hp"] == [25, 25], "team hit points are scaled to 25")


func t_adjacent_middle() -> void:
	ok(g.adjacent(1).has(2) and g.adjacent(2).has(1), "the middle two landscapes are adjacent despite the gap")


func t_knit_kitty() -> void:
	# The player's table: the kitty next door to a Бомба из бобов in 2 на 2.
	var b = mk("bean_ball_bomba", 0)
	await g._put_building(0, b, 2)
	var k = await put(0, "knit_kitty", 1)
	k.damage = 6
	ok(g.can_floop(0, "building", 2), "2 на 2: Бомба из бобов видит Вязаного котика в соседней зоне")
	await g.cmd_floop(0, "building", 2)
	ok(k.damage == 4, "2 на 2: с котика снято до 4 урона (got %d)" % k.damage)
