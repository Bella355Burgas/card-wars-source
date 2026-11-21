extends SceneTree
## The cards a «reveal» opens fly out by the lanes face up (windowed):
##   godot --path . -s res://tests/shots_reveal.gd -- <output_dir>
## Галантный броненосец opens the top card and the player picks its lane; Газы огра opens three.

const MainScene := preload("res://scenes/main.tscn")

var out_dir := "user://shots_reveal"
var n := 0
var main


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	root.get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, shot_name])
	print("shot ", shot_name)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _press(text: String) -> void:
	for b in main.overlay.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()


func _run() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	await _wait(1.0)
	main.start_new_game(["fern", "flame_princess"])
	var board = null
	for i in 60:
		await _wait(0.25)
		_press("Дальше")
		_press("Смотреть руку")
		_press("Я ")
		_press("Начать ход")
		_press("В бой!")
		board = main.board
		if board == null:
			continue
		if board.arrange_panel.visible:
			board._arrange_done.emit()
		if board.mulligan_panel.visible:
			board._mulligan_done.emit(false)
		if main.game.phase == "main" and not board._busy and not board.arrange_panel.visible and i > 20:
			break
	var g = main.game
	var p: int = g.turn_player
	g.turn_number = 5
	g.players[p].actions = 5
	for l in 4:
		g.players[p].lands[l]["type"] = "cute"
	await g._put_creature(p, g._make_card("cow", p), 0)
	g.players[p].deck.append(g._make_card("archer_dan", p))
	var ga = g._make_card("gallant_armourdillo", p)
	g.players[p].hand.append(ga)
	board.sync()
	await _wait(0.6)
	g.cmd_play(p, ga.uid, 0)
	await _wait(1.6)
	await _shot("gallant_reveal")
	await _wait(3.0)
	await _shot("gallant_still_choosing")
	while board._choice != null:
		board._resolve_choice(board._choice["options"][0])
		await _wait(0.5)
	await _wait(1.0)
	# Газы огра: two of the three go to the discard, the kept one goes back under the deck
	# and must leave the show too (it used to stay by the lanes for the rest of the game).
	for id in ["cow", "archer_dan", "cow"]:
		g.players[p].deck.append(g._make_card(id, p))
	var gas = g._make_card("ogre_gas", p)
	g.players[p].hand.append(gas)
	board.sync()
	await _wait(0.6)
	g.cmd_play(p, gas.uid, -1)
	await _wait(1.6)
	await _shot("ogre_gas_reveal")
	while board._choice == null:
		await _wait(0.2)
	board._resolve_choice(board._choice["options"][0])
	await _wait(4.0)
	await _shot("ogre_gas_after")
	var ok: bool = board._revealed.is_empty()
	print("OGRE_GAS ", "OK" if ok else "FAIL revealed=%s" % [board._revealed])
	quit(0 if ok else 1)
