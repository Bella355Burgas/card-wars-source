extends SceneTree
## Interface scale («Масштаб» in the settings): every screen at every step, with a check that
## no button or text leaves the screen, and screenshots.
##   godot --path . --resolution 2400x1080 -s res://tests/zoom_test.gd -- <output_dir> [zooms] [fonts] [phone]
## zooms: comma separated (default all steps, e.g. 1,1.5). fonts: «Шрифт» steps for the hero
## selection, comma separated (default 1; the other screens are checked with the first one).

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const Phone = preload("res://scripts/ui/phone.gd")

var out_dir := "user://shots_zoom"
var zooms: Array = []
var fonts: Array = [1.0]
var main
var fails := 0
var tag := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		for z in args[1].split(","):
			zooms.append(float(z))
	if args.size() > 2:
		fonts = []
		for f in args[2].split(","):
			fonts.append(float(f))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var phone := args.size() > 3 and args[3] == "phone"
	# The real mouse of the PC that runs the test goes past the window: over it, it would hover
	# other buttons than the test's clicks.
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	main = MainScene.instantiate()
	main.phone_layout = phone          # the table of a phone: its middle, bigger
	root.add_child(main)
	if zooms.is_empty():
		zooms = main.zooms()
	_run()


func _set_zoom(z: float) -> void:
	main.ui_zoom = z
	main.apply_zoom()        # a phone: twice as big (scripts/ui/phone.gd)
	tag = "%d" % roundi(z * 100.0)


func _wait(t: float) -> void:
	await create_timer(t).timeout


## Screenshot, then every visible button and text must be inside the screen.
func _check(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, tag, name])
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(2.0)
	var bad := []
	for c: Node in main.find_children("*", "Control", true, false):
		if not (c is Button or c is Label or c is LineEdit or c is TextureRect) or not c.is_visible_in_tree():
			continue
		# The swaying title is a screen-wide box around a centered text.
		if c.name == "Title" or _in_scroll(c) or _in_tall_window(c):
			continue
		var r: Rect2 = _screen_rect(c)
		if r.size.x < 1.0 or r.size.y < 1.0 or c.modulate.a == 0.0:
			continue
		# Windows over the table keep off the very edge (on a phone it is under the cutout).
		var room := screen if c.get_canvas_layer_node() == null else screen.grow(-10.0)
		if r.size.x >= screen.size.x - 8.0 and r.size.y >= screen.size.y - 8.0:
			continue                  # a background over the whole screen
		if not room.encloses(r):
			bad.append("%s «%s» %s" % [c.get_class(), c.get("text") if c.get("text") != null else "", r])
	if bad.is_empty():
		print("OK   %s %s" % [tag, name])
	else:
		fails += 1
		print("FAIL %s %s: %d out of the screen" % [tag, name, bad.size()])
		for b in bad.slice(0, 6):
			print("       ", b)


## A grid of the hero selection takes no more columns than its page shows (none cut at the side).
func _check_grid(grid_name: String) -> void:
	for g: GridContainer in main.overlay.find_children(grid_name, "GridContainer", true, false):
		if not g.is_visible_in_tree():
			continue
		var page: Control = g.get_parent().get_parent().get_parent()     # grid < margin < scroll < pages
		var pr := _screen_rect(page)
		var gr := _screen_rect(g)
		var ok := gr.position.x >= pr.position.x - 2.0 and gr.end.x <= pr.end.x + 2.0     # it scrolls down
		print(("OK   " if ok else "FAIL ") + "%s %s %d columns" % [tag, grid_name, g.columns], "" if ok else " %s %s" % [pr, gr])
		if not ok:
			fails += 1


## Every hero card's text fits the text panel of the hero selection, and the panel keeps its size.
func _check_card_texts() -> void:
	var grid: GridContainer = main.overlay.find_children("HeroGrid", "GridContainer", true, false)[0]
	var panel_h := -1.0
	var bad := []
	for tile: Control in grid.get_children():
		tile.mouse_entered.emit()
		await process_frame
		var room: Control = null
		for l: Label in main.overlay.find_children("*", "Label", true, false):
			if l.get_parent().name == "TextRoom" and l.is_visible_in_tree():
				room = l.get_parent()
				if l.size.y > room.size.y + 1.0:
					bad.append("%s %d" % [l.text.left(30), l.label_settings.font_size])
		var panel: Control = room.get_parent().get_parent()
		var h: float = panel.size.y
		if panel_h >= 0.0 and not is_equal_approx(h, panel_h):
			bad.append("panel height %s -> %s" % [panel_h, h])
		panel_h = h
		var cut := await _ink_below(room, panel)
		if cut != "":
			bad.append("%s: %s" % [tile.get_child(0).get_child(1).text, cut])
		tile.mouse_exited.emit()
	print(("OK   " if bad.is_empty() else "FAIL ") + "%s card texts fit" % tag, "" if bad.is_empty() else " %s" % [bad.slice(0, 5)])
	if not bad.is_empty():
		fails += 1


## Letters drawn between the bottom of the note's text room and the note's edge, in window
## pixels: there must be none (a letter there sits on the edge or is cut by it).
func _ink_below(room: Control, panel: Control) -> String:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var k := root.get_final_transform()
	var r := k * _screen_rect(room)
	var p := k * _screen_rect(panel)
	var edge := 7.0 * k.get_scale().y            # the hand-drawn outline and its wobble
	for y in range(int(r.end.y) + 1, int(p.end.y - edge)):
		for x in range(int(r.position.x), int(r.end.x), 2):
			var c := img.get_pixel(x, y)
			if c.r < 0.5 and c.g < 0.42 and c.b < 0.38:
				return "ink at %d, %d (text room ends at %d, the note at %d)" % [x, y, int(r.end.y), int(p.end.y)]
	return ""


func _screen_rect(c: Control) -> Rect2:
	var t := c.get_global_transform_with_canvas()
	return Rect2(t.origin, c.size * t.get_scale()).abs()


## A phone: a window taller than the screen scrolls under the finger (FitCenter).
func _in_tall_window(c: Node) -> bool:
	var p := c.get_parent()
	while p != null and p != main:
		if p.has_method("can_scroll") and p.can_scroll():
			return true
		p = p.get_parent()
	return false


func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p != null and p != main:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


## Press and release of the left button at a point of the screen, through the window input.
func _click(at: Vector2) -> void:
	var px := root.get_final_transform() * at
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = px
		e.global_position = px
		root.push_input(e)
		await process_frame


func _press_curtain() -> void:
	for r in main.overlay.get_children():
		for b in r.find_children("*", "Button", true, false):
			if b.is_visible_in_tree() and not b.disabled:
				b.pressed.emit()
				return


## «Связь потеряна» in a relay game, at every «Шрифт» step: «Переподключиться» and «Выйти в
## меню» both show, apart (they used to lie on one spot).
func _link_lost_check() -> void:
	var z_tag := tag
	for f in WoodUI.FONTS:
		WoodUI.font_scale = f
		tag = z_tag + ("" if f == 1.0 else "_font%d" % roundi(f * 100.0))
		var was: String = main.net.mode
		main.net.mode = "relay"
		main.lobby._show_link_lost()
		main.net.mode = was
		await _wait(0.5)
		await _check("link_lost")
		var btns := []
		for btn: Button in main._link_root.find_children("*", "Button", true, false):
			if btn.is_visible_in_tree():
				btns.append(btn)
		var ok := btns.size() == 2 and not _screen_rect(btns[0]).intersects(_screen_rect(btns[1]))
		print(("OK   " if ok else "FAIL ") + tag + " link lost buttons apart", "" if ok else " %s" % [btns.map(func(x): return [x.text, _screen_rect(x)])])
		if not ok:
			fails += 1
		main.lobby._close_link_overlay()
		await _wait(0.4)
	WoodUI.font_scale = 1.0
	tag = z_tag


func _close_overlays() -> void:
	for r in main.overlay.get_children():
		main._close_overlay(r)
	await _wait(0.4)


## The hero selection in every mode, both steps.
func _hero_select_checks() -> void:
	main.show_hero_select("hotseat")
	await _wait(0.8)
	await _check("hero_select")
	await _close_overlays()
	for mode in ["teams", "ai", "run"]:
		main.show_hero_select(mode)
		await _wait(0.8)
		await _check("hero_select_" + mode)
		_check_grid("HeroGrid")
		if mode == "teams":
			await _check_card_texts()
		for btn in main.overlay.find_children("*", "Button", true, false):
			if btn.text == "2  Колода":
				btn.pressed.emit()
		await _wait(0.5)
		await _check("hero_select_%s_deck" % mode)
		_check_grid("DeckGrid")
		await _close_overlays()


## The menus and windows at the zoom z (with the «Шрифт» step set before).
func _menu_checks(z: float) -> void:
	await _check("title")
	main.show_play_menu()
	await _wait(0.5)
	await _check("play")
	await _close_overlays()
	main.show_settings()
	await _wait(0.5)
	await _check("settings")
	# A real click on «Масштаб» reaches the button in the scaled window and steps the scale.
	var zb: Button = null
	for btn in main.overlay.find_children("*", "Button", true, false):
		if btn.text.begins_with("Масштаб"):
			zb = btn
	await _click(_screen_rect(zb).get_center())
	var steps: Array = main.zooms()
	var want: float = steps[(steps.find(z) + 1) % steps.size()]
	var ok: bool = is_equal_approx(main.ui_zoom, want) and is_equal_approx(root.content_scale_factor, Phone.content_scale(want))
	print(("OK   " if ok else "FAIL ") + tag + " click on the scale button", "" if ok else " %s %s %s" % [_screen_rect(zb), main.ui_zoom, root.gui_get_hovered_control()])
	if not ok:
		fails += 1
	var t := tag
	_set_zoom(z)
	tag = t
	await _close_overlays()
	main._pick_background(func(): pass)
	await _wait(0.5)
	await _check("background")
	await _close_overlays()
	main.show_rules()
	await _wait(0.5)
	await _check("rules")
	await _close_overlays()
	main.show_replays()
	await _wait(0.5)
	await _check("replays")
	await _close_overlays()
	main.show_net_lobby()
	await _wait(0.6)
	await _check("lobby")
	await _close_overlays()
	main.show_login()
	await _wait(0.5)
	await _check("login")
	await _close_overlays()
	if main.account.logged_in():
		main.show_profile()
		await _wait(0.5)
		await _check("profile")
		for btn in main.overlay.find_children("*", "Button", true, false):
			if btn.text == "Сменить аватарку":
				btn.pressed.emit()
		await _wait(0.3)
		await _check("profile_avatars")
		await _close_overlays()


func _run() -> void:
	await _wait(1.0)
	var saved: float = main.ui_zoom
	for z in zooms:
		_set_zoom(z)
		await _wait(0.3)
		var z_tag := tag
		for f in fonts:
			WoodUI.font_scale = f
			tag = z_tag + ("" if f == 1.0 else "_font%d" % roundi(f * 100.0))
			main.show_title()
			await _wait(0.4)
			await _menu_checks(z)
			await _hero_select_checks()
		WoodUI.font_scale = 1.0
		tag = z_tag
		main.show_title()
		main.show_deck_builder("")
		await _wait(1.2)
		await _check("deck_builder")
		await _close_overlays()
		main.start_new_game()
		await _wait(2.0)
		await _check("coin")
		_press_curtain()
		for i in 2:
			await _wait(0.8)
			_press_curtain()
			await _wait(1.0)
			if i == 0:
				await _check("mulligan")
			main.board._mulligan_done.emit(i == 1)
			await _wait(1.2)
		_press_curtain()
		await _wait(1.5)
		_press_curtain()
		await _wait(1.0)
		await _check("board")
		var b = main.board
		var p: int = main.game.turn_player
		b._open_inspect(main.game.players[p].hand[0].id)
		await _wait(0.5)
		await _check("inspect")
		b._close_inspect()
		var ids := []
		for c in main.game.players[p].deck:
			ids.append(c.id)
		b._show_cards("Колода", ids)
		await _wait(0.6)
		await _check("picker")
		b.picker_layer.visible = false
		main.show_pause()
		await _wait(0.5)
		await _check("pause")
		await _close_overlays()
		await _link_lost_check()
		main._on_game_over(0)
		await _wait(1.5)
		await _check("game_over")
		await _close_overlays()
		main.show_title()
		await _wait(0.5)
	main._save_setting("ui", "zoom", saved)
	print("ZOOM fails=%d" % fails)
	quit(1 if fails > 0 else 0)
