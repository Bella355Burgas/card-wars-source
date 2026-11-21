extends Node
## Screenshots of the hero selection, land arrangement and a busy table:
##   godot --path . res://tests/shots_heroes.tscn -- <output_dir>

const MainScene := preload("res://scenes/main.tscn")

var out_dir := "user://shots_heroes"
var main
var n := 0


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
	print("shot ", name)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _press(text: String) -> bool:
	for b in main.overlay.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return true
	return false


func _run() -> void:
	await _wait(1.2)
	await _shot("title")
	main.show_hero_select("hotseat")
	await _wait(0.8)
	await _shot("hero_select")
	_press("Назад")
	await _wait(0.4)
	main.show_hero_select("ai")
	await _wait(0.8)
	await _shot("hero_select_ai")
	_press("Назад")
	await _wait(0.4)
	var levels: Array = main._ai_levels.duplicate()
	main._ai_levels = ["novice", "impossible"]
	main.show_hero_select("aivsai")
	await _wait(0.8)
	await _shot("hero_select_aivsai")
	_press("Назад")
	main._ai_levels = levels
	await _wait(0.4)
	main.start_new_game(["lemongrab@pb", "marceline@magic_man"])
	await _wait(2.4)
	_press("Дальше")
	await _wait(1.0)
	var board = main.board
	if board.arrange_panel.visible:
		await _shot("arrange")
		board._arrange_click(board.land_pos(board._arranging, 0))
		board._arrange_click(board.land_pos(board._arranging, 1))
		await _wait(0.6)
		await _shot("arrange_swapped")
		board._arrange_done.emit()
	# Click through the rest of the setup.
	for i in 30:
		await _wait(0.4)
		if board.arrange_panel.visible:
			board._arrange_done.emit()
		elif board.mulligan_panel.visible:
			board._mulligan_done.emit(false)
		else:
			for t in ["Дальше", "Начать ход"]:
				_press(t)
			for b in main.overlay.find_children("*", "Button", true, false):
				if b.is_visible_in_tree() and b.text.begins_with("Я "):
					b.pressed.emit()
		if main.game.phase == "main":
			break
	await _wait(1.0)
	await _busy_table(board, main.game)
	await _shot("table")
	# Hero card preview: the mouse over the bottom hero panel.
	get_viewport().warp_mouse(Vector2(200, 900))
	await _wait(0.4)
	await _shot("hero_preview")
	main.board.picker_layer.visible = false
	get_tree().quit()


## Puts a bit of everything on the table for the screenshot.
func _busy_table(board, g) -> void:
	var p: int = g.turn_player
	var o: int = 1 - p
	var mk := func(id: String, owner: int): return g._make_card(id, owner)
	await g._put_creature(p, mk.call("burly_lumberjack", p), 0)
	await g._put_building(p, mk.call("celestial_castle", p), 0)
	await g._put_building(p, mk.call("blood_fortress", p), 0)
	await g._put_creature(p, mk.call("albino_eyebat", p), 1)
	await g._put_creature(o, mk.call("frosted_snowwoman", o), 2)
	await g._put_creature(o, mk.call("hag_ghost", o), 1)
	await g._put_building(o, mk.call("oppressive_pyramid", o), 1)
	await g.freeze(p, 3)
	await g.freeze(o, 3)
	var silo = mk.call("silo_of_freedom", p)
	await g._put_building(p, silo, 2)
	await g.set_land_override(p, 2, "ice", p)
	g.players[p].hand.append(mk.call("unempty_coffin", p))
	g.players[p].hand.append(mk.call("lost_golem", p))
	board.sync()
	await _wait(1.2)
