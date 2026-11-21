extends SceneTree
## Fingerprints of random «Бесконечный поезд» fights, to compare two versions of the train rules:
##   godot --headless --path . -s res://tests/hash_train.gd -- [games] [seed]
## Like hash_games.gd, but every fight has a wagon rule, random hero and enemy stats
## (crits, items, curses) and sometimes a second enemy. Same output: same train rules.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")
const TrainWagons = preload("res://scripts/train/train_wagons.gd")

const STATS := ["actions", "armor", "atk", "bleed", "building_cheap", "building_def", "building_draw",
	"building_regen", "crit", "crit_dmg", "death_bleed", "death_heal", "dodge", "draw", "edge_def",
	"enter_def", "face_dmg", "first_action", "first_free", "floop_def", "hand", "kill_atk", "lifesteal",
	"lone", "no_freeze", "rainbow_cheap", "regen", "spell_buff", "spell_cheap", "spell_dmg", "spell_heal",
	"spell_tax", "third_spell", "thorns", "vs_atk", "weak_up", "death_draw", "first_crit", "first_return",
	"floop_draw", "kill_action", "last_stand", "revive", "spell_draw"]


func _stats(rng: RandomNumberGenerator) -> Dictionary:
	var st := {}
	for n in rng.randi_range(0, 8):
		var key: String = STATS[rng.randi() % STATS.size()]
		st[key] = rng.randi_range(1, 60) if key in ["crit", "crit_dmg", "dodge", "draw", "lifesteal"] else rng.randi_range(1, 2)
	return st


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 200
	var base_seed := int(args[1]) if args.size() > 1 else 1
	var heroes: Array = CardDB.hero_ids()
	var wagons: Array = [""] + TrainWagons.WAGONS.keys()
	var all := []
	for n in games:
		var seed_value := base_seed + n
		var agent := RandomAgent.new(seed_value * 31)
		var rng := agent.rng
		var pair := [heroes[rng.randi() % heroes.size()], heroes[rng.randi() % heroes.size()]]
		var game := Game.new()
		game.chooser = agent
		game.setup(pair, seed_value % 2, seed_value)
		var wagon: String = wagons[rng.randi() % wagons.size()]
		for p in 2:
			game.players[p].hp = rng.randi_range(8, 25)
			game.players[p].max_hp = 25
			game.train.set_stats(p, _stats(rng))
		game.train.set_wagon(wagon)
		game.train.limit_enemy_deck(20)
		if rng.randf() < 0.3:
			game.train.set_follow(heroes[rng.randi() % heroes.size()], rng.randi_range(5, 12), _stats(rng), 20)
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
		print("fight %d %s %s turns=%d winner=%d hash=%d" % [seed_value, pair, wagon, game.turn_number, game.winner, game.state_hash()])
		all.append(game.state_hash())
	print("ALL ", hash(all))
	quit()
