extends "res://tests/zoom_test.gd"
## Field zoom on the table: the mouse wheel, a drag on bare table, a pinch of two fingers and a
## double click back. The hand keeps its place and size on the screen, the field never leaves
## its part of the screen, a card under the pointer is still found.
##   godot --path . --resolution 1600x900 -s res://tests/field_zoom_test.gd -- <output_dir> [zoom]


func _run() -> void:
	await _wait(1.0)
	var saved: float = main.ui_zoom
	_set_zoom(zooms[0] if not zooms.is_empty() else 1.0)
	main.start_new_game()
	await _wait(2.0)
	_press_curtain()
	for i in 2:
		await _wait(0.8)
		_press_curtain()
		await _wait(1.0)
		main.board._mulligan_done.emit(i == 1)
		await _wait(1.2)
	_press_curtain()
	await _wait(1.5)
	_press_curtain()
	await _wait(1.5)
	var b = main.board
	var p: int = main.game.turn_player
	var hv = b.views[main.game.players[p].hand[0].uid]
	var hand_before: Vector2 = hv.get_global_transform_with_canvas().origin
	var hand_scale: float = hv.get_global_transform_with_canvas().get_scale().x
	await _check("field_100")

	# The wheel over lane 2: the point under the pointer stays under it.
	var lane_board: Vector2 = b.creature_pos(p, 1)
	var lane_screen: Vector2 = b.get_global_transform_with_canvas() * lane_board
	for i in 5:
		_wheel(lane_screen, true)
		await process_frame
	await _wait(0.8)
	_expect(b._zoom > 1.9, "the wheel zooms the field (%.2f)" % b._zoom)
	var still: Vector2 = b.get_global_transform_with_canvas() * (b.world.transform * lane_board)
	_expect(still.distance_to(lane_screen) < 2.0, "the point under the wheel stays (%s -> %s)" % [lane_screen, still])
	var hand_now: Vector2 = hv.get_global_transform_with_canvas().origin
	_expect(hand_now.distance_to(hand_before) < 3.0 and absf(hv.get_global_transform_with_canvas().get_scale().x - hand_scale) < 0.01,
		"the hand keeps its place and size (%s -> %s)" % [hand_before, hand_now])
	_expect(b._view_at(hand_now) == hv, "a hand card is found under the pointer when zoomed")
	_expect(_covered(b), "the zoomed field covers its view")
	await _check("field_zoomed")

	# A drag on bare table moves the field; its release is no click.
	var bare: Vector2 = _bare_point(b)
	var pan0: Vector2 = b.world.position
	await _drag(bare, bare + Vector2(-300, -200))
	_expect(b.world.position.distance_to(pan0) > 50.0, "a drag on bare table moves the field")
	_expect(b._selected_uid == -1 and not b.context_menu.visible, "the drag's release clicked nothing")
	_expect(_covered(b), "the moved field still covers its view")
	await _drag(bare, bare + Vector2(3000, 3000))
	_expect(_covered(b), "a field moved far stops at its edge")
	await _check("field_moved")

	# Double click on bare table: the whole field again.
	bare = _bare_point(b)
	await _click(bare)
	var e := _button(bare, true)
	e.double_click = true
	root.push_input(e)
	root.push_input(_button(bare, false))
	await _wait(0.6)
	_expect(is_equal_approx(b._zoom, 1.0) and b.world.position.length() < 0.5, "a double click shows the whole field")

	# Two fingers: apart zooms in, the hand stays.
	var c: Vector2 = b.get_global_transform_with_canvas() * Vector2(840, 540)
	_touch(0, c + Vector2(-60, 0), true)
	_touch(1, c + Vector2(60, 0), true)
	for i in 10:
		_drag_touch(0, c + Vector2(-60 - i * 14, 0))
		_drag_touch(1, c + Vector2(60 + i * 14, 0))
		await process_frame
	_touch(0, c + Vector2(-200, 0), false)
	_touch(1, c + Vector2(200, 0), false)
	await _wait(0.8)
	_expect(b._zoom > 1.8, "a pinch zooms the field (%.2f)" % b._zoom)
	_expect(b._drag_view == null and b._selected_uid == -1, "a pinch takes and plays nothing")
	_expect(hv.get_global_transform_with_canvas().origin.distance_to(hand_before) < 3.0, "the hand stays through a pinch")
	await _check("field_pinched")
	main._save_setting("ui", "zoom", saved)
	print("ZOOM fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + tag + " " + what)
	if not ok:
		fails += 1


## The zoomed field fills its whole view: no bare edge shows.
func _covered(b) -> bool:
	var view := Rect2(Vector2.ZERO, b.FIELD_VIEW.size)
	var shown: Rect2 = b.world.transform * view
	return shown.grow(0.5).encloses(view)


## A screen point over the field with no card under it.
func _bare_point(b) -> Vector2:
	for y in range(200, 900, 37):
		for x in range(120, 1500, 41):
			var s: Vector2 = b.get_global_transform_with_canvas() * Vector2(x, y)
			if b._view_at(s) == null:
				return s
	return Vector2.ZERO


func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = root.get_final_transform() * at
	e.global_position = e.position
	return e


func _wheel(at: Vector2, up: bool) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = pressed
		e.factor = 1.0
		e.position = root.get_final_transform() * at
		e.global_position = e.position
		root.push_input(e)


func _drag(from: Vector2, to: Vector2) -> void:
	root.push_input(_button(from, true))
	await process_frame
	for i in range(1, 11):
		var m := InputEventMouseMotion.new()
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.position = root.get_final_transform() * from.lerp(to, i / 10.0)
		m.global_position = m.position
		root.push_input(m)
		await process_frame
	root.push_input(_button(to, false))
	await _wait(0.3)


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.pressed = pressed
	t.position = root.get_final_transform() * at
	root.push_input(t)


func _drag_touch(index: int, at: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = root.get_final_transform() * at
	root.push_input(d)


## Only the picture: a zoomed field is cut at its view, its cards may lie past the screen.
func _check(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, tag, name])
