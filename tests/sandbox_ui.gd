extends SceneTree
## «Песочница» on the real screen: the way in from the «Играть» menu and from the deck builder,
## the panel's buttons with clicks of the window, a tap on the table that picks a card, undo,
## the start of the table again, the other side's turn by hand, the AI on and off, 2 на 2 and
## на троих; every visible button and text of the table must stay on the screen, the panel's
## buttons must be big enough for a finger. Screenshots go to <output_dir>.
##   godot --path . --resolution 2400x1080 -s res://tests/sandbox_ui.gd -- <output_dir> [phone]
##   godot --path . --resolution 1024x768 -s res://tests/sandbox_ui.gd -- <output_dir>

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")
const Sandbox = preload("res://scripts/core/sandbox.gd")

var out_dir := "user://shots_sandbox"
var main
var fails := 0
var checks := 0
var shot := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	main = MainScene.instantiate()
	main.phone_layout = args.size() > 1 and args[1] == "phone"
	root.add_child(main)
	_run()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


func _wait(t: float) -> void:
	await create_timer(t).timeout


## Waits until the table runs no step.
func _idle() -> void:
	for i in 400:
		await process_frame
		if main.board == null or (not main.board._busy and main.board._choice == null):
			break
	await _wait(0.25)


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


## Screenshot; every visible button and text inside the screen; the panel's buttons a finger high.
func _check(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	shot += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, shot, name])
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(2.0)
	var bad := []
	for c: Node in main.find_children("*", "Control", true, false):
		if not (c is Button or c is Label or c is LineEdit) or not c.is_visible_in_tree() or _in_scroll(c) or _in_tall_window(c):
			continue
		if c.name == "Title" or (main.board != null and c == main.board.banner):
			continue      # the turn banner is a table-wide strip with its text in the middle
		var r := _screen_rect(c)
		if r.size.x < 1.0 or r.size.y < 1.0 or c.modulate.a == 0.0:
			continue
		if r.size.x >= screen.size.x - 8.0 and r.size.y >= screen.size.y - 8.0:
			continue
		if not screen.encloses(r):
			bad.append("%s «%s» %s" % [c.get_class(), c.get("text") if c.get("text") != null else "", r])
	ok(bad.is_empty(), "%s: %d out of the screen %s" % [name, bad.size(), bad.slice(0, 5)])
	var b = main.board
	if b != null and b.sb_panel != null and b.sb_panel.is_visible_in_tree():
		var small := []
		var k: float = root.get_final_transform().get_scale().y      # window pixels per screen unit
		for btn: Button in b.sb_panel.find_children("*", "Button", true, false):
			if btn.is_visible_in_tree() and not _in_scroll(btn) and _screen_rect(btn).size.y * k < 0.85 * 58.0 * k * b.sb_panel.get_global_transform_with_canvas().get_scale().y:
				small.append(btn.text)
		ok(small.is_empty(), "%s: small buttons %s" % [name, small.slice(0, 5)])
		ok(screen.encloses(_screen_rect(b.sb_panel)), "%s: the panel is on the screen" % name)
	print("shot %s" % name)


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


## A press of a button, as a finger would.
func _tap(c: Control) -> void:
	if c is BaseButton:
		c.pressed.emit()
	else:
		await _click(_screen_rect(c).get_center())
	await _idle()


func _panel_button(text: String) -> Button:
	for btn: Button in main.board.sb_panel.find_children("*", "Button", true, false):
		if btn.is_visible_in_tree() and btn.text == text:
			return btn
	return null


func _press(text: String) -> void:
	var btn := _panel_button(text)
	ok(btn != null and not btn.disabled, "button «%s»" % text)
	if btn != null:
		await _tap(btn)


func _overlay_button(text: String) -> Button:
	for btn: Button in main.overlay.find_children("*", "Button", true, false):
		if btn.text == text and btn.is_visible_in_tree() and not btn.is_queued_for_deletion():
			return btn
	return null


func _builder_button(builder) -> Button:
	for btn: Button in builder.find_children("*", "Button", true, false):
		if btn.text == "Песочница":
			return btn
	return null


func _run() -> void:
	await _wait(1.0)
	# The way in: «Играть» → «Песочница» → the table → the heroes.
	main.show_play_menu()
	await _wait(0.6)
	var tile: Button = null
	for btn: Button in main._play_root.find_children("*", "Button", true, false):
		if btn.get_meta("game", "") == "Песочница":
			tile = btn
	ok(tile != null, "«Песочница» in the «Играть» menu")
	await _check("play_menu")
	tile.pressed.emit()
	await _wait(0.6)
	await _check("tables")
	var one: Button = null
	for btn: Button in main.overlay.find_children("*", "Button", true, false):
		if btn.text == "1 на 1" and btn.is_visible_in_tree():
			one = btn
	ok(one != null, "«1 на 1»")
	one.pressed.emit()
	await _wait(1.2)
	await _check("heroes")
	var go: Button = null
	for btn: Button in main.overlay.find_children("*", "Button", true, false):
		if btn.text == "Начать" and btn.is_visible_in_tree():
			go = btn
	ok(go != null, "«Начать»")
	var switches: Array = main.overlay.find_children("*", "Button", true, false).filter(func(x): return x.text == "С героем" and x.is_visible_in_tree())
	ok(switches.size() == 2, "a hero switch for every seat")
	switches[1].pressed.emit()
	await _wait(0.2)
	ok(switches[1].text == "Без героя", "the opponent without a hero")
	await _check("heroes_switch")
	go.pressed.emit()
	await _wait(2.0)
	await _idle()
	var b = main.board
	var g = main.game
	ok(b != null and b.sandbox != null and main._mode == "sandbox", "a sandbox game")
	ok(g.journal == null, "no journal: no replay")
	ok(b.sb_panel.visible, "the panel is open")
	ok(not g.is_first_turn(), "no first turn limits")
	ok(g.players[0].hero_card != "" and g.players[1].hero_card == "", "the switch reached the game")
	await _check("panel_cards")

	# «Карты»: search, a filter, a card into the other player's hand and onto the table.
	var panel = b.sb_panel
	panel._search.text = "пёс"
	panel._search.text_changed.emit("пёс")
	await _wait(0.2)
	var row: Button = null
	for r: Button in panel._list.get_children():
		if r.text.begins_with("Крутой пёс"):
			row = r
	ok(row != null, "the search finds Крутой пёс")
	row.pressed.emit()
	await _wait(0.2)
	await _check("card_picked")
	await _tap(panel._seats.get_child(1))
	var n: int = g.players[1].hand.size()
	await _press("В руку")
	ok(g.players[1].hand.size() == n + 1 and g.players[1].hand[-1].id == "cool_dog", "into the other player's hand")
	await _tap(panel._seats.get_child(0))
	await _press("2")
	ok(g.players[0].creatures[1] != null and g.players[0].creatures[1].id == "cool_dog", "onto lane 2")
	await _press("Наверх колоды")
	ok(g.players[0].deck[-1].id == "cool_dog", "on top of the deck")
	await _press("В сброс")
	ok(g.players[0].discard[-1].id == "cool_dog", "into the discard pile")
	panel._filter("kind")
	panel._filter("cost")
	await _wait(0.2)
	var fine := true
	for r: Button in panel._list.get_children():
		var t: String = r.text
		fine = fine and t.ends_with("· 0")
	ok(fine and panel._list.get_child_count() > 0, "type and cost filters")
	await _check("filters")
	panel._filter("deck")
	await _wait(0.2)
	await _check("deck_filter")
	panel._list.get_child(1).pressed.emit()      # the chosen player's deck
	await _wait(0.2)
	ok(panel._deck == "@0", "the player's deck as a filter")

	# A tap on the table picks the card: «Стол».
	# (the window's clicks land off the table's spots when the OS shrinks the window: the tap itself)
	b._sb_tap(b.creature_pos(0, 1), b.views[g.players[0].creatures[1].uid])
	await _idle()
	ok(panel._tab == "table" and panel._target.get("uid", -1) == g.players[0].creatures[1].uid, "a tap picks the card on the table")
	await _check("panel_table")
	await _press("Урон 1")
	ok(g.players[0].creatures[1].damage == 1, "damage")
	await _press("Лечить 1")
	ok(g.players[0].creatures[1].damage == 0, "healing")
	await _press("Атака +1")
	await _press("Защита −1")
	ok(g.atk_of(0, 1) == 3 and g.def_of(0, 1) == 6, "attack and defence")
	await _press("Заморозить")
	ok(g.is_frozen(0, 1), "frozen")
	await _check("frozen")
	await _press("Растопить")
	ok(not g.is_frozen(0, 1), "thawed")
	await _press("Перевернуть")
	ok(g.players[0].lands[1]["flipped"], "land face down")
	var corn_btn: Button = null
	for btn: Button in panel._table_page.find_children("*", "Button", true, false):
		if btn.tooltip_text == CardDB.land_name("corn"):
			corn_btn = btn
	await _tap(corn_btn)
	ok(g.players[0].lands[1]["type"] == "corn", "land type")
	await _press("Повернуть")
	ok(g.players[0].creatures[1].exhausted, "turned")
	# Undo, step by step, then the whole table.
	var hist: int = b.sandbox.history.size()
	ok(hist >= 10, "every step is kept (%d)" % hist)
	await _press("Шаг назад")
	ok(not g.players[0].creatures[1].exhausted, "a step back")
	await _tap(b.undo_button)
	ok(g.players[0].lands[1]["type"] != "corn", "the undo button of the table too")
	await _press("Уничтожить")
	ok(g.players[0].creatures[1] == null, "destroyed")
	await _press("Сначала")
	ok(g.players[0].creatures[1] == null and g.players[1].hand.size() == n and b.sandbox.history.is_empty(), "the table as at the start")

	# «Игроки».
	panel.show_tab("players")
	await _wait(0.2)
	await _check("panel_players")
	await _press("−5")
	ok(g.players[0].hp == 20, "hit points −5")
	await _press("+1")
	ok(g.players[0].hp == 21, "hit points +1")
	await _press("Бесконечные действия: нет")
	ok(g.players[0].actions == Sandbox.INF_ACTIONS, "infinite actions")
	var hand: int = g.players[0].hand.size()
	await _press("Взять карту")
	ok(g.players[0].hand.size() == hand + 1, "a card drawn")
	await _press("Очистить руку")
	ok(g.players[0].hand.is_empty(), "the hand cleared")
	await _press("Перемешать колоду")
	await _check("players_done")

	# The turn of the other side, played by hand: the table turns to it.
	await _press("Передать ход")
	await _idle()
	ok(g.turn_player == 1 and b.viewer == 1, "the other side's turn, the table turned to it")
	ok(b._plays(1) and b._can_act(), "it is played from here")
	b._issue({"cmd": "draw"})
	await _idle()
	ok(g.players[1].actions == 1, "the other side spends an action")
	await _check("other_side")
	# «Журнал».
	panel.show_tab("log")
	await _wait(0.3)
	ok(panel._log.get_parsed_text().contains("Крутой пёс") or panel._log.get_parsed_text().contains("передаёт ход"), "the log shows the steps")
	await _check("panel_log")
	# The AI takes the other side.
	await _press("Передать ход")
	await _idle()
	ok(g.turn_player == 0 and b.viewer == 0, "back to the first player")
	await _press("ИИ: нет")
	for i in 300:
		await process_frame
		if b.sb_ai_on():
			break
	ok(b.sb_ai_on() and b._is_ai_seat(1) and not b._plays(1), "the AI plays the other side")
	await _press("Передать ход")
	for i in 600:
		await _wait(0.1)
		if g.turn_player == 0 and g.phase == "main" and not b._busy:
			break
	ok(g.turn_player == 0, "the AI played its turn and gave it back")
	ok(b.viewer == 0, "the table stays with the player")
	await _check("after_ai")
	await _press("ИИ: да")
	await _wait(0.3)
	ok(not b.sb_ai_on(), "the AI is off")
	# A win does not end the sandbox.
	panel.show_tab("players")
	await _tap(panel._seats.get_child(1))
	b.sb_do(func(): await b.sandbox.set_hp(1, 0))
	await _idle()
	await _wait(0.8)
	ok(g.phase == "over" and main._game_over_root == null, "a win shows no end screen")
	await _check("win")
	await _press("Шаг назад")
	ok(g.phase == "main", "a step back brings the game back")
	# The panel hides and comes back.
	await _tap(b.sb_button)
	ok(not panel.visible, "the panel hides")
	await _check("panel_hidden")
	await _tap(b.sb_button)
	ok(panel.visible, "and shows again")
	b._sb_tap(b.land_pos(1, 2), null)
	await _idle()
	ok(panel._target.get("side", -1) == 1 and panel._target.get("lane", -1) == 2, "a tap on a land picks it")
	await _check("land_picked")

	# 2 на 2 and на троих.
	main.sandbox_start.start(["finn", "jake", "bmo", "marceline"])
	await _wait(2.0)
	await _idle()
	ok(main.game.teams() and main.board.sandbox != null, "2 на 2 sandbox")
	ok(main.board.humans.size() == 4, "every seat played from here")
	await _check("teams")
	main.board.sb_panel.show_tab("players")
	await _wait(0.2)
	await _check("teams_players")
	main.sandbox_start.start(["finn", "jake", "bmo"])
	await _wait(2.0)
	await _idle()
	ok(main.game.three() and main.board.sandbox != null, "на троих sandbox")
	await _check("three")

	# From the deck builder: the deck on it, with its hero or without.
	main._end_game()
	main.show_title()
	main.show_deck_builder("")
	await _wait(1.5)
	var builder = main._open_builder()
	builder._load_state("Проба", ["plain", "plain", "corn", "corn"], {"cool_dog": 3, "husker_knight": 2}, "bmo")
	builder._refresh()
	await _wait(0.3)
	await _check("builder")
	var try: Button = null
	for btn: Button in builder.find_children("*", "Button", true, false):
		if btn.text == "Песочница":
			try = btn
	ok(try != null and try.is_visible_in_tree(), "«Песочница» in the deck builder")
	try.pressed.emit()
	await _wait(0.8)
	ok(_overlay_button("С героем") != null, "the window asks: with the hero by default")
	await _check("builder_ask_hero")
	_overlay_button("Начать").pressed.emit()
	await _wait(2.0)
	await _idle()
	ok(main.board != null and main.board.sandbox != null, "the sandbox from the builder")
	var ps = main.game.players[0]
	var ids := {}
	for c in ps.deck + ps.hand:
		ids[c.id] = true
	ok(ids.keys().size() == 2 and ids.has("cool_dog") and ids.has("husker_knight"), "with the builder's deck")
	ok(ps.hero_card == "bmo", "and its hero")
	ok(main._open_builder() == null, "the builder is closed")
	await _check("from_builder")
	main.show_pause()
	await _wait(0.5)
	var back := _overlay_button("В конструктор")
	ok(back != null, "«В конструктор» in the pause menu")
	await _check("pause")
	back.pressed.emit()
	await _wait(1.5)
	var again = main._open_builder()
	ok(again != null and again._deck.has("husker_knight") and again.hero_card() == "bmo", "back in the builder with the same deck and hero")
	# The same deck without its hero.
	_builder_button(again).pressed.emit()
	await _wait(0.8)
	_overlay_button("С героем").pressed.emit()
	await _wait(0.3)
	ok(_overlay_button("Без героя") != null, "the switch: without the hero")
	await _check("builder_no_hero")
	_overlay_button("Начать").pressed.emit()
	await _wait(2.0)
	await _idle()
	ok(main.game.players[0].hero_card == "" and main.game.players[0].name == "Проба", "the deck alone, by its name")
	ok(not main.board.hero_button.visible, "no hero button")
	await _check("no_hero_game")
	# The hero of a seat from the panel.
	panel = main.board.sb_panel
	panel.show_tab("players")
	await _wait(0.2)
	await _press("Сменить героя")
	await _check("hero_list")
	row = null
	for r: Button in panel._player_page.get_children().filter(func(x): return x is Button):
		if r.text == CardDB.hero_card("finn")["name"]:
			row = r
	ok(row != null, "the hero list")
	if row != null:
		row.pressed.emit()
		await _idle()
	ok(main.game.players[0].hero_card == "finn", "a hero chosen in the panel")
	await _press("Без героя")
	ok(main.game.players[0].hero_card == "", "and taken away")
	await _press("Шаг назад")
	ok(main.game.players[0].hero_card == "finn", "a step back brings it again")

	# Edge decks of the builder: each opens the sandbox (one card and no hero used to crash).
	var cases := [["one card, no hero", ["plain", "plain", "plain", "plain"], {"cool_dog": 1}, ""],
		["empty", ["plain", "plain", "plain", "plain"], {}, ""],
		["no creatures", ["plain", "plain", "plain", "plain"], {"schoolhouse": 2}, "finn"],
		["no lands", [], {"cool_dog": 2}, ""]]
	for cs in cases:
		main._end_game()
		main.show_title()
		main.show_deck_builder("")
		await _wait(1.2)
		var bld = main._open_builder()
		bld._load_state("Край", cs[1], cs[2], cs[3])
		bld._lands = cs[1].duplicate()          # a deck from a file may come with no lands at all
		_builder_button(bld).pressed.emit()
		await _wait(0.8)
		var start := _overlay_button("Начать")
		ok(start != null, "%s: the window" % cs[0])
		if start == null:
			continue
		start.pressed.emit()
		await _wait(2.0)
		await _idle()
		var gg = main.game
		ok(main.board != null and gg != null and gg.phase == "main", "%s: the sandbox opens" % cs[0])
		if gg == null:
			continue
		ok(not gg.players[0].hand.has(null), "%s: no empty places in the hand" % cs[0])
		var n_cards: int = 0
		for v in cs[2].values():
			n_cards += int(v)
		ok(gg.players[0].hand.size() + gg.players[0].deck.size() == n_cards, "%s: %d cards" % [cs[0], n_cards])
		await _press("Передать ход")
		await _press("Передать ход")
		ok(gg.turn_player == 0 and gg.phase == "main", "%s: turns go round" % cs[0])
		await _check("edge_" + cs[0].replace(" ", "_").replace(",", ""))

	print("sandbox ui: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)
