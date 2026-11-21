extends SceneTree
## Taps of a finger on the hero select, the way a phone sends them (screen touches in window
## pixels, Godot makes the left button of them). The hero list scrolls, so TouchInput holds
## the press and gives it back on release: the tile must still get it when the window is
## not 1080 high (a phone at 1440 or a lowered game resolution).
##   godot --path . --resolution 1440x720 -s res://tests/touch_test.gd
##   godot --path . --resolution 2400x1080 -s res://tests/touch_test.gd

const MainScene := preload("res://scenes/main.tscn")

var main
var fails := 0
var hit: Control = null   # the tile the last left press reached


func _initialize() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	_run()


func _wait(t: float) -> void:
	await create_timer(t).timeout


## A finger down and up at a point of the screen (canvas units), sent in window pixels.
func _tap(at: Vector2, drift := Vector2.ZERO) -> void:
	var px := root.get_final_transform() * at
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = px
	Input.parse_input_event(down)
	await process_frame
	if drift != Vector2.ZERO:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = px + drift
		drag.relative = drift
		Input.parse_input_event(drag)
		await process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = px + drift
	Input.parse_input_event(up)
	await process_frame
	await process_frame


func _center(c: Control) -> Vector2:
	var t := c.get_global_transform_with_canvas()
	return t.origin + c.size * t.get_scale() / 2.0


func _pages() -> Array:
	var out := []
	for sc: Node in main.overlay.find_children("*", "ScrollContainer", true, false):
		out.append(sc)
	return out


func _watch(tiles: Array) -> void:
	hit = null
	for t: Control in tiles:
		t.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				hit = t)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("OK   ", what)
	else:
		fails += 1
		print("FAIL ", what)


func _run() -> void:
	await _wait(1.0)
	print("window ", root.size, " scale ", root.get_final_transform().get_scale())
	main.show_hero_select("ai")
	await _wait(0.6)
	var pages := _pages()
	var hero_page: ScrollContainer = pages[0]
	var deck_page: ScrollContainer = pages[1]
	var scrolls: bool = hero_page.get_v_scroll_bar().max_value > hero_page.size.y + 1
	print("hero list scrolls: ", scrolls)
	var tiles: Array = hero_page.get_child(0).get_child(0).get_children()
	_watch(tiles)
	await _tap(_center(tiles[4]), Vector2(3, 2))
	await _wait(0.4)
	_check(hit == tiles[4] and deck_page.visible, "a tap on a hero picks that hero")
	await _wait(0.3)
	# A deck goes to the first seat, then the second seat picks its hero.
	var deck_tiles: Array = deck_page.get_child(0).get_child(0).get_children()
	print("deck list scrolls: ", deck_page.get_v_scroll_bar().max_value > deck_page.size.y + 1)
	_watch(deck_tiles)
	await _tap(_center(deck_tiles[1]))
	await _wait(0.4)
	_check(hit == deck_tiles[1] and hero_page.visible, "a tap on a deck takes that deck")
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
