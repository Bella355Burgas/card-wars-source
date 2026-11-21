extends SceneTree
## The server's check of the train of the day (scripts/train/run_check.gd): a run is played here as
## the table plays it (the player's seat by a network too, the enemy by its own with seed_base), with
## its journal; the check must take it and get the same score, and must refuse changed journals.
##   godot --headless --path . -s res://tests/run_check_test.gd [-- <wagons>]

const TrainRun = preload("res://scripts/train/train_run.gd")
const RunCheck = preload("res://scripts/train/run_check.gd")
const Game = preload("res://scripts/core/game.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const AIHelper = preload("res://scripts/ai/ai_helper.gd")

const DATE := "2026-11-04"
const SAVE := "user://test_run_daily.json"

var fails := 0
var ui_like := false        # the player's moves as the table sends them (see fight)
var direct := 0             # attacks sent from the main phase
var hero_floops := 0        # «ФЛЮП героя» on a card with no floop of its own
var updated_on_load := false    # the run is read back by the newest train rules (a run going on after an update)


func _initialize() -> void:
	_main()


## Args: the wagons to play at most (default 12) and the number of days (trains) to play (default 3).
func _main() -> void:
	var args := OS.get_cmdline_user_args()
	var wagons := int(args[0]) if args.size() > 0 else 12
	var days := int(args[1]) if args.size() > 1 else 3
	var lines := []
	for k in days:
		var date := DATE if k == 0 else Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(DATE) + 86400 * k)
		ui_like = k > 0
		direct = 0
		var l := await _honest(date, wagons)
		if ui_like:
			print("  attacks from the main phase: %d" % direct)
			_expect(direct > 0, "the run of %s has attacks from the main phase" % date)
		if k == 0:
			lines = l
	# An ordinary run (a record): started from its pick, seed and difficulty.
	ui_like = true
	hero_floops = 0
	var plain := await _honest("", wagons, "marceline@finn")
	print("  hero floops from the card's menu: %d" % hero_floops)
	_expect(hero_floops > 0, "the record has hero floops from the card's menu")
	ui_like = false
	# A run of the older train rules (a client not updated yet): its start line says nothing of them.
	var old := await _honest("", wagons, "marceline@prismo", 1)
	old[0].erase("train_rules")
	var old_out: Dictionary = await RunCheck.check(old, "")
	_expect(old_out["err"] == "", "a run of the older train rules is taken: %s" % old_out["err"])
	# A run begun by the rules 2 and going on after an update: the load line says the rules changed.
	updated_on_load = true
	var moved := await _honest("", wagons, "marceline@finn", 2)
	updated_on_load = false
	_expect(moved[0]["train_rules"] == 2 and moved.any(func(st): return st.get("a") == "load" and st.get("tr") == TrainRun.TRAIN_RULES), "the update shows in the load line")
	await _refused(plain, "train rules from the future", func(l: Array): l[0]["train_rules"] = TrainRun.TRAIN_RULES + 1)
	# Real journals the server once refused by mistake.
	await _real("tests/runs/daily_2026-11-05_build55.gz", "2026-11-05", 19)     # build 55, items before copies
	await _real("tests/runs/record_hero_floop.gz", "", 5)                       # «ФЛЮП героя» from the card's menu
	await _refused(plain, "a record of another seed", func(l: Array): l[0]["seed"] = int(l[0]["seed"]) + 1)
	await _refused(plain, "a record with an own deck", func(l: Array): l[0]["pick"] = "custom:x")

	# Changed journals.
	await _refused(lines, "another day", func(l: Array): l[0]["date"] = "2026-11-03")
	await _refused(lines, "no end", func(l: Array): l.pop_back())
	await _refused(lines, "more wagons said", func(l: Array):
		for st in l:
			if st.get("a") == "enter":
				st["n"] = int(st["n"]) + 1
				break)
	await _refused(lines, "the enemy gives up", func(l: Array):
		var f: Dictionary = _first_fight(l)
		f["steps"].insert(_after_start(f["steps"]), {"t": "over", "w": 0}))
	await _refused(lines, "the enemy's move left out", func(l: Array):
		var f: Dictionary = _first_fight(l)
		for k in f["steps"].size():
			var st: Dictionary = f["steps"][k]
			if st.get("t") == "cmd" and st.get("p") == 1 and st["c"]["cmd"] != "end_turn":
				f["steps"].remove_at(k)
				break)
	await _refused(lines, "the enemy only ends its turns", func(l: Array):
		var f: Dictionary = _first_fight(l)
		for st: Dictionary in f["steps"]:
			if st.get("t") == "cmd" and st.get("p") == 1:
				st["c"] = {"cmd": "end_turn"})
	await _refused(lines, "a card the player can't play", func(l: Array):
		var f: Dictionary = _first_fight(l)
		for st: Dictionary in f["steps"]:
			if st.get("t") == "cmd" and st.get("p") == 0 and st["c"]["cmd"] == "play":
				st["c"]["uid"] = 9999
				break)
	await _refused(lines, "a win without a fight", func(l: Array):
		for k in l.size():
			if l[k].get("a") == "fight":
				l.remove_at(k)
				break)
	await _refused(lines, "a step the run has not", func(l: Array):
		l.insert(2, {"a": "save", "x": [], "ph": "doors", "n": 0, "c": 0, "hp": l[1]["hp"]}))
	print("run_check_test: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


## A run of the day played and checked: its journal.
func _honest(date: String, wagons: int, pick := "marceline@prismo", rules := TrainRun.TRAIN_RULES) -> Array:
	var run := TrainRun.new()
	run.save_path = SAVE
	run.train_rules = rules
	if date != "":
		run.start_daily(date)
	else:
		run.start(pick, 4242, "", 2)
	var t0 := Time.get_ticks_msec()
	run = await drive(run, wagons)
	print("%s: %d wagons, %d wins (%d ms)" % [date, run.passed, run.wins, Time.get_ticks_msec() - t0])
	var text := FileAccess.get_file_as_string(run.journal_path)
	var lines := RunCheck.parse(text)
	var kinds := {}
	for st in lines:
		kinds[st.get("a")] = int(kinds.get(st.get("a"), 0)) + 1
	print("journal: %d steps, %d bytes, %d packed: %s" % [lines.size(), text.length(), run.packed_journal().size(), kinds])
	t0 = Time.get_ticks_msec()
	var out: Dictionary = await RunCheck.check(lines, date)
	print("check: %s %s wagons, %s wins (%d ms)" % [out["err"], out["score"], out["wins"], Time.get_ticks_msec() - t0])
	_expect(out["err"] == "", "the honest run of %s is taken: %s" % [date, out["err"]])
	_expect(out["score"] == run.passed and out["wins"] == run.wins and out["deck"] == run.deck_code(), "the same score")
	_expect(out["restarts"] == 1, "the fight started over is seen")
	return lines


func _real(path: String, date: String, wagons: int) -> void:
	var packed := FileAccess.get_file_as_bytes("res://" + path)
	var text := packed.decompress_dynamic(32 * 1024 * 1024, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	var out: Dictionary = await RunCheck.check(RunCheck.parse(text), date)
	print("  %s: %s %s wagons" % [path.get_file(), out["err"], out["score"]])
	_expect(out["err"] == "" and out["score"] == wagons, "the real run %s is taken" % path.get_file())


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + what)


func _refused(lines: Array, what: String, change: Callable) -> void:
	var l: Array = lines.duplicate(true)
	change.call(l)
	var out: Dictionary = await RunCheck.check(l, String(lines[0]["date"]))
	print("  %s: %s" % [what, out["err"]])
	_expect(out["err"] != "", what + " is refused")


static func _first_fight(l: Array) -> Dictionary:
	for st in l:
		if st.get("a") == "fight":
			return st
	return {}


static func _after_start(steps: Array) -> int:
	for k in steps.size():
		if steps[k].get("t") == "start":
			return k + 1
	return 0


# ---------------------------------------------------------------- the run as the game plays it

## Plays the run up to `wagons` wagons and gives up there. After the second wagon the run is read
## from its save (the game closed and opened); its first fight is left halfway once and started over.
func drive(run, wagons: int):
	var restarted := false
	while run.phase != "over":
		match run.phase:
			"doors":
				if run.passed >= wagons:
					run.lose(false)
				elif run.passed == 2 and not run.has_meta("read"):
					var again := TrainRun.new()
					again.save_path = SAVE
					again.train_rules = TrainRun.TRAIN_RULES if updated_on_load else run.train_rules     # the game updated while it was closed
					again.restore()
					again.note_load()
					again.set_meta("read", true)
					run = again
				else:
					run.enter(0)
			"fight":
				if not restarted:
					restarted = true
					await fight(run, 6)
					var again := TrainRun.new()
					again.save_path = SAVE
					again.train_rules = run.train_rules
					again.restore()
					again.note_load()
					run = again
					continue
				var g = await fight(run)
				run.note_fight(g)
				if g.winner == 0:
					run.fight_won(g.players[0].hp, bool(g.players[0].item_state.get("revive", false)))
				else:
					run.lose(true)
			"reward":
				if run.offers.is_empty():
					run.skip()
				else:
					run.take(run.offers[0])
			"item":
				run.take_item(run.item_offers[0])
			"level":
				run.pick_perk(run.perks[0])
			"rest":
				run.rest_heal()
			"shop":
				for id: String in run.shop["cards"].duplicate():
					if run.can_pay(run.shop_price(TrainRun.card_price(id))):
						run.buy_card(id)
				run.leave_shop()
			"event":
				_event(run)
	return run


static func _event(run) -> void:
	match String(run.event["stage"]):
		"options":
			for i in run.event_options().size():
				if run.event_block(i) == "":
					run.choose_event(i)
					return
			run.leave_event()
		"pick":
			var ids: Array = run.curses.duplicate() if run.event["pick"] == "curse" else run.cards.keys()
			for id: String in ids:
				run.event_pick(id)
				if run.event["stage"] != "pick":
					return
			run.lose(false)
		"result":
			run.finish_event()


## Answers the engine's choices: the enemy's network for its seat, the player's for the player.
class Table extends RefCounted:
	var g
	var me
	var foes: Array
	var double := false

	func foe():
		return foes[1] if double and g.train.follow.is_empty() else foes[0]

	func choose(req: Dictionary):
		return (foe() if int(req.get("player", 0)) == 1 else me).pick_choice(g, req)


## The fight of the wagon as main.gd and board.gd play it, up to `limit` commands (0: to the end).
func fight(run, limit := 0):
	var door: Dictionary = run.current
	var seed_value := int(door["seed"])
	var g := Game.new()
	g.setup([run.player_pick(), String(door["enemy"])], seed_value % 2, seed_value)
	run.prepare_fight(g)
	g.journal = []
	var t := Table.new()
	t.g = g
	t.me = AILevels.agent("impossible", run.player_pick())
	t.foes = [AILevels.agent(String(door["level"]), String(door["enemy"])), null]
	t.foes[0].seed_base = seed_value
	if door.has("second"):
		t.double = true
		t.foes[1] = AILevels.agent(String(door["second"]["level"]), String(door["second"]["enemy"]))
		t.foes[1].seed_base = seed_value + 1
	run.note_go()
	g.chooser = t
	if t.foe().mulligan(g, 1):
		await g.cmd_mulligan(1)
	await g.start_game()
	var n := 0
	while g.phase != "over" and n < 4000 and (limit == 0 or n < limit):
		if g.phase == "handoff":
			await g.cmd_start_turn()
			continue
		if g.phase == "attack" and g.attackers_left(g.turn_player).is_empty():
			await g.cmd_end_turn(g.turn_player)
			continue
		n += 1
		var p: int = g.turn_player
		var agent = t.foe() if p == 1 else t.me
		var cmd: Dictionary = agent.pick_command(g, p)
		if p == 0 and ui_like:
			# As a player at the table: «Атаковать» from the card's menu without «В атаку!» first,
			# «ФЛЮП героя» (Финн) on a card with no floop of its own, and a press that the engine
			# does nothing with (an attack from an empty lane).
			if cmd["cmd"] == "begin_attack":
				cmd = {"cmd": "attack", "lane": g.attackers_left(0)[0]}
				direct += 1
			elif cmd["cmd"] == "floop" and not cmd.has("hero") and cmd["kind"] == "creature" 					and not g.own_floop_ok(0, "creature", cmd["lane"]) and g.hero_floop_ok(0, "creature", cmd["lane"]):
				cmd = {"cmd": "floop", "kind": "creature", "lane": cmd["lane"], "hero": true}
				hero_floops += 1
			elif cmd["cmd"] == "end_turn" and g.phase == "main" and g.players[0].creatures.has(null):
				await g.run_command(0, {"cmd": "attack", "lane": g.players[0].creatures.find(null)})
		var before: int = g.state_hash()
		await g.run_command(p, cmd)
		if g.state_hash() == before and g.turn_player == p and (g.phase == "main" or g.phase == "attack"):
			agent.ban_command(before, cmd)
		AIHelper.clear_plan(g)
	print("  fight of wagon %d (%s): %s after %d commands, %d steps" % [run.passed + 1, door["kind"],
		"won" if g.winner == 0 else ("lost" if g.phase == "over" else "left"), n, g.journal.size()])
	return g
