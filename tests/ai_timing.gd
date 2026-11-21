extends SceneTree
## Times what the AI costs the game: loading each level's network (first and cached)
## and its decisions in AI-vs-AI games.
## godot --headless --path . -s res://tests/ai_timing.gd -- [games] [level]

const AILevels = preload("res://scripts/ai/ai_levels.gd")
const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 3
	var level := String(args[1]) if args.size() > 1 else "medium"
	for id in AILevels.ids():
		var t0 := Time.get_ticks_usec()
		AILevels.agent(id, "jake")
		var t1 := Time.get_ticks_usec()
		AILevels.agent(id, "jake")
		var t2 := Time.get_ticks_usec()
		print("LOAD %-10s first %7.1f ms, again %6.1f ms" % [id, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	await _games(games, level)
	quit()


func _games(n: int, level: String) -> void:
	var heroes: Array = CardDB.hero_ids()
	var cmd_ms := []
	var choice_ms := []
	for g in n:
		var picks := [heroes[randi() % heroes.size()], heroes[randi() % heroes.size()]]
		var agents := [AILevels.agent(level, picks[0]), AILevels.agent(level, picks[1])]
		var game = Game.new()
		game.setup(picks, randi() % 2)
		game.chooser = Chooser.new(game, agents, choice_ms)
		await game.start_game()
		var steps := 0
		while game.phase != "over" and steps < 600:
			steps += 1
			if game.phase == "handoff":
				await game.cmd_start_turn()
				continue
			var p: int = game.turn_player
			var t := Time.get_ticks_usec()
			var cmd: Dictionary = await agents[p].pick_command_async(game, p)
			cmd_ms.append((Time.get_ticks_usec() - t) / 1000.0)
			var before: int = game.state_hash()
			await game.run_command(p, cmd)
			if game.state_hash() == before and game.turn_player == p:
				agents[p].ban_command(before, cmd)
	_report("COMMAND", cmd_ms)
	_report("CHOICE", choice_ms)


func _report(what: String, ms: Array) -> void:
	if ms.is_empty():
		print("%s none" % what)
		return
	ms.sort()
	var total := 0.0
	for v in ms:
		total += v
	print("%s n=%d mean %.1f ms, median %.1f, p95 %.1f, max %.1f" % [what, ms.size(), total / ms.size(),
		ms[ms.size() / 2], ms[int(ms.size() * 0.95)], ms[-1]])


class Chooser:
	var game
	var agents: Array
	var ms: Array

	func _init(g, a: Array, out: Array) -> void:
		game = g
		agents = a
		ms = out

	func choose(req: Dictionary):
		var t := Time.get_ticks_usec()
		var a = agents[int(req.get("player", game.turn_player))].pick_choice(game, req)
		ms.append((Time.get_ticks_usec() - t) / 1000.0)
		return a
