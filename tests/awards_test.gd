extends SceneTree
## The tournament awards (scripts/ui/awards_shelf.gd, docs/AWARDS.md): the strings of a profile's
## "aw" that are cups and medals, the shelf in a player's profile card at a phone's size, a tap
## on the cup shows it big with its plate engraved, a tap beside closes it.
##   godot --path . --resolution 2400x1080 -s res://tests/awards_test.gd -- [pc]
## CW_SHOTS=<dir> keeps pictures. Exit code 1 when a check fails.

const MainScene := preload("res://scenes/main.tscn")
const Phone = preload("res://scripts/ui/phone.gd")
const AwardsShelf = preload("res://scripts/ui/awards_shelf.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")

var main
var fails := 0
var checks := 0
var phone := true


func _initialize() -> void:
	phone = not OS.get_cmdline_user_args().has("pc")
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	main = MainScene.instantiate()
	main.phone_layout = phone
	root.add_child(main)
	_run()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	var dir := OS.get_environment("CW_SHOTS")
	if dir == "":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var w := DisplayServer.window_get_size()
	root.get_texture().get_image().save_png(dir.path_join("%s_%s_%dx%d.png" % [name, "phone" if phone else "pc", w.x, w.y]))


func _finger(at: Vector2) -> void:
	Input.warp_mouse(at)
	for down in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = at
		t.pressed = down
		Input.parse_input_event(t)
		await process_frame
	await process_frame


func _px(c: Control) -> Rect2:
	var k := root.get_final_transform() * c.get_global_transform_with_canvas()
	return Rect2(k * Vector2.ZERO, (k * c.size) - (k * Vector2.ZERO))


func _run() -> void:
	await _wait(1.0)
	# The strings: three pictures, the rest stays a plate.
	var cup := AwardsShelf.parse("Кубок 07.11.2026 Ферн")
	ok(cup.get("place") == 1 and cup.get("date") == "07.11.2026" and cup.get("hero") == "fern", "the cup is read: %s" % [cup])
	ok(AwardsShelf.parse("Серебро 07.11.2026").get("place") == 2, "the silver medal is read")
	ok(AwardsShelf.parse("Бронза 07.11.2026").get("place") == 3, "the bronze medal is read")
	ok(AwardsShelf.parse("Чемпион").is_empty() and AwardsShelf.parse("Кубок вчера").is_empty(), "other awards are no pictures")
	ok(AwardsShelf.texture(AwardsShelf.parse("Кубок 01.01.2027 Джейк")) != null, "a cup of a hero without its picture still shows")
	ok(AwardsShelf.make(["Чемпион"]) == null, "no shelf without a cup or a medal")

	# A player's profile card (SocialPanel.show_profile's window) with the three and a plate.
	var p := {"nick": "COOKISH", "st": "off", "aw": ["Серебро 07.11.2026", "Кубок 07.11.2026 Ферн", "Бронза 07.11.2026", "Чемпион"],
		"best": 120, "w": 30, "l": 12, "pt": 36000, "since": 1793622911, "bio": "Пара слов о себе"}
	var layer := CanvasLayer.new()
	layer.layer = 12
	root.add_child(layer)
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WoodUI.window(34, 26))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(560, 0)
	panel.add_child(v)
	main.social_ui._fill_profile(v, p)
	await _wait(0.8)
	var shelf: Control = v.find_child("AwardsShelf", true, false)
	ok(shelf != null, "the profile has the shelf")
	if shelf == null:
		_end()
		return
	# A phone: the card is taller than the screen and is scrolled to its end, as a finger would.
	center.scroll_y = 100000.0
	center.queue_sort()
	await _wait(0.4)
	var pics := shelf.find_children("*", "TextureRect", true, false)
	ok(pics.size() == 3, "three awards stand on it (%d)" % pics.size())
	ok(pics.size() > 0 and pics[0].get_meta("award")["place"] == 1, "the cup stands first")
	var screen := Rect2(Vector2.ZERO, Vector2(DisplayServer.window_get_size()))
	for pic in pics:
		var r := _px(pic)
		ok(screen.encloses(r), "%s is on the screen (%s)" % [pic.tooltip_text, r])
		if phone:
			ok(minf(r.size.x, r.size.y) >= Phone.touch_px(), "%s is a finger big (%s, %.0f)" % [pic.tooltip_text, r.size, Phone.touch_px()])
	await _shot("profile")

	# A tap on the cup: big, «ПОБЕДИТЕЛЬ» on its plate, «1 место» beside; a tap beside closes it.
	await _finger(_px(pics[0]).get_center())
	await _wait(0.5)
	var zoom := root.find_child("CardZoom", true, false)
	ok(zoom != null, "a tap on the cup shows it big")
	if zoom != null:
		var texts := zoom.find_children("*", "Label", true, false).map(func(l): return l.text)
		ok(texts.has("ПОБЕДИТЕЛЬ") and texts.has("Турнир 07.11.2026"), "the plate is engraved: %s" % [texts])
		ok(texts.has("1 место"), "beside it: 1 место")
		await _shot("cup_big")
		await _finger(Vector2(8, DisplayServer.window_get_size().y * 0.5))
		await _wait(0.4)
		ok(not is_instance_valid(zoom) or zoom.is_queued_for_deletion(), "a tap beside closes it")
	await _finger(_px(pics[1]).get_center())
	await _wait(0.5)
	zoom = root.find_child("CardZoom", true, false)
	ok(zoom != null and zoom.find_children("*", "Label", true, false).any(func(l): return l.text == "2 место"), "a tap on the silver medal shows it, 2 место")
	await _shot("medal_big")
	_end()


func _end() -> void:
	print("awards_test: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)
