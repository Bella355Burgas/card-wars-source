extends Node
## 2 на 2 through the real UI, with screenshots:
##   godot --path . res://tests/teams_watch.tscn -- <output_dir> [seconds] [time_scale] [people]
## people: how many seats the test plays as a person at this PC (0: all four are AI, 1: seat 0,
## 2: seats 0 and 1, passing the PC round). The test's people play random legal commands
## through the table's own input path and answer choices with the first option. Prints every
## finished game and anything that looks stuck; game overs press "Реванш".

const MainScene := preload("res://scenes/main.tscn")

var out_dir := "user://teams_watch"
var main
var n := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var seconds := float(args[1]) if args.size() > 1 else 60.0
	Engine.time_scale = float(args[2]) if args.size() > 2 else 1.0
	var people := int(args[3]) if args.size() > 3 else 1
	DirAccess.make_dir_recursive_absolute(out_dir)
	rng.seed = 5
	main = MainScene.instantiate()
	add_child(main)
	_run(seconds, people)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, name])
	print("shot ", name)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _press(text: String) -> bool:
	for root in [main.overlay, main]:
		for b in root.find_children("*", "Button", true, false):
			if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
				b.pressed.emit()
				return true
	return false


func _run(seconds: float, people: int) -> void:
	await _wait(1.0)
	await _shot("title")
	main._teams_ai = [people < 1, people < 2, true, true]
	main._teams_heroes = ["finn", "marceline@prismo", "ice_king", "lemongrab@jake_2x2"]
	main.show_hero_select("teams")
	await _wait(0.6)
	await _shot("select")
	_press("В бой!")
	await _wait(1.5)     # the selection fades out: its button must not start a second game
	var t0 := Time.get_ticks_msec()
	var last_hash := 0
	var same := 0
	var games := 0
	var next_shot := 3.0
	var shots_choice := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await _wait(0.25)
		var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
		var g = main.game
		var board = main.board
		if g == null or board == null:
			continue
		for t in ["Дальше", "Смотреть руку", "Я ", "Начать"] + (["В бой!"] if g.phase == "setup" else []):
			_press(t)
		if board.arrange_panel.visible:
			board._arrange_done.emit()
		if board.mulligan_panel.visible:
			board._mulligan_done.emit(false)
		if board._choice != null:
			if shots_choice < 3:
				shots_choice += 1
				await _shot("choice")
			var opts: Array = board._choice["options"]
			board._resolve_choice(opts[rng.randi() % opts.size()] if not opts.is_empty() else null)
			continue
		var p: int = g.turn_player
		if board.humans.has(p) and p == board.viewer and (g.phase == "main" or g.phase == "attack") \
				and not board._busy and board._choice == null:
			var cmds: Array = g.legal_commands(p)
			var acts := cmds.filter(func(c): return c["cmd"] != "end_turn")
			var c: Dictionary = acts[rng.randi() % acts.size()] if not acts.is_empty() and rng.randf() < 0.8 \
				else {"cmd": "end_turn"}
			board._issue(c)
		if elapsed > next_shot:
			next_shot = elapsed + 6.0
			await _shot("table_t%d" % g.turn_number)
		if g.phase == "over" and main._game_over_root != null:
			games += 1
			print("GAME OVER winner team %d (%s) after %d turns, hp %d : %d" % [g.winner, g.side_name(g.winner),
				g.turn_number, g.players[0].hp, g.players[1].hp])
			await _shot("game_over")
			_press("Реванш")
			await _wait(1.0)
			continue
		var h: int = g.state_hash()
		if h == last_hash and not board._busy:
			same += 1
			if same == 120:
				print("STUCK? turn %d player %d phase %s busy %s choice %s ai_running %s" % [g.turn_number, p, g.phase,
					board._busy, board._choice != null, board._ai_turn_running])
				await _shot("stuck")
		else:
			same = 0
			last_hash = h
	print("teams watch: %d games finished in %.0f s" % [games, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()
