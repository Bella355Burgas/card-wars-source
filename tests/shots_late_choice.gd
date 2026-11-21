extends SceneTree
## Screenshots of every choice screen of a late «Бесконечный поезд» run (windowed):
##   godot --path . --resolution 1280x720 -s res://tests/shots_late_choice.gd -- <output_dir> <tag>
## A high train, level, many items, curses, the highest difficulty and luck; the doors, a
## level-up (one and several in a row), items, trophies, a dark chest, shop, event, rest.

const MainScene := preload("res://scenes/main.tscn")
const TrainRun = preload("res://scripts/train/train_run.gd")
const TrainItems = preload("res://scripts/train/train_items.gd")
const TrainEvents = preload("res://scripts/train/train_events.gd")

var out_dir := "user://shots_late"
var tag := ""
var n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		tag = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _shot(shot_name: String) -> void:
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	n += 1
	root.get_viewport().get_texture().get_image().save_png("%s/%s%02d_%s.png" % [out_dir, tag, n, shot_name])
	print("shot ", shot_name)


func _run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	var run := TrainRun.new()
	run.save_path = "user://run_late_shots.json"
	run.start("finn", 7, "", TrainRun.MAX_DIFFICULTY)
	run.train = 5
	run.wagon = 6
	run.level = 18
	run.hp = 22
	run.max_hp = 40
	run.coins = 480
	for key: String in TrainRun.STATS:
		if key != "max_hp":
			run.stats[key] = int(TrainRun.STATS[key]["max"]) - int(TrainRun.STATS[key]["step"])
	run.stats["luck"] = 2
	var ids: Array = TrainItems.ITEMS.keys()
	for id: String in ids:
		if run.items.size() < 14 and not TrainItems.is_trophy(id):
			run.items.append(id)
	run.curses = TrainItems.CURSES.keys().slice(0, 3)
	main.run = run
	main.show_run()
	var rs = main.run_screen
	for at: Array in [[8, 6], [12, 5], [12, 9]]:
		run.train = at[0]
		run.wagon = at[1]
		run.passed = at[1] + at[0] * 10
		run._make_doors()
		rs.rebuild()
		await _shot("doors_t%d_w%d" % [at[0], at[1]])
	run.train = 5
	run.wagon = 6

	run.levels_due = 3
	run._offer_perks()
	run.phase = "level"
	rs.rebuild()
	await _shot("level")

	run.items = run.items.slice(0, 8)
	run._offer_items(4)
	run.current = {"kind": "treasure"}
	run.phase = "item"
	rs.rebuild()
	await _shot("items_dark4")

	run.picks_left = 2
	run.current = {"kind": "elite", "enemy": "lich"}
	run._offer_cards(["lich"])
	run.phase = "reward"
	rs.rebuild()
	await _shot("reward%d" % run.offers.size())

	run.phase = "shop"
	run._stock_shop()
	rs.rebuild()
	await _shot("shop")

	run.phase = "rest"
	rs.rebuild()
	await _shot("rest")

	for id: String in TrainEvents.EVENTS:
		run.current = {"kind": "event", "event": id}
		run.event = {"id": id, "stage": "options", "pick": "", "result": "", "got": []}
		run.phase = "event"
		rs.rebuild()
		await _shot("event_" + id)
	run._make_doors()
	quit()
