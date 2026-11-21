extends SceneTree
## Fingerprints of random games, to compare two versions of the engine:
##   godot --headless --path . -s res://tests/hash_games.gd -- [games] [seed] [seats: 2, 3 or 4]
## Plays seeded random games (random decks, hero cards and choices) and prints the
## state hash each one ends with. Same output from two versions: same rules.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 200
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
		game.chooser = agent
		game.setup(pair, seed_value % seats, seed_value)
		await game.start_game()
		var steps := 0
		while game.phase != "over" and steps < 3000:
			if game.phase == "handoff":
				await game.cmd_start_turn()
				continue
			var cmds: Array = game.legal_commands(game.turn_player)
			if cmds.is_empty():
				break
			await game.run_command(game.turn_player, agent.pick_command(cmds))
			steps += 1
		print("game %d %s turns=%d winner=%d hash=%d" % [seed_value, pair, game.turn_number, game.winner, game.state_hash()])
		all.append(game.state_hash())
	print("ALL ", hash(all))
	quit()
