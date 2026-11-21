extends SceneTree
## The two steps of the hero selection: a hero card, then a deck.
##   godot --path . -s res://tests/shots_hero_select.gd -- <output_dir>

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")

var out_dir := "user://shots_hero_select"
var main
var n := 0
var fails := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MainScene.instantiate()
	root.add_child(main)
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, name])
	print("shot ", name)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _press(text: String) -> bool:
	for b in main.overlay.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return true
	return false


func _click(c: Control) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	c.gui_input.emit(e)


## The visible grid of the hero selection: "HeroGrid" or "DeckGrid".
func _grid(name: String) -> GridContainer:
	for g: GridContainer in main.overlay.find_children(name, "GridContainer", true, false):
		if g.is_visible_in_tree():
			return g
	return null


func _run() -> void:
	await _wait(1.0)
	var ids: Array = CardDB.hero_card_ids()
	main.show_hero_select("teams")
	await _wait(0.8)
	await _shot("teams_hero")
	_click(_grid("HeroGrid").get_child(0))
	await _wait(0.8)
	await _shot("teams_deck")
	_press("Назад")
	await _wait(0.5)

	main.show_hero_select("net")
	await _wait(0.6)
	_click(_grid("HeroGrid").get_child(ids.find("bmo")))
	await _wait(0.8)
	await _shot("net_deck")
	_press("Назад")
	await _wait(0.5)
	main._last_heroes = ["finn", "jake"]
	main.show_hero_select("hotseat")
	await _wait(0.8)
	await _shot("hero_step")
	var heroes := _grid("HeroGrid")
	_check(heroes != null and _grid("DeckGrid") == null, "the selection opens on the hero step")
	# Player 1 takes Марселин's card: her deck comes with it, the deck step opens.
	_click(heroes.get_child(ids.find("marceline")))
	await _wait(0.6)
	_check(_grid("DeckGrid") != null and _grid("HeroGrid") == null, "a hero card opens the deck step")
	await _shot("deck_step")
	# Then Снежный король's deck: the next player picks a hero.
	var decks := _grid("DeckGrid")
	_click(decks.get_child(CardDB.hero_ids().find("ice_king")))
	await _wait(0.6)
	_check(_grid("HeroGrid") != null, "a deck sends the next seat to the hero step")
	_click(heroes.get_child(ids.find("prismo")))
	await _wait(0.6)
	await _shot("deck_step_any_card")
	_click(_grid("DeckGrid").get_child(CardDB.hero_ids().find("lich")))
	await _wait(0.5)
	await _shot("both_picked")
	_press("В бой!")
	await _wait(0.6)
	_check(main._last_heroes == ["ice_king@marceline", "lich@prismo"], "picks %s" % [main._last_heroes])

	# Малыши Финн и Джейк: decks with a creature of attack above 3 stay dim and are not taken.
	main._last_heroes = ["charlie", "finn"]
	main.show_hero_select("hotseat")
	await _wait(0.8)
	_click(_grid("HeroGrid").get_child(ids.find("baby_finn_and_jake")))
	await _wait(0.6)
	_click(_grid("DeckGrid").get_child(CardDB.hero_ids().find("charlie")))
	await _wait(0.4)
	_check(_grid("DeckGrid") != null, "Малыши Финн и Джейк: колода Чарли не берётся")
	await _shot("baby_finn_and_jake_decks")
	_click(_grid("DeckGrid").get_child(CardDB.hero_ids().find("marceline")))
	await _wait(0.6)
	_press("В бой!")
	await _wait(0.6)
	_check(main._last_heroes == ["marceline@baby_finn_and_jake", "finn"], "picks %s" % [main._last_heroes])
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
