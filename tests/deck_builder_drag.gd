extends SceneTree
## Drags and clicks in the own deck builder with real mouse events (the GUI's own
## drag and drop), headless:
##   godot --headless --path . -s res://tests/deck_builder_drag.gd

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")

var failures := 0
var vp: Viewport


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _frames(n := 3) -> void:
	for i in n:
		await process_frame


func _button(pos: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	vp.push_input(ev, true)
	await _frames(2)


func _click(pos: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await _button(pos, true, button)
	await _button(pos, false, button)


func _drag(from: Vector2, to: Vector2) -> void:
	await _button(from, true)
	var last := from
	for i in range(1, 13):
		var ev := InputEventMouseMotion.new()
		var p := from.lerp(to, i / 12.0)
		ev.position = p
		ev.global_position = p
		ev.relative = p - last
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
		last = p
		vp.push_input(ev, true)
		await _frames(1)
	await _button(to, false)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	vp = root
	await _frames(10)
	main.show_deck_builder("")
	await _frames(20)
	var overlay_root = main.overlay.get_child(main.overlay.get_child_count() - 1)
	var b = overlay_root.get_child(overlay_root.get_child_count() - 1)
	var deck_panel: Control = b._deck_list.get_parent()

	var id: String = b._sorted(CardDB.card_ids())[0]
	var tile: Control = b._tiles[id]["box"]
	await _drag(_center(tile), _center(deck_panel))
	_check(int(b._deck.get(id, 0)) == 1, "drag pool -> deck adds a copy")
	await _click(_center(tile))
	_check(int(b._deck.get(id, 0)) == 2, "left click adds a copy")
	await _click(_center(tile), MOUSE_BUTTON_RIGHT)
	_check(b._popup != null and b._inspect_id == id and int(b._deck.get(id, 0)) == 2, "right click shows the card big")
	b._close_popup()
	b._add(id, -1)
	await _frames(5)
	var row: Control = b._deck_list.get_child(0)
	await _drag(_center(row), _center(tile))
	_check(not b._deck.has(id), "drag deck -> pool takes it away")

	var lane0: Control = b._lanes[0]["box"]
	var lane1: Control = b._lanes[1]["box"]
	var corn: Control = null
	for t in lane0.get_parent().get_parent().get_child(2).get_children():
		if t.tooltip_text == CardDB.land_name("corn"):
			corn = t
	await _drag(_center(corn), _center(lane0))
	_check(b._lands[0] == "corn", "land tile dragged onto a lane")
	await _drag(_center(lane0), _center(lane1))
	_check(b._lands[0] == "plain" and b._lands[1] == "corn", "lanes swap places")
	var before: String = b._lands[2]
	await _click(_center(b._lanes[2]["box"]))
	_check(b._lands[2] != before, "click turns a lane to the next land")

	b._land_filter = "corn"
	b._only_payable = true
	b._apply_filter()
	var shown := 0
	for k: String in b._tiles:
		if b._tiles[k]["box"].visible:
			shown += 1
			if CardDB.get_def(k)["land"] != "corn" or not b._payable(k):
				failures += 1
	_check(shown > 0, "filters: %d corn cards the lanes can pay for" % shown)

	# The search looks through the whole text, «ё» as «е», name hits first.
	b._land_filter = ""
	b._only_payable = false
	for q: String in ["хрум", "ХРУМ", "флюп"]:
		b._search.text = q
		b._apply_filter()
		var hits := 0
		var want := 0
		for k: String in b._tiles:
			if b._tiles[k]["box"].visible:
				hits += 1
			if String(CardDB.get_def(k).get("text", "")).to_lower().contains(q.to_lower()):
				want += 1
		_check(hits > 0 and hits == want, "search «%s» by text: %d cards" % [q, hits])
	b._search.text = "берет"
	b._apply_filter()
	var with_yo := 0
	for k: String in b._tiles:
		if b._tiles[k]["box"].visible and String(CardDB.get_def(k).get("text", "")).to_lower().contains("берёт"):
			with_yo += 1
	_check(with_yo > 0, "search «берет» finds «берёт»: %d cards" % with_yo)
	b._search.text = "кукуруз"
	b._apply_filter()
	var first: Control = null
	for ch: Control in b._grid.get_children():
		if ch.visible:
			first = ch
			break
	var first_id := ""
	for k: String in b._tiles:
		if b._tiles[k]["box"] == first:
			first_id = k
	_check(first_id != "" and CardDB.get_def(first_id)["name"].to_lower().contains("кукуруз"), "name hits come first: %s" % first_id)
	b._search.text = ""
	b._apply_filter()
	_check(b._grid.get_child(0) == b._tiles[b._pool_order[0]]["box"], "empty search puts the order back")
	print("deck builder drag: %s" % ("OK" if failures == 0 else "%d failures" % failures))
	quit(1 if failures > 0 else 0)
