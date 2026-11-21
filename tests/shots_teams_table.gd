extends Node
## Screens of the 2 на 2 table that a game seldom shows by itself:
##   godot --path . res://tests/shots_teams_table.tscn -- <output_dir>
## the land arrangement, the drop targets of a creature from the hand, a target choice over
## every seat, a land choice, frozen lands, командные карты, and clicks on turned spots.

const MainScene := preload("res://scenes/main.tscn")

var out_dir := "user://shots_teams_table"
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


func _press(text: String) -> void:
	for b in main.overlay.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()


func _run() -> void:
	await _wait(0.8)
	main._teams_ai = [false, true, true, true]
	main._teams_random = [false, false, false, false]
	main.start_teams_game(["lemongrab", "ice_king", "jake", "marceline"])
	var board = null
	for i in 40:
		await _wait(0.25)
		_press("Дальше")
		board = main.board
		if board != null and board.arrange_panel.visible:
			break
	await _wait(0.6)
	await _shot("arrange")
	board._arrange_click(board.land_pos(board._arranging, 0))
	await _wait(0.2)
	await _shot("arrange_pick")
	board._arrange_done.emit()
	for i in 40:
		await _wait(0.25)
		_press("Смотреть руку")
		_press("В бой!")
		if board.mulligan_panel.visible:
			board._mulligan_done.emit(false)
		if main.game.phase == "main" and main.game.turn_player == 0 and not board._busy:
			break
	var g = main.game
	# A board with something on every seat.
	g.turn_number = 7
	for side in 4:
		for lane in [0, 2, 3]:
			var c = g._make_card(["evil_eye", "nice_ice_baby", "sharp_guy"][lane % 3], side)
			await g._put_creature(side, c, lane)
		var b = g._make_card("spirit_tower", side)
		await g._put_building(side, b, 1)
	for side in 4:
		await g.put_teamwork(side, g._make_card(["assistance", "camaraderie", "collaboration", "assistance"][side], side))
	# Жетоны: attack by the ATK badge, fire by the DEF badge.
	await g.add_atk_tokens(g.players[0].creatures[3], 2)
	await g.burn_creature(1, 0, 3, 2)
	g.players[1].creatures[0].exhausted = true
	await g.freeze(1, 1)
	await g.freeze(0, 1)
	board.sync()
	await _wait(1.0)
	await _shot("board")
	# A командная карта lies sideways and is shown upright in the preview.
	var tw = board.views[g.players[0].teamwork.uid]
	get_viewport().warp_mouse(board.world.get_global_transform_with_canvas() * tw.target_pos)
	await _wait(0.5)
	await _shot("teamwork_preview")
	# Drop targets of a creature in the hand.
	var hand_c = g._make_card("evil_eye", 0)
	g.players[0].hand.append(hand_c)
	g.players[0].actions = 2
	board.sync()
	await _wait(0.4)
	board._select(hand_c.uid)
	await _wait(0.4)
	print("drop targets: ", board._drop_targets.size())
	var t0 = board._drop_targets[0]
	print("drop target hit at its center: ", board._drop_target_at(t0["shape"]["c"]) != null)
	await _shot("drop_targets")
	board._clear_selection()
	# A target over every seat.
	var pick_done := {"v": null}
	var picker := func(): pick_done["v"] = await g.pick_creature(0, g.sides(), "Тест: выбери существо")
	picker.call()
	await _wait(0.6)
	await _shot("choice_creature")
	var opt = board._choice["options"][5]
	var target = g.slot(opt["p"], "creature", opt["lane"])
	get_viewport().warp_mouse(board.world.get_global_transform_with_canvas() * board.views[target.uid].position)
	await _wait(0.1)
	board._choice_click(board.views[target.uid].position)
	await _wait(0.3)
	print("picked by a click on the turned card: ", pick_done["v"] == opt)
	# A land choice.
	var land_done := {"v": null}
	var lander := func(): land_done["v"] = await g.pick_land(0, g.land_opts(g.sides()), "Тест: выбери землю")
	lander.call()
	await _wait(0.6)
	await _shot("choice_land")
	var lo = board._choice["options"][9]
	board._choice_click(board.land_pos(lo["p"], lo["lane"]))
	await _wait(0.3)
	print("land picked by a click on the turned land: ", land_done["v"] == lo)
	await _wait(0.5)
	get_tree().quit()
