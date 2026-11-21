extends SceneTree
## A whole game against the AI by the keys alone: the title, «Играть», «Против ИИ», the heroes,
## «В бой!», the curtains, the start hand, the turns (cards from the hand to the lands, spells
## by their menu, attacks, the end of the turn), the choices of the game, the end screen.
## The test reads where the frames stand to know which key to press; every action is a key.
##   godot --headless --path . -s res://tests/keyboard_test.gd [-- train]

const MainScene := preload("res://scenes/main.tscn")
const Board = preload("res://scripts/ui/board.gd")
const TrainRun = preload("res://scripts/train/train_run.gd")
const RUN_SAVE := "user://run_keys_test.json"

var main
var kn
var fails := 0
var played := 0          # cards played from the hand by the keys
var keys := 0
var by_number := 0       # cards put on a zone by the keys 1-4
var looked := false      # the discard pile was looked through by the keys
var hover_ok := false    # the card under the table frame was lifted as under the mouse


func _initialize() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	_run()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _key(code: Key, physical := false, ctrl := false) -> void:
	keys += 1
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame
	await process_frame


func _has_text(c: Node, s: String) -> bool:
	if c is Button and (c as Button).text == s:
		return true
	for l in c.find_children("*", "Label", true, false):
		if (l as Label).text == s:
			return true
	return false


## The window frame (KeyNav) goes to the target `pred` picks and presses it.
func _nav_press(pred: Callable, what: String, enter := true) -> bool:
	for i in 40:
		var cands: Array = kn.targets()
		var goal: Control = null
		for c in cands:
			if pred.call(c):
				goal = c
				break
		if goal == null:
			await _wait(0.2)
			continue
		if not kn.keyboard or kn.current == null or not is_instance_valid(kn.current) or not cands.has(kn.current):
			await _key(KEY_DOWN)
			continue
		if kn.current == goal:
			if enter:
				await _key(KEY_ENTER)
			return true
		await _key(_toward(kn.rect_of(kn.current).get_center(), kn.rect_of(goal).get_center(), i))
	_check(false, "frame reaches " + what)
	return false


func _toward(from: Vector2, to: Vector2, i: int) -> Key:
	var d := to - from
	# Now and then the other axis: a frame stuck on one line gets off it.
	var horizontal := absf(d.x) > absf(d.y)
	if i % 7 == 6:
		horizontal = not horizontal
	if horizontal and absf(d.x) > 2.0 or absf(d.y) <= 2.0:
		return KEY_RIGHT if d.x > 0 else KEY_LEFT
	return KEY_DOWN if d.y > 0 else KEY_UP


## The table frame goes to the target with this id and presses it.
func _board_press(board, id: String) -> bool:
	for i in 30:
		if not kn.keyboard:
			await _key(KEY_RIGHT)
			continue
		var cur: Dictionary = board._kb_current()
		var goal := {}
		for t in board._kb_targets():
			if t["id"] == id:
				goal = t
		if goal.is_empty():
			return false
		if cur["id"] == id:
			await _wait(0.1)
			hover_ok = goal.has("view") and board._hover_view == goal["view"] and goal["view"].focused
			await _key(KEY_SPACE)
			return true
		await _key(_toward(board._kb_at(cur), board._kb_at(goal), i))
	_check(false, "table frame reaches " + id)
	return false


func _run() -> void:
	await process_frame
	kn = root.get_node("KeyNav")
	Board.turn_speed = 4.0
	await _wait(1.5)
	if OS.get_cmdline_user_args().has("train"):     # -- train: only the train part (and the rest of the screens)
		await _train()
		await _builder()
		_rebind()
		print("FAILS: %d" % fails)
		quit(1 if fails > 0 else 0)
		return
	_check(await _nav_press(func(c): return _has_text(c, "Играть"), "«Играть»"), "title: «Играть» by the keys")
	await _wait(0.6)
	# The title stays under the menu: the frame must not stay on its button.
	_check(kn.current != null and is_instance_valid(kn.current) and kn.targets().has(kn.current)
		and not _has_text(kn.current, "Играть"), "the frame went over to the play menu")
	_check(await _nav_press(func(c): return c is Button and _has_text(c, "Против ИИ"), "«Против ИИ»"), "play menu: «Против ИИ»")
	await _wait(1.0)
	# A hero card by the keys: the frame stands on a tile, Enter takes it.
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	_check(kn.current != null and not (kn.current is Button), "hero select: the frame on a hero tile")
	await _key(KEY_I)
	await _wait(0.3)
	await _key(KEY_E)        # the main button of the screen, wherever the frame is
	await _wait(1.0)
	_check(main.board != null or main.overlay.find_children("*", "Button", true, false).all(
		func(b): return not (b.text == "В бой!" and b.is_visible_in_tree())), "hero select: E presses «В бой!»")
	var board = null
	var t0 := Time.get_ticks_msec()
	var tried := {}
	var turn := -1
	var shot_frame := false
	while Time.get_ticks_msec() - t0 < 900000:
		await _wait(0.15)
		board = main.board
		if board == null or board.game == null:
			# The curtains before the game: their button by the keys.
			if kn.keyboard and kn.current != null and is_instance_valid(kn.current) and kn.targets().has(kn.current):
				await _key(KEY_ENTER)
			elif not kn.targets().is_empty():
				await _key(KEY_DOWN)
			continue
		var game = board.game
		if game.phase == "over":
			break
		if board._busy and board._choice == null:
			continue
		if not board._kb_free():
			# A window: the start hand, a list of cards to pick from, a menu, a curtain.
			if board.mulligan_panel.visible:
				await _nav_press(func(c): return c is Button and c.text == "Оставить", "«Оставить»")
			elif not kn.targets().is_empty():
				if kn.keyboard and kn.current != null and is_instance_valid(kn.current) and kn.targets().has(kn.current):
					await _key(KEY_ENTER)
				else:
					await _key(KEY_DOWN)
			continue
		if board._arranging >= 0:
			await _board_press(board, "arrange")
			continue
		if board._choice != null:
			if not kn.keyboard:
				await _key(KEY_RIGHT)
			await _key(KEY_ENTER)
			continue
		if not board._can_act():
			continue
		if game.turn_number != turn:
			turn = game.turn_number
			tried.clear()
		if not looked and board._drop_targets.is_empty() and not game.players[board.viewer].discard.is_empty():
			looked = true
			await _discard_look(board)
			continue
		if not board._drop_targets.is_empty():
			# Every other card goes by the number of its zone.
			if played % 2 == 0:
				await _key(KEY_1 + int(board._drop_targets[0]["lane"]))
				by_number += 1
			else:
				await _key(KEY_ENTER)
			played += 1
			await _wait(0.2)
			continue
		if game.phase == "main":
			var pick := -1
			for c in game.players[board.viewer].hand:
				if not tried.has(c.uid) and game.can_play(board.viewer, c.uid):
					pick = c.uid
					break
			if pick >= 0:
				tried[pick] = true
				if await _board_press(board, "u:%d" % pick):
					if not shot_frame:
						shot_frame = true
						_check(hover_ok, "hand card under the frame is lifted and framed")
					await _wait(0.3)
					if board.context_menu.visible:
						await _key(KEY_ENTER)     # a spell: its menu, the frame on «Сыграть»
						played += 1
				continue
		await _key(KEY_E)
	board = main.board
	_check(board != null and board.game != null and board.game.phase == "over", "the game reached its end")
	_check(played >= 2, "cards played by the keys: %d" % played)
	_check(by_number >= 1, "cards put on a zone by its number: %d" % by_number)
	_check(looked, "the discard pile was opened by the keys")
	await _wait(2.5)
	_check(await _nav_press(func(c): return c is Button and c.text == "Главное меню", "«Главное меню»"), "end screen: «Главное меню»")
	await _wait(1.0)
	_check(main.board == null or not is_instance_valid(main.board), "back at the title")
	await _train()
	await _builder()
	_rebind()
	print("keys pressed: %d" % keys)
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)


## «Бесконечный поезд»: the shop and an event by the keys, Tab opens the items and closes them.
func _train() -> void:
	main.run = TrainRun.new()
	main.run.save_path = RUN_SAVE
	main.run.start("finn")
	var run = main.run
	run.coins = 500
	run.current = {"kind": "shop"}
	run._stock_shop()
	run.phase = "shop"
	main.show_run()
	await _wait(1.0)
	var deck: int = run.deck_size()
	var items: int = run.items.size()
	# The first tile on the shelf: a card or an item for coins.
	await _key(KEY_DOWN)
	await _nav_press(func(c): return not (c is Button) and c.gui_input.get_connections().size() > 0, "a shelf tile")
	await _wait(0.4)
	_check(run.deck_size() > deck or run.items.size() > items, "shop: bought by the keys")
	await _key(KEY_TAB)
	await _wait(0.3)
	var page = main.run_screen._popup
	_check(page != null and is_instance_valid(page) and page.has_meta("items"), "Tab opens the items")
	await _key(KEY_TAB)
	await _wait(0.3)
	_check(main.run_screen._popup == null or not is_instance_valid(main.run_screen._popup), "Tab closes them")
	_check(await _nav_press(func(c): return c is Button and c.text == "Уйти", "«Уйти»"), "shop: «Уйти» by the keys")
	await _wait(0.4)
	_check(run.phase != "shop", "shop left")
	# An event: its first offer by the keys.
	run.current = {"kind": "event"}
	run.event = {"id": "magic_man", "stage": "options", "pick": "", "result": "", "got": []}
	run.phase = "event"
	main.run_screen.rebuild()
	await _wait(0.6)
	await _key(KEY_DOWN)
	await _nav_press(func(c): return c is Button and c.text == "Выбрать", "«Выбрать»")
	await _wait(0.4)
	_check(run.event.get("stage", "") != "options" or run.phase != "event", "event: an offer taken by the keys")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_SAVE))


## The deck builder: hundreds of cards, a step of the frame must still be quick.
func _builder() -> void:
	main._close_run_screen()
	main.show_deck_builder("")
	await _wait(1.5)
	await _key(KEY_DOWN)
	var t0 := Time.get_ticks_usec()
	var n: int = kn.targets().size()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("builder: %d targets in %.1f ms" % [n, ms])
	_check(n > 20 and ms < 120.0, "deck builder: the targets are found quickly")
	t0 = Time.get_ticks_usec()
	await _key(KEY_RIGHT)
	await _key(KEY_DOWN)
	_check((Time.get_ticks_usec() - t0) / 1000.0 < 400.0, "deck builder: two steps of the frame are quick")
	# A card of the pool: Enter puts a copy in, Delete and Ctrl+Enter take one out.
	var b = main._open_builder()
	await _nav_press(func(c): return c.has_meta("kn_remove") and not c.has_meta("kn_zoom"), "a card of the pool", false)
	var total := func(): return b._deck.values().reduce(func(a, x): return a + x, 0)
	var n0: int = total.call()
	_check(kn.current.has_meta("kn_remove") and kn._frame != null and kn._frame.get_parent() == kn.current,
		"the frame is drawn by the card under it")
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	_check(total.call() == n0 + 2, "deck builder: Enter adds a copy")
	await _key(KEY_DELETE)
	_check(total.call() == n0 + 1, "deck builder: Delete takes a copy out")
	await _key(KEY_ENTER, false, true)
	_check(total.call() == n0, "deck builder: Ctrl+Enter takes a copy out")
	main._press_back()
	await _wait(0.5)


## A key changed in «Управление» works, the old one does not; the settings file is put back.
func _rebind() -> void:
	var path := "user://settings.cfg"
	var had := FileAccess.file_exists(path)
	var before := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()
	kn.set_key("draw", [KEY_G, false, false, false])
	var g := InputEventKey.new()
	g.physical_keycode = KEY_G
	g.pressed = true
	var d := InputEventKey.new()
	d.physical_keycode = KEY_D
	d.pressed = true
	_check(kn.is_action(g, "draw") and not kn.is_action(d, "draw"), "a key changed: G draws, D does not")
	kn.set_key("main", [KEY_G, false, false, false])
	_check(kn.is_action(g, "main") and not kn.is_action(g, "draw"), "a key taken by another action leaves the old one")
	kn.reset_keys()
	_check(kn.is_action(d, "draw"), "«Как было» gives the keys back")
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(before)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	kn.load_keys()


## The discard pile by the keys: the frame on it, Enter opens it, Enter on a card shows it big.
func _discard_look(board) -> void:
	await _board_press(board, "discard:%d" % board.viewer)
	await _wait(0.4)
	_check(board.picker_layer.visible, "discard: Enter opens the pile")
	await _wait(0.4)
	_check(kn.current != null and kn.current.has_meta("kn_zoom"), "discard: the frame on its top card")
	await _key(KEY_ENTER)
	await _wait(0.3)
	_check(board.zoom_layer.get_child_count() > 0, "discard: Enter shows the card big")
	await _key(KEY_ESCAPE)
	await _wait(0.2)
	await _key(KEY_ESCAPE)
	await _wait(0.3)
	_check(not board.picker_layer.visible, "discard: Esc closes it")
