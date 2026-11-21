extends SceneTree
## A game against the AI by the gamepad alone (gamepad.gd): only InputEventJoypadButton and
## InputEventJoypadMotion are fed. The title, «Играть», «Против ИИ», «С героем» / «Без героя»,
## «В бой!», the curtains, the start hand, cards played, an attack, a choice on the table and
## one in a window, X draws, Y shows a card big, Select the log, the shoulders the hand, the
## end of the turn, Start the pause, B back, the pause's way out. Also the InputMap actions,
## the makes of pads, the dead zone, the repeat, a pad plugged in and out, the mouse that
## hides the hints, a button changed in «Геймпад».
##   godot --headless --path . -s res://tests/gamepad_test.gd
## Screenshots of the frame in the menus and of the table frame in 1 на 1, 2 на 2, на троих:
##   godot --path . --resolution 1920x1080 -s res://tests/gamepad_test.gd -- shots <dir> [phone]

const MainScene := preload("res://scenes/main.tscn")
const Board = preload("res://scripts/ui/board.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const Gamepad = preload("res://scripts/ui/gamepad.gd")

var main
var kn
var pad
var fails := 0
var presses := 0
var played := 0
var attacked := 0
var chosen := 0
var turns_ended := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	main = MainScene.instantiate()
	if args.size() > 2 and args[2] == "phone":
		main.phone_layout = true
	root.add_child(main)
	if args.size() > 0 and args[0] == "shots":
		_shots(args[1] if args.size() > 1 else "user://gamepad_shots")
	else:
		_run()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


# ---------------------------------------------------------------- the pad

func _btn(b: JoyButton) -> void:
	presses += 1
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = b
		e.pressed = down
		e.pressure = 1.0 if down else 0.0
		Input.parse_input_event(e)
		await _frames(3)
	await process_frame


func _axis(a: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)
	await _frames(3)


func _trigger(a: JoyAxis) -> void:
	presses += 1
	await _axis(a, 1.0)
	await _axis(a, 0.0)


## A step of the frame: by the cross, or now and then by the left stick.
func _step(d: Vector2, i: int) -> void:
	presses += 1
	if i % 3 == 2:
		var axis := JOY_AXIS_LEFT_X if d.x != 0.0 else JOY_AXIS_LEFT_Y
		await _axis(axis, d.x + d.y)
		await _axis(axis, 0.0)
		return
	var b: JoyButton = {Vector2.LEFT: JOY_BUTTON_DPAD_LEFT, Vector2.RIGHT: JOY_BUTTON_DPAD_RIGHT,
		Vector2.UP: JOY_BUTTON_DPAD_UP, Vector2.DOWN: JOY_BUTTON_DPAD_DOWN}[d]
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(3)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(2)


func _toward(from: Vector2, to: Vector2, i: int) -> Vector2:
	var d := to - from
	var horizontal := absf(d.x) > absf(d.y)
	if i % 7 == 6:
		horizontal = not horizontal
	if horizontal and absf(d.x) > 2.0 or absf(d.y) <= 2.0:
		return Vector2.RIGHT if d.x > 0 else Vector2.LEFT
	return Vector2.DOWN if d.y > 0 else Vector2.UP


func _has_text(c: Node, s: String) -> bool:
	if c is Button and (c as Button).text == s:
		return true
	for l in c.find_children("*", "Label", true, false):
		if (l as Label).text == s:
			return true
	return false


func _frame_ok() -> bool:
	return kn.keyboard and kn.current != null and is_instance_valid(kn.current) and kn.targets().has(kn.current)


## The window frame goes by the pad to what `pred` picks; A presses it.
func _nav_press(pred: Callable, what: String, press := true) -> bool:
	for i in 50:
		var cands: Array = kn.targets()
		var goal: Control = null
		for c in cands:
			if pred.call(c):
				goal = c
				break
		if goal == null:
			await _wait(0.2)
			continue
		if not _frame_ok():
			await _step(Vector2.DOWN, 0)
			continue
		if kn.current == goal:
			if press:
				await _btn(JOY_BUTTON_A)
			return true
		await _step(_toward(kn.rect_of(kn.current).get_center(), kn.rect_of(goal).get_center(), i), i)
	_check(false, "frame reaches " + what)
	return false


## The table frame goes by the pad to the target with this id; A presses it.
func _board_press(board, id: String, press := true) -> bool:
	for i in 40:
		if not kn.keyboard:
			await _step(Vector2.RIGHT, 0)
			continue
		var cur: Dictionary = board._kb_current()
		var goal := {}
		for t in board._kb_targets():
			if t["id"] == id:
				goal = t
		if goal.is_empty():
			return false
		if cur["id"] == id:
			if press:
				await _btn(JOY_BUTTON_A)
			return true
		await _step(_toward(board._kb_at(cur), board._kb_at(goal), i), i)
	_check(false, "table frame reaches " + id)
	return false


# ---------------------------------------------------------------- the test

func _run() -> void:
	await process_frame
	kn = root.get_node("KeyNav")
	pad = root.get_node("Gamepad")
	Board.turn_speed = 4.0
	await _wait(1.5)
	_basics()
	await _stick_and_repeat()
	await _menus()
	await _game()
	await _plug()
	_rebind()
	print("pad presses: %d, keys made: %d" % [presses, pad.sent])
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)


func _basics() -> void:
	var all := true
	for id in ["pad_up", "pad_down", "pad_left", "pad_right", "pad_accept", "pad_back", "pad_end", "pad_draw", "pad_pause", "pad_card"]:
		var evs := InputMap.action_get_events(id) if InputMap.has_action(id) else []
		if evs.is_empty() or not evs.all(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion):
			all = false
			print("  no pad events: ", id)
	_check(all, "InputMap has the pad actions")
	_check(Gamepad.kind_of("Xbox Series Controller") == "xbox" and Gamepad.kind_of("XInput Controller") == "xbox"
		and Gamepad.kind_of("PS5 Controller") == "ps" and Gamepad.kind_of("DualSense Wireless Controller") == "ps"
		and Gamepad.kind_of("PS4 Controller") == "ps" and Gamepad.kind_of("Nintendo Switch Pro Controller") == "nintendo"
		and Gamepad.kind_of("USB Gamepad") == "generic" and Gamepad.kind_of("", {"vendor_id": 0x054c}) == "ps",
		"the makes of pads by name and vendor")
	_check(Gamepad.Glyph.label_of("b%d" % JOY_BUTTON_A, "nintendo") == "B" and Gamepad.Glyph.label_of("b%d" % JOY_BUTTON_B, "xbox") == "B"
		and Gamepad.Glyph.label_of("a%d+" % JOY_AXIS_TRIGGER_RIGHT, "ps") == "R2" and Gamepad.Glyph.label_of("b%d" % JOY_BUTTON_START, "nintendo") == "+",
		"button names by the make")


func _stick_and_repeat() -> void:
	main.show_title()
	await _wait(0.6)
	# A little push of the stick stays in the dead zone.
	var n0: int = pad.sent
	await _axis(JOY_AXIS_LEFT_X, 0.12)
	await _frames(4)
	await _axis(JOY_AXIS_LEFT_X, 0.0)
	_check(pad.sent == n0, "the stick in the dead zone does nothing")
	await _axis(JOY_AXIS_LEFT_Y, 1.0)
	await _frames(3)
	_check(pad.active and kn.keyboard, "the stick shows the frame and the hints")
	_check(pad._bar_box.visible, "the hints bar is shown")
	# Held: the frame goes on by itself.
	var n1: int = pad.sent
	await _wait(1.0)
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	_check(pad.sent - n1 >= 4, "a held stick repeats: %d steps" % (pad.sent - n1))
	# The mouse hides the frame and the hints.
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(20, 5)
	mm.position = Vector2(400, 300)
	Input.parse_input_event(mm)
	await _frames(3)
	_check(not pad.active and not kn.keyboard and not pad._bar_box.visible, "the mouse hides the frame and the hints")


func _menus() -> void:
	# Settings: the «Геймпад» window by the pad, B back.
	_check(await _nav_press(func(c): return _has_text(c, "Настройки"), "«Настройки»"), "title: «Настройки» by the pad")
	await _wait(0.5)
	_check(await _nav_press(func(c): return c is Button and c.text == "Геймпад", "«Геймпад»"), "settings: «Геймпад»")
	await _wait(0.5)
	_check(_find_button("Как было") != null, "the «Геймпад» window is open")
	await _btn(JOY_BUTTON_B)
	await _wait(0.5)
	_check(_find_button("Как было") == null and _find_button("Геймпад") != null, "B: back to the settings")
	await _btn(JOY_BUTTON_B)
	await _wait(0.5)
	_check(_find_button("Геймпад") == null, "B closes the settings")
	_check(await _nav_press(func(c): return _has_text(c, "Играть"), "«Играть»"), "title: «Играть» by the pad")
	await _wait(0.6)
	_check(await _nav_press(func(c): return c is Button and _has_text(c, "Против ИИ"), "«Против ИИ»"), "play menu: «Против ИИ»")
	await _wait(1.0)
	# «С героем» / «Без героя» by the pad, there and back.
	var hb := _find_button("С героем")
	if hb != null:
		await _nav_press(func(c): return c == hb, "«С героем»")
		await _wait(0.2)
		_check(hb.text == "Без героя", "hero select: A turns «С героем» into «Без героя»")
		await _btn(JOY_BUTTON_A)
		await _wait(0.2)
		_check(hb.text == "С героем", "hero select: and back")
	else:
		_check(false, "hero select: «С героем» found")
	# RB / LB in a list: no error, the frame stays.
	await _btn(JOY_BUTTON_RIGHT_SHOULDER)
	await _btn(JOY_BUTTON_LEFT_SHOULDER)
	# Y on a hero tile: its card in the preview, the screen stays.
	await _step(Vector2.DOWN, 0)
	await _step(Vector2.RIGHT, 0)
	await _btn(JOY_BUTTON_Y)
	await _wait(0.3)
	_check(main.board == null and _find_button("В бой!") != null, "Y on a tile keeps the hero select")
	await _trigger(JOY_AXIS_TRIGGER_RIGHT)       # «В бой!» wherever the frame is
	await _wait(1.0)


func _find_button(text: String) -> Button:
	for b in main.find_children("*", "Button", true, false):
		if b is Button and b.text == text and b.is_visible_in_tree():
			return b
	return null


func _game() -> void:
	var board = null
	var t0 := Time.get_ticks_msec()
	var tried := {}
	var turn := -1
	var my_turns := 0
	var drew := false
	var looked := false
	var logged := false
	var forced := false
	var stepped := false
	var paused := false
	var told := 0
	while Time.get_ticks_msec() - t0 < 400000:
		await _wait(0.12)
		board = main.board
		if Time.get_ticks_msec() - told > 15000:
			told = Time.get_ticks_msec()
			print("  game: board %s, phase %s, frame on %s %s, played %d, attacks %d, turns %d" % [board != null,
				board.game.phase if board != null and board.game != null else "-", kn.current if is_instance_valid(kn.current) else null,
				kn.current.text if is_instance_valid(kn.current) and kn.current is Button else "", played, attacked, turns_ended])
		if board == null or board.game == null:
			# The curtains before the game.
			if _frame_ok():
				await _btn(JOY_BUTTON_A)
			elif not kn.targets().is_empty():
				await _step(Vector2.DOWN, 0)
			continue
		var game = board.game
		if game.phase == "over":
			break
		if board._busy and board._choice == null:
			continue
		if not board._kb_free():
			if board.mulligan_panel.visible:
				await _nav_press(func(c): return c is Button and c.text == "Оставить", "«Оставить»")
			elif board.picker_layer.visible and board._choice != null:
				if _frame_ok():
					await _btn(JOY_BUTTON_A)
					chosen += 1
				else:
					await _step(Vector2.DOWN, 0)
			elif not kn.targets().is_empty():
				if _frame_ok():
					await _btn(JOY_BUTTON_A)
				else:
					await _step(Vector2.DOWN, 0)
			continue
		if board._arranging >= 0:
			await _board_press(board, "arrange")
			continue
		if board._choice != null:
			if not kn.keyboard:
				await _step(Vector2.RIGHT, 0)
			await _btn(JOY_BUTTON_A)
			chosen += 1
			continue
		if not board._can_act():
			continue
		if game.turn_number != turn:
			turn = game.turn_number
			tried.clear()
			my_turns += 1
			# The turn before ended by RT: only the pad ends a turn here.
			turns_ended = maxi(turns_ended, my_turns - 1)
		var me: int = board.viewer
		if not stepped and game.players[me].hand.size() >= 2:
			stepped = true
			await _step(Vector2.RIGHT, 0)
			var id0: String = board._kb_id
			await _btn(JOY_BUTTON_RIGHT_SHOULDER)
			var id1: String = board._kb_id
			await _btn(JOY_BUTTON_LEFT_SHOULDER)
			_check(id1 != id0 and id1.begins_with("u:") and board._kb_id == id0, "RB and LB step through the hand")
		if not paused:
			# Start: the pause; B closes it.
			paused = true
			await _btn(JOY_BUTTON_START)
			await _wait(0.4)
			_check(main._pause_root != null and is_instance_valid(main._pause_root), "Start opens the pause")
			await _btn(JOY_BUTTON_B)
			await _wait(0.4)
			_check(main._pause_root == null or not is_instance_valid(main._pause_root), "B closes the pause")
			continue
		if not logged:
			logged = true
			await _btn(JOY_BUTTON_BACK)
			await _wait(0.3)
			_check(board.pad_log_open(), "Select opens the log")
			await _axis(JOY_AXIS_RIGHT_Y, 1.0)
			await _wait(0.2)
			await _axis(JOY_AXIS_RIGHT_Y, 0.0)
			await _btn(JOY_BUTTON_B)
			await _wait(0.3)
			_check(not board.pad_log_open(), "B closes the log")
		if not looked:
			looked = true
			var v = board._kb_view()
			if v == null:
				await _step(Vector2.RIGHT, 0)
				v = board._kb_view()
			await _btn(JOY_BUTTON_Y)
			await _wait(0.3)
			_check(board.inspect_layer.visible, "Y shows the card under the frame big")
			await _btn(JOY_BUTTON_B)
			await _wait(0.3)
			_check(not board.inspect_layer.visible and main._pause_root == null, "B closes it, no pause")
		if not drew and game.phase == "main" and game.can_draw_for_action(me) and game.players[me].deck.size() > 0:
			drew = true
			var h0: int = game.players[me].hand.size()
			await _btn(JOY_BUTTON_X)
			await _wait(0.8)
			_check(game.players[me].hand.size() == h0 + 1, "X draws a card")
			continue
		if not forced and my_turns >= 2 and game.phase == "main":
			forced = true
			await _forced_choices(board)
			continue
		if game.phase == "attack":
			var lane := -1
			for l in 4:
				if not tried.has("a%d" % l) and game.can_attack(me, l):
					lane = l
					break
			if lane >= 0:
				tried["a%d" % lane] = true
				var c = game.players[me].creatures[lane]
				if c != null and await _board_press(board, "u:%d" % c.uid):
					attacked += 1
					await _wait(0.5)
				continue
		if not board._drop_targets.is_empty():
			await _btn(JOY_BUTTON_A)        # the frame on the first place the card may go
			played += 1
			await _wait(0.2)
			continue
		if game.phase == "main":
			var pick := -1
			for c in game.players[me].hand:
				if not tried.has(c.uid) and game.can_play(me, c.uid):
					pick = c.uid
					break
			if pick >= 0:
				tried[pick] = true
				if await _board_press(board, "u:%d" % pick):
					await _wait(0.3)
					if board.context_menu.visible:
						await _btn(JOY_BUTTON_A)     # a spell: its menu, the frame on «Сыграть»
						played += 1
				continue
		await _trigger(JOY_AXIS_TRIGGER_RIGHT)
		await _wait(0.3)
		if turns_ended >= 2 and attacked >= 1 and played >= 2 and forced:
			break
	board = main.board
	print("  game left: board %s, phase %s, turn %s, my turns %d" % [board != null, board.game.phase if board != null and board.game != null else "-",
		board.game.turn_number if board != null and board.game != null else -1, my_turns])
	if board != null and board.game != null and board.game.phase == "over":
		for l in board._log_lines.slice(-12):
			print("    ", l.strip_edges())
	_check(played >= 2, "cards played by the pad: %d" % played)
	_check(attacked >= 1, "attacks by the pad: %d" % attacked)
	_check(chosen >= 2, "choices made by the pad: %d" % chosen)
	_check(turns_ended >= 1, "turns ended by the pad: %d" % turns_ended)
	if board == null or board.game == null:
		return
	if board.game.phase == "over":
		# The game is over: the end screen by the pad.
		await _wait(2.5)
		_check(await _nav_press(func(c): return c is Button and c.text == "Главное меню", "«Главное меню»"), "end screen: «Главное меню» by the pad")
		await _wait(1.0)
		_check(main.board == null or not is_instance_valid(main.board), "back at the title")
		return
	# Start again and the pause's way out.
	for i in 60:
		if board._kb_free() and not board._busy:
			break
		await _wait(0.2)
	await _btn(JOY_BUTTON_START)
	await _wait(0.4)
	_check(await _nav_press(func(c): return c is Button and c.text.contains("выйти в меню"), "the way out"), "pause: out by the pad")
	await _wait(1.0)
	_check(main.board == null or not is_instance_valid(main.board), "back at the title")


## A choice in a window (options) and one on the table (a land of the other side), by the pad.
func _forced_choices(board) -> void:
	var res := {}
	var ask := func(req): res["r"] = await board.choose(req)
	ask.call({"kind": "option", "player": board.viewer, "prompt": "Что сделать?", "options": ["Первое", "Второе"]})
	await _wait(0.4)
	_check(board.picker_layer.visible, "a choice window is open")
	await _nav_press(func(c): return c is Button and c.text == "Второе", "«Второе»")
	await _wait(0.3)
	_check(res.get("r") == "Второе", "the window's choice by the pad")
	chosen += 1
	res.clear()
	var foe: int = 1 - board.viewer if board.game.players.size() == 2 else (board.viewer + 1) % board.game.players.size()
	ask.call({"kind": "land", "player": board.viewer, "prompt": "Выбери землю",
		"options": [{"p": board.viewer, "lane": 0}, {"p": foe, "lane": 2}]})
	await _wait(0.4)
	await _board_press(board, "land:%d:2" % foe)
	await _wait(0.3)
	_check(res.get("r") is Dictionary and int(res["r"].get("p", -1)) == foe, "the table's choice by the pad")
	chosen += 1


func _plug() -> void:
	pad._on_joy_connection(0, true)
	await _frames(2)
	_check(pad._note.visible and pad._note.text == "Геймпад подключён", "a pad plugged in: a note")
	pad.active = true
	pad._on_joy_connection(0, false)
	await _frames(2)
	_check(pad._note.text == "Геймпад отключён" and not pad.active, "a pad pulled out: a note, the hints gone")


## A button changed in «Геймпад» works, the old one does not; the settings file is put back.
func _rebind() -> void:
	var path := "user://settings.cfg"
	var had := FileAccess.file_exists(path)
	var before := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()
	pad.set_bind("pad_draw", "b%d" % JOY_BUTTON_LEFT_STICK)
	var ls := InputEventJoypadButton.new()
	ls.button_index = JOY_BUTTON_LEFT_STICK
	ls.pressed = true
	var x := InputEventJoypadButton.new()
	x.button_index = JOY_BUTTON_X
	x.pressed = true
	_check(ls.is_action("pad_draw") and not x.is_action("pad_draw") and not ls.is_action("pad_items"),
		"a button changed: L3 draws, X does not, L3 left the items")
	pad.set_sense(4)
	_check(is_equal_approx(InputMap.action_get_deadzone("pad_left"), pad.DEAD_ZONES[4]), "the stick's sensitivity sets the dead zone")
	pad.reset_binds()
	_check(x.is_action("pad_draw"), "«Как было» gives the buttons back")
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(before)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	pad.load_binds()


# ---------------------------------------------------------------- screenshots

## The pictures of this make of pad (a test has no real pad to name it).
func _kind(k: String) -> void:
	pad.kind = k
	pad._bar_mode = ""
	pad.active = true


func _shot(dir: String, name: String) -> void:
	await _frames(4)
	var img := root.get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("shot ", path)


func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	# The real mouse over the window must not hide the hints.
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	await process_frame
	kn = root.get_node("KeyNav")
	pad = root.get_node("Gamepad")
	Board.turn_speed = 4.0
	await _wait(1.5)
	var suffix := "_%dx%d%s" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y, "_phone" if main.phone_layout else ""]
	main.show_title()
	await _wait(0.5)
	await _step(Vector2.DOWN, 0)
	await _step(Vector2.DOWN, 0)
	_kind("xbox")
	await _wait(0.3)
	await _shot(dir, "pad_title" + suffix)
	main.show_hero_select("ai")
	await _wait(1.0)
	await _step(Vector2.DOWN, 0)
	await _step(Vector2.RIGHT, 0)
	_kind("ps")
	await _wait(0.3)
	await _shot(dir, "pad_heroes" + suffix)
	for r in main.overlay.get_children():
		main._close_overlay(r)
	await _wait(0.3)
	main.show_gamepad()
	await _wait(0.6)
	await _step(Vector2.DOWN, 0)
	await _wait(0.3)
	await _shot(dir, "pad_settings" + suffix)
	for it in [["one", ["finn", "jake"], "xbox"], ["teams", ["finn", "jake", "bmo", "marceline"], "nintendo"], ["three", ["finn", "jake", "bmo"], "generic"]]:
		for r in main.overlay.get_children():
			main._close_overlay(r)
		main.show_title()
		await _wait(0.3)
		main.sandbox_start.start(it[1])
		await _wait(2.0)
		for i in 300:
			await process_frame
			if main.board != null and not main.board._busy:
				break
		var b = main.board
		var g = main.game
		var sb = b.sandbox
		b.sb_panel.visible = false
		var ids := ["cool_dog", "corn_lord", "big_foot", "archer_dan"]
		for p in g.players.size():
			for lane in 4:
				if (lane + p) % 4 != 3:
					await sb.add_card(p, ids[(lane + p) % ids.size()], "creature", lane)
			for i in 2:
				await sb.add_card(p, "cool_dog", "hand")
		b.sync()
		b._update_hud()
		await _wait(1.0)
		# The frame from the hand up to a creature of an opponent.
		await _step(Vector2.RIGHT, 0)
		for i in 3:
			await _step(Vector2.UP, 0)
		_kind(it[2])
		await _wait(0.5)
		await _shot(dir, "pad_table_%s%s" % [it[0], suffix])
		main._end_game()
		await _wait(0.4)
	quit(0)
