extends SceneTree
## На троих rules, headless:
##   godot --headless --path . -s res://tests/three_rules_test.gd
## Seats 0, 1, 2 each for itself, 25 HP each; lanes 0 and 1 face the next seat's lanes 3 and 2,
## lanes 2 and 3 the seat before's 1 and 0. The first player at 0 HP drops out: their cards go,
## the other two play on lane against lane.

const Game = preload("res://scripts/core/game.gd")
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
	var tests := ["t_setup", "t_first_turns", "t_attack_across", "t_pick_foe", "t_drop_out", "t_drop_out_own_turn",
		"t_drop_out_lanes", "t_win", "t_ai_view", "t_concede"]
	for t in tests:
		_fresh()
		await call(t)
	print("three rules tests: %d checks failed" % failures)
	quit(1 if failures > 0 else 0)


func _fresh() -> void:
	g = Game.new()
	bot = Scripted.new()
	g.chooser = bot
	g.setup(["finn", "jake", "bmo"], 0, 7)
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
	ok(g.three() and not g.teams() and not g.duel(), "three picks: a game на троих")
	ok(g.players.all(func(ps): return ps.hp == 25 and ps.max_hp == 25), "25 HP each")
	ok(g.foes(0) == [1, 2] and g.foes(1) == [2, 0], "both others are foes")
	ok(g.is_foe(0, 2) and g.is_foe(1, 2), "seats 0 and 2 are not a team")
	ok(g.across(0, 0) == [1, 3] and g.across(0, 1) == [1, 2], "lanes 0-1 face the next seat's 3-2")
	ok(g.across(0, 2) == [2, 1] and g.across(0, 3) == [2, 0], "lanes 2-3 face the seat before's 1-0")
	ok(g.total_lands() == 12, "12 lands")


func t_first_turns() -> void:
	g.turn_number = 1
	ok(g.is_first_turn(), "turn 1: no fights")
	g.turn_number = 2
	ok(g.is_first_turn(), "turn 2: no fights")
	g.turn_number = 3
	ok(not g.is_first_turn(), "turn 3: the third player may fight")


func t_attack_across() -> void:
	var a = await put(0, "evil_eye", 0)
	g.phase = "attack"
	await g.cmd_attack(0, 0)
	ok(g.players[1].hp < 25 and g.players[2].hp == 25, "lane 0 hits the next seat")
	var hp1: int = g.players[1].hp
	a.exhausted = false
	await g.move_creature(0, 0, 3)
	g.players[0].creatures[3].exhausted = false
	await g.cmd_attack(0, 3)
	ok(g.players[2].hp < 25 and g.players[1].hp == hp1, "lane 3 hits the seat before")


func t_pick_foe() -> void:
	# Суровая лесорубка: "N damage to the opponent", на троих the player picks which one.
	bot.answers = [func(req): return req["options"][1]]
	var o: int = await g.foe_to_hit(0, "кому?")
	ok(o == 2 and bot.asked.size() == 1, "foe_to_hit asks and gives the picked seat")


func t_drop_out() -> void:
	await put(1, "evil_eye", 0)
	var c2 = await put(2, "evil_eye", 1)
	g.players[1].hp = 3
	g.players[0].hp = 10
	await g.damage_player(1, 5)
	ok(g.phase != "over", "two left: the game goes on")
	ok(g.is_out(1) and g.duel(), "seat 1 is out")
	ok(g.players[1].creatures.all(func(c): return c == null), "its creatures leave the table")
	ok(g.players[1].discard.size() >= 1, "into the discard pile")
	ok(g.players[2].creatures[1] == c2, "the others' cards stay")
	ok(g.foes(0) == [2] and g.foes(2) == [0], "one foe each")
	ok(g.next_seat(0) == 2 and g.next_seat(2) == 0, "turns skip seat 1")
	ok(g.sides() == [0, 2], "sides without seat 1")
	ok(g.across(0, 3) == [2, 0] and g.across(2, 0) == [0, 3], "the lanes that faced each other still do")
	ok(g.across(0, 0) == [2, 3] and g.across(2, 3) == [0, 0], "the lanes that faced seat 1 face the other one, mirrored")
	var all_pairs := true
	for s in [0, 2]:
		for lane in 4:
			var a: Array = g.across(s, lane)
			all_pairs = all_pairs and g.across(a[0], a[1]) == [s, lane]
	ok(all_pairs, "every lane faces back the one facing it")
	ok(g.turn_player == 0 and g.phase == "main", "the turn goes on")


func t_drop_out_own_turn() -> void:
	g.journal = []
	g.players[0].hp = 1
	g.turn_number = 7
	g._calls = 1      # as inside a command
	await g.lose_hp(0, 1, "тест")
	ok(g.is_out(0) and g.phase == "over", "inside the call the turn stops")
	await g._end_call()      # what the outermost call does at its end
	ok(g.turn_player == 1 and g.phase == "handoff" and g.turn_number == 8, "then the next seat gets the turn")
	_fresh()
	# Through real commands: burn tokens at the start of the turn.
	g.players[1].hp = 1
	g.players[1].burn = 1
	await g.cmd_end_turn(0)
	await g.cmd_start_turn()
	ok(g.is_out(1), "seat 1 burns down at the start of its turn")
	ok(g.turn_player == 2 and g.phase == "handoff", "and the turn passes to seat 2")
	await g.cmd_start_turn()
	ok(g.turn_player == 2 and g.phase == "main", "seat 2 plays")


func t_drop_out_lanes() -> void:
	# After the drop out a creature of seat 0 on lane 2 still faces seat 2's lane 1 (bug report:
	# the creatures that fought each other got new foes), its lane 1 (it faced seat 1) faces lane 2.
	var x = await put(2, "evil_eye", 1)
	var y = await put(2, "evil_eye", 2)
	ok(g.foe_creature(0, 2) == x, "before: lane 2 of seat 0 faces lane 1 of seat 2")
	g.players[1].hp = 1
	await g.damage_player(1, 1)
	ok(g.foe_creature(0, 2) == x and g.facing(2, 1, 0, 2), "after: still the same foe")
	ok(g.foe_creature(0, 1) == y, "lane 1 of seat 0 now faces lane 2 of seat 2")


func t_win() -> void:
	g.players[1].hp = 1
	await g.damage_player(1, 1)
	g.players[2].hp = 2
	await g.damage_player(2, 5)
	ok(g.phase == "over" and g.winner == 0, "the last one standing wins")
	_fresh()
	g.players[1].hp = 1
	g.players[2].hp = 1
	await g.damage_player(1, 1)
	ok(g.is_out(1) and g.phase != "over", "first one down drops out")
	await g.damage_player(2, 3)
	ok(g.phase == "over" and g.winner == 0, "the second one down ends the game")
	_fresh()
	g.players[1].hp = 0
	g.players[2].hp = 0
	await g._check_win()
	ok(g.phase == "over" and g.winner == 0, "two down at once: the third wins")


func t_ai_view() -> void:
	var v: Dictionary = AIView.state_view(g, 0)
	ok(v["hp"] == [25, 25], "HP as in a game for two (not scaled like 2 на 2)")
	g.players[1].hp = 1
	await g.damage_player(1, 1)
	await put(2, "evil_eye", 0)
	v = AIView.state_view(g, 0)
	ok(v["hp"][1] == g.players[2].hp, "after the drop out the view's opponent is the one left")


func t_concede() -> void:
	await g.run_command(1, {"cmd": "concede"})
	ok(not g.is_out(1), "not in someone else's turn")
	await g.run_command(0, {"cmd": "concede"})
	ok(g.is_out(0) and g.turn_player == 1 and g.phase == "handoff", "in own turn: drops out, the turn goes on")
	await g.cmd_start_turn()
	await g.run_command(1, {"cmd": "concede"})
	ok(g.phase == "over" and g.winner == 2, "the second to give up leaves the third the winner")
