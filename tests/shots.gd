extends Node
## Visual smoke test. Runs the real game in a window, clicks through curtains,
## plays random legal moves through the board UI and saves screenshots:
##   godot --path . res://tests/shots.tscn -- <output_dir> [turns]

const RandomAgent = preload("res://scripts/core/random_agent.gd")
const MainScene := preload("res://scenes/main.tscn")

var out_dir := "user://shots"
var max_turns := 6
var main: Node
var agent := RandomAgent.new(42)
var shot_n := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		max_turns = int(args[1])
	if args.size() > 2 and args[2] == "fast":
		Engine.time_scale = 5.0
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MainScene.instantiate()
	add_child(main)
	_drive()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	shot_n += 1
	img.save_png("%s/%02d_%s.png" % [out_dir, shot_n, name])
	print("shot ", name)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _press_curtain() -> bool:
	for root in main.overlay.get_children():
		var b := _find_button(root)
		if b != null and not b.disabled:
			b.pressed.emit()
			return true
	return false


func _find_button(n: Node) -> Button:
	if n is Button and n.is_visible_in_tree():
		return n
	for ch in n.get_children():
		var b := _find_button(ch)
		if b != null:
			return b
	return null


func _drive() -> void:
	await _wait(1.5)
	await _shot("title")
	main.start_new_game()
	await _wait(2.5)
	await _shot("coin")
	_press_curtain()
	for i in 2:
		await _wait(0.8)
		_press_curtain()
		await _wait(1.0)
		await _shot("mulligan_%d" % i)
		main.board._mulligan_done.emit(i == 1)
		await _wait(1.2)
	_press_curtain()
	await _wait(2.0)
	var board = main.board
	var game = main.game
	var hover_done := false
	var last_turn := -1
	var steps := 0
	while game.phase != "over" and game.turn_number <= max_turns and steps < 400:
		steps += 1
		await _wait(0.15)
		if main.overlay.get_child_count() > 0 and game.phase != "over":
			if game.turn_number != last_turn and game.phase == "handoff":
				await _shot("curtain_turn_%d" % game.turn_number)
				last_turn = game.turn_number
			_press_curtain()
			await _wait(0.6)
			continue
		if board._choice != null:
			await _shot("choice_%s" % board._choice["kind"])
			var opts: Array = board._choice["options"]
			board._resolve_choice(opts[agent.rng.randi() % opts.size()])
			continue
		if board._busy or game.phase != "main" and game.phase != "attack":
			continue
		var p: int = game.turn_player
		if not hover_done and game.turn_number == 2 and not game.players[p].hand.is_empty():
			var hv = board.views[game.players[p].hand[0].uid]
			var gp: Vector2 = hv.get_global_transform_with_canvas().origin + Vector2(30, -20)
			Input.warp_mouse(gp * get_viewport().get_final_transform().get_scale())
			await _wait(0.8)
			await _shot("hover_hand")
			Input.warp_mouse(Vector2(5, 5))
			hover_done = true
		var cmds: Array = game.legal_commands(p)
		var c: Dictionary = agent.pick_command(cmds)
		if c["cmd"] == "end_turn":
			await _shot("before_end_turn_%d" % game.turn_number)
		board._run(func(): await game.run_command(p, c))
		await _wait(0.1)
	await _wait(2.5)
	await _shot("final")
	print("phase=%s winner=%d turn=%d hp=%d/%d" % [game.phase, game.winner, game.turn_number,
		game.players[0].hp, game.players[1].hp])
	get_tree().quit()
