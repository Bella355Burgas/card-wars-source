extends SceneTree
## The deck builder with a finger, as on a phone: a tap on a card adds a copy, a finger that
## moves scrolls the pool and adds nothing, a held finger shows the card big with «−» and «+»,
## «−» in the deck list takes a copy away, a tap on a land tile puts it on a lane.
##   godot --path . --resolution 2400x1080 -s res://tests/builder_touch.gd

const MainScene := preload("res://scenes/main.tscn")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")

var main
var fails := 0


func _initialize() -> void:
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	main = MainScene.instantiate()
	root.add_child(main)
	_run()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _at(c: Control) -> Vector2:
	return root.get_final_transform() * c.get_global_rect().get_center()


func _touch(at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = pressed
	Input.parse_input_event(e)
	await process_frame


func _tap(c: Control) -> void:
	await _touch(_at(c), true)
	await _wait(0.1)
	await _touch(_at(c), false)
	await _wait(0.3)


func _run() -> void:
	await _wait(1.0)
	WoodUI.font_scale = 1.0
	main.show_deck_builder("")
	await _wait(1.5)
	var r = main.overlay.get_child(main.overlay.get_child_count() - 1)
	var b = r.get_child(r.get_child_count() - 1)
	var ids: Array = []
	for id: String in b._tiles:
		if b._tiles[id]["box"].visible:
			ids.append(id)
	ids = b._sorted(ids)
	var first: String = ids[0]
	var tile: Control = b._tiles[first]["box"]

	await _tap(tile)
	_check(int(b._deck.get(first, 0)) == 1, "a tap adds a copy")
	await _tap(b._land_buttons["payable"])
	_check(b._only_payable, "a tap on a chip turns its filter on once")
	await _tap(b._land_buttons["payable"])
	_check(not b._only_payable, "the next tap turns it off")

	var at := _at(tile)
	await _touch(at, true)
	for k in 12:
		var e := InputEventScreenDrag.new()
		e.index = 0
		e.relative = Vector2(0, -25)
		at += e.relative
		e.position = at
		Input.parse_input_event(e)
		await process_frame
	await _touch(at, false)
	await _wait(2.0)
	_check(int(b._deck.get(first, 0)) == 1 and b._pool_scroll.scroll_vertical > 0, "a moving finger scrolls and adds nothing")
	b._pool_scroll.scroll_vertical = 0
	await _wait(0.3)

	await _touch(_at(tile), true)
	await _wait(1.0)
	await _touch(_at(tile), false)
	await _wait(0.4)
	_check(b._popup != null and b._inspect_id == first and int(b._deck.get(first, 0)) == 1, "a held finger shows the card")
	if b._inspect_plus != null:
		await _tap(b._inspect_plus)
		_check(int(b._deck.get(first, 0)) == 2, "«+» under the big card adds a copy")
		var shot := root.get_texture().get_image()
		shot.save_png("user://builder_touch_inspect.png")
	for btn: Button in b._popup.find_children("*", "Button", true, false) if b._popup != null else []:
		if btn.text == "Закрыть":
			await _tap(btn)
	_check(b._popup == null, "«Закрыть» closes the big card")

	var minus: Button = null
	for btn: Button in b._deck_list.find_children("*", "Button", true, false):
		if btn.text == "−":
			minus = btn
	await _tap(minus)
	_check(int(b._deck.get(first, 0)) == 1, "«−» in the deck list takes a copy away")

	var palette: Control = b._field.find_child("Palette", true, false)
	var corn: Control = null
	for t: Control in palette.get_children():
		if t.tooltip_text == "Кукурузные поля" or t.tooltip_text.to_lower().contains("кукуруз"):
			corn = t
	await _tap(corn)
	_check(b._lands.count("corn") == 1, "a tap on a land tile puts it on a lane: %s" % [b._lands])
	await _tap(corn)
	_check(b._lands.count("corn") == 2, "the next tap on the next lane: %s" % [b._lands])

	print("BUILDER TOUCH fails=%d" % fails)
	quit(1 if fails > 0 else 0)
