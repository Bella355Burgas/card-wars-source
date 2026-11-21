extends SceneTree
## «С героем» / «Без героя» in the hero selection of every game that has it (not the train):
## the switch is on each seat, turns the pick into "deck@" and back to the card it had, a deck
## picked keeps it; every button and text stays on the screen. Screenshots go to <output_dir>.
##   godot --path . --resolution 2400x1080 -s res://tests/shots_no_hero.gd -- <output_dir>

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")

var out_dir := "user://shots_no_hero"
var main
var fails := 0
var checks := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	main = MainScene.instantiate()
	root.add_child(main)
	_run()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


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
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(2.0)
	var bad := []
	for c: Node in main.find_children("*", "Control", true, false):
		if not (c is Button or c is Label) or not c.is_visible_in_tree() or _in_scroll(c) or c.name == "Title":
			continue
		var r := _screen_rect(c)
		if r.size.x < 1.0 or r.size.y < 1.0 or c.modulate.a == 0.0:
			continue
		if r.size.x >= screen.size.x - 8.0 and r.size.y >= screen.size.y - 8.0:
			continue
		if not screen.encloses(r):
			bad.append("%s «%s» %s" % [c.get_class(), c.get("text"), r])
	ok(bad.is_empty(), "%s: %d out of the screen %s" % [name, bad.size(), bad.slice(0, 4)])
	print("shot ", name)


func _switches() -> Array:
	return main.overlay.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() \
		and (b.text == "С героем" or b.text == "Без героя"))


func _close() -> void:
	for ch in main.overlay.get_children():
		main._close_overlay(ch)
	await _wait(0.4)


func _run() -> void:
	await _wait(1.0)
	main._last_heroes = ["finn", "jake@bmo"]
	main.my_hero = "finn"
	for mode in ["ai", "hotseat", "net", "teams", "three"]:
		main.show_hero_select(mode)
		await _wait(1.0)
		var sw := _switches()
		var seats: int = {"ai": 2, "hotseat": 2, "net": 1, "teams": 4, "three": 3}[mode]
		ok(sw.size() == seats, "%s: a switch on every seat (%d)" % [mode, sw.size()])
		ok(sw.all(func(b): return b.text == "С героем"), "%s: with the hero by default" % mode)
		var last: Button = sw[-1]
		last.pressed.emit()
		await _wait(0.3)
		ok(last.text == "Без героя", "%s: the switch turns" % mode)
		await _check("%s_no_hero" % mode)
		last.pressed.emit()
		await _wait(0.2)
		ok(last.text == "С героем", "%s: and back" % mode)
		await _close()
	# The pick reaches the game: «Против ИИ» with seat 1 without a hero.
	main.show_hero_select("ai")
	await _wait(1.0)
	var sw2 := _switches()
	sw2[1].pressed.emit()
	await _wait(0.2)
	var go: Button = null
	for b: Button in main.overlay.find_children("*", "Button", true, false):
		if b.text == "В бой!" and b.is_visible_in_tree():
			go = b
	go.pressed.emit()
	for i in 200:
		await _wait(0.1)
		if main.game != null:
			break
	ok(main.game != null and CardDB.is_no_hero(main._last_heroes[1]), "the AI's seat goes without a hero: %s" % [main._last_heroes])
	if main.game != null:
		ok(main.game.players[1].hero_card == "", "the engine has no hero card for it")
		ok(main.game.players[0].hero_card != "", "the player keeps theirs")
	await _wait(2.0)
	await _check("ai_game_coin")
	main._end_game()
	# The train offers no switch: a run has its own hero.
	main.show_title()
	main.show_hero_select("run")
	await _wait(1.0)
	ok(_switches().is_empty(), "no switch in the train")
	await _check("run_no_switch")
	print("no hero shots: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)
