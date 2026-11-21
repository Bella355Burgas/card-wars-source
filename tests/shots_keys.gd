extends Node
## Screenshots of the keyboard frames: the title, a card of the hand, where it may go, the menu
## of a card in play, a list of cards to pick from, the keys list, the items of the train:
##   godot --path . res://tests/shots_keys.tscn -- <output_dir>

const MainScene := preload("res://scenes/main.tscn")
const TrainRun = preload("res://scripts/train/train_run.gd")

var out_dir := "user://shots_keys"
var main
var kn
var n := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	# The real mouse over the window would hide the frames.
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	main = MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	kn = get_node("/root/KeyNav")
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, name])
	print("shot ", name)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await get_tree().process_frame
	await _wait(0.25)


func _run() -> void:
	await _wait(1.2)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _shot("title_frame")
	# «Играть»: the frame goes over to the menu on top, not stays on the title.
	await _key(KEY_UP)
	await _key(KEY_ENTER)
	await _wait(0.8)
	await _shot("play_menu_frame")
	await _key(KEY_ESCAPE)
	await _wait(0.6)
	main.show_settings()
	await _wait(0.5)
	main.show_controls()
	await _wait(0.6)
	await _key(KEY_DOWN)
	await _shot("controls")
	await _key(KEY_ESCAPE)
	for ch in main.overlay.get_children():
		main._close_overlay(ch)
	await _wait(0.5)
	main.start_new_game(["lich@lich", "finn@charlie"])
	await _wait(2.0)
	var board = main.board
	# The setup by the keys: the curtains, the lands, the start hand.
	for i in 60:
		if main.game.phase == "main" and board._can_act():
			break
		if board.arrange_panel.visible and board._kb_free():
			await _key(KEY_DOWN)
			await _shot("arrange_frame")
			board._arrange_done.emit()
		elif board.mulligan_panel.visible:
			await _key(KEY_RIGHT)
			if i < 12:
				await _shot("mulligan_frame")
			await _key(KEY_LEFT)
			await _key(KEY_ENTER)
		elif not board._kb_free():
			await _key(KEY_ENTER)     # a curtain: its button
		await _wait(0.3)
	await _wait(0.8)
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	await _shot("hand_frame")
	# A creature: where it may go.
	var g = main.game
	for c in g.players[board.viewer].hand:
		if c.kind() == "creature" and g.can_play(board.viewer, c.uid):
			board._kb_id = "u:%d" % c.uid
			break
	await _wait(0.4)
	await _key(KEY_SPACE)
	await _key(KEY_RIGHT)
	await _shot("drop_frame")
	await _key(KEY_SPACE)
	await _wait(1.5)
	# The frame on a card in play, then its menu.
	await _key(KEY_UP)
	await _key(KEY_UP)
	await _shot("field_frame")
	# A list of cards: the frame on one of them.
	board._show_cards("Рука", g.players[board.viewer].hand.map(func(c): return c.id))
	await _wait(0.4)
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	await _shot("picker_frame")
	await _key(KEY_ESCAPE)
	await _key(KEY_E)
	await _wait(2.0)
	await _shot("curtain_frame")
	kn.toggle_help()
	await _wait(0.3)
	await _shot("keys_list")
	kn.toggle_help()
	# «Бесконечный поезд»: the frame over the doors, Tab shows the items.
	main.board.queue_free()       # no replay of this table is kept
	main.board = null
	main.game = null
	for ch in main.overlay.get_children():
		main._close_overlay(ch)       # the curtain of the next turn
	main.run = TrainRun.new()
	main.run.save_path = "user://run_keys_shots.json"
	main.run.start("finn")
	main.show_run()
	await _wait(1.5)
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	await _shot("run_frame")
	await _key(KEY_TAB)
	await _wait(0.5)
	await _shot("run_items")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://run_keys_shots.json"))
	# The deck builder: the note at the bottom covers the frame, not the other way round.
	main._close_run_screen()
	main.show_deck_builder("")
	await _wait(1.5)
	await _key(KEY_DOWN)
	for i in 8:
		await _key(KEY_DOWN)
	for i in 4:
		await _key(KEY_ENTER)
	await _shot("builder_note")
	await _key(KEY_DELETE)
	await _shot("builder_removed")
	get_tree().quit()
