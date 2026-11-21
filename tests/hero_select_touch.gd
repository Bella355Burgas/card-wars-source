extends SceneTree
## The hero selection with a finger, as on a phone: a tap takes a hero card, a finger that
## moves scrolls the cards and takes nothing, a held finger shows a card's text in the note.
##   godot --path . --resolution 2400x1080 -s res://tests/hero_select_touch.gd

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")

var main
var fails := 0


func _initialize() -> void:
	# The real mouse of the PC that runs the test goes past the window: over it, it would hover
	# other cards than the finger.
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


## A point of a control in window pixels (touches come in window pixels).
func _at(c: Control) -> Vector2:
	return root.get_final_transform() * c.get_global_rect().get_center()


func _touch(at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = pressed
	Input.parse_input_event(e)
	await process_frame


func _drag(from: Vector2, by: Vector2, steps := 12) -> void:
	var at := from
	for k in steps:
		var e := InputEventScreenDrag.new()
		e.index = 0
		e.relative = by / steps
		at += by / steps
		e.position = at
		Input.parse_input_event(e)
		await process_frame


func _grid(grid_name: String) -> GridContainer:
	for g: GridContainer in main.overlay.find_children(grid_name, "GridContainer", true, false):
		if g.is_visible_in_tree():
			return g
	return null


func _note() -> String:
	for l: Label in main.overlay.find_children("*", "Label", true, false):
		if l.get_parent().name == "TextRoom" and l.is_visible_in_tree():
			return l.text
	return ""


func _run() -> void:
	await _wait(1.0)
	WoodUI.font_scale = 1.0           # the tiles where the test expects them, whatever the player set
	main._last_heroes = ["finn", "jake"]
	main.show_hero_select("hotseat")
	await _wait(1.0)
	var ids: Array = CardDB.hero_card_ids()
	var grid := _grid("HeroGrid")
	var scroll: ScrollContainer = grid.get_parent().get_parent()

	# A finger that moves over the cards scrolls them and takes none.
	var start := _at(grid.get_child(ids.find("bmo")))
	await _touch(start, true)
	await _drag(start, Vector2(0, -260))
	await _touch(start + Vector2(0, -260), false)
	await _wait(0.4)
	_check(scroll.scroll_vertical > 0, "a moving finger scrolls the cards (%d)" % scroll.scroll_vertical)
	_check(_grid("HeroGrid") != null and main._last_heroes[0] == "finn", "and takes no card")

	# A held finger shows the card's text and takes nothing (the list stops rolling first).
	await _wait(2.0)
	scroll.scroll_vertical = 0
	await _wait(0.3)
	var held := _at(grid.get_child(ids.find("marceline")))
	await _touch(held, true)
	await _wait(0.7)
	await _touch(held, false)
	await _wait(0.3)
	_check(_note() == CardDB.hero_card("marceline")["text"], "a held finger shows Марселин's text: «%s»" % _note().left(40))
	_check(_grid("HeroGrid") != null, "and stays on the hero step")

	# A tap takes the card: the deck step opens, the note shows the card taken.
	var tap := _at(grid.get_child(ids.find("bmo")))
	await _touch(tap, true)
	await _wait(0.1)
	await _touch(tap, false)
	await _wait(0.5)
	_check(_grid("DeckGrid") != null, "a tap takes Бимо's card and opens the deck step")
	_check(_note() == CardDB.hero_card("bmo")["text"], "the note shows the card taken: «%s»" % _note().left(40))
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
