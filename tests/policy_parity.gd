extends SceneTree
## Plays games with an exported self-play network on both seats, the way the AI
## seats of the game do (policy_agent.gd: hand, commands, choices, bans), and
## dumps every decision with the network's scores:
##   godot --headless --path . -s res://tests/policy_parity.gd -- <model.json> <out.jsonl> [games]
## rl_training/check_parity.py runs this and compares the scores with PyTorch.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const PolicyAgent = preload("res://scripts/ai/policy_agent.gd")


class AgentChooser extends RefCounted:
	var game_ref: WeakRef
	var agent
	func choose(req: Dictionary):
		return agent.pick_choice(game_ref.get_ref(), req)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <model.json> <out.jsonl> [games]")
		quit(2)
		return
	var games := int(args[2]) if args.size() > 2 else 3
	var agent := PolicyAgent.new(args[0])
	if agent.model == null:
		quit(2)
		return
	agent.trace = []
	var out := FileAccess.open(args[1], FileAccess.WRITE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var heroes: Array = CardDB.hero_ids()
	var cards: Array = CardDB.hero_card_ids()
	var unfinished := 0
	var decisions := 0
	var t0 := Time.get_ticks_msec()
	for gi in games:
		var pair := []
		for i in 2:
			pair.append(CardDB.loadout(heroes[rng.randi() % heroes.size()], cards[rng.randi() % cards.size()]))
		var g := Game.new()
		g.fast_mode = true
		var ch := AgentChooser.new()
		ch.game_ref = weakref(g)
		ch.agent = agent
		g.chooser = ch
		g.setup(pair, gi % 2, 100 + gi)
		for p in [g.first_player, 1 - g.first_player]:
			if agent.mulligan(g, p):
				await g.cmd_mulligan(p)
		await g.start_game()
		var steps := 0
		while g.phase != "over" and steps < 3000 and g.turn_number <= 80:
			if g.phase == "handoff":
				await g.cmd_start_turn()
				continue
			var p := g.turn_player
			var cmd: Dictionary = agent.pick_command(g, p)
			var before := g.state_hash()
			await g.run_command(p, cmd)
			steps += 1
			if g.phase != "over" and g.turn_player == p and g.state_hash() == before:
				agent.ban_command(before, cmd)
		if g.phase != "over":
			unfinished += 1
			printerr("unfinished: %s turn %d" % [pair, g.turn_number])
		for d in agent.trace:
			out.store_line(JSON.stringify(d))
		decisions += agent.trace.size()
		agent.trace = []
		g.chooser = null
	out.close()
	var ms := Time.get_ticks_msec() - t0
	print("games=%d unfinished=%d decisions=%d ms_per_decision=%.1f" % [games, unfinished, decisions,
		float(ms) / maxi(decisions, 1)])
	quit(1 if unfinished > 0 else 0)
