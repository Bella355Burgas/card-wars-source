extends SceneTree
## Screenshots of the own deck builder, hero selection with an own deck and a
## table played with it (windowed, not headless):
##   godot --path . -s res://tests/shots_deck_builder.gd -- <output_dir>

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")
const CustomDecks = preload("res://scripts/core/custom_decks.gd")

const TEST_NAME := "Кукурузный тест"

var out_dir := "user://shots_deck_builder"
var n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	root.get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, shot_name])
	print("shot ", shot_name)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _press(text: String) -> bool:
	for b in root.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return true
	return false


func _run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await _wait(1.2)
	await _shot("title")

	main.show_deck_builder("")
	await _wait(0.8)
	var overlay_root = main.overlay.get_child(main.overlay.get_child_count() - 1)
	var builder = overlay_root.get_child(overlay_root.get_child_count() - 1)
	await _wait(1.0)   # the pool's pictures load in the background
	await _shot("builder_empty")

	# Командные карты lie landscape in the pool, the deck list and the preview.
	builder._kind_filter = "teamwork"
	builder._apply_filter()
	builder._add("assistance", 1)
	await _wait(1.0)
	builder._hover("assistance")
	await _wait(0.3)
	await _shot("builder_teamwork")
	builder._add("assistance", -1)
	builder._kind_filter = ""
	builder._apply_filter()

	# Four corn lands, then 40 cards that cost at most 2 corn lands: a legal deck.
	for lane in 4:
		builder._set_land(lane, "corn" if lane < 3 else "sandy")
	var added := 0
	for id in CardDB.card_ids():
		var d := CardDB.get_def(id)
		if d["land"] == "corn" and int(d["cost"]) <= 2 and added < 40:
			builder._add(id, 2 if added % 3 == 0 else 1)
			added += 1
	builder._hover(builder._deck.keys()[0])
	await _wait(1.0)
	await _shot("builder_filled")
	builder._name_edit.text = TEST_NAME
	builder._name = TEST_NAME
	builder._on_save()
	await _wait(0.4)
	print("saved codes: ", CustomDecks.codes())

	main._close_overlay(overlay_root)
	await _wait(0.5)
	# A pick is always "deck@hero card" (CardDB.loadout), never a bare deck code.
	var own: String = CardDB.loadout(CustomDecks.codes()[0], "finn")
	main._last_heroes = [own, "jake"]
	main.show_hero_select("hotseat")
	await _wait(0.8)
	_press("2  Колода")
	await _wait(0.8)
	await _shot("hero_select_own_deck")

	# "Изменить" on an own deck's tile opens the builder on it;
	# "В колоду" puts the finished deck back into the seat.
	print("press edit: ", _press("Изменить"))
	await _wait(0.8)
	var pick_root = main.overlay.get_child(main.overlay.get_child_count() - 1)
	var pick_builder = pick_root.get_child(pick_root.get_child_count() - 1)
	print("builder opened on: ", pick_builder._name, " cards: ", pick_builder._deck.size())
	pick_builder._on_use()
	await _wait(0.8)
	await _shot("hero_select_after_builder")

	main.start_new_game([own, "jake"])
	await _wait(2.6)
	await _shot("table_own_deck")
	CustomDecks.remove(TEST_NAME)
	quit(0)
