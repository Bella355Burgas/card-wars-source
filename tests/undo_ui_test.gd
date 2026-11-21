extends Node
## Undo on the real table against the AI (windowed):
##   godot --path . res://tests/undo_ui.tscn -- <shots_dir>
## On the player's turn a card is played, the undo button takes it back (the state is
## as before), and a second undo in the same turn is not offered.

const MainScene := preload("res://scenes/main.tscn")

var main: Node
var shots_dir := ""
var shot_n := 0
var fails := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	shots_dir = args[0] if args.size() > 0 else ""
	main = MainScene.instantiate()
	add_child(main)
	await _real_wait(0.5)
	main._last_heroes = ["finn", "ice_king"]
	main._ai_random = [false, false]
	Engine.time_scale = 4.0
	main.start_ai_game()
	var board = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000:
		await _real_wait(0.2)
		for t in ["Дальше", "Смотреть руку", "Оставить", "В бой!", "Готово"]:
			_press(t)
		board = main.board
		if board != null and main.game.turn_player == 0 and main.game.phase == "main" and not board._busy \
				and main.game.turn_number >= 2:
			break
	Engine.time_scale = 1.0
	var game = main.game
	print("STATE phase=%s turn=%d player=%d busy=%s" % [game.phase, game.turn_number, game.turn_player, board._busy if board else null])
	await _shot("start")
	ok(board != null and game.turn_player == 0, "the player's turn came")
	ok(board.undo_button.visible and board.undo_button.disabled, "the undo button is there, nothing to undo yet")
	ok(board.draw_button.position.x + board.draw_button.size.x + 8.0 <= board.undo_button.position.x,
		"a gap between the draw and the undo buttons")
	var plays: Array = game.legal_commands(0).filter(func(c): return c["cmd"] == "play")
	ok(not plays.is_empty(), "a card can be played")
	if plays.is_empty():
		_finish()
		return
	var before: int = game.state_hash()
	var hand_n: int = game.players[0].hand.size()
	await board._issue(plays[0])
	await _real_wait(1.0)
	ok(game.state_hash() != before, "the card was played")
	ok(not board.undo_button.disabled, "undo is offered after the move")
	await _shot("after_play")
	board._on_undo_button()
	await _real_wait(1.0)
	ok(game.state_hash() == before and game.players[0].hand.size() == hand_n, "undo puts the state back")
	await _shot("after_undo")
	plays = game.legal_commands(0).filter(func(c): return c["cmd"] == "play")
	await board._issue(plays[0])
	await _real_wait(1.0)
	ok(board.undo_button.disabled, "only one undo per turn")
	board.ai_agent = board.ai_agent    # the AI takes no part in the undo
	ok(not board._undo_seat(1), "the AI seat has no undo")
	_finish()


func _finish() -> void:
	print("RESULT %s (%d failed)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		fails += 1


func _real_wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _shot(name: String) -> void:
	if shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [shots_dir, shot_n, name])


## Presses the first visible enabled button with this text anywhere.
func _press(text: String) -> void:
	for b in get_tree().root.find_children("*", "Button", true, false):
		if b.text == text and not b.disabled and b.is_visible_in_tree():
			b.pressed.emit()
			return
