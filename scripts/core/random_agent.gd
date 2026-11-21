extends RefCounted
## Plays legal random moves. Used by the headless simulation to fuzz the engine.

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value


func choose(req: Dictionary):
	var options: Array = req["options"]
	if req.get("optional", false) and rng.randf() < 0.3:
		return null
	return options[rng.randi() % options.size()]


func pick_command(cmds: Array) -> Dictionary:
	# Mostly do things; end the turn only when bored or out of options.
	var actions := cmds.filter(func(c): return c["cmd"] != "end_turn")
	if actions.is_empty() or rng.randf() < 0.12:
		for c in cmds:
			if c["cmd"] == "end_turn":
				return c
	return actions[rng.randi() % actions.size()]
