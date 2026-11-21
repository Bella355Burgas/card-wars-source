extends SceneTree
## Items of «Бесконечный поезд» in cards.json, headless:
##   godot --headless --path . -s res://tests/items_test.gd

const CardDB = preload("res://scripts/core/card_db.gd")

const RARITIES := ["обычный", "редкий", "легендарный"]

var failures := 0


func _initialize() -> void:
	var ids := CardDB.item_ids()
	expect(ids.size() == 50, "50 items, got %d" % ids.size())
	for id: String in ids:
		var it := CardDB.item(id)
		expect(it["name"] != "", "name of %s" % id)
		expect(RARITIES.has(it["rarity"]), "rarity of %s" % id)
		expect(it["text"].begins_with("ВЛАДЕНИЕ >>> "), "text of %s" % id)
		# Items stay out of the deck pool, trophies and the AI.
		expect(not CardDB.has_def(id), "%s is not a card" % id)
		expect(not CardDB.card_ids().has(id), "%s is not in card_ids" % id)
	print("items tests: %d checks failed" % failures)
	quit(1 if failures > 0 else 0)


func expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
