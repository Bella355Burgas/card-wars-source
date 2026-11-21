extends SceneTree
## «Без героя»: a pick "deck@" plays the deck with no hero card, in every game but the train
## and the ranked games. The code, the engine, the AI on both sides, the replay of such a game
## and the online room's check of the picks.
##   godot --headless --path . -s res://tests/no_hero_test.gd

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const Replay = preload("res://scripts/core/replay.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")
const Lobby = preload("res://scripts/ui/main/lobby.gd")

var failures := 0
var checks := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	ok(CardDB.valid_loadout("finn@") and CardDB.is_no_hero("finn@"), "«finn@» is a pick without a hero")
	ok(not CardDB.is_no_hero("finn") and not CardDB.is_no_hero("finn@bmo"), "the others have heroes")
	ok(not CardDB.valid_loadout("nothing@") and not CardDB.valid_loadout("finn@nothing"), "unknown decks and cards still fail")
	ok(CardDB.no_hero("jake@bmo") == "jake@" and CardDB.with_hero("jake@") == "jake" and CardDB.with_hero("jake@", "bmo") == "jake@bmo", "the switch both ways")
	ok(CardDB.pick_of("finn", CardDB.NO_HERO) == "finn@" and CardDB.pick_of("finn", "bmo") == "finn@bmo", "pick of a deck and a card")
	ok(CardDB.hero_card(CardDB.NO_HERO)["name"] == "Без героя" and ResourceLoader.exists(CardDB.hero_thumb(CardDB.NO_HERO)), "what the screens show")
	# The engine: no hero card, no hero ability, the deck's name.
	var g = Game.new()
	g.setup(["finn@", "jake@bmo"], 0, 3)
	ok(g.players[0].hero_card == "" and g.players[0].name == "Финн", "seat 0 without a hero, named by its deck")
	ok(g.players[1].hero_card == "bmo", "seat 1 with Бимо")
	await g.start_game()
	ok(not g.can_hero_power(0) and not g.legal_commands(0).any(func(c): return c["cmd"] == "hero"), "no hero command")

	# The AI plays without a hero and against one; the replay keeps «finn@».
	for pair in [["finn@", "jake"], ["marceline", "lich@"], ["bmo@", "pb@"]]:
		await _ai_game(pair)
	# 2 на 2 and на троих.
	await _ai_game(["finn@", "jake", "bmo@", "marceline"])
	await _ai_game(["finn", "jake@", "bmo@"])

	# Online: the room takes such picks; the train does not offer them.
	var lobby = Lobby.new(null)
	ok(lobby._start_ok({"seed": 5, "first": 0, "heroes": ["finn@", "jake@bmo"]}, 2), "an online start takes picks without a hero")
	ok(lobby._start_ok({"seed": 5, "first": 1, "heroes": ["finn@", "jake", "bmo@", "lich@"]}, 4), "and at four seats")
	ok(not lobby._start_ok({"seed": 5, "first": 0, "heroes": ["finn@nothing", "jake"]}, 2), "a broken pick still fails")
	print("no hero tests: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _ai_game(pair: Array) -> void:
	var g = Game.new()
	g.setup(pair, 0, 17)
	g.chooser = RandomAgent.new(7)       # the choices are recorded as a table records them
	g.journal = []
	var agents := []
	for p in pair.size():
		agents.append(AILevels.agent(AILevels.DEFAULT, pair[p]))
	await g.start_game()
	var steps := 0
	while g.phase != "over" and steps < 3000:
		steps += 1
		if g.phase == "handoff":
			await g.cmd_start_turn()
			continue
		var p: int = g.turn_player
		var agent = agents[p]
		var cmd: Dictionary = await agent.pick_command_async(g, p) if agent.has_method("pick_command_async") else agent.pick_command(g, p)
		var before: int = g.state_hash()
		await g.run_command(p, cmd)
		if g.state_hash() == before and g.turn_player == p and g.phase != "over":
			if agent.has_method("ban_command"):
				agent.ban_command(before, cmd)
			await g.run_command(p, {"cmd": "end_turn"})
	ok(g.phase == "over", "%s: the AI finishes the game (%d steps)" % [pair, steps])
	var data := Replay.from_game(g, "ai", 0, "test")
	ok(data["heroes"] == pair, "%s: the replay keeps the picks %s" % [pair, data["heroes"]])
	var back := Replay.parse(JSON.stringify(data))
	ok(not back.is_empty(), "%s: the replay parses" % [pair])
	if not back.is_empty():
		var err: String = await Replay.verify(back)
		ok(err == "", "%s: the replay plays back %s" % [pair, err])
