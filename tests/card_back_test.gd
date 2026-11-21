extends Node
## «Рубашка карт»: the window to pick a back, the picked one on the table and in the settings file,
## another one picked over a game. Puts the player's own back back at the end.
##   godot --path . res://tests/card_back_test.tscn -- <output_dir>

const MainScene := preload("res://scenes/main.tscn")
const CardBacks = preload("res://scripts/ui/card_backs.gd")
const CardView = preload("res://scripts/ui/card_view.gd")

var out_dir := "user://card_back_test"
var main
var fails := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	main = MainScene.instantiate()
	add_child(main)
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


## The tiles of the open «Рубашка карт» window.
func _tiles() -> Array:
	return main.overlay.find_children("*", "TextureButton", true, false).filter(func(b): return b.has_meta("card_back"))


func _pick(path: String) -> void:
	main.show_settings()
	await _wait(0.5)
	var open: Array = main.overlay.find_children("*", "Button", true, false).filter(func(b): return b.text == "Рубашка карт")
	_check(open.size() == 1, "settings has «Рубашка карт»")
	open[0].pressed.emit()
	await _wait(0.6)
	var tiles: Array = _tiles()
	_check(tiles.size() == CardBacks.all().size() and tiles.size() >= 6, "every back is in the window: %d" % tiles.size())
	await _shot("picker_" + path.get_file().get_basename())
	for b in tiles:
		if b.get_meta("card_back") == path:
			b.pressed.emit()
	await _wait(0.5)
	for ch in main.overlay.get_children():
		main._close_overlay(ch)
	await _wait(0.4)


func _run() -> void:
	var own: String = CardBacks.path
	await _wait(1.2)
	var backs := CardBacks.all()
	_check(backs[0] == CardBacks.CLASSIC, "the classic back is first")
	await _pick(backs[1])
	_check(CardBacks.path == backs[1], "picked back is on")
	_check(str(main._load_setting("ui", "card_back", "")) == backs[1], "picked back is saved")
	main.start_ai_vs_ai_game(["lich@lich", "finn@charlie"])
	await _wait(5.0)
	await _shot("table_1")
	var board = main.board
	_check(board.piles[0].get_child(0).texture == CardBacks.texture(), "deck pile has the back")
	# Another one over the game: the cards on the table change at once.
	main.show_pause()
	await _wait(0.4)
	for ch in main.overlay.get_children():
		main._close_overlay(ch)
	await _pick(backs[3])
	_check(board.piles[0].get_child(0).texture == CardBacks.texture(), "deck pile has the new back")
	var down: Array = get_tree().get_nodes_in_group("card_views").filter(func(v): return not v.face_up)
	_check(down.all(func(v): return v._face.texture == CardBacks.texture()), "face-down cards have the new back: %d" % down.size())
	var size_ok: bool = absf(board.piles[0].get_child(0).texture.get_width() * board.piles[0].get_child(0).scale.x - CardView.SIZE.x * board.S_PILE) < 0.5
	_check(size_ok, "deck pile card is as big as before")
	await _shot("table_2")
	CardBacks.pick(own)
	main._save_setting("ui", "card_back", own)
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
