extends RefCounted
## «Бесконечный поезд» from the main screen (main.gd): opening a run, the train of the day,
## a fight of the run and its end. The run itself is scripts/train/train_run.gd, its screen
## scripts/ui/run_screen.gd. Its functions work on the main screen `m`, which keeps all the state.

const Main = preload("res://scripts/ui/main.gd")
const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const TrainRun = preload("res://scripts/train/train_run.gd")
const RunScreen = preload("res://scripts/ui/run_screen.gd")
const DailyBoard = preload("res://scripts/net/daily_board.gd")
const DailyScreen = preload("res://scripts/ui/daily_screen.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")

const PROOF_PATH := "user://daily_proof.gz"

var m: Main


func _init(main: Main) -> void:
	m = main


## The roguelike: the menu of the train. The saved run goes on, or a new one starts with the
## hero picked; the train of the day is the same for everybody, once a day.
func open_run() -> void:
	m._close_play_menu()
	var saved = TrainRun.new()
	var has_run: bool = saved.restore()
	var state := _daily_state()
	var root := m._message_overlay("Бесконечный поезд", "")
	(root.get_meta("text") as Label).visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	root.get_meta("box").add_child(v)
	var go := WoodUI.button("Продолжить забег" if has_run else "Новый забег", Main.RUN_COLOR, 34, Vector2(520, 76))
	go.pressed.connect(func():
		m._close_overlay(root)
		if has_run:
			saved.note_load()
			m.run = saved
			show_run()
		else:
			m.show_hero_select("run"))
	v.add_child(go)
	var day_text: String = {"new": "Поезд дня · %s" % CardDB.hero(TrainRun.daily_deck(TrainRun.daily_date()))["name"],
		"continue": "Продолжить поезд дня", "done": "Поезд дня сыгран"}[state]
	var day := WoodUI.button(day_text, UI.ORANGE, 32, Vector2(520, 70))
	day.disabled = state == "done"
	day.pressed.connect(func():
		m._close_overlay(root)
		start_daily())
	v.add_child(day)
	var board := WoodUI.button("Таблица дня", UI.BLUE, 32, Vector2(520, 70))
	board.pressed.connect(func():
		m._close_overlay(root)
		show_daily_board())
	v.add_child(board)
	var back := WoodUI.button("Назад", UI.PURPLE, 30, Vector2(520, 64))
	back.pressed.connect(func():
		m._close_overlay(root)
		m._back_to_play())
	v.add_child(back)


## "new": not played today, "continue": a train of today is going on, "done": played (or its
## save is gone: one train a day).
func _daily_state() -> String:
	var today := TrainRun.daily_date()
	var saved = TrainRun.new()
	saved.save_path = TrainRun.DAILY_PATH
	if saved.restore() and saved.daily == today:
		return "continue"
	if str(m._load_setting("daily", "started", "")) == today or str(m._load_setting("daily", "done", "")) == today:
		return "done"
	return "new"


## Starts or goes on with the train of today. A guest plays it too, only the table does not get
## the result.
func start_daily() -> void:
	var state := _daily_state()
	if state == "done":
		return
	var d = TrainRun.new()
	d.save_path = TrainRun.DAILY_PATH
	if state == "continue":
		d.restore()
		d.note_load()
	else:
		d.start_daily(TrainRun.daily_date())
		m._save_setting("daily", "started", d.daily)
	m.run = d
	show_run()


## The table of the day over the game.
func show_daily_board() -> void:
	var root := m._overlay_root(Color(0.03, 0.02, 0.07, 1.0))
	root.add_child(WoodUI.table())
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var screen = DailyScreen.new()
	screen.setup(m.net.relay_url, TrainRun.daily_date(), m.account, _send_pending)
	center.add_child(screen)
	screen.closed.connect(func(): m._close_overlay(root))
	screen.login_requested.connect(func():
		m._close_overlay(root)
		m.show_login(show_daily_board))


## A train of the day is over (lost or given up): its result is kept, sent to the table
## (only a logged in player has a result there) and what came of it shows under the end of the
## run. The game never waits for the server.
func _daily_over(by_fight := false) -> void:
	m._save_setting("daily", "done", m.run.daily)
	m._save_setting("daily", "score", m.run.passed)
	var result: Dictionary = m.run.daily_result()
	result["by"] = m.account.nick
	# The train of the day counts for the record too: the server puts it there with the result of the
	# day, so no record of its own goes (and an older record's journal is not sent with a newer number).
	if m.run.passed > int(m._load_setting("run", "best", 0)):
		m._save_setting("run", "best", m.run.passed)
		m.social.best = maxi(m.social.best, m.run.passed)
		DirAccess.remove_absolute(m.social.best_proof)
	m.run.lose(by_fight)
	_keep_proof(m.run)
	m._save_setting("daily", "pending", result if m.account.logged_in() else {})
	show_run()
	var screen = m.run_screen
	screen.set_daily_status("Отправка")
	var text := await _send_pending()
	if m.run_screen == screen and is_instance_valid(screen):
		screen.set_daily_status(text)


## The journal of the train of the day that just ended, packed, waits in PROOF_PATH with its result
## (the next train of the day starts a journal of its own).
func _keep_proof(run) -> void:
	var f := FileAccess.open(PROOF_PATH, FileAccess.WRITE)
	if f != null:
		f.store_buffer(run.packed_journal())


## Sends the result left in the settings, if there is one and the player is logged in (a result
## belongs to the account it was played in). Returns a short line about it.
func _send_pending() -> String:
	if not m.account.logged_in():
		return "Войди, чтобы попасть в таблицу"
	var pending = m._load_setting("daily", "pending", {})
	if not pending is Dictionary or pending.is_empty():
		return ""
	if String(pending.get("by", m.account.nick)).to_lower() != m.account.nick.to_lower():
		return ""
	var proof := FileAccess.get_file_as_bytes(PROOF_PATH) if FileAccess.file_exists(PROOF_PATH) else PackedByteArray()
	var answer: Dictionary = await DailyBoard.submit(m.get_tree(), m.net.relay_url, pending, m.account.token, proof)
	if answer["ok"]:
		m._save_setting("daily", "pending", {})
		if answer.get("check", false):
			return "Сервер проверяет забег"
		return "Место %d из %d" % [int(answer["rank"]), int(answer["total"])]
	var why := String(answer["r"])
	if why == "auth":                                      # the token is no good: it stays until the next login
		return "Войди снова, отправлю позже"
	if why in ["dup", "date", "bad", "full", "big", "proof"]:    # it will never be taken: no use to keep it
		m._save_setting("daily", "pending", {})
		return "Результат уже в таблице" if why == "dup" else "Сервер не принял результат"
	return "%s, отправлю позже" % DailyScreen.REASONS.get(why, "Нет связи")


## The hero a new run offers first: the last one, a ready deck.
func _run_hero() -> String:
	var pick := str(m._load_setting("run", "hero", "finn"))
	if not CardDB.valid_loadout(pick) or CardDB.is_custom(CardDB.loadout_deck(pick)) or CardDB.is_no_hero(pick):
		pick = "finn"
	return pick


func start_run(pick: String, difficulty := 0) -> void:
	m.run = TrainRun.new()
	m.run.start(pick, -1, "", difficulty)
	show_run()


## The levels of difficulty open to the player (0 is always open) and the one picked for the next run.
func _run_open() -> int:
	return clampi(int(m._load_setting("run", "open", 0)), 0, TrainRun.MAX_DIFFICULTY)


func _run_level() -> int:
	return clampi(int(m._load_setting("run", "level", 0)), 0, _run_open())


## "Сложность 3" with arrows over the open levels, and the penalty that level adds under it.
func _difficulty_picker(width := 430) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var prev := WoodUI.button("◀", WoodUI.BLUE, 24, Vector2(56, 56))
	var next := WoodUI.button("▶", WoodUI.BLUE, 24, Vector2(56, 56))
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.custom_minimum_size = Vector2(width, 0)
	text.mouse_filter = Control.MOUSE_FILTER_STOP
	var name_l := WoodUI.text("", 30, RunScreen.GOLD, true, 8)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var penalty_l := WoodUI.text("", 22, WoodUI.PAPER, false, 5)
	penalty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	penalty_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	penalty_l.custom_minimum_size = Vector2(width, 56)
	for l: Label in [name_l, penalty_l]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(l)
	var refresh := func():
		var lv := _run_level()
		name_l.text = "Сложность %d" % lv
		penalty_l.text = TrainRun.difficulty_text(lv) if lv > 0 else "Без штрафов"
		text.tooltip_text = "
".join(TrainRun.difficulty_lines(lv))
		prev.disabled = lv <= 0
		next.disabled = lv >= _run_open()
	for dir in [-1, 1]:
		var step: int = dir
		(prev if dir < 0 else next).pressed.connect(func():
			m._save_setting("run", "level", clampi(_run_level() + step, 0, _run_open()))
			UI.sfx("select")
			refresh.call())
	box.add_child(prev)
	box.add_child(text)
	box.add_child(next)
	refresh.call()
	return box


## The records of the ordinary runs: the best of all, of the run's deck, of the run's difficulty, and
## the open levels. They are all in the game settings.
func _run_records() -> Dictionary:
	return {"best": int(m._load_setting("run", "best", 0)), "open": _run_open(),
		"deck": int(m._load_setting("run_deck", m.run.deck_id, 0)), "level": int(m._load_setting("run_level", str(m.run.difficulty), 0))}


## The run screen. prev: the records before the run that just ended.
func show_run(prev := {}) -> void:
	_close_run_screen()
	m._clear_title()
	var records := _run_records()
	m.run_screen = RunScreen.new()
	m.run_screen.setup(m.run, records, prev if not prev.is_empty() else records)
	m.stage.add_child(m.run_screen)
	m.run_screen.fight_requested.connect(start_run_fight)
	m.run_screen.give_up_requested.connect(_run_over)
	m.run_screen.new_run_requested.connect(func():
		m.show_title()
		m.show_hero_select("run"))
	m.run_screen.exit_requested.connect(m.show_title)
	m.run_screen.board_requested.connect(show_daily_board)
	# The networks of the enemies behind the doors read while the player chooses one.
	for door: Dictionary in m.run.doors:
		if door.has("level") and door.has("enemy"):
			AILevels.warm(String(door["level"]), String(door["enemy"]))


func _close_run_screen() -> void:
	if m.run_screen != null and is_instance_valid(m.run_screen):
		m.run_screen.queue_free()
	m.run_screen = null


## A fight of the run: the run deck against the wagon's enemy, with the hit points the
## run has left. The seed is the wagon's, so a fight left halfway starts over the same.
func start_run_fight() -> void:
	_close_run_screen()
	m._clear_title()
	var door: Dictionary = m.run.current
	var heroes := [m.run.player_pick(), String(door["enemy"])]
	if not await m._wait_ai([[String(door["level"]), heroes[1]]]):
		return
	m.online = false
	m.ai_mode = true
	m._ai_vs_ai_mode = false
	m.seat = 0
	m._mode = "run"
	var agent = AILevels.agent(String(door["level"]), heroes[1])
	m.game = Game.new()
	var my_game = m.game
	var seed_value: int = door["seed"]
	var first := seed_value % 2
	m.game.setup(heroes, first, seed_value)
	m.run.prepare_fight(m.game)
	if m.run.journal_path != "":    # the server may play the run again from its journal (TrainRun.note_fight)
		m.game.journal = []
	if "seed_base" in agent:    # its decisions depend on the state only, so the server gets the same
		agent.seed_base = seed_value
	m.run.note_go()
	m._new_board()
	m.board.enable_ai(agent, 1, 0)
	m.board.set_hands_hidden(true)
	var enemy: String = m.game.players[1].name
	var text := "%s: %s, %d HP.\n%s" % [RunScreen.KINDS[door["kind"]]["name"], enemy, int(door["hp"]),
		"Первым ходишь ты!" if first == 0 else "Первым ходит %s." % enemy]
	if door.has("second"):      # the second enemy comes after the first, see _second_enemy_intro
		var sec: Dictionary = door["second"]
		text += "\nПотом %s, %d HP." % [CardDB.hero(String(sec["enemy"]))["name"], int(sec["hp"])]
		m.board.enemy_intro = _second_enemy_intro
	var traits := TrainRun.enemy_stat_lines(door.get("stats", {}))
	if not traits.is_empty():
		text += "\n" + " · ".join(traits)
	if m.game.train.wagon != "":
		var wg: Dictionary = TrainRun.TrainWagons.wagon(m.game.train.wagon)
		text += "\n%s: %s" % [wg["name"], wg["text"]]
	if not await m._prepare_local_game(first, [0], text, false, false, "Вагон %d" % (m.run.wagon + 1)):
		return
	if not await m._ai_mulligan(1, agent):
		return
	m.board.set_viewer(0)
	m.board.set_hands_hidden(false)
	await m.board.run_engine(func(): await m.game.start_game())
	if first == 1:
		m.board.trigger_ai_turn()


## A double wagon: the first enemy is beaten and the second sits down (the table shows it
## already): a screen says who it is, and its own AI takes over the seat.
func _second_enemy_intro(_ev: Dictionary) -> void:
	var sec: Dictionary = m.run.current["second"]
	m.board.ai_agent = AILevels.agent(String(sec["level"]), String(sec["enemy"]))
	if "seed_base" in m.board.ai_agent:
		m.board.ai_agent.seed_base = int(m.run.current["seed"]) + 1
	await m._curtain(1, "Второй враг", "%s, %d HP.\nТвои HP, рука и поле остаются." % [m.game.players[1].name, m.game.players[1].hp], "Дальше")


## The end of a run fight: on to the trophies, or the run is over.
func _on_run_fight_over(winner: int) -> void:
	await m.get_tree().create_timer(0.8).timeout
	if m.game == null:
		return
	var won := winner == 0
	var hp_left: int = m.game.players[0].hp
	var root := m._message_overlay("ПОБЕДА!" if won else "ПОРАЖЕНИЕ",
		"Вагон пройден, осталось %d HP.\n+%s" % [hp_left, RunScreen.coins_text(m.run.coin_reward(String(m.run.current["kind"])))] if won
		else "Поезд едет дальше без тебя.")
	m._game_over_root = root
	if won:
		m._confetti(root)
	var b := WoodUI.button("Дальше" if won else "Итоги забега", UI.GREEN if won else UI.PURPLE, 30, Vector2(320, 70))
	b.pressed.connect(func():
		var revived := bool(m.game.players[0].item_state.get("revive", false))     # _end_game drops the game
		m.run.note_fight(m.game)
		m._close_overlay(root)
		m._game_over_root = null
		m._end_game()
		if won:
			m.run.fight_won(hp_left, revived)
			var opened := _run_unlock()
			show_run()
			if opened > 0:
				m.run_screen.announce("Открыта сложность %d" % opened)
		else:
			_run_over(true))
	root.get_meta("box").add_child(b)


## A beaten locomotive opens the next difficulty. Returns the level that is open now and was not
## before, 0 when there is none.
func _run_unlock() -> int:
	var n: int = m.run.unlocks()
	if n <= _run_open():
		return 0
	m._save_setting("run", "open", n)
	return n


## A lost fight or giving up: the records are kept, the save goes. by_fight: the fight was lost.
func _run_over(by_fight := false) -> void:
	if m.run.daily != "":
		_daily_over(by_fight)
		return
	var prev := _run_records()
	for rec: Array in [["run", "best", "best"], ["run_deck", m.run.deck_id, "deck"], ["run_level", str(m.run.difficulty), "level"]]:
		if m.run.passed > int(prev[rec[2]]):
			m._save_setting(rec[0], rec[1], m.run.passed)
	_run_unlock()
	m.run.lose(by_fight)
	# A new record goes to the server with the run's journal: the server plays it again (social.gd).
	if m.run.passed > int(prev["best"]):
		m.social.report_best(m.run.passed, m.run.packed_journal())
	show_run(prev)
