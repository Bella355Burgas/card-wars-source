extends SceneTree
## PPO agent against itself with every deck and random hero cards, headless:
##   godot --headless --path . -s res://tests/ai_all_heroes.gd -- [games_per_hero] [own_deck_code ...]
## Plays like the AI seats of the real game (board.gd): hero abilities and
## targets come from AIHelper. Own decks (pick codes from CardDB.custom_code)
## given after the count are added to the decks. Checks that every game finishes.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const AIHelper = preload("res://scripts/ai/ai_helper.gd")


## Answers the engine's choice requests the way the AI seats do.
class HelperChooser:
	var game
	func choose(req: Dictionary):
		return AIHelper.choose(game, req)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var per_hero := int(args[0]) if args.size() > 0 else 2
	var PPOAgent = load("res://scripts/ai/ppo_agent.gd")
	var agent = PPOAgent.new()
	var heroes: Array = CardDB.hero_ids() + Array(args.slice(1))
	var cards: Array = CardDB.hero_card_ids()
	var stuck := 0
	var wins := {}
	var powers := 0
	var n := 0
	for i in heroes.size():
		for k in per_hero:
			var opponent: String = heroes[(i + 1 + k) % heroes.size()]
			if CardDB.is_custom(opponent):
				opponent = CardDB.loadout(opponent, "jake")    # an own deck needs a hero card
			var pair := [CardDB.loadout(heroes[i], cards[(i * per_hero + k) % cards.size()]), opponent]
			var g := Game.new()
			g.fast_mode = true
			var chooser := HelperChooser.new()
			chooser.game = g
			g.chooser = chooser
			g.setup(pair, (i + k) % 2, 500 + n)
			await g.start_game()
			var steps := 0
			var hero_skip := {}
			while g.phase != "over" and steps < 4000:
				var p: int = g.turn_player
				var hero_ok: bool = hero_skip.get(p, -1) != g.turn_number
				var cmd: Dictionary = AIHelper.hero_command(g, p) if hero_ok else {}
				if cmd.is_empty():
					cmd = agent.pick_command(g, p)
					if hero_ok and (cmd["cmd"] == "end_turn" or cmd["cmd"] == "begin_attack"):
						var spare: Dictionary = AIHelper.spare_action_command(g, p)
						if not spare.is_empty():
							cmd = spare
				var before: int = g.state_hash()
				await g.run_command(p, cmd)
				AIHelper.clear_plan(g)
				if cmd["cmd"] == "hero":
					powers += 1
				# Never let a turn stall on a command that does nothing.
				if g.state_hash() == before and g.phase != "over":
					if cmd["cmd"] == "hero":
						hero_skip[p] = g.turn_number
					else:
						await g.run_command(p, {"cmd": "end_turn"})
				steps += 1
				if g.turn_number > 80:
					break
			n += 1
			if g.phase != "over":
				stuck += 1
				printerr("unfinished: %s turn %d" % [pair, g.turn_number])
			else:
				wins[pair[g.winner]] = wins.get(pair[g.winner], 0) + 1
	print("games=%d unfinished=%d hero_abilities=%d wins=%s" % [n, stuck, powers, wins])
	quit(1 if stuck > n / 4 else 0)
