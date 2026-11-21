extends SceneTree
## Screenshots of the wagons of «Бесконечный поезд» (windowed, not headless):
##   godot --path . -s res://tests/shots_wagons.gd -- <output_dir>
## Doors with a wagon rule (the tallest: an elite with stats), the boss's door with its
## rule, and the table in Туман, Ночной вагон, Прозрачный вагон and Метель with cards
## of both sides in play. The run is saved to user://run_shots.json (removed at the end).

const MainScene := preload("res://scenes/main.tscn")
const TrainRun = preload("res://scripts/train/train_run.gd")

var out_dir := "user://shots_wagons"
var n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	root.get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, shot_name])
	print("shot ", shot_name)


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _press(text: String) -> bool:
	for b in root.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return true
	print("no button ", text)
	return false


func _run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await _wait(1.0)
	var run := TrainRun.new()
	run.save_path = "user://run_shots.json"
	run.start("finn", 3)
	run.wagon = 4
	run.doors = [
		{"kind": "fight", "enemy": "jake", "hp": 10, "level": "easy", "seed": 5, "stats": {}},
		{"kind": "elite", "enemy": "marceline", "hp": 15, "level": "medium", "seed": 6,
			"stats": {"crit": 20, "lifesteal": 50}, "wagon": "lich_dice"},
		{"kind": "rest"},
	]
	main.run = run
	main.show_run()
	await _wait(0.8)
	await _shot("doors_rule")
	run.wagon = 9
	run.doors = [{"kind": "boss", "enemy": "ice_king", "hp": 20, "level": "hard", "seed": 7,
		"stats": {"crit": 20, "armor": 1}, "wagon": "boss_ice_king"}]
	main.run_screen.rebuild()
	await _wait(0.8)
	await _shot("doors_boss")

	for rule in ["fog", "night", "glass", "boss_ice_king"]:
		run.wagon = 4
		run.phase = "fight"
		run.current = {"kind": "fight", "enemy": "jake", "hp": 10, "level": "novice", "seed": 4,
			"stats": {}, "wagon": rule}
		main.start_run_fight()
		await _wait(1.6)
		await _shot(rule + "_coin")
		_press("Дальше")
		await _wait(1.2)
		_press("Оставить")
		await _wait(2.5)
		# Cards of both sides in play, as after a few turns.
		var g = main.game
		for side in 2:
			for lane in [0, 2, 3]:
				for c in g.players[side].deck:
					if c.kind() == "creature":
						g.players[side].deck.erase(c)
						g.players[side].creatures[lane] = c
						break
			for c in g.players[side].deck:
				if c.kind() == "building":
					g.players[side].deck.erase(c)
					g.players[side].buildings[1] = c
					break
		if rule == "boss_ice_king":
			g.train.wagon_state["closed"] = 2
		main.board.sync()
		await _wait(1.2)
		await _shot(rule + "_table")
		main.board.force_over(0)
		main._on_game_over(0)
		await _wait(1.2)
		_press("Дальше")
		await _wait(0.6)
		run.phase = "fight"
	run.lose()
	quit()
