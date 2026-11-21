extends SceneTree
## Screenshots of the difficulty and the chronicle of «Бесконечный поезд» (windowed, not headless):
##   godot --path . -s res://tests/shots_difficulty.gd -- <output_dir>
## The choice of the level before a run, the level in the status line and its penalties, the shop with
## the marked-up prices, a locomotive beaten and the level it opens, the end screen with the chronicle
## (a short run, a long one that scrolls, a train of the day) and the records kept by _run_over.
## The run is saved to user://run_shots_diff.json (removed at the end); the settings are put back.

const MainScene := preload("res://scenes/main.tscn")
const TrainRun = preload("res://scripts/train/train_run.gd")

var out_dir := "user://shots_difficulty"
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


## The two arrows of the difficulty picker (left, right) in the open hero selection; [] when it is not there.
func _picker_arrows() -> Array:
	for l in root.find_children("*", "Label", true, false):
		if l.text.begins_with("Сложность ") and l.is_visible_in_tree() and l.get_parent().get_parent() is HBoxContainer and l.get_parent().get_parent().get_child_count() == 3:
			var box: Node = l.get_parent().get_parent()
			if box.get_child(0) is Button:
				return [box.get_child(0), box.get_child(2)]
	return []


func _check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "FAIL ") + what)


## A run of `wagons` wagons of all kinds, as if played.
func _played(pick: String, difficulty: int, wagons: int) -> Object:
	var run := TrainRun.new()
	run.save_path = "user://run_shots_diff.json"
	run.start(pick, 11, "", difficulty)
	var kinds := ["fight", "fight", "treasure", "elite", "rest", "shop", "double", "event", "fight", "fight"]
	var heroes: Array = ["jake", "bmo", "marceline", "pb", "fionna", "ice_king", "lich", "cake", "lsp", "gunter"]
	for k in wagons:
		var kind: String = kinds[k % kinds.size()]
		if k % TrainRun.TRAIN_LEN == TrainRun.TRAIN_LEN - 1:
			kind = "boss"
		var fights := TrainRun.FIGHTS.has(kind)
		run.current = {"kind": kind}
		if fights:
			run.current["enemy"] = heroes[(k * 3) % heroes.size()]
			if kind == "double":
				run.current["second"] = {"enemy": heroes[(k * 3 + 1) % heroes.size()]}
			if k % 4 == 1:
				run.current["wagon"] = "fair"
		run.chronicle.append(run._chronicle_entry())
		run.passed += 1
		run.wins += 1 if fights else 0
	run.train = 1 + wagons / TrainRun.TRAIN_LEN
	run.bosses = wagons / TrainRun.TRAIN_LEN
	run.items = ["finn_sword", "ice_crown", "lich_cloak", "bmo_console", "cat_paw"]
	run.curses = ["lich_chill", "rusty_chain"]
	run.upgraded = {run.cards.keys()[0]: 1, run.cards.keys()[1]: 1}
	run.coins = 33
	return run


func _run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await _wait(1.2)
	var settings: String = main.SETTINGS_PATH
	var backup := "user://settings_shots_diff.bak"
	var had_settings := FileAccess.file_exists(settings)
	if had_settings:
		DirAccess.copy_absolute(settings, backup)
	var cfg := ConfigFile.new()
	cfg.load(settings)
	for section in ["run", "run_deck", "run_level"]:
		if cfg.has_section(section):
			cfg.erase_section(section)
	cfg.save(settings)

	# Nothing open yet: no choice of the level before the run.
	main.show_hero_select("run")
	await _wait(0.8)
	_check(_picker_arrows().is_empty() and main._run_open() == 0, "no level picker before a locomotive is beaten")
	await _shot("select_closed")
	_press("Назад")
	await _wait(0.4)

	# A locomotive of a plain run is beaten: level 1 opens, the line says so.
	var run := TrainRun.new()
	run.save_path = "user://run_shots_diff.json"
	run.start("finn", 3)
	main.run = run
	run.passed = 9
	run.wagon = 9
	run.phase = "fight"
	run.current = {"kind": "boss", "enemy": "lich", "hp": 20, "level": "hard", "seed": 5, "stats": {"crit": 20, "armor": 1}}
	run.fight_won(14)
	var opened: int = main._run_unlock()
	main.show_run()
	if opened > 0:
		main.run_screen.announce("Открыта сложность %d" % opened)
	await _wait(1.0)
	_check(opened == 1 and main._run_open() == 1, "the first locomotive opens level 1, open %d" % main._run_open())
	await _shot("boss_won")
	main._run_unlock()
	_check(main._run_open() == 1, "the same locomotive opens nothing twice")

	# Levels 0 and 1 open: the picker; the arrows go up to the open level and no further.
	main.show_hero_select("run")
	await _wait(0.8)
	await _shot("select_level1")
	var arrows := _picker_arrows()
	_check(arrows.size() == 2 and arrows[0].disabled and not arrows[1].disabled, "level 0 is picked, the right arrow is free")
	arrows[1].pressed.emit()
	_check(main._run_level() == 1 and arrows[1].disabled and not arrows[0].disabled, "the arrow picks level 1 and stops there")
	arrows[1].pressed.emit()
	_check(main._run_level() == 1, "level 2 is not open")
	arrows[0].pressed.emit()
	_check(main._run_level() == 0, "the left arrow goes back to level 0")
	arrows[1].pressed.emit()
	main._save_setting("run", "open", 7)
	main._save_setting("run", "level", 4)
	main._close_overlay(main.overlay.get_children().back())
	await _wait(0.4)
	main.show_hero_select("run")
	await _wait(0.8)
	await _shot("select_level4")
	_press("В путь!")
	await _wait(1.0)
	_check(main.run.difficulty == 4, "the run starts at level 4, got %d" % main.run.difficulty)
	await _shot("run_level4")
	main.run_screen._open_difficulty()
	await _wait(0.6)
	await _shot("penalties")
	main.run_screen._close_popup()

	# The shop with the markup.
	run = main.run
	run.save_path = "user://run_shots_diff.json"
	run.coins = 40
	run.passed = 4
	run.wagon = 4
	run.history = ["fight", "treasure", "fight", "rest"]
	run.met = ["jake", "", "bmo", ""]
	run.wagons = ["", "", "", ""]
	run.doors = [{"kind": "shop"}, {"kind": "rest"}]
	run.enter(0)
	main.run_screen.rebuild()
	await _wait(0.8)
	await _shot("shop_level4")
	run.phase = "doors"
	run.shop = {}
	run.doors = [{"kind": "rest"}, {"kind": "rest"}]
	main.run_screen.rebuild()
	await _wait(0.6)
	await _shot("rest_level4")
	run.lose()

	# The end screens.
	var short = _played("finn", 3, 7)
	short.phase = "fight"
	short.current = {"kind": "elite", "enemy": "marceline", "hp": 12, "level": "medium", "seed": 5, "stats": {"crit": 20}, "wagon": "fair"}
	short.lose(true)
	main.run = short
	main.show_run({"best": 5, "deck": 3, "level": 2, "open": 4})
	await _wait(0.8)
	await _shot("over_short")
	var long = _played("jake", 0, 34)
	long.bosses = 3
	long.phase = "fight"
	long.current = {"kind": "boss", "enemy": "ice_king", "hp": 28, "level": "impossible", "seed": 5, "stats": {"crit": 20}}
	long.lose(true)
	main.run = long
	main.show_run({"best": 20, "deck": 20, "level": 20, "open": 0})
	await _wait(0.8)
	await _shot("over_long")
	var scroll: ScrollContainer = main.run_screen.find_children("*", "ScrollContainer", true, false)[0]
	scroll.scroll_vertical = 1000
	await _wait(0.4)
	await _shot("over_long_scrolled")
	var gave_up = _played("finn", 0, 0)
	gave_up.lose()
	main.run = gave_up
	main.show_run()
	await _wait(0.8)
	await _shot("over_empty")
	main.run_screen._open_deck("")
	await _wait(0.6)
	await _shot("over_deck")
	main.run_screen._close_popup()
	var day := TrainRun.new()
	day.save_path = "user://run_shots_diff.json"
	day.start_daily("2026-10-16")
	day.passed = 8
	day.wins = 7
	day.lose(true)
	main.run = day
	main.show_run()
	main.run_screen.set_daily_status("Место 3 из 12")
	await _wait(0.8)
	await _shot("over_daily")

	# The records written by the end of a run: the best of all, of the deck and of the level.
	cfg = ConfigFile.new()
	cfg.load(settings)
	for section in ["run_deck", "run_level"]:
		if cfg.has_section(section):
			cfg.erase_section(section)
	cfg.set_value("run", "best", 6)
	cfg.set_value("run", "open", 2)
	cfg.set_value("run_deck", "finn", 4)
	cfg.set_value("run_level", "2", 9)
	cfg.save(settings)
	var rec = _played("finn", 2, 12)
	rec.phase = "fight"
	rec.current = {"kind": "fight", "enemy": "bmo", "hp": 12, "level": "medium", "seed": 5, "stats": {}}
	main.run = rec
	main._run_over(true)
	_check(main._load_setting("run", "best", 0) == 12 and main._load_setting("run_deck", "finn", 0) == 12 and main._load_setting("run_level", "2", 0) == 12,
		"the records are kept: %s" % [main._run_records()])
	_check(rec.fell.get("enemy", "") == "bmo", "a lost fight is in the chronicle")
	await _wait(0.8)
	await _shot("over_records")
	var again = _played("jake", 2, 5)
	again.lose()
	main.run = again
	main._run_over()
	_check(main._load_setting("run", "best", 0) == 12 and main._load_setting("run_deck", "jake", 0) == 5 and main._load_setting("run_level", "2", 0) == 12,
		"a shorter run keeps the old records: %s" % [main._run_records()])

	if had_settings:
		DirAccess.copy_absolute(backup, settings)
		DirAccess.remove_absolute(backup)
	else:
		DirAccess.remove_absolute(settings)
	DirAccess.remove_absolute("user://run_shots_diff.json")
	quit()
