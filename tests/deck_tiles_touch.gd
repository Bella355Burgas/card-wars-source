extends SceneTree
## The deck step of the hero selection with a finger when own decks exist: their tiles have an
## «Изменить» button. A finger that goes down on it and moves scrolls the list, a tap opens the builder.
##   godot --path . --resolution 2400x1080 -s res://tests/deck_tiles_touch.gd -- [shot dir] [«Масштаб», e.g. 1.5]

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")
const CustomDecks = preload("res://scripts/core/custom_decks.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")

const NAMES := ["ТЕСТ колода 1", "ТЕСТ колода 2", "ТЕСТ колода 3"]

var main
var fails := 0
var shot_dir := ""
var zoom := 1.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		shot_dir = args[0]
		DirAccess.make_dir_recursive_absolute(shot_dir)
	if args.size() > 1:
		zoom = float(args[1])
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


func _shot(name: String) -> void:
	if shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [shot_dir, name])


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


func _edit_buttons() -> Array:
	return main.overlay.find_children("*", "Button", true, false).filter(
		func(b: Button): return b.text == "Изменить" and b.is_visible_in_tree())


func _run() -> void:
	await _wait(1.0)
	WoodUI.font_scale = 1.0
	main.ui_zoom = zoom
	root.content_scale_factor = zoom
	main._layout()
	var lands := ["plain", "plain", "plain", "plain"]
	var ids: Array = CardDB.card_ids()
	for n in NAMES:
		var deck := {}
		for i in 40:
			deck[ids[i]] = 1
		CustomDecks.put({"name": n, "lands": lands, "deck": deck})
	main._last_heroes = ["finn", "jake"]
	main.show_hero_select("hotseat")
	await _wait(1.0)
	var heroes := _grid("HeroGrid")
	await _touch(_at(heroes.get_child(0)), true)
	await _wait(0.1)
	await _touch(_at(heroes.get_child(0)), false)
	await _wait(1.0)
	var grid := _grid("DeckGrid")
	_check(grid != null, "the deck step is open")
	var scroll: ScrollContainer = grid.get_parent().get_parent()
	var edits := _edit_buttons()
	var raised: Array = main.overlay.find_children("*", "Control", true, false).filter(
		func(c: Control): return c.z_index != 0 and grid.is_ancestor_of(c))
	_check(raised.is_empty(), "no tile part has a z_index: it would show through a window over the tiles (%d)" % raised.size())
	_check(edits.size() == NAMES.size(), "an «Изменить» button on each own deck (%d)" % edits.size())
	await _shot("deck_step")
	var view: Rect2 = scroll.get_global_rect()
	print("scroll rect ", view, " content ", scroll.get_v_scroll_bar().max_value)
	for b: Button in edits:
		print("edit ", b.get_global_rect(), " inside view: ", view.encloses(b.get_global_rect()))

	# A finger down on «Изменить» that moves scrolls the list and does not press the button.
	var opened := [false]
	main.overlay.child_entered_tree.connect(func(_n): opened[0] = true)
	var target: Button = edits[0]
	scroll.scroll_vertical = 0
	var start := _at(target)
	await _touch(start, true)
	await _drag(start, Vector2(0, -260))
	await _touch(start + Vector2(0, -260), false)
	await _wait(0.4)
	_check(scroll.scroll_vertical > 0, "a finger moving from «Изменить» scrolls the decks (%d)" % scroll.scroll_vertical)
	_check(not opened[0] and _grid("DeckGrid") != null, "and does not open the builder")
	await _shot("after_drag")

	# Every «Изменить» of the list, brought to the middle of the view, lets the finger scroll.
	await _wait(2.0)
	for i in edits.size():
		scroll.scroll_vertical = 0
		await _wait(0.3)
		var b: Button = _edit_buttons()[i]
		scroll.scroll_vertical = maxi(0, roundi(b.global_position.y - view.position.y - view.size.y * 0.5) + scroll.scroll_vertical)
		await _wait(0.3)
		var inside := view.encloses(b.get_global_rect())
		var before := scroll.scroll_vertical
		var at := _at(b)
		await _touch(at, true)
		await _drag(at, Vector2(0, 120))
		await _touch(at + Vector2(0, 120), false)
		await _wait(1.0)
		_check(inside and scroll.scroll_vertical < before, "a drag down from button %d scrolls the list back (%d -> %d)" % [i + 1, before, scroll.scroll_vertical])
		await _wait(0.5)

	# The builder opened from here (as in the modes) lies over the hero selection: its card
	# pool scrolls under the finger, the tiles below take nothing and show nothing through.
	scroll.scroll_vertical = 0
	await _wait(0.3)
	var edit: Button = _edit_buttons()[0]
	var below := scroll.scroll_vertical
	edit.pressed.emit()
	await _wait(1.5)
	var builder = null
	for n in main.overlay.find_children("*", "Control", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("deck_builder.gd"):
			builder = n
	_check(builder != null, "the builder is open over the deck step")
	await _shot("builder_over")
	if builder != null:
		var pool: ScrollContainer = builder._pool_scroll
		_check(pool != null and pool.is_visible_in_tree(), "its card pool is shown")
		var from := _at(pool)
		var pool_before := pool.scroll_vertical
		await _touch(from, true)
		await _drag(from, Vector2(0, -260))
		await _touch(from + Vector2(0, -260), false)
		await _wait(0.5)
		_check(pool.scroll_vertical > pool_before, "a finger moving over the card pool scrolls the pool (%d -> %d)" % [pool_before, pool.scroll_vertical])
		_check(scroll.scroll_vertical == below, "and not the deck list under it (%d)" % scroll.scroll_vertical)

	for n in NAMES:
		CustomDecks.remove(n)
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
