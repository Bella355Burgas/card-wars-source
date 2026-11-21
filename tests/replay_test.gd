extends SceneTree
## Replays must play back to the very same game:
##   godot --headless --path . -s res://tests/replay_test.gd -- [games] [seed]
## Plays random games with random heroes, hero cards (or none) and choices (as sim.gd),
## recording them; each replay goes through JSON, is played again by the engine
## alone and must reach the recorded state at every step and at the end.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")
const Replay = preload("res://scripts/core/replay.gd")

var failures := 0
var jumps := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 200
	var base_seed := int(args[1]) if args.size() > 1 else 1
	var heroes: Array = CardDB.hero_ids()
	var hero_cards: Array = CardDB.hero_card_ids()
	var steps_total := 0
	var picks_total := 0
	var bytes_total := 0
	var t0 := Time.get_ticks_msec()
	for n in games:
		var seed_value := base_seed + n
		var agent := RandomAgent.new(seed_value * 31)
		var pair := []
		for i in 2:
			var deck: String = heroes[agent.rng.randi() % heroes.size()]
			var card: String = hero_cards[agent.rng.randi() % hero_cards.size()] if agent.rng.randf() < 0.5 else deck
			# Some games without a hero ("deck@"): the replay has to keep that too.
			pair.append(CardDB.no_hero(deck) if (n + i * 3) % 5 == 0 else CardDB.loadout(deck, card))
		var game := Game.new()
		game.chooser = agent
		game.setup(pair, seed_value % 2)       # no seed given: the game picks one, as in the real game
		game.journal = []
		for p in 2:
			var types: Array = game.players[p].lands.map(func(l): return l["type"])
			if agent.rng.randf() < 0.5:
				types.reverse()
				await game.cmd_arrange_lands(p, types)
			if agent.rng.randf() < 0.3:
				await game.cmd_mulligan(p)
		await game.start_game()
		var surrender_at := 2 + agent.rng.randi() % 12 if n % 10 == 9 else -1
		var steps := 0
		while game.phase != "over" and steps < 3000:
			if game.turn_number == surrender_at:
				# What the table does when a player gives up online.
				game.journal.append({"t": "over", "w": 1 - game.turn_player})
				game.phase = "over"
				game.winner = 1 - game.turn_player
				break
			if game.phase == "handoff":
				await game.cmd_start_turn()
				continue
			var p: int = game.turn_player
			var cmds: Array = game.legal_commands(p)
			if cmds.is_empty():
				break
			var c: Dictionary = agent.pick_command(cmds)
			if c["cmd"] == "end_turn" and agent.rng.randf() < 0.3:
				await game.cmd_end_turn(p)      # the table ends turns this way after the last attack
			else:
				await game.run_command(p, c)
			steps += 1
		var data := Replay.from_game(game, "hotseat", 0, "test")
		var text := JSON.stringify(data)
		bytes_total += text.length()
		var back := Replay.parse(text)
		if back.is_empty():
			_fail(seed_value, pair, "the replay does not parse")
			continue
		for st in back["steps"]:
			steps_total += 1
			if st["t"] == "pick":
				picks_total += 1
		if back["heroes"] != pair:
			_fail(seed_value, pair, "the replay keeps other picks: %s" % [back["heroes"]])
		var err: String = await Replay.verify(back)
		if err != "":
			_fail(seed_value, pair, err)
		# «Ходы»: every turn is found, and a jump to one gives the game recorded there.
		var marks: Array = await Replay.turn_marks(back)
		if marks.is_empty() or int(marks[-1]["n"]) != mini(game.turn_number, int(marks[-1]["n"])) 				or marks.size() < game.turn_number - 1:
			_fail(seed_value, pair, "turn marks: %d for %d turns" % [marks.size(), game.turn_number])
		elif not marks.is_empty():
			var m: Dictionary = marks[agent.rng.randi() % marks.size()]
			var jumped = await Replay.play_to(back, int(m["pos"]))
			var st: Dictionary = back["steps"][int(m["pos"])]
			if int(st.get("h", jumped.state_hash())) != jumped.state_hash() or String(st["t"]) not in ["start", "turn"]:
				_fail(seed_value, pair, "a jump to turn %d gives another game" % m["n"])
			jumps += 1
	# A replay from another version of the game stops where it stops matching.
	var bad := Replay.parse(JSON.stringify(await _one_game_data()))
	bad["steps"][3]["h"] = 12345
	var err2: String = await Replay.verify(bad)
	if not err2.begins_with("state differs"):
		_fail(0, [], "a broken replay was not noticed: '%s'" % err2)
	print("jumps=%d" % jumps)
	print("games=%d  steps=%d  picks=%d  avg_size=%.1f KB  failures=%d  time=%.1fs" % [games, steps_total,
		picks_total, bytes_total / 1024.0 / maxi(games, 1), failures, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failures > 0 else 0)


func _one_game_data() -> Dictionary:
	var game := Game.new()
	game.chooser = RandomAgent.new(5)
	game.setup(["finn", "jake"], 0, 77)
	game.journal = []
	await game.start_game()
	for i in 6:
		if game.phase == "handoff":
			await game.cmd_start_turn()
		else:
			await game.run_command(game.turn_player, {"cmd": "end_turn"})
	return Replay.from_game(game, "ai", 0, "test")


func _fail(seed_value: int, pair: Array, msg: String) -> void:
	failures += 1
	if failures <= 25:
		printerr("seed %d %s: %s" % [seed_value, pair, msg])
