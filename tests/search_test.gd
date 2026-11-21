extends SceneTree
## Checks the AI search (scripts/ai/search.gd) on random positions:
##   godot --headless --path . -s res://tests/search_test.gd -- [positions] [seed]
## 1. Nothing hidden is used: a copy of the position in which the opponent's hand and
##    deck cards are moved around (and the engine rng differs) gets the same command
##    from the search with the same seed.
## 2. The command is one of the real game's legal commands, and the search leaves the
##    real game exactly as it was.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const PolicyAgent = preload("res://scripts/ai/policy_agent.gd")
const Search = preload("res://scripts/ai/search.gd")


## Answers choices from its own rng, so two chooser copies seeded alike answer alike.
class Det extends RefCounted:
	var rng := RandomNumberGenerator.new()

	func choose(req: Dictionary):
		var options: Array = req.get("options", [])
		if options.is_empty():
			return null
		if req.get("optional", false) and rng.randf() < 0.3:
			return null
		return options[rng.randi() % options.size()]


var failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var positions := int(args[0]) if args.size() > 0 else 12
	var base_seed := int(args[1]) if args.size() > 1 else 1
	var agent = PolicyAgent.new("res://data/ai_policy.json", 0.0)
	if agent.model == null or not agent.model.has_value:
		printerr("no model with a value head")
		quit(2)
		return
	var search = Search.new(agent, {"samples": 2, "width": [4, 2, 2], "time_ms": 0, "yield": false})
	var heroes: Array = CardDB.hero_ids()
	var hero_cards: Array = CardDB.hero_card_ids()
	var checked := 0
	var same := 0
	var t0 := Time.get_ticks_msec()
	for trial in positions:
		var seed_value := base_seed + trial
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var pair := []
		for i in 2:
			var deck: String = heroes[rng.randi() % heroes.size()]
			var card: String = hero_cards[rng.randi() % hero_cards.size()] if rng.randf() < 0.5 else deck
			pair.append(CardDB.loadout(deck, card))
		var game := Game.new()
		game.fast_mode = true
		var ch := Det.new()
		game.chooser = ch
		game.setup(pair, seed_value % 2, seed_value)
		await game.start_game()
		var steps := 0
		var tests := 0
		while game.phase != "over" and steps < 400 and tests < 3:
			if game.phase == "handoff":
				await game.cmd_start_turn()
				continue
			var p: int = game.turn_player
			var cmds: Array = game.legal_commands(p)
			if p == 0 and game.phase == "main" and game.turn_number >= 2 and cmds.size() > 1 and steps % 7 == 0:
				tests += 1
				checked += 1
				# The twin: the opponent's hand and deck shuffled, another engine rng.
				var twin = game.clone()
				twin.rng.seed = seed_value * 31 + steps
				var oh: Array = twin.players[1].hand
				var od: Array = twin.players[1].deck
				if not oh.is_empty() and not od.is_empty():
					var x = oh[0]
					oh[0] = od[0]
					od[0] = x
				twin.reshuffle(1)
				var before: int = game.state_hash()
				var a: Dictionary = await search.pick(game, p, seed_value + steps)
				var b: Dictionary = await search.pick(twin, p, seed_value + steps)
				if game.state_hash() != before:
					_fail(seed_value, "the search changed the game")
				if not cmds.has(a):
					_fail(seed_value, "the search chose an illegal command %s" % a)
				if a == b:
					same += 1
				else:
					_fail(seed_value, "the choice depends on hidden cards: %s vs %s" % [a, b])
			var cmd: Dictionary = cmds[rng.randi() % cmds.size()] if not cmds.is_empty() else {"cmd": "end_turn"}
			ch.rng.seed = rng.randi()
			await game.run_command(p, cmd)
			steps += 1
	print("positions=%d  checked=%d  same=%d  failures=%d  time=%.1fs" % [positions, checked, same, failures,
		(Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failures > 0 else 0)


func _fail(seed_value: int, msg: String) -> void:
	failures += 1
	if failures <= 25:
		printerr("seed %d: %s" % [seed_value, msg])
