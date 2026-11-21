extends SceneTree
## The deck builder at every «Масштаб» and «Шрифт» step: screenshots of the empty and the
## filled deck, the «Поле» tab of a narrow screen, the held card and the windows over it,
## with a check that no button or text leaves the screen (windowed):
##   godot --path . --resolution 2400x1080 -s res://tests/builder_layout.gd -- <output_dir> [zooms] [fonts]

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")

var out_dir := "user://shots_builder"
var zooms: Array = [1.0, 1.5]
var fonts: Array = [1.0, 1.3]
var main
var fails := 0
var tag := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		zooms = Array(args[1].split(",")).map(func(z): return float(z))
	if args.size() > 2:
		fonts = Array(args[2].split(",")).map(func(f): return float(f))
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	main = MainScene.instantiate()
	root.add_child(main)
	_run()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _screen_rect(c: Control) -> Rect2:
	var t := c.get_global_transform_with_canvas()
	return Rect2(t.origin, c.size * t.get_scale()).abs()


func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p != null and p != main:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _check(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, tag, name])
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-8.0)
	var bad := []
	for c: Node in main.overlay.find_children("*", "Control", true, false):
		if not (c is Button or c is Label or c is LineEdit) or not c.is_visible_in_tree() or _in_scroll(c):
			continue
		var r := _screen_rect(c)
		if r.size.x < 1.0 or c.modulate.a == 0.0:
			continue
		if not screen.encloses(r):
			bad.append("%s «%s» %s" % [c.get_class(), c.get("text"), r])
		elif c is Button and not c.text.is_empty() and c.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING \
				and c.get_theme_font("font").get_string_size(c.text, 0, -1, c.get_theme_font_size("font_size")).x > c.size.x:
			bad.append("cut %s «%s»" % [c.get_class(), c.text])
	print(("OK   " if bad.is_empty() else "FAIL ") + "%s %s" % [tag, name], "" if bad.is_empty() else " %s" % [bad.slice(0, 6)])
	if not bad.is_empty():
		fails += 1


func _builder() -> Control:
	var r = main.overlay.get_child(main.overlay.get_child_count() - 1)
	return r.get_child(r.get_child_count() - 1)


func _run() -> void:
	await _wait(1.0)
	var saved_zoom: float = main.ui_zoom
	for z: float in zooms:
		main.ui_zoom = z
		root.content_scale_factor = z
		main._layout()
		for f: float in fonts:
			WoodUI.font_scale = f
			tag = "%d_font%d" % [roundi(z * 100.0), roundi(f * 100.0)]
			main.show_deck_builder("")
			await _wait(1.6)
			var b := _builder()
			await _check("empty")
			b._set_hero("jake_2x2")       # the longest hero name
			for lane in 4:
				b._set_land(lane, "corn" if lane < 3 else "sandy")
			var added := 0
			for id in CardDB.card_ids():
				var d := CardDB.get_def(id)
				if d["land"] == "corn" and int(d["cost"]) <= 2 and added < 16:
					b._add(id, 3 if added % 3 == 0 else 1)
					added += 1
			b._say("Сохранено: «Моя колода»")
			await _wait(1.2)
			await _check("filled")
			if b._narrow:
				b._show_page(true)
				await _wait(0.3)
				await _check("field_tab")
				b._show_page(false)
			b._inspect(b._deck.keys()[0])
			await _wait(0.8)
			await _check("inspect")
			b._inspect("assistance")
			await _wait(0.8)
			await _check("inspect_wide")
			b._show_decks()
			await _wait(0.4)
			await _check("decks")
			b._show_sets()
			await _wait(0.4)
			await _check("sets")
			b._show_heroes()
			await _wait(0.8)
			await _check("heroes")
			b._show_hero("jake_2x2")
			await _wait(0.8)
			await _check("hero")
			b._show_hero("betty")         # the longest ability, no deck of its own
			await _wait(0.8)
			await _check("hero_long")
			b._copy_hero_deck("jake_2x2")
			b._set_hero("baby_finn_and_jake")
			b._refresh()
			await _wait(0.8)
			await _check("hero_copy")
			b._close_popup()
			main._close_overlay(main.overlay.get_child(main.overlay.get_child_count() - 1))
			await _wait(0.4)
	WoodUI.font_scale = 1.0
	main._save_setting("ui", "zoom", saved_zoom)
	print("BUILDER fails=%d" % fails)
	quit(1 if fails > 0 else 0)
