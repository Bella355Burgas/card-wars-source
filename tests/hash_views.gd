extends SceneTree
## Fingerprint of what the AI sees (ai_view.gd) along random games, to compare two
## versions of the code: same output, same network inputs.
##   godot --headless --path . -s res://tests/hash_views.gd -- [games] [seed] [seats: 2, 3 or 4]

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")
const AIView = preload("res://scripts/ai/ai_view.gd")


class Watcher extends RefCounted:
	var agent
	var game_ref: WeakRef
	var views: Array

	func choose(req: Dictionary):
		views.append(hash(var_to_str(AIView.choice_view(game_ref.get_ref(), req)["view"])))
		return agent.choose(req)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 50
	var base_seed := int(args[1]) if args.size() > 1 else 1
	var seats := int(args[2]) if args.size() > 2 else 2
	var heroes: Array = CardDB.hero_ids()
	var hero_cards: Array = CardDB.hero_card_ids()
	var all := []
	for n in games:
		var seed_value := base_seed + n
		var agent := RandomAgent.new(seed_value * 31)
		var pair := []
		for i in seats:
			var deck: String = heroes[agent.rng.randi() % heroes.size()]
			var card: String = hero_cards[agent.rng.randi() % hero_cards.size()] if agent.rng.randf() < 0.5 else deck
			pair.append(CardDB.loadout(deck, card))
		var game := Game.new()
		var w := Watcher.new()
		w.agent = agent
		w.game_ref = weakref(game)
		w.views = all
		game.chooser = w
		game.setup(pair, seed_value % seats, seed_value)
		all.append(hash(var_to_str(AIView.mulligan_view(game, 0))))
		await game.start_game()
		var steps := 0
		while game.phase != "over" and steps < 3000:
			if game.phase == "handoff":
				await game.cmd_start_turn()
				continue
			var cmds: Array = game.legal_commands(game.turn_player)
			if cmds.is_empty():
				break
			all.append(hash(var_to_str(AIView.command_view(game, game.turn_player, cmds))))
			await game.run_command(game.turn_player, agent.pick_command(cmds))
			steps += 1
	print("VIEWS %d %d" % [all.size(), hash(all)])
	quit()
