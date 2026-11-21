extends SceneTree

func _initialize() -> void:
	var PPOAgent = load("res://scripts/ai/ppo_agent.gd")
	var agent = PPOAgent.new()
	assert(PPOAgent.is_available(), "Model must be available")
	
	var Game = load("res://scripts/core/game.gd")
	var g = Game.new()
	g.setup(["finn", "jake"], 1, 123)
	await g.start_game()
	
	var t0 = Time.get_ticks_usec()
	var act = agent.predict_action(g, 1, true)
	var t1 = Time.get_ticks_usec()
	var dt = t1 - t0
	
	var cmd = agent.pick_command(g, 1)
	print("TEST PPO: Action=", act, " Command=", cmd, " Inference time: ", dt, " microseconds (", float(dt)/1000.0, " ms)")
	assert(act >= 0 and act < 64, "Action must be valid index")
	print("PPO INFERENCE TEST SUCCESSFUL!")
	quit(0)
