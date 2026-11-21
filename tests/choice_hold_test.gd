extends "res://tests/zoom_test.gd"
## A card chosen from the hand (a discard the opponent forces): the press only starts the pick,
## the release picks. A held finger (or the right button) looks at the card and picks nothing.
##   godot --path . --resolution 1600x900 -s res://tests/choice_hold_test.gd -- <output_dir>

const TouchInput = preload("res://scripts/ui/touch_input.gd")


func _run() -> void:
	await _wait(1.0)
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
	var p: int = b.viewer
	var hand: Array = main.game.players[p].hand
	var uids := hand.map(func(c): return c.uid)
	var hv = b.views[uids[0]]
	var at: Vector2 = hv.get_global_transform_with_canvas().origin
	var req := {"kind": "hand_card", "player": p, "options": uids, "prompt": "Сбрось карту"}
	var got := []
	(func():
		var r = await b._local_choice(req)
		got.append(r)).call()
	await process_frame
	await process_frame
	_expect(b._choice != null, "the choice is asked")

	# The press alone picks nothing.
	await _move(at)
	await process_frame
	Input.parse_input_event(_button(at, true))
	await _wait(0.2)
	_expect(b._choice != null and got.is_empty(), "a pressed card is not picked yet")

	# A held finger: the right button looks at the card, the release after it picks nothing.
	TouchInput.long_pressed = true
	await _move(at)
	var rb := _button(at, true)
	rb.button_index = MOUSE_BUTTON_RIGHT
	Input.parse_input_event(rb)
	await _wait(0.2)
	_expect(b.inspect_layer.visible, "a held card opens its big picture")
	Input.parse_input_event(_button(at, false))
	await _wait(0.2)
	_expect(b._choice != null and got.is_empty(), "the release of a held finger picks nothing")
	TouchInput.long_pressed = false
	b._close_inspect()
	await _wait(0.2)

	# A finger that moved away picks nothing.
	Input.parse_input_event(_button(at, true))
	await process_frame
	await _move(at + Vector2(0, -200))
	Input.parse_input_event(_button(at + Vector2(0, -200), false))
	await _wait(0.2)
	_expect(b._choice != null and got.is_empty(), "a press dragged away picks nothing")

	# The right button on a card, then a plain tap: the card goes.
	await _move(at)
	await _click(at)
	await _wait(0.3)
	_expect(got.size() == 1 and got[0] == uids[0], "a tap picks the card (%s)" % [got])
	print("CHOICE HOLD fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


## The pointer comes to a point first, as a real mouse or finger does.
func _move(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = root.get_final_transform() * at
	m.global_position = m.position
	Input.warp_mouse(m.position)
	Input.parse_input_event(m)
	await process_frame


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		Input.parse_input_event(_button(at, pressed))
		await process_frame


func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = root.get_final_transform() * at
	e.global_position = e.position
	return e
