extends "res://tests/zoom_test.gd"
## The screens of the ranked games and the quick game (scripts/ui/main/ranked.gd) at a scale, with the
## check that nothing leaves the screen, and screenshots:
##   godot --path . --resolution 2400x1080 -s res://tests/zoom_rank.gd -- <output_dir> 1,1.5 1 phone --relay ws://127.0.0.1:9
##   godot --path . --resolution 1440x1080 -s res://tests/zoom_rank.gd -- <output_dir> 1,1.5 --relay ws://127.0.0.1:9
## The «Играть» menu, the rank window (and its «Скоро» note), the quick game window, the search, the bans,
## the pick, the decks picked, the end of a ranked game, the nick of the other player on the table.
## Nothing goes to a server: the states are made up here.

const DECKS := ["finn", "jake", "pb", "lsp", "bmo", "rainicorn", "ice_king", "marceline", "lemongrab", "gunter",
	"fionna", "cake", "flame_princess", "fern", "prismo", "lich", "peppermint_butler", "magic_man", "jake_2x2", "charlie",
	"grand_prix", "monica"]


func _rank_tour(phase: String, done: Array, bans: Array, heroes: Array, over := false) -> Dictionary:
	var r := {"phase": phase, "decks": DECKS, "done": done, "left": 21}
	if phase != "ban":
		r["bans"] = bans
	if over:
		r["delta"] = [16, -12]
		r["st"] = [4, 2]
	return {"match": "X", "label": "Рейтинг", "bo": 1, "names": ["Очень_длинный_ник", "Соперник_2"], "heroes": heroes,
		"score": [0, 0], "game": 1, "seed": 5, "first": 0, "turn_time": 120, "undo": false, "over": over,
		"winner": 0 if over else null, "dispute": "", "last": {}, "rank": r}


func _run() -> void:
	await _wait(1.0)
	var saved: float = main.ui_zoom
	main.social.set_process(false)          # no link: the states below are made up
	main.account.token = "test"
	main.social.link_up = true
	main.social.rank = {"op": "r_me", "st": 4, "in": 72, "need": 160, "w": 12, "l": 7, "left": 23 * 86400 + 4 * 3600, "code": ""}
	for z: float in zooms:
		_set_zoom(z)
		main.show_play_menu()
		await _wait(0.6)
		await _check("play_menu")
		await _close_overlays()
		main.ranked.show_rank()
		await _wait(0.6)
		for b: Button in main.overlay.find_children("*", "Button", true, false):
			if b.text == "Скоро":
				b.pressed.emit()
		await _wait(0.2)
		await _check("rank_window")
		await _close_overlays()
		main.ranked.show_quick()
		await _wait(0.6)
		await _check("quick_window")
		await _close_overlays()
		main.ranked._show_search("rank")
		await _wait(1.2)
		await _check("search")
		main.ranked._close_search()
		await _close_overlays()

		# The bans, the pick, the decks of the game.
		main.lobby.show_net_lobby("rank")
		main.net.tour = _rank_tour("ban", [false, true], [], ["", ""])
		main.net.is_host = true
		main.ranked.draft_update()
		main.ranked._tap("finn")
		main.ranked._tap("lich")
		await _wait(0.6)
		await _check("rank_bans")
		main.net.tour = _rank_tour("pick", [false, false], [["finn", "lich"], ["bmo"]], ["", ""])
		main.ranked.draft_update()
		main.ranked._tap("marceline")
		await _wait(0.4)
		await _check("rank_pick")
		main.net.tour = _rank_tour("play", [true, true], [["finn", "lich"], ["bmo"]], ["marceline", "ice_king"])
		main.ranked.draft_update()
		await _wait(0.4)
		await _check("rank_play")
		main.lobby._close_lobby()
		await _close_overlays()

		# A game: the other player's nick on its panel, «+» by it; the end of a ranked game.
		main.start_new_game()
		await _wait(2.0)
		_press_curtain()
		for i in 2:
			await _wait(0.8)
			_press_curtain()
			await _wait(1.0)
			main.board._mulligan_done.emit(i == 1)
			await _wait(1.2)
		_press_curtain()
		await _wait(1.5)
		_press_curtain()
		await _wait(1.0)
		main.board.set_foe("Очень_длинный_ник", true)
		await _wait(0.4)
		await _check("board_foe")
		main.net.tour = _rank_tour("play", [true, true], [["finn"], []], ["marceline", "ice_king"], true)
		main.online = true
		main._on_game_over(0)
		await _wait(1.5)
		main.lobby._show_rematch_note()
		await _wait(0.2)
		await _check("rank_over")
		main.net.tour = {}
		main.online = false
		await _close_overlays()
		main._end_game()
		main.show_title()
		await _wait(0.5)
	main.account.token = ""
	main._save_setting("ui", "zoom", saved)
	print("ZOOM fails=%d" % fails)
	quit(1 if fails > 0 else 0)
