extends SceneTree
## How strong a deck is: it plays every ready deck (with its own hero card), the strongest network on both seats:
##   godot --headless --path . -s res://tests/deck_eval.gd -- <pairs per opponent> <seed> <pick> [pick ...]
## A pick is a ready deck, "deck@card" or an own deck code (+ "@card"). A pair is two games with the same
## first player and engine seed, seats swapped. CW_OPPS="jake,lich" limits the opponents. Prints one line per pick: "EVAL <win %> <wins>/<games> <pick>".

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const PolicyAgent = preload("res://scripts/ai/policy_agent.gd")

const MODEL := "res://data/ai_policy.json"
const TURN_CAP := 150


class SeatChooser extends RefCounted:
	var agent
	var game_ref: WeakRef

	func choose(req: Dictionary):
		return agent.pick_choice(game_ref.get_ref(), req)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var pairs := int(args[0])
	var seed_value := int(args[1])
	var agent = PolicyAgent.new(MODEL, 0.0)
	var opps: Array = CardDB.hero_ids()
	if OS.get_environment("CW_OPPS") != "":
		opps = Array(OS.get_environment("CW_OPPS").split(","))
	for pick: String in args.slice(2):
		var wins := 0
		var games := 0
		var per := {}
		for opp: String in opps:
			for i in pairs:
				var engine_seed := seed_value * 100000 + hash(opp) % 1000 * 100 + i
				for swap in 2:
					var picks := [pick, opp] if swap == 0 else [opp, pick]
					var winner := await _play(agent, picks, i % 2, engine_seed)
					games += 1
					if winner == swap:
						wins += 1
						per[opp] = per.get(opp, 0) + 1
		print("EVAL %.1f %d/%d %s %s" % [100.0 * wins / games, wins, games, pick, JSON.stringify(per)])
	quit(0)


## The seat that won, -1 when the game did not finish.
func _play(agent, picks: Array, first: int, engine_seed: int) -> int:
	var g := Game.new()
	g.fast_mode = true
	var ch := SeatChooser.new()
	ch.agent = agent
	ch.game_ref = weakref(g)
	g.chooser = ch
	g.setup(picks, first, engine_seed)
	for p in [g.first_player, 1 - g.first_player]:
		if agent.mulligan(g, p):
			await g.cmd_mulligan(p)
	await g.start_game()
	var steps := 0
	while g.phase != "over" and steps < 4000 and g.turn_number <= TURN_CAP:
		if g.phase == "handoff":
			await g.cmd_start_turn()
			continue
		var p: int = g.turn_player
		var cmd: Dictionary = agent.pick_command(g, p)
		var before: int = g.state_hash()
		await g.run_command(p, cmd)
		steps += 1
		if g.phase != "over" and g.turn_player == p and g.state_hash() == before:
			agent.ban_command(before, cmd)
	var winner: int = g.winner if g.phase == "over" else -1
	g.chooser = null
	return winner
