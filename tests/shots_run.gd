extends SceneTree
## Screenshots of «Бесконечный поезд» (windowed, not headless):
##   godot --path . -s res://tests/shots_run.gd -- <output_dir>
## The title, the hero selection, the doors, a fight from its coin toss to the win,
## the hero's stats under the mouse, the trophies, the deck, a rest, a level-up, the
## stats screen, a fight left halfway and the end of the run. Also the rest with its four
## choices, improved cards, the change of a land and a double wagon: its door, the fight
## and the second enemy walking in.
## The run is saved to user://run_shots.json (removed at the end); the settings are
## only read.

const MainScene := preload("res://scenes/main.tscn")
const TrainRun = preload("res://scripts/train/train_run.gd")

var out_dir := "user://shots_run"
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


## The door frames of the run screen (the panels that take the clicks).
func _door_frames(screen: Node) -> Array:
	return screen.find_children("*", "Panel", true, false).filter(
		func(p): return p.custom_minimum_size == screen.DOOR_SIZE)


func _run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await _wait(1.2)
	await _shot("title")
	main.show_hero_select("run")
	await _wait(0.8)
	await _shot("hero_select")
	_press("Назад")
	await _wait(0.5)

	var run := TrainRun.new()
	run.save_path = "user://run_shots.json"
	run.start("finn", 3)
	main.run = run
	main.show_run()
	await _wait(0.8)
	await _shot("doors")
	var frames := _door_frames(main.run_screen)
	frames[0].mouse_entered.emit()
	await _wait(0.6)
	await _shot("door_open")
	frames[0].mouse_exited.emit()

	# A fight: the coin toss, the starting hand, the table.
	var fight := 0
	for i in run.doors.size():
		if run.doors[i]["kind"] == "fight":
			fight = i
	run.enter(fight)
	main.start_run_fight()
	await _wait(1.6)
	await _shot("fight_coin")
	_press("Дальше")
	await _wait(1.2)
	await _shot("fight_hand")
	_press("Оставить")
	await _wait(2.5)
	await _shot("fight_table")
	main.board._show_stats_tip("bottom")
	await _wait(0.3)
	await _shot("fight_stats_tip")
	main.board._hide_stats_tip()
	main.board.force_over(0)
	main._on_game_over(0)
	await _wait(1.6)
	await _shot("fight_won")
	_press("Дальше")
	await _wait(0.8)
	await _shot("reward")
	run.take(run.offers[0])
	main.run_screen.rebuild()
	await _wait(0.6)
	await _shot("train_rolling")
	await _wait(1.2)
	await _shot("doors_2")
	main.run_screen._open_deck("")
	await _wait(1.0)
	await _shot("deck")
	main.run_screen._close_popup()

	run.phase = "rest"
	run.current = {"kind": "rest"}
	run.hp = 13
	main.run_screen.rebuild()
	await _wait(0.6)
	await _shot("rest")

	# Improved cards: the deck to improve from, the deck with the improved ones, a land to change.
	var improved := 0
	for id: String in run.cards:
		if TrainRun.upgradable(id) and improved < 4:
			run.upgraded[id] = 1
			improved += 1
	run.cards["the_pig"] = 2
	main.run_screen._open_deck("upgrade")
	await _wait(1.0)
	await _shot("upgrade_deck")
	main.run_screen._close_popup()
	main.run_screen._open_deck("remove")
	await _wait(1.0)
	await _shot("remove_deck")
	main.run_screen._close_popup()
	main.run_screen._open_lands()
	await _wait(0.8)
	await _shot("lands_pick")
	main.run_screen._open_lands(1)
	await _wait(0.8)
	await _shot("lands_type")
	main.run_screen._close_popup()

	# A double wagon: the door among others, the fight and the second enemy.
	run.phase = "doors"
	run.current = {}
	run.doors = [
		{"kind": "double", "enemy": "jake", "hp": 9, "level": "medium", "seed": 6, "stats": {}, "wagon": "fog",
			"second": {"enemy": "marceline", "hp": 9, "level": "medium", "stats": {}}},
		{"kind": "rest"}]
	main.run_screen.rebuild()
	await _wait(0.6)
	var dframes := _door_frames(main.run_screen)
	dframes[0].mouse_entered.emit()
	await _wait(0.7)
	await _shot("door_double")
	dframes[0].mouse_exited.emit()
	run.enter(0)
	main.start_run_fight()
	await _wait(1.6)
	await _shot("double_coin")
	_press("Дальше")
	await _wait(1.2)
	_press("Оставить")
	await _wait(2.5)
	await _shot("double_table")
	# The first enemy falls: the curtain with the second one.
	main.board.run_engine(func(): await main.game.damage_player(1, 100))
	await _wait(2.6)
	await _shot("double_second")
	_press("Дальше")
	await _wait(1.0)
	await _shot("double_second_table")
	main.board.force_over(0)
	main._on_game_over(0)
	await _wait(1.6)
	_press("Дальше")
	await _wait(0.8)
	await _shot("double_reward")
	run.skip()
	main.run_screen.rebuild()

	# A level-up, then the hero's stats.
	run.phase = "level"
	run.level = 3
	run.levels_due = 1
	run.xp = 1
	run.stats = {"crit": 21, "crit_dmg": 50, "dodge": 7, "armor": 1, "regen": 1}
	run._offer_perks()
	main.run_screen.rebuild()
	await _wait(0.6)
	await _shot("level_up")
	main.run_screen._open_stats()
	await _wait(0.6)
	await _shot("stats")
	main.run_screen._close_popup()
	run.pick_perk(run.perks[0])

	# Items: a chest to pick one from, then everything the hero has.
	run.phase = "item"
	run.current = {"kind": "treasure"}
	run._offer_items(3)
	main.run_screen.rebuild()
	await _wait(0.6)
	await _shot("items")
	run.take_item(run.item_offers[0])
	for id in ["lemongrab_clock", "marceline_bass", "ice_crown", "lich_cloak", "bmo_console", "cat_paw", "jelly_ball"]:
		if not run.items.has(id):
			run.items.append(id)
	main.run_screen.rebuild()
	main.run_screen._open_items()
	await _wait(0.6)
	await _shot("items_owned")
	main.run_screen._open_stats()
	await _wait(0.6)
	await _shot("stats_items")
	main.run_screen._close_popup()

	# Wagon 10 of the first train: the locomotive, a boss fight left halfway.
	run.wagon = 9
	run.history = ["fight", "treasure", "fight", "elite", "rest", "fight", "fight", "elite", "rest"]
	run.met = ["jake", "", "bmo", "marceline", "", "pb", "fionna", "ice_king", ""]
	run.phase = "fight"
	run.current = {"kind": "boss", "enemy": "lich", "hp": 20, "level": "hard", "seed": 5, "stats": {"crit": 20, "armor": 1}}
	main.run_screen.rebuild()
	await _wait(0.6)
	await _shot("boss_fight")

	run.passed = 7
	run.wins = 6
	run.lose()
	main.show_run({"best": 3, "deck": 0, "level": 0, "open": 0})
	await _wait(0.6)
	await _shot("over")
	quit()
