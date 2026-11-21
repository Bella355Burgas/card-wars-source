extends Node
## A 2 на 2 replay through the real replay screen, with screenshots:
##   godot --path . res://tests/teams_replay_ui.tscn -- <output_dir>
## Plays a random 2 на 2 game in the engine, opens its replay on the table, switches the
## seat it is watched from and waits for the replay's end screen.

const MainScene := preload("res://scenes/main.tscn")
const Game = preload("res://scripts/core/game.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")
const Replay = preload("res://scripts/core/replay.gd")

var out_dir := "user://teams_replay"
var main
var n := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.time_scale = 8.0
	main = MainScene.instantiate()
	add_child(main)
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, name])
	print("shot ", name)


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	var agent := RandomAgent.new(3)
	var game := Game.new()
	game.chooser = agent
	game.setup(["finn", "jake@grand_prix", "bmo", "rainicorn"], 1, 99)
	game.journal = []
	await game.start_game()
	var steps := 0
	while game.phase != "over" and steps < 3000:
		if game.phase == "handoff":
			await game.cmd_start_turn()
			continue
		await game.run_command(game.turn_player, agent.pick_command(game.legal_commands(game.turn_player)))
		steps += 1
	var data := Replay.from_game(game, "teams", 0, "test")
	print("title: ", Replay.title(data), " / ", Replay.result(data))
	var back := Replay.parse(JSON.stringify(data))
	print("parsed: ", not back.is_empty(), " verify: '", await Replay.verify(back), "'")
	main.start_replay(back)
	var t0 := Time.get_ticks_msec()
	var switched := false
	while Time.get_ticks_msec() - t0 < 120000:
		await get_tree().create_timer(0.5).timeout
		for root in main.overlay.get_children():
			for btn in root.find_children("*", "Button", true, false):
				if btn.text == "Смотреть" and btn.is_visible_in_tree():
					btn.pressed.emit()
		var board = main.board
		if board == null or main.game == null:
			continue
		if not switched and main.game.turn_number >= 6:
			switched = true
			await _shot("replay_seat0")
			board._on_hero_button()
			await get_tree().create_timer(0.3).timeout
			await _shot("replay_seat1")
			print("viewer after switch: ", board.viewer)
		if main.game.phase == "over":
			await get_tree().create_timer(8.0).timeout
			await _shot("replay_end")
			print("replay ended at turn %d (game %d), phase %s (%s), pos %d/%d, hash same: %s" % [main.game.turn_number,
				game.turn_number, main.game.phase, game.phase, board._replay_pos, board.replay_steps.size(),
				main.game.state_hash() == game.state_hash()])
			break
	get_tree().quit()
