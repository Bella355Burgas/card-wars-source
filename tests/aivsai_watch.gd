extends Node
## Watches the AI-vs-AI mode through the real UI and takes screenshots:
##   godot --path . res://tests/aivsai_watch.tscn -- <output_dir> [seconds] [time_scale] [mode] [hero_a] [hero_b] [level_a] [level_b]
## mode "aivsai" (default) or "ai" (the test plays the human seat); levels are
## ai_levels.gd ids (vs AI only level_b counts), else the saved ones. Checks the
## pause button and the pause menu, prints every finished game, hero abilities
## used by the AI and anything that looks stuck.

const MainScene := preload("res://scenes/main.tscn")

var out_dir := "user://aivsai"
var main
var n := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var seconds := float(args[1]) if args.size() > 1 else 60.0
	Engine.time_scale = float(args[2]) if args.size() > 2 else 1.0
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MainScene.instantiate()
	add_child(main)
	var mode: String = args[3] if args.size() > 3 else "aivsai"
	var heroes: Array = [args[4], args[5]] if args.size() > 5 else ["finn", "marceline@prismo"]
	if args.size() > 7:
		main._ai_levels = [args[6], args[7]]
	_run(seconds, mode, heroes)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, name])
	print("shot ", name)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _press(text: String) -> bool:
	for b in main.overlay.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return true
	return false


func _run(seconds: float, mode: String, heroes: Array) -> void:
	await _wait(1.0)
	main._last_heroes = heroes
	main.show_hero_select(mode)
	await _wait(0.6)
	await _shot("select")
	_press("В бой!")
	var checked_pause := false
	var powers := 0
	var t0 := Time.get_ticks_msec()
	var last_hash := 0
	var same := 0
	var games := 0
	var shot_every := 8.0
	var next_shot := 2.0
	while (Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await _wait(0.5)
		var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
		for t in ["Начать!", "Дальше", "В бой!", "Смотреть руку"]:
			_press(t)
		var g = main.game
		if g == null:
			continue
		var board = main.board
		if board.arrange_panel.visible:
			board._arrange_done.emit()
		if board.mulligan_panel.visible:
			board._mulligan_done.emit(false)
		# Against the AI the test is the human: it just ends its turns.
		if mode == "ai" and g.turn_player == 0 and g.phase == "main" and not board._busy and board._choice == null:
			board._issue({"cmd": "end_turn"})
		if board._choice != null and mode == "ai":
			board._resolve_choice(board._choice["options"][0])
		if mode == "aivsai" and not checked_pause and g.turn_number >= 4 and g.phase != "over":
			checked_pause = true
			await _check_pause(board, g)
		if elapsed >= next_shot:
			next_shot += shot_every
			await _shot("t%03d_turn%d_%s" % [int(elapsed), g.turn_number, g.phase])
		var h: int = g.state_hash()
		if h == last_hash and g.phase != "over":
			same += 1
			if same == 20:
				print("STUCK? turn=%d phase=%s player=%d busy=%s choice=%s" % [g.turn_number, g.phase, g.turn_player,
					main.board._busy, main.board._choice])
				await _shot("stuck")
		else:
			same = 0
		last_hash = h
		if g.phase == "over" and g.get_meta("seen", false) == false:
			g.set_meta("seen", true)
			games += 1
			print("GAME OVER winner=%d (%s) turn=%d" % [g.winner, g.players[g.winner].name, g.turn_number])
			for line: String in g.log_lines:
				if line.contains("способность героя") or line.contains("ПРИЁМ героя"):
					powers += 1
			await _wait(1.5)
			await _shot("game_over")
	print("games finished: %d, hero abilities used: %d" % [games, powers])
	if main.game != null:
		for line in main.game.log_lines.slice(-40):
			print("  log: ", line)
	get_tree().quit()


## The pause button and the pause menu must both stop the AI.
func _check_pause(board, g) -> void:
	board._on_main_button()
	await _wait(1.0)
	var h: int = g.state_hash()
	await _wait(4.0)
	print("pause button holds the game: ", g.state_hash() == h and board.ai_paused)
	board._on_main_button()
	await _wait(1.0)
	main.show_pause()
	await _wait(1.0)
	h = g.state_hash()
	await _wait(4.0)
	print("pause menu holds the game: ", g.state_hash() == h)
	await _shot("pause_menu")
	_press("Продолжить")
	await _wait(1.0)
