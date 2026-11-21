extends SceneTree
## Tournament: the search level against the same network without search (greedy):
##   godot --headless --path . -s res://tests/search_match.gd -- [pairs] [first pair] [seed] [samples] [width] [time_ms] [save dir]
## Defaults: 4 pairs from 0, seed 1, 3 samples, width 8,3,2, no time limit (the game's level).
## With a save dir every game is written as a replay (tools/replay_log.gd reads them).
## A pair is two games with the same heroes, first player and engine seed, seats swapped.
## Heroes: a ready deck with its own hero card or another one, as in the menus.
## Prints the search's win rate with a 95% interval, its time per decision and the unfinished games.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const Replay = preload("res://scripts/core/replay.gd")
const PolicyAgent = preload("res://scripts/ai/policy_agent.gd")

const MODEL := "res://data/ai_policy.json"
const TURN_CAP := 150

var wins_a := 0
var games := 0
var unfinished := 0
var decisions_a := 0
var ms_a := 0
var max_ms := 0
var turns_total := 0
var save_dir := ""


## Answers the choices of each seat with that seat's agent.
class SeatChooser extends RefCounted:
	var agents: Array = []
	var game_ref: WeakRef

	func choose(req: Dictionary):
		var p: int = int(req.get("player", 0))
		return agents[p].pick_choice(game_ref.get_ref(), req)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var pairs := int(args[0]) if args.size() > 0 else 4
	var first_pair := int(args[1]) if args.size() > 1 else 0
	var seed_value := int(args[2]) if args.size() > 2 else 1
	var samples := int(args[3]) if args.size() > 3 else 3
	var width := [8, 3, 2]
	if args.size() > 4:
		width = []
		for part in String(args[4]).split(","):
			width.append(int(part))
	var time_ms := int(args[5]) if args.size() > 5 else 0
	save_dir = String(args[6]) if args.size() > 6 else ""
	var search_cfg := {"samples": samples, "width": width, "time_ms": time_ms, "yield": false,
		"hp_weight": float(OS.get_environment("CW_HP_WEIGHT") or 0.5),
		"open_weight": float(OS.get_environment("CW_OPEN_WEIGHT") or 0.5),
		"reply": OS.get_environment("CW_REPLY") == "1",
		"value_weight": float(OS.get_environment("CW_VALUE_WEIGHT") or 1.0)}
	var search_agent = PolicyAgent.new(MODEL, 0.0, search_cfg)
	var plain_agent = PolicyAgent.new(MODEL, 0.0)
	if search_agent.search == null or plain_agent.model == null:
		printerr("the search needs the model with its value head")
		quit(2)
		return
	var heroes: Array = CardDB.hero_ids()
	var hero_cards: Array = CardDB.hero_card_ids()
	var t0 := Time.get_ticks_msec()
	for i in range(first_pair, first_pair + pairs):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 1000 + i
		var picks := []
		for s in 2:
			var deck: String = heroes[rng.randi() % heroes.size()]
			var card: String = deck if rng.randf() < 0.5 else hero_cards[rng.randi() % hero_cards.size()]
			picks.append(CardDB.loadout(deck, card))
		var first := rng.randi() % 2
		var engine_seed := seed_value * 100000 + i
		var before_wins := wins_a
		for swap in 2:
			var seats := [search_agent, plain_agent] if swap == 0 else [plain_agent, search_agent]
			var search_seat := swap
			await _play(picks, first, engine_seed, seats, search_seat, "pair%d_%d" % [i, swap])
		print("pair %d %s vs %s: search won %d of 2" % [i, picks[0], picks[1], wins_a - before_wins])
	var n := maxi(games, 1)
	var rate := float(wins_a) / n
	var half := 1.96 * sqrt(rate * (1.0 - rate) / n)
	print("games=%d  search wins=%d (%.1f%% +- %.1f)  unfinished=%d" % [games, wins_a, rate * 100.0,
		half * 100.0, unfinished])
	print("search decisions=%d  ms per decision avg %.1f max %d  avg turns %.1f  time %.1fs" % [decisions_a,
		float(ms_a) / maxi(decisions_a, 1), max_ms, float(turns_total) / n,
		(Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if unfinished > 0 else 0)


func _play(picks: Array, first: int, engine_seed: int, seats: Array, search_seat: int, label: String) -> void:
	var g := Game.new()
	g.fast_mode = true
	if save_dir != "":
		g.journal = []
	var ch := SeatChooser.new()
	ch.agents = seats
	ch.game_ref = weakref(g)
	g.chooser = ch
	g.setup(picks, first, engine_seed)
	for p in [g.first_player, 1 - g.first_player]:
		if seats[p].mulligan(g, p):
			await g.cmd_mulligan(p)
	await g.start_game()
	var steps := 0
	while g.phase != "over" and steps < 4000 and g.turn_number <= TURN_CAP:
		if g.phase == "handoff":
			await g.cmd_start_turn()
			continue
		var p: int = g.turn_player
		var agent = seats[p]
		var cmd: Dictionary
		if p == search_seat:
			var t := Time.get_ticks_msec()
			cmd = await agent.pick_command_async(g, p)
			var dt := Time.get_ticks_msec() - t
			ms_a += dt
			max_ms = maxi(max_ms, dt)
			decisions_a += 1
		else:
			cmd = agent.pick_command(g, p)
		var before: int = g.state_hash()
		await g.run_command(p, cmd)
		steps += 1
		if g.phase != "over" and g.turn_player == p and g.state_hash() == before:
			agent.ban_command(before, cmd)
	if save_dir != "":
		DirAccess.make_dir_recursive_absolute(save_dir)
		var data := Replay.from_game(g, "aivsai", 0, "search")
		Replay.write(save_dir.path_join("%s_%s.cwreplay" % [label, "won" if g.winner == search_seat else "lost"]), data)
	games += 1
	turns_total += g.turn_number
	if g.phase != "over":
		unfinished += 1
		printerr("unfinished: turn %d" % g.turn_number)
	elif g.winner == search_seat:
		wins_a += 1
	g.chooser = null
