extends SceneTree
## Heroes in the deck builder: the strip shows the hero the builder was opened for, the window of
## heroes has every hero card, «Копия колоды» opens a hero's deck as an own deck that is edited
## and saved apart (the hero's deck stays as it is), the hero is saved with the deck and in a deck
## file, the limit of Малыши Финн и Джейк is checked, and «В колоду» gives the hero back:
##   godot --headless --path . -s res://tests/builder_heroes.gd

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")
const CustomDecks = preload("res://scripts/core/custom_decks.gd")

var main
var fails := 0


func _initialize() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	_run()


func _ok(what: String, cond: bool) -> void:
	print(("OK   " if cond else "FAIL ") + what)
	if not cond:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for id in a:
		if int(a[id]) != int(b.get(id, -1)):
			return false
	return true


func _builder() -> Control:
	var r = main.overlay.get_child(main.overlay.get_child_count() - 1)
	return r.get_child(r.get_child_count() - 1)


func _press(node: Node, text: String) -> bool:
	for b in node.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return true
	return false


func _run() -> void:
	await _wait(0.5)
	var saved_before := CustomDecks.load_all()
	var jake_deck: Dictionary = CardDB.hero("jake")["deck"].duplicate()
	var jake_lands: Array = CardDB.hero("jake")["lands"].duplicate()

	# Opened for a hero (hero selection passes the seat's hero card).
	var got := []
	main.show_deck_builder("", func(code: String, hero: String): got.append([code, hero]), "", "finn")
	await _wait(0.6)
	var b := _builder()
	_ok("strip shows the hero", b.hero_card() == "finn" and b._hero_name.text == CardDB.hero_card("finn")["name"])
	_ok("strip shows the hero's 4 lands", b._hero_lands.get_child_count() == 4)
	_ok("strip shows the ability", b._hero_text.text == CardDB.hero_card("finn")["text"])

	# The window of heroes: every hero card.
	b._show_heroes()
	await _wait(0.3)
	var grid: GridContainer = b._popup.find_child("HeroGrid", true, false)
	_ok("all %d hero cards in the window" % CardDB.hero_card_ids().size(),
		grid != null and grid.get_child_count() == CardDB.hero_card_ids().size())
	grid.get_node("Hero_jake").pressed.emit()
	await _wait(0.3)
	_ok("a hero tile opens the hero", b._popup.find_child("HeroPicture", true, false) != null)
	_ok("copy button for a hero with a deck", _press(b._popup, "Копия колоды"))
	await _wait(0.2)
	_ok("copy has the hero's cards", _same(b._deck, jake_deck))
	_ok("copy has the hero's lands", b._lands == jake_lands)
	_ok("copy is built for that hero", b.hero_card() == "jake")
	var copy_name: String = b._name
	_ok("copy has its own name «%s»" % copy_name, copy_name.begins_with(CardDB.hero("jake")["name"]) and copy_name.contains("копия"))

	# Edit and save: the own deck changes, the hero's deck does not.
	var first: String = b._deck.keys()[0]
	b._add(first, -1)
	var extra := ""
	for id in CardDB.pool_ids():
		if not b._deck.has(id) and CardDB.get_def(id)["land"] == "corn" and int(CardDB.get_def(id)["cost"]) > 0:
			extra = id
			break
	b._add(extra, 1)
	b._set_land(3, "sandy")
	b._on_save()
	var saved := {}
	for e in CustomDecks.load_all():
		if e["name"] == copy_name:
			saved = e
	_ok("copy saved as an own deck", not saved.is_empty())
	_ok("saved with its hero", saved.get("hero", "") == "jake")
	_ok("saved with the edits", saved.get("deck", {}).has(extra) and saved.get("lands", [])[3] == "sandy")
	_ok("the hero's deck is unchanged", CardDB.hero("jake")["deck"] == jake_deck and CardDB.hero("jake")["lands"] == jake_lands)
	_ok("the saved deck is legal", CardDB.has_hero(CustomDecks.code_of(saved)))

	# A second copy gets a free name.
	b._show_hero("jake")
	await _wait(0.2)
	_press(b._popup, "Копия колоды")
	_ok("second copy has another name", b._name != copy_name)

	# The saved deck opens with its hero.
	b._show_hero("finn")
	_press(b._popup, "Выбрать")
	_ok("«Выбрать» sets the hero", b.hero_card() == "finn")
	b._show_decks()
	await _wait(0.2)
	for btn in b._popup.find_children("*", "Button", true, false):
		if String(btn.text).begins_with(copy_name):
			btn.pressed.emit()
			break
	_ok("saved deck opens with its hero", b._name == copy_name and b.hero_card() == "jake")

	# A deck file keeps the hero.
	var path := OS.get_user_data_dir().path_join("hero_test.cwdeck")
	CustomDecks.write_file(path, b._entry(copy_name))
	_ok("deck file keeps the hero", CustomDecks.read_file(path).get("hero", "") == "jake")
	DirAccess.remove_absolute(path)

	# The limit of a hero card: Малыши Финн и Джейк take creatures of attack up to 3.
	b._set_hero("baby_finn_and_jake")
	b._refresh()
	var over: Array = b._over_hero_limit()
	_ok("hero limit is checked", b._check_hero.visible and (over.is_empty() == (b._check_hero.text.begins_with("✓"))))
	b._set_hero("jake")
	b._refresh()
	_ok("no limit line for a hero without one", not b._check_hero.visible)

	# «В колоду» gives the deck and the hero back.
	b._on_use()
	await _wait(0.2)
	_ok("pick gives the hero", got.size() == 1 and got[0][1] == "jake" and CardDB.is_custom(got[0][0]))

	# The title builder: no hero at first.
	main.show_deck_builder("")
	await _wait(0.5)
	var t := _builder()
	_ok("no hero at first from the title", t.hero_card() == "" and t._hero_btn.text == "Выбрать")
	main._close_overlay(main.overlay.get_child(main.overlay.get_child_count() - 1))

	CustomDecks.save_all(saved_before)
	print("HEROES fails=%d" % fails)
	quit(1 if fails > 0 else 0)
