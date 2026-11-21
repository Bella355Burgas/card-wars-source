extends Node
## Scripted UI test: builds a known board, then drives drag & drop, floops
## with target choices and attacks through real mouse events.
##   godot --path . res://tests/scenario.tscn -- <output_dir>

const MainScene := preload("res://scenes/main.tscn")

var out_dir := "user://scenario"
var main: Node
var board
var game
var shot_n := 0
var failures := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MainScene.instantiate()
	add_child(main)
	_drive()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, shot_n, name])
	print("shot ", name)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _expect(cond: bool, what: String) -> void:
	if cond:
		print("ok   ", what)
	else:
		failures += 1
		printerr("FAIL ", what)


## Pulls a card with this id out of the player's deck.
func _take(p: int, id: String):
	var ps = game.players[p]
	for c in ps.deck:
		if c.id == id:
			ps.deck.erase(c)
			return c
	push_error("no %s in deck" % id)
	return null


func _screen(world_pos: Vector2) -> Vector2:
	# Window pixels: canvas transform, then the stretch transform of the root viewport.
	return get_viewport().get_final_transform() * (board.world.get_global_transform_with_canvas() * world_pos)


func _mouse(world_pos: Vector2, pressed: int = -1) -> void:
	var sp := _screen(world_pos)
	Input.warp_mouse(sp)
	var mm := InputEventMouseMotion.new()
	mm.position = sp
	mm.global_position = sp
	Input.parse_input_event(mm)
	if pressed >= 0:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed == 1
		mb.position = sp
		mb.global_position = sp
		Input.parse_input_event(mb)


func _click(world_pos: Vector2) -> void:
	_mouse(world_pos)
	await _wait(0.1)
	_mouse(world_pos, 1)
	await _wait(0.05)
	_mouse(world_pos, 0)
	await _wait(0.2)


func _drive() -> void:
	await _wait(0.5)
	main.start_new_game()
	# Click through the coin toss, both mulligans and the first-turn curtain.
	for i in 8:
		await _wait(0.9)
		for root in main.overlay.get_children():
			var b := _find_button(root)
			if b != null and not b.disabled:
				b.pressed.emit()
		if main.board != null and main.board.mulligan_panel.visible:
			main.board._mulligan_done.emit(false)
	await _wait(2.5)
	board = main.board
	game = main.game
	var finn := 0
	var jake := 1
	# --- build a known mid-game position, Finn to act on turn 3 ---
	game.turn_player = finn
	game.turn_number = 3
	game.phase = "main"
	game.players[finn].actions = 2
	for p in 2:
		var ps = game.players[p]
		ps.deck.append_array(ps.hand)
		ps.hand.clear()
	game.players[finn].creatures[0] = _take(finn, "dragon_claw")
	game.players[finn].creatures[1] = _take(finn, "the_pig")
	game.players[finn].buildings[1] = _take(finn, "woad_mobile_home")
	game.players[jake].creatures[1] = _take(jake, "husker_knight")
	game.players[jake].creatures[2] = _take(jake, "corn_dog")
	game.players[jake].creatures[2].damage = 17
	game.players[jake].buildings[2] = _take(jake, "celestial_castle")
	for id in ["teleport", "woad_talisman", "cerebral_bloodstorm", "spirit_soldier", "celestial_castle"]:
		game.players[finn].hand.append(_take(finn, id))
	for id in ["cornataur", "field_reaper", "corn_scepter"]:
		game.players[jake].hand.append(_take(jake, id))
	board.set_viewer(finn)
	board.set_hands_hidden(false)
	await _wait(1.2)
	await _shot("position")

	# --- drag a creature from hand into zone 3 ---
	var soldier = game.players[finn].hand[3]
	var from: Vector2 = board.views[soldier.uid].position
	var to: Vector2 = board.creature_pos(finn, 2)
	_mouse(from)
	await _wait(0.3)
	_mouse(from, 1)
	await _wait(0.05)
	for i in 12:
		_mouse(from.lerp(to, (i + 1) / 12.0))
		await _wait(0.03)
	await _shot("dragging")
	_mouse(to, 0)
	await _wait(1.5)
	_expect(game.players[finn].creatures[2] == soldier, "drag & drop puts the soldier into zone 3")
	_expect(game.players[finn].actions == 1, "playing a 1-cost creature spends one action")
	await _shot("after_drop")

	# --- click the pig: context menu → floop flips Jake's cornfield in zone 2 ---
	await _click(board.creature_pos(finn, 1))
	await _shot("pig_menu")
	_expect(board.context_menu.visible, "clicking own creature opens the action menu")
	var floop_btn: Button = board.context_menu.get_child(0)
	floop_btn.pressed.emit()
	await _wait(2.0)
	_expect(game.players[jake].lands[1]["flipped"], "pig floop flipped Jake's cornfield in zone 2")
	await _shot("after_pig")

	# --- dragon claw: choose creature, then empty lane ---
	board._run(func(): await game.cmd_floop(finn, "creature", 0))
	await _wait(0.8)
	_expect(board._choice != null and board._choice["kind"] == "creature", "dragon claw asks for a creature")
	await _shot("choice_creature")
	await _click(board.creature_pos(finn, 2))
	await _wait(0.5)
	# Only zone 4 is empty, so the engine picks it without asking.
	await _wait(1.0)
	_expect(game.players[finn].creatures[3] != null and game.players[finn].creatures[3].id == "spirit_soldier",
		"soldier moved to zone 4")

	# --- cast a spell by clicking it, then its menu button ---
	var storm = null
	for c in game.players[finn].hand:
		if c.id == "cerebral_bloodstorm":
			storm = c
	await _click(board.views[storm.uid].position + Vector2(0, -40))
	await _wait(0.4)
	await _shot("spell_menu")
	if board.context_menu.visible:
		board.context_menu.get_child(0).pressed.emit()
	await _wait(2.5)
	_expect(game.players[finn].discard.has(storm), "bloodstorm went to the discard")
	_expect(game.players[jake].creatures[2] == null, "corn dog (17 dmg; DEF 12 + 3 fields + 3 castle) died to the storm")
	await _shot("after_storm")

	# --- attack ---
	board._on_main_button()
	await _wait(0.6)
	await _shot("attack_phase")
	var hp_before: int = game.players[jake].hp
	board._on_main_button()
	await _wait(4.0)
	_expect(game.players[jake].hp < hp_before, "attacks damaged Jake")
	await _shot("after_attack")
	print("failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)


func _find_button(n: Node) -> Button:
	if n is Button and n.is_visible_in_tree():
		return n
	for ch in n.get_children():
		var b := _find_button(ch)
		if b != null:
			return b
	return null
