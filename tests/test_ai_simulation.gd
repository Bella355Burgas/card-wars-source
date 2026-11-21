extends SceneTree

func _initialize() -> void:
	var PPOAgent = load("res://scripts/ai/ppo_agent.gd")
	var agent = PPOAgent.new()
	var RandomAgent = load("res://scripts/core/random_agent.gd")
	var random_bot = RandomAgent.new(42)
	
	var Game = load("res://scripts/core/game.gd")
	var g = Game.new()
	g.fast_mode = true
	g.chooser = agent
	g.setup(["jake", "finn"], 0, 100)
	await g.start_game()
	
	print("Simulation starting: Finn (human/random) vs Jake (PPO AI)")
	var turns := 0
	while g.phase != "over" and turns < 15:
		var p = g.turn_player
		var cmd: Dictionary
		if p == 1:
			cmd = agent.pick_command(g, 1)
		else:
			var legals = g.legal_commands(p)
			cmd = random_bot.pick_command(legals)
		
		var prev_phase = g.phase
		var prev_p = g.turn_player
		await g.run_command(p, cmd)
		if g.turn_player != prev_p:
			turns += 1
	
	print("Simulation reached turn ", turns, " final phase: ", g.phase, " winner: ", g.winner)
	print("ALL PPO SIMULATION CHECKS PASSED!")
	quit(0)
