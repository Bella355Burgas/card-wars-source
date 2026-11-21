extends Node
## A discard pile opens with a left click in anybody's turn, and a big one scrolls:
##   godot --path . res://tests/shots_discard.tscn -- <output_dir>
## Plays against the AI; in the AI's turn it clicks the AI's discard pile (60 cards), then
## a pile of 2 на 2 in an AI's turn as well.

const MainScene := preload("res://scenes/main.tscn")

var out_dir := "user://shots_discard"
var main
var n := 0
var fails := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MainScene.instantiate()
	add_child(main)
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, name])


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _press_all() -> void:
	for b in main.overlay.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.disabled and b.text in ["Дальше", "Смотреть руку", "В бой!"]:
			b.pressed.emit()


## A real left click (press and release) at a point of the table.
func _click(board, wpos: Vector2) -> void:
	var at: Vector2 = board.world.get_global_transform_with_canvas() * wpos
	get_viewport().warp_mouse(at)
	await get_tree().process_frame
	# Input events come in window pixels; the window may be smaller than the 1920x1080 stage.
	var win: Vector2 = get_viewport().get_final_transform() * at
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = win
		e.global_position = win
		Input.parse_input_event(e)
		await get_tree().process_frame


## The person's turn: end it, so the AI's turn comes.
func _end_my_turn(board) -> void:
	var g = main.game
	if board != null and g != null and g.turn_player == 0 and g.phase == "main" and not board._busy and board._choice == null:
		board._issue({"cmd": "end_turn"})


func _check(board, side: int, what: String) -> void:
	var g = main.game
	print("before click: discard_at=%d choice=%s busy=%s picker=%s inspect=%s overlay_children=%d" % [board._discard_at(board.discard_pos(side)),
		board._choice != null, board._busy, board.picker_layer.visible, board.inspect_layer.visible, main.overlay.get_child_count()])
	await _click(board, board.discard_pos(side))
	var hov = get_viewport().gui_get_hovered_control()
	print("hovered control: %s, discard_at after: %d, picker %s" % [hov.get_path() if hov != null else "none",
		board._discard_at(board.discard_pos(side)), board.picker_layer.visible])
	await _wait(0.4)
	var ok: bool = board.picker_layer.visible and board.picker_grid.get_child_count() == g.players[side].discard.size()
	print("%s %s: picker %s, cards %d of %d, scroll height %.0f" % ["ok  " if ok else "FAIL", what,
		board.picker_layer.visible, board.picker_grid.get_child_count(), g.players[side].discard.size(),
		board.picker_scroll.custom_minimum_size.y])
	if not ok:
		fails += 1
	await _shot(what)
	board.picker_layer.visible = false


func _run() -> void:
	await _wait(0.8)
	main._last_heroes = ["finn", "jake"]
	main._ai_random = [false, false]
	main.start_ai_game(["finn", "jake"])
	var board = null
	for i in 200:
		await _wait(0.2)
		_press_all()
		board = main.board
		if board != null and board.mulligan_panel.visible:
			board._mulligan_done.emit(false)
		if main.game != null and main.game.phase == "main" and main.game.turn_player == 1:
			break
		_end_my_turn(board)
	var g = main.game
	for i in 60:
		g.players[1].discard.append(g._make_card(["evil_eye", "husker_knight", "corn_dog"][i % 3], 1))
	board.sync()
	board.hold_ai += 1          # the AI waits while we look
	await _wait(0.5)
	print("turn of seat %d (the AI), the person can act: %s" % [g.turn_player, board._can_act()])
	await _check(board, 1, "ai_turn_big_pile")
	board.hold_ai -= 1
	main._end_game()
	main._teams_ai = [false, true, true, true]
	main.start_teams_game(["finn", "jake", "bmo", "marceline"])
	for i in 300:
		await _wait(0.2)
		_press_all()
		board = main.board
		if board != null and board.mulligan_panel.visible:
			board._mulligan_done.emit(false)
		if main.game != null and main.game.phase == "main" and main.game.turn_player != 0:
			break
		_end_my_turn(board)
	for i in 25:
		main.game.players[3].discard.append(main.game._make_card("evil_eye", 3))
	board.sync()
	board.hold_ai += 1
	await _wait(0.5)
	await _check(board, 3, "teams_ai_turn")
	print("discard tests: %d failed" % fails)
	get_tree().quit()
