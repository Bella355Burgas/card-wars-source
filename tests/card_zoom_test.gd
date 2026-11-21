extends SceneTree
## The card big over a list of cards (CardZoom), with the mouse and with a finger, at every
## «Масштаб»: a discard pile and a choice in a fight, the train's deck and a rest's
## «Выкинуть карту» with «Точно сбросить?» Да / Нет. The window must stay inside the screen.
##   godot --path . --resolution 2400x1080 -s res://tests/card_zoom_test.gd -- <output_dir> [zooms]

const MainScene := preload("res://scenes/main.tscn")
const TrainRun = preload("res://scripts/train/train_run.gd")

var out_dir := "user://shots_card_zoom"
var zooms: Array = [1.0, 1.5]
var main
var fails := 0
var tag := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		zooms = Array(args[1].split(",")).map(func(z): return float(z))
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	main = MainScene.instantiate()
	root.add_child(main)
	_run()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + tag + " " + what)
	if not ok:
		fails += 1


func _at(c: Control) -> Vector2:
	return root.get_final_transform() * (c.get_global_transform_with_canvas() * (c.size * 0.5))


func _mouse(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.button_mask = 0
	e.pressed = pressed
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)
	await process_frame


func _click(c: Control, button := MOUSE_BUTTON_LEFT) -> void:
	var at := _at(c)
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	Input.parse_input_event(m)
	await process_frame
	await _mouse(at, button, true)
	await _mouse(at, button, false)
	await _wait(0.3)


func _touch(at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = pressed
	Input.parse_input_event(e)
	await process_frame


func _hold(c: Control) -> void:
	await _touch(_at(c), true)
	await _wait(1.0)
	await _touch(_at(c), false)
	await _wait(0.4)


func _tap_at(at: Vector2) -> void:
	await _touch(at, true)
	await _wait(0.1)
	await _touch(at, false)
	await _wait(0.4)


## The open window: on the screen as a whole, with a big card.
func _window_ok(zoom: CanvasLayer, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, tag, name])
	var win: Control = zoom.find_children("*", "PanelContainer", true, false)[0]
	var t := win.get_global_transform_with_canvas()
	var r := Rect2(t.origin, win.size * t.get_scale())
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(1.0)
	var pic: Control = zoom.find_child("Card", true, false)
	var ph: float = pic.size.y * t.get_scale().y
	_check(screen.encloses(r) and ph > screen.size.y * 0.55, "%s: window inside the screen %s, card %d px high" % [name, r, ph])


## A click on the dim at the left edge of the screen, beside the window.
func _click_beside(zoom: CanvasLayer) -> void:
	var at := Vector2(6, root.get_visible_rect().size.y * 0.5)
	at = root.get_final_transform() * at
	await _mouse(at, MOUSE_BUTTON_LEFT, true)
	await _mouse(at, MOUSE_BUTTON_LEFT, false)
	await _wait(0.3)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, tag, name])


func _zoom_of(host: Node) -> CanvasLayer:
	for ch in host.get_children():
		if ch.name.begins_with("CardZoom") and not ch.is_queued_for_deletion():
			return ch
	return null


func _press(parent: Node, text: String) -> void:
	for b: Button in parent.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree():
			await _click(b)
			return
	_check(false, "no button " + text)


func _run() -> void:
	await _wait(1.0)
	var saved_zoom: float = main.ui_zoom
	for z: float in zooms:
		main.ui_zoom = z
		root.content_scale_factor = z
		main._layout()
		tag = "%d" % roundi(z * 100.0)
		await _train()
		await _fight()
	main._save_setting("ui", "zoom", saved_zoom)
	print("CARD ZOOM fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _close_overlays() -> void:
	for r in main.overlay.get_children():
		main._close_overlay(r)
	await _wait(0.4)


func _train() -> void:
	await _close_overlays()
	var run := TrainRun.new()
	run.save_path = "user://run_zoom_test.json"
	run.start("finn", 3)
	main.run = run
	main.show_run()
	await _wait(1.0)
	var rs = main.run_screen
	run.phase = "rest"
	run.current = {"kind": "rest"}
	rs.rebuild()
	await _wait(0.4)
	var size0: int = run.deck_size()

	rs._open_deck("")
	await _wait(0.8)
	await _shot("deck")
	var tiles: Array = rs._popup.find_children("*", "TextureRect", true, false).filter(
		func(t): return t.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND)
	await _click(tiles[0], MOUSE_BUTTON_RIGHT)
	var z := _zoom_of(rs)
	_check(z != null, "deck: the right button shows the card big")
	if z != null:
		await _window_ok(z, "deck_right")
		await _click_beside(z)
		_check(_zoom_of(rs) == null, "deck: a click beside closes it")
	await _hold(tiles[1])
	z = _zoom_of(rs)
	_check(z != null and run.deck_size() == size0, "deck: a held finger shows the card big")
	if z != null:
		await _tap_at(root.get_final_transform() * Vector2(6, root.get_visible_rect().size.y * 0.5))
		_check(_zoom_of(rs) == null, "deck: a tap beside closes it")
	rs._close_popup()

	rs._open_deck("remove")
	await _wait(0.8)
	tiles = rs._popup.find_children("*", "TextureRect", true, false).filter(
		func(t): return t.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND)
	await _hold(tiles[0])
	z = _zoom_of(rs)
	_check(z != null and z.find_children("*", "Button", true, false).is_empty() and run.deck_size() == size0,
		"rest: a held finger shows the card, throws nothing out")
	if z != null:
		await _tap_at(root.get_final_transform() * Vector2(6, root.get_visible_rect().size.y * 0.5))
	await _click(tiles[0])
	z = _zoom_of(rs)
	_check(z != null and z.find_children("*", "Button", true, false).size() == 2, "rest: a click asks «Точно сбросить?»")
	if z != null:
		await _window_ok(z, "rest_confirm")
		await _press(z, "Нет")
		_check(_zoom_of(rs) == null and run.deck_size() == size0, "rest: «Нет» keeps the card")
	await _click(tiles[0])
	z = _zoom_of(rs)
	if z != null:
		await _press(z, "Да")
	_check(run.deck_size() == size0 - 1, "rest: «Да» throws it out (%d → %d)" % [size0, run.deck_size()])
	DirAccess.remove_absolute("user://run_zoom_test.json")
	main.show_title()
	await _wait(0.6)


func _fight() -> void:
	main.start_new_game()
	await _wait(2.5)
	await _close_overlays()             # the coin toss: the board under it is enough here
	var b = main.board
	var g = main.game
	var ids := []
	for c in g.players[0].deck:
		ids.append(c.id)
	b._show_cards("Сброс", ids.slice(0, 8))
	await _wait(0.6)
	await _shot("discard")
	await _click(b.picker_grid.get_child(2), MOUSE_BUTTON_RIGHT)
	var z := _zoom_of(b.zoom_layer)
	_check(z != null, "discard: the right button shows the card big")
	if z != null:
		await _window_ok(z, "discard_right")
		await _click_beside(z)
	_check(_zoom_of(b.zoom_layer) == null and b.picker_layer.visible, "discard: a click beside closes it, the pile stays")
	await _hold(b.picker_grid.get_child(0))
	_check(_zoom_of(b.zoom_layer) != null, "discard: a held finger shows the card big")
	b._close_zoom()
	await _wait(0.2)

	var uids := []
	for c in g.players[0].deck.slice(0, 5):
		uids.append(c.uid)
	b._choice = {"kind": "card", "options": uids}
	b._choice_result = null
	b._open_picker({"kind": "card", "options": uids, "prompt": "Выбери карту"})
	await _wait(0.5)
	await _hold(b.picker_grid.get_child(1))
	_check(_zoom_of(b.zoom_layer) != null and b._choice_result == null, "choice: a held finger shows the card, takes nothing")
	b._close_zoom()
	b._choice = null
	b.picker_layer.visible = false
	await _wait(0.3)
	main.show_title()
	await _wait(0.6)
