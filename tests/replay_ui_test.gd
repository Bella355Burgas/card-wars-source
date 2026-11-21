extends Node
## Replays on the real table (windowed):
##   godot --path . res://tests/replay_ui.tscn -- <shots_dir> [hero_a] [hero_b]
## An AI-against-AI game is played to the end; its replay goes to the list and is
## played back on the table (fast, from the list, with a change of sides) and must
## end in the very state the game ended in. Screenshots: game over, the replay
## list, the replay on the table (both sides), its end screen.
## «Ходы»: at turn 5 the replay jumps back to turn 2 (must be the recorded state there),
## and from the end screen to the last turn; it must end in the same state again.

const MainScene := preload("res://scenes/main.tscn")
const Replay = preload("res://scripts/core/replay.gd")
const CustomDecks = preload("res://scripts/core/custom_decks.gd")

var main: Node
var shots_dir := ""
var shot_n := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "open":
		_open_files(args[1], args[2])
		return
	shots_dir = args[0] if args.size() > 0 else ""
	main = MainScene.instantiate()
	add_child(main)
	await _real_wait(0.5)
	main._last_heroes = [args[1] if args.size() > 1 else "finn", args[2] if args.size() > 2 else "ice_king"]
	Engine.time_scale = 6.0
	main.start_ai_vs_ai_game()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		await _real_wait(0.2)
		_press_named("Начать!")
		if main.board != null:
			main.board.ai_speed = 4
		if main.game != null and main.game.phase == "over":
			break
	if main.game == null or main.game.phase != "over":
		print("RESULT FAIL the AI game did not finish")
		get_tree().quit(1)
		return
	Engine.time_scale = 1.0      # the game-over screen's countdown to the next AI game runs in real time
	await _real_wait(1.0)
	var final_hash: int = main.game.state_hash()
	var data: Dictionary = main._game_replay()
	var err: String = await Replay.verify(Replay.parse(JSON.stringify(data)))
	print("VERIFY '%s' steps=%d turns=%d winner=%d" % [err, data["steps"].size(), data["turns"], data["winner"]])
	await _shot("game_over")

	var kept := Replay.keep(data)
	for ch in main.overlay.get_children():
		main._close_overlay(ch)
	main._end_game()
	main.show_title()
	await _real_wait(0.5)
	main.show_replays()
	await _real_wait(1.0)
	await _shot("replays")
	_press_named("Смотреть")            # the newest row: this game
	await _real_wait(0.6)
	_press_named("Смотреть")            # the curtain
	Engine.time_scale = 6.0
	var flipped := false
	var jumped := false
	var jump_ok := false
	var shot_turns := {}
	var ended := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		await _real_wait(0.1)
		var board = main.board
		if board == null:
			continue
		board.ai_speed = 4
		if _overlay_titles().has("Конец реплея"):
			ended = true
			break
		var turn: int = main.game.turn_number
		if turn in [3, 4] and not shot_turns.has(turn) and main.game.phase == "main" and not board._busy:
			shot_turns[turn] = true
			Engine.time_scale = 1.0
			await _real_wait(0.6)
			await _shot("replay_turn_%d" % turn)
			if not flipped:
				flipped = true
				board.hero_button.pressed.emit()     # watch from the other side
				await _real_wait(0.5)
				await _shot("replay_turn_%d_other_side" % turn)
			Engine.time_scale = 6.0
		if turn >= 5 and not jumped and main.game.phase == "main" and not board._busy:
			jumped = true
			jump_ok = await _jump(board, 2, "back")
	Engine.time_scale = 1.0
	await _real_wait(1.0)
	await _shot("replay_end")
	# From the end screen to the last turn: the replay plays on and ends again.
	_press_named("Ходы")
	await _real_wait(1.5)
	var last: Dictionary = main._replay_marks[-1]
	var last_text := "Ход %d: %s" % [last["n"], main.game.players[int(last["p"])].name]
	_press_named(last_text)
	_press_named("▶ " + last_text)       # the turn on the table is marked
	await _real_wait(1.0)
	var resumed: bool = not _overlay_titles().has("Конец реплея") and main.game.turn_number == int(last["n"])
	Engine.time_scale = 6.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000 and not _overlay_titles().has("Конец реплея"):
		await _real_wait(0.2)
	Engine.time_scale = 1.0
	await _real_wait(0.5)
	print("JUMP back_ok=%s end_resumed=%s ended_again=%s" % [jump_ok, resumed, _overlay_titles().has("Конец реплея")])
	ended = ended and jump_ok and resumed and _overlay_titles().has("Конец реплея")
	var same: bool = main.game != null and main.game.state_hash() == final_hash
	print("RESULT %s ended=%s same_state=%s overlays=%s" % ["OK" if ended and same and err == "" else "FAIL",
		ended, same, _overlay_titles()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(kept))
	get_tree().quit(0 if ended and same and err == "" else 1)


## «Ходы» on the table, a click on turn n: the table must show the recorded state there.
func _jump(board, n: int, tag: String) -> bool:
	Engine.time_scale = 1.0
	board.ai_paused = true               # paused, the table stays where it jumped
	board.turns_button.pressed.emit()
	await _real_wait(1.5)
	await _shot("turns_list_" + tag)
	var mark: Dictionary = {}
	for m in main._replay_marks:
		if int(m["n"]) == n:
			mark = m
	if mark.is_empty():
		return false
	_press_named("Ход %d: %s" % [n, main.game.players[int(mark["p"])].name])
	await _real_wait(1.5)
	var st: Dictionary = main._replay["steps"][int(mark["pos"])]
	var ok: bool = main.board == board and main.game.turn_number == n and board.replay_pos() == int(mark["pos"]) 		and main.game.state_hash() == int(st["h"])
	print("JUMP to=%d turn=%d pos=%d/%d ok=%s" % [n, main.game.turn_number, board.replay_pos(), mark["pos"], ok])
	await _shot("jumped_to_turn_%d" % n)
	board.ai_paused = false
	Engine.time_scale = 6.0
	return ok


## Opening files (windowed):
##   godot --path . res://tests/replay_ui.tscn <replay.cwreplay> -- open <deck.cwdeck> <shots_dir>
## The replay given at launch (as a double click on it does) must start by itself;
## a deck file opened on the title screen must join the decks and open in the builder.
func _open_files(deck_path: String, dir: String) -> void:
	shots_dir = dir
	var replays_before := DirAccess.get_files_at(Replay.DIR)
	main = MainScene.instantiate()
	add_child(main)
	await _real_wait(2.0)
	await _shot("launched_with_replay")
	var started: bool = main._replay != null and _overlay_titles().has("Реплей")
	_press_named("Смотреть")
	await _real_wait(4.0)
	await _shot("replay_playing")
	main._end_game()
	main.show_title()
	await _real_wait(0.5)
	main.open_file(deck_path)
	await _real_wait(1.0)
	await _shot("deck_opened")
	var deck_ok := false
	for e in CustomDecks.load_all():
		deck_ok = deck_ok or e.get("name", "") == "Колода друга"
	var builder = main._open_builder()
	var note: String = builder._status.text if builder != null else ""
	print("RESULT %s replay_started=%s deck_added=%s builder_note='%s'" % ["OK" if started and deck_ok
		and note.contains("добавлена") else "FAIL", started, deck_ok, note])
	CustomDecks.remove("Колода друга")
	for name in DirAccess.get_files_at(Replay.DIR):
		if not replays_before.has(name):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Replay.DIR.path_join(name)))
	get_tree().quit()


func _real_wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _shot(name: String) -> void:
	if shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [shots_dir, shot_n, name])


## Presses the first enabled button with this text on an open overlay.
func _press_named(text: String) -> void:
	for root in main.overlay.get_children():
		if root.is_queued_for_deletion() or (root is Control and root.mouse_filter == Control.MOUSE_FILTER_IGNORE):
			continue
		for b in root.find_children("*", "Button", true, false):
			if b.text == text and not b.disabled and b.is_visible_in_tree():
				b.pressed.emit()
				return


func _overlay_titles() -> Array:
	var out := []
	for root in main.overlay.get_children():
		for l in root.find_children("*", "Label", true, false):
			if l.label_settings != null and l.label_settings.font_size >= 48:
				out.append(l.text)
	return out
