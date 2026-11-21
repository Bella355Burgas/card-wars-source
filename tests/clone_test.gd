extends SceneTree
## Checks Game.clone() (scripts/core/game.gd):
##   godot --headless --path . -s res://tests/clone_test.gd -- [games] [seed]
## Plays random games. Now and then the game is copied: the copy must hash the same,
## both sides then run the same command with the same answers to their choices, and
## the hashes must agree after it. Running the copy must not change the game.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")

var failures := 0


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


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 40
	var base_seed := int(args[1]) if args.size() > 1 else 1
	var heroes: Array = CardDB.hero_ids()
	var hero_cards: Array = CardDB.hero_card_ids()
	var copies := 0
	var checks := 0
	var t0 := Time.get_ticks_msec()
	for gi in games:
		var seed_value := base_seed + gi
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var pair := []
		for i in 2:
			var deck: String = heroes[rng.randi() % heroes.size()]
			var card: String = hero_cards[rng.randi() % hero_cards.size()] if rng.randf() < 0.5 else deck
			pair.append(CardDB.loadout(deck, card))
		var game := Game.new()
		# Copies run fast (no handoff between turns); compare like with like.
		game.fast_mode = true
		var ch := Det.new()
		game.chooser = ch
		game.setup(pair, seed_value % 2, seed_value)
		# «Бесконечный поезд»: some games have improved cards, some a second enemy to come.
		if gi % 3 == 0:
			for c in game.all_cards(0) + game.all_cards(1):
				c.upgraded = rng.randf() < 0.3
		if gi % 4 == 0:
			game.train.set_follow(heroes[rng.randi() % heroes.size()], 6 + rng.randi() % 6, {})
		await game.start_game()
		var steps := 0
		while game.phase != "over" and steps < 3000:
			if game.phase == "handoff":
				await game.cmd_start_turn()
				continue
			var p: int = game.turn_player
			var cmds: Array = game.legal_commands(p)
			if cmds.is_empty():
				_fail(seed_value, "no legal commands in phase %s" % game.phase)
				break
			var cmd: Dictionary = cmds[rng.randi() % cmds.size()]
			var answers := rng.randi()
			if rng.randf() < 0.2:
				copies += 1
				var before: int = game.state_hash()
				var copy = game.clone()
				checks += 1
				if copy.state_hash() != before:
					_fail(seed_value, "copy hashes differently at step %d" % steps)
				var cc := Det.new()
				copy.chooser = cc
				cc.rng.seed = answers
				await copy.run_command(p, cmd)
				checks += 1
				if game.state_hash() != before:
					_fail(seed_value, "running the copy changed the game at step %d" % steps)
				ch.rng.seed = answers
				await game.run_command(p, cmd)
				checks += 1
				if copy.state_hash() != game.state_hash():
					_fail(seed_value, "copy and game diverged at step %d (%s)" % [steps, cmd])
				if copy.rng.state != game.rng.state or copy.fast_mode != true or copy.journal != null:
					_fail(seed_value, "copy state differs at step %d" % steps)
			else:
				ch.rng.seed = answers
				await game.run_command(p, cmd)
			steps += 1
		if game.phase != "over":
			_fail(seed_value, "game did not finish (turn %d)" % game.turn_number)
	print("games=%d  copies=%d  checks=%d  failures=%d  time=%.1fs" % [games, copies, checks, failures,
		(Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failures > 0 else 0)


func _fail(seed_value: int, msg: String) -> void:
	failures += 1
	if failures <= 25:
		printerr("seed %d: %s" % [seed_value, msg])
