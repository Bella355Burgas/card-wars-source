extends "res://tests/zoom_test.gd"
## More screens for the scale: the train menu, the table of the day, the deck builder lists,
## the AI hero select, and the scale changed in the middle of a game from the pause menu.


func _run() -> void:
	await _wait(1.0)
	var saved: float = main.ui_zoom
	_set_zoom(1.5)
	main.open_run()
	await _wait(0.5)
	await _check("run_menu")
	await _close_overlays()
	main.show_daily_board()
	await _wait(2.0)
	await _check("daily")
	await _close_overlays()
	main.show_hero_select("ai")
	await _wait(0.8)
	await _check("hero_select_ai")
	await _close_overlays()
	main.show_deck_builder("")
	await _wait(1.0)
	var b = main.overlay.find_children("*", "OptionButton", true, false)
	if not b.is_empty():
		b[0].show_popup()
		await _wait(0.4)
		await _check("builder_list")
	await _close_overlays()
	# The scale changed in a game: 100% at the start, then 150% from the pause menu.
	_set_zoom(1.0)
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
	main.show_pause()
	await _wait(0.5)
	for btn in main.overlay.find_children("*", "Button", true, false):
		if btn.text == "Настройки":
			btn.pressed.emit()
	await _wait(0.5)
	for i in 3:
		var zb: Button = null
		for btn in main.overlay.find_children("*", "Button", true, false):
			if btn.text.begins_with("Масштаб"):
				zb = btn
		await _click(_screen_rect(zb).get_center())
		await _wait(0.3)
	tag = "live%d" % roundi(main.ui_zoom * 100.0)
	await _check("settings")
	await _close_overlays()
	await _check("board")
	main.show_pause()
	await _wait(0.5)
	await _check("pause")
	await _close_overlays()
	main._save_setting("ui", "zoom", saved)
	print("ZOOM fails=%d" % fails)
	quit(1 if fails > 0 else 0)
