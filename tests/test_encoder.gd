extends SceneTree

func _initialize() -> void:
	var AIEncoder = load("res://scripts/ai/ai_encoder.gd")
	AIEncoder.init()
	print("TEST: Card IDs count: ", AIEncoder._card_id_to_int.size())
	print("TEST: ancient_scholar ID: ", AIEncoder.card_to_int("ancient_scholar"))
	print("TEST: archer_dan ID: ", AIEncoder.card_to_int("archer_dan"))
	
	var Game = load("res://scripts/core/game.gd")
	var g = Game.new()
	g.setup(["finn", "jake"], 0, 42)
	await g.start_game()
	
	var state = AIEncoder.encode_state(g, 0)
	print("TEST: State size: ", state.size())
	assert(state.size() == 181, "State size must be 181")
	
	var mask = AIEncoder.get_action_mask(g, 0)
	print("TEST: Mask size: ", mask.size(), " End turn legal: ", mask[58])
	assert(mask.size() == 64, "Mask size must be 64")
	assert(mask[58] == true, "End turn must be legal")
	
	var cmds = g.legal_commands(0)
	print("TEST: Legal commands count: ", cmds.size())
	
	var true_mask_count = 0
	for m in mask:
		if m:
			true_mask_count += 1
	print("TEST: Legal actions in mask: ", true_mask_count)
	
	print("TEST SUCCESSFUL!")
	quit(0)
