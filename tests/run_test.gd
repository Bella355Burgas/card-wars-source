extends SceneTree
## «Бесконечный поезд» without the screens:
##   godot --headless --path . -s res://tests/run_test.gd -- [runs] [wagons] [seed]
## Plays runs of every ready deck: random doors, trophies and rests, and every fight
## as a real engine game between random players with the run's hit points. A lost
## fight still goes on (the test wants the later trains), it is only counted.
## Checks the run deck code, the door rules, hit points within the maxima, and that
## the save gives back the same run after every step. Saves to user://run_test.json.
## Balance: -- balance [runs] [player AI level] [seed]: the player is an AI of that level
## (ai_levels.gd), the enemies play at their doors' levels, a lost fight ends the run;
## prints how far the runs get.
## Quick: -- quick: only the checks of improved cards, changed lands and double wagons.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")
const TrainRun = preload("res://scripts/train/train_run.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const TrainItems = preload("res://scripts/train/train_items.gd")
const TrainWagons = preload("res://scripts/train/train_wagons.gd")
const TrainEvents = preload("res://scripts/train/train_events.gd")
const SAVE := "user://run_test.json"

var failures := 0


## Choice requests go to the AI of the seat that answers.
class SeatChooser:
	var game
	var agents := []
	func choose(req: Dictionary):
		return agents[int(req.get("player", game.turn_player))].pick_choice(game, req)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "balance":
		await _balance(int(args[1]) if args.size() > 1 else 10, args[2] if args.size() > 2 else "medium",
			int(args[3]) if args.size() > 3 else 1)
		return
	if args.size() > 0 and args[0] == "quick":
		await _check_upgrades()
		await _check_lands()
		await _check_double()
		_check_shop()
		_check_trophies()
		_check_copies()
		_check_no_teamwork()
		_check_hero_limit()
		_check_event_data()
		await _check_events()
		await _check_curses()
		_check_difficulty()
		_check_chronicle()
		_check_skip()
		print("FAILURES: %d" % failures)
		quit(1 if failures > 0 else 0)
		return
	_check_item_data()
	_check_trophies()
	_check_copies()
	_check_no_teamwork()
	_check_hero_limit()
	_check_sets()
	_check_tear()
	await _check_item_stats()
	await _check_item_rules(int(args[3]) if args.size() > 3 else 6)
	await _check_wagon_rules()
	await _check_wagon_fights(int(args[3]) if args.size() > 3 else 6)
	await _check_upgrades()
	await _check_lands()
	await _check_double()
	_check_shop()
	_check_sale()
	_check_dark()
	_check_event_data()
	await _check_events()
	await _check_curses()
	_check_difficulty()
	_check_chronicle()
	_check_skip()
	var runs := int(args[0]) if args.size() > 0 else 14
	var wagons := int(args[1]) if args.size() > 1 else 25
	var base_seed := int(args[2]) if args.size() > 2 else 1
	var decks: Array = CardDB.hero_ids()
	var hero_cards: Array = CardDB.hero_card_ids()
	var fights := 0
	var won := 0
	var turns := 0
	var t0 := Time.get_ticks_msec()
	for r in runs:
		var seed_value := base_seed + r
		var agent := RandomAgent.new(seed_value * 7919)
		var deck: String = decks[r % decks.size()]
		var card: String = hero_cards[agent.rng.randi() % hero_cards.size()] if r % 2 == 1 else deck
		var run := TrainRun.new()
		run.save_path = SAVE
		run.start(CardDB.loadout(deck, card), seed_value, "", (r * 3) % (TrainRun.MAX_DIFFICULTY + 1))     # every level in turn
		_check_start(run)
		var steps := 0
		while run.passed < wagons and steps < 400:
			steps += 1
			match run.phase:
				"doors":
					_check_doors(run)
					run.enter(agent.rng.randi() % run.doors.size())
				"fight":
					var res: Array = await _fight(run, agent, seed_value)
					fights += 1
					turns += int(res[1])
					if res[0]:
						won += 1
					run.fight_won(maxi(int(res[2]), 1))
				"level":
					_check_level(run)
					run.pick_perk(run.perks[agent.rng.randi() % run.perks.size()])
				"item":
					_check_items(run)
					if agent.rng.randf() < 0.15:
						run.skip_item()
					else:
						run.take_item(run.item_offers[agent.rng.randi() % run.item_offers.size()])
				"reward":
					if run.offers.is_empty():
						_fail(run, "no trophies to pick from")
					for id: String in run.offers:
						if not run.payable(id):
							_fail(run, "offered %s, the lands cannot pay for it" % id)
					if agent.rng.randf() < 0.2:
						run.skip()
					else:
						run.take(run.offers[agent.rng.randi() % run.offers.size()])
				"shop":
					_shop_step(run, agent)
				"event":
					_event_step(run, agent)
				"rest":
					var pick: float = agent.rng.randf()
					if run.can_remove() and pick < 0.25:
						var ids: Array = run.cards.keys()
						run.remove_card(ids[agent.rng.randi() % ids.size()], agent.rng.randf() < 0.5)
					elif run.has_upgrades() and pick < 0.5:
						var ups: Array = run.cards.keys().filter(func(id): return run.can_upgrade(id))
						run.upgrade_card(ups[agent.rng.randi() % ups.size()])
					elif pick < 0.65:
						var types: Array = CardDB.land_types()
						var lane: int = agent.rng.randi() % run.lands.size()
						var type: String = types[agent.rng.randi() % types.size()]
						if type == run.lands[lane]:
							run.rest_heal()
						else:
							run.change_land(lane, type)
					else:
						run.rest_heal()
			_check_saved(run)
			if run.chronicle.size() != run.passed:
				_fail(run, "chronicle of %d wagons, %d passed" % [run.chronicle.size(), run.passed])
			if run.hp < 1 or run.hp > run.max_hp:
				_fail(run, "hp %d of %d" % [run.hp, run.max_hp])
			if run.deck_size() < run.min_deck():
				_fail(run, "deck of %d cards" % run.deck_size())
		print("run %d %s: train %d, %d wagons passed, deck %d, hp %d, level %d %s, items %s, curses %s, coins %d" % [r, CardDB.loadout(deck, card),
			run.train, run.passed, run.deck_size(), run.hp, run.level, run.fight_stats(), run.items, run.curses, run.coins])
		run.lose()
		if FileAccess.file_exists(SAVE):
			_fail(run, "the save is still there after the run ended")
	print("fights %d, the run deck won %d (%.0f%%), %.1f turns per fight, %.1f s" % [fights, won,
		100.0 * won / maxi(fights, 1), float(turns) / maxi(fights, 1), (Time.get_ticks_msec() - t0) / 1000.0])
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func _check_start(run) -> void:
	if run.deck_size() != TrainRun.START_CARDS:
		_fail(run, "starting deck of %d cards" % run.deck_size())
	var pick: String = run.player_pick()
	if not CardDB.valid_loadout(pick):
		_fail(run, "the run deck is not a valid pick: " + pick)
		return
	var h := CardDB.hero(CardDB.loadout_deck(pick))
	if h["lands"] != run.lands or h["deck"] != run.cards or h["name"] != CardDB.hero(run.deck_id)["name"]:
		_fail(run, "the run deck code reads back wrong")


func _check_doors(run) -> void:
	var w: int = run.wagon + 1
	var kinds: Array = run.doors.map(func(d): return d["kind"])
	if w == TrainRun.TRAIN_LEN and kinds != ["boss"]:
		_fail(run, "locomotive doors %s" % [kinds])
	if w == TrainRun.TRAIN_LEN - 1 and not kinds.has("rest"):
		_fail(run, "no rest before the locomotive: %s" % [kinds])
	if w < TrainRun.TRAIN_LEN and (kinds.size() < 2 or kinds.size() > 3 or kinds.has("boss")):
		_fail(run, "wagon %d doors %s" % [w, kinds])
	if kinds.has("shop") and (w < TrainRun.SHOP_FROM or kinds.count("shop") > 1 or (not run.history.is_empty() and run.history.back() == "shop")):
		_fail(run, "shop in wagon %d: %s after %s" % [w, kinds, run.history.back() if not run.history.is_empty() else ""])
	if kinds.has("event"):
		var ev_doors: Array = run.doors.filter(func(d): return d["kind"] == "event")
		var ev_id := String(ev_doors[0].get("event", ""))
		if ev_doors.size() > 1 or not TrainEvents.has(ev_id) or w < int(TrainEvents.event(ev_id)["from"]) or w < TrainRun.EVENT_FROM \
				or (not run.history.is_empty() and run.history.back() == "event") \
				or (TrainEvents.event(ev_id)["needs"] == "curse" and run.curses.is_empty()):
			_fail(run, "event door %s in wagon %d: %s" % [ev_id, w, kinds])
	var enemies := []
	for d: Dictionary in run.doors:
		if d.has("enemy"):
			if enemies.has(d["enemy"]) or d["enemy"] == run.deck_id:
				_fail(run, "enemy %s twice or the player's own deck" % d["enemy"])
			enemies.append(d["enemy"])
		# A double door: another deck as the second enemy, not in the first wagons, one at a time.
		if d["kind"] == "double":
			var sec: Dictionary = d.get("second", {})
			if sec.is_empty() or enemies.has(sec["enemy"]) or sec["enemy"] == run.deck_id or int(sec["hp"]) <= 0 \
					or not AILevels.ids().has(sec["level"]):
				_fail(run, "double door without a proper second enemy: %s" % [d])
			else:
				enemies.append(sec["enemy"])
			if w < TrainRun.DOUBLE_FROM or run.doors.filter(func(x): return x["kind"] == "double").size() > 1:
				_fail(run, "double door in wagon %d: %s" % [w, kinds])
		elif d.has("second"):
			_fail(run, "a second enemy at a %s door" % d["kind"])
	# Wagon rules: one fight door has one, the boss has its own.
	var rules: Array = run.doors.filter(func(d): return d.has("wagon")).map(func(d): return String(d["wagon"]))
	var fight_doors: int = run.doors.filter(func(d): return TrainRun.FIGHTS.has(d["kind"])).size()
	if rules.size() != mini(fight_doors, 1):
		_fail(run, "wagon %d: %d fight doors, rules %s" % [w, fight_doors, rules])
	for d: Dictionary in run.doors:
		if d.has("wagon") and (not TrainRun.FIGHTS.has(d["kind"]) or not TrainWagons.has(String(d["wagon"]))):
			_fail(run, "rule %s on a %s door" % [d["wagon"], d["kind"]])
	for rule: String in rules:
		var lv := String(TrainWagons.wagon(rule)["level"])
		if w == TrainRun.TRAIN_LEN:
			if rule != TrainWagons.boss_rule(String(run.doors[0]["enemy"])):
				_fail(run, "boss rule %s" % rule)
			continue
		if lv == "boss" or (w <= TrainWagons.EASY_START and not lv in ["light", "festive"]):
			_fail(run, "wagon %d with the %s rule %s" % [w, lv, rule])
		if not run.wagons.is_empty() and run.wagons.back() == rule:
			_fail(run, "rule %s twice in a row" % rule)
		var heavy: int = run.wagons.filter(func(id): return id != "" and TrainWagons.wagon(id)["level"] == "heavy").size()
		if lv == "heavy" and heavy >= TrainWagons.HEAVY_PER_TRAIN:
			_fail(run, "a heavy wagon %s after %d heavy ones" % [rule, heavy])


func _check_level(run) -> void:
	if run.levels_due < 1 or run.perks.size() != TrainRun.PERK_OFFERS:
		_fail(run, "level-up with %d due and perks %s" % [run.levels_due, run.perks])
	for key: String in run.perks:
		if run.perks.count(key) > 1 or run.stat(key) >= run.stat_cap(key):
			_fail(run, "perk %s offered twice or at its maximum" % key)
	for key: String in run.stats:
		if int(run.stats[key]) > run.stat_cap(key):
			_fail(run, "stat %s above its maximum" % key)


## Every item: a known rarity, a text, and mods the run knows what to do with.
func _check_item_data() -> void:
	var known := TrainRun.STATS.keys() + TrainRun.FIGHT_STATS.keys() + TrainRun.ITEM_RULES + ["win_heal",
		"hp_per_win", "fight_hp", "rest_heal", "xp_win", "xp_elite", "min_deck"]
	var curse_known := known + ["enemy_hp", "enemy_crit", "fight_loss", "junk"]
	_expect(TrainItems.CURSES.size() >= 6 and TrainItems.CURSES.size() <= 8, "curses: %d of them" % TrainItems.CURSES.size())
	for id: String in TrainItems.CURSES:
		var cu: Dictionary = TrainItems.CURSES[id]
		_expect(String(cu["name"]) != "" and String(cu["text"]) != "" and String(cu["look"]) != "" and not cu["mods"].is_empty(), "curse %s: name, text, look or mods" % id)
		_expect(not TrainItems.ITEMS.has(id), "curse %s is an item too" % id)
		for key: String in cu["mods"]:
			_expect(curse_known.has(key), "curse %s: unknown mod %s" % [id, key])
	for id: String in TrainItems.ITEMS:
		var it: Dictionary = TrainItems.ITEMS[id]
		if not TrainItems.RARITY.has(it["rarity"]) or String(it["text"]) == "" or it["mods"].is_empty():
			failures += 1
			print("FAIL item %s: rarity, text or mods" % id)
		for key: String in it["mods"]:
			if not known.has(key):
				failures += 1
				print("FAIL item %s: unknown mod %s" % [id, key])
	print("items: %d" % TrainItems.ITEMS.size())


## The trophies of the locomotives: each boss has a legend of its own; a beaten boss offers it
## first; the rewards and the shop never give one.
func _check_trophies() -> void:
	for boss: String in TrainRun.BOSSES:
		var id := String(TrainItems.TROPHIES.get(boss, ""))
		_expect(id != "" and TrainItems.ITEMS.has(id) and TrainItems.item(id)["rarity"] == "legend", "trophy: %s has no legend item" % boss)
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start("finn", 41)
	for boss: String in TrainRun.BOSSES:
		run.items = []
		run.phase = "fight"
		run.current = {"kind": "boss", "enemy": boss, "hp": 20, "level": "hard", "seed": 5, "stats": {}}
		run.fight_won(10)
		_expect(run.item_offers.size() == int(TrainRun.ITEM_OFFERS["boss"]) and run.item_offers[0] == TrainItems.TROPHIES[boss],
			"trophy: %s offers %s" % [boss, run.item_offers])
		run.skip_item()
	run.items = [TrainItems.TROPHIES["lich"]]
	run.phase = "fight"
	run.current = {"kind": "boss", "enemy": "lich", "hp": 20, "level": "hard", "seed": 5, "stats": {}}
	run.fight_won(10)
	_expect(not run.item_offers.has(TrainItems.TROPHIES["lich"]), "trophy: a boss offers a trophy the hero has")
	run.skip_item()
	var trophies := TrainItems.TROPHIES.values()
	for i in 20:
		run.items = []
		for rare in [false, true]:
			for id: String in run._roll_items(TrainItems.ITEMS.size(), rare):
				_expect(not trophies.has(id), "trophy: %s in the rewards or the shop" % id)
	run.items = []
	run.coins = 500
	run.phase = "doors"
	run.doors = [{"kind": "shop"}]
	run.enter(0)
	for id: String in run.shop["items"]:
		_expect(not trophies.has(id), "trophy: %s on the shelf" % id)


## Copies of items: with every item taken the rewards still give some, their mods add up,
## and a copy that would do nothing (a once-only rule, a stat at its top) never comes.
func _check_copies() -> void:
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start("finn", 41)
	run.items = []
	for id: String in TrainItems.ITEMS:
		if not TrainItems.is_trophy(id):
			run.items.append(id)
	for i in 30:
		var got: Array = run._roll_items(3, false)
		_expect(got.size() == 3, "copies: %d items rolled with every item taken" % got.size())
		for id: String in got:
			_expect(run.copy_useful(id), "copies: %s rolled but a copy does nothing" % id)
			_expect(not TrainItems.is_trophy(id), "copies: trophy %s rolled" % id)
	run.items = ["finn_sword"]
	var crit := run.stat("crit")
	run._add_item("finn_sword")
	_expect(run.stat("crit") == crit + 16, "copies: two swords give crit %d" % run.stat("crit"))
	run.items = ["finn_backpack", "finn_backpack"]     # hand at its top: 2 (train rules 2)
	run.train_rules = 2
	_expect(not run.copy_useful("finn_backpack"), "copies: a third backpack is offered")
	run.train_rules = 3
	_expect(run.copy_useful("finn_backpack"), "copies: no top in rules 3, a third backpack does something")
	run.train_rules = TrainRun.TRAIN_RULES
	_expect(not run.copy_useful("finn_backpack"), "copies: the top is back in rules 4")
	var once := ""
	for id: String in TrainItems.ITEMS:
		if TrainItems.item(id)["mods"].keys() == ["first_crit"]:
			once = id
	run.items = [once]
	_expect(once != "" and not run.copy_useful(once), "copies: a second %s is offered" % once)


## The командные карты are for 2 на 2: never in the start deck, the rewards or the shop.
func _check_no_teamwork() -> void:
	for deck: String in ["jake_2x2", "charlie", "grand_prix", "monica"]:
		if not CardDB.hero_ids().has(deck):
			continue
		var run := TrainRun.new()
		run.save_path = SAVE
		run.start(deck, 7)
		run.lands = ["rainbow", "rainbow", "rainbow", "rainbow"]
		for id: String in run.cards.keys() + run.pool.keys():
			_expect(TrainRun.train_card(id), "teamwork: %s in the run deck of %s" % [id, deck])
		for i in 40:
			run._offer_cards([deck] if i % 2 == 0 else [])
			for id: String in run.offers + run._roll_cards(5):
				_expect(TrainRun.train_card(id), "teamwork: %s offered" % id)
			run._fill_shelf()
			for id: String in run.shop["cards"]:
				_expect(TrainRun.train_card(id), "teamwork: %s on the shelf" % id)


## Малыши Финн и Джейк: no creature with more than 3 ATK comes into the run deck (train
## rules 5), in the rewards, the random cards or the shop. Older runs keep their rules.
func _check_hero_limit() -> void:
	var big := func(id: String) -> bool:
		var d := CardDB.get_def(id)
		return d["kind"] == "creature" and int(d["atk"]) > 3
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start("finn@baby_finn_and_jake", 7)
	run.lands = ["rainbow", "rainbow", "rainbow", "rainbow"]
	_expect(not run.cards.keys().any(big), "hero limit: the start deck")
	var seen := 0
	for i in 40:
		run._offer_cards(["jake"] if i % 2 == 0 else [])
		var got: Array = run.offers + run._roll_cards(5)
		run._fill_shelf()
		got += run.shop["cards"]
		seen += got.size()
		for id: String in got:
			_expect(not big.call(id), "hero limit: %s offered to Малыши Финн и Джейк" % id)
	_expect(seen > 100, "hero limit: cards were offered")
	var old := TrainRun.new()
	old.save_path = SAVE
	old.train_rules = 4
	old.start("finn@baby_finn_and_jake", 7)
	old.lands = ["rainbow", "rainbow", "rainbow", "rainbow"]
	var any_big := false
	for i in 20:
		any_big = any_big or old._roll_cards(5).any(big)
	_expect(any_big, "hero limit: train rules 4 still give big creatures (old runs)")
	var plain := TrainRun.new()
	plain.save_path = SAVE
	plain.start("finn", 7)
	plain.lands = ["rainbow", "rainbow", "rainbow", "rainbow"]
	any_big = false
	for i in 20:
		any_big = any_big or plain._roll_cards(5).any(big)
	_expect(any_big, "hero limit: other heroes get big creatures")


## Слеза Принцессы Пламени: the run hands it to the fights while the hero has it, and takes it
## away when a fight it saved is won (the other wins keep it).
func _check_tear() -> void:
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start("finn", 41)
	run.items = ["princess_tear"]
	_expect(run.fight_stats().get("revive", 0) == 1, "tear: the fights get %s" % [run.fight_stats()])
	run.phase = "fight"
	run.current = {"kind": "fight", "enemy": "jake", "hp": 8, "level": "novice", "seed": 5, "stats": {}}
	run.fight_won(5)
	_expect(run.items == ["princess_tear"], "tear: a fight won without it took the tear away")
	run.phase = "fight"
	run.current = {"kind": "fight", "enemy": "jake", "hp": 8, "level": "novice", "seed": 5, "stats": {}}
	run.fight_won(5, true)
	_expect(run.items.is_empty() and not run.fight_stats().has("revive"), "tear: a fight it saved did not take it away: %s" % [run.items])
	run.skip_item()


## The stats only items give, in an engine game: a smaller starting hand, one more
## action, HP lost at the start of the turn.
func _check_item_stats() -> void:
	var game := Game.new()
	game.chooser = RandomAgent.new(5)
	game.setup(["finn", "jake"], 0, 77)
	game.train.set_stats(0, {"hand": -1, "actions": 1, "bleed": 2, "atk": 1})
	var hand: int = game.players[0].hand.size()
	await game.start_game()
	if game.phase == "handoff":
		await game.cmd_start_turn()
	var ps = game.players[0]
	if hand != Game.START_HAND - 1 or game.turn_player != 0 or ps.actions != Game.ACTIONS_PER_TURN + 1 or ps.hp != 23:
		failures += 1
		print("FAIL item stats: hand %d, turn of %d, actions %d, hp %d" % [hand, game.turn_player, ps.actions, ps.hp])


## The sets of items: each has its items and mods the rules know. Its mods count once the hero has
## `need` of its items, in bonus() and in the fight stats; before that they do not.
func _check_sets() -> void:
	var known := TrainRun.STATS.keys() + TrainRun.FIGHT_STATS.keys() + TrainRun.ITEM_RULES + ["win_heal",
		"hp_per_win", "fight_hp", "rest_heal", "xp_win", "xp_elite", "min_deck"]
	for id: String in TrainItems.SETS:
		var st: Dictionary = TrainItems.SETS[id]
		_expect(String(st["name"]) != "" and String(st["text"]) != "" and int(st["need"]) >= 2 and int(st["need"]) <= st["items"].size(),
			"set %s: name, text or need" % id)
		for item: String in st["items"]:
			_expect(TrainItems.ITEMS.has(item) or TrainItems.TROPHIES.values().has(item), "set %s: no item %s" % [id, item])
		for key: String in st["mods"]:
			_expect(known.has(key), "set %s: unknown mod %s" % [id, key])
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start("finn", 91)
	var fin: Array = TrainItems.SETS["finn"]["items"]
	run.items = [fin[0]]
	_expect(run.set_count("finn") == 1 and not run.set_done("finn") and run.bonus("first_crit") == 0,
		"set: one of finn's items gives first_crit %d" % run.bonus("first_crit"))
	run.items.append(fin[1])
	_expect(run.set_done("finn") and run.bonus("first_crit") == 1 and run.fight_stats().get("first_crit", 0) == 1,
		"set: two of finn's items give %s" % [run.fight_stats()])
	run.items.append(fin[2])
	_expect(run.set_count("finn") == 3 and run.bonus("first_crit") == 1, "set: three of finn's items give %d" % run.bonus("first_crit"))
	# The set's mods add up with the items' own: Принцесса's vial gives 1 HP a win, the set 2 more.
	run.items = TrainItems.SETS["princess"]["items"].duplicate()
	_expect(run.bonus("hp_per_win") == 1 + 2, "set: princess gives hp_per_win %d" % run.bonus("hp_per_win"))
	# Лич: the cloak (18 dodge) and the pumpkin (7 dodge, 1 thorns) and the set (10 dodge, 1 thorns).
	run.items = ["lich_cloak", "lich_pumpkin"]
	_expect(run.stat("dodge") == 35 and run.stat("thorns") == 2 and run.fight_stats().get("dodge", 0) == 35,
		"set: lich dodge %d, thorns %d" % [run.stat("dodge"), run.stat("thorns")])
	run.items = ["lich_pumpkin"]
	_expect(run.stat("dodge") == 7 and run.stat("thorns") == 1, "set: lich's pumpkin alone gives dodge %d" % run.stat("dodge"))
	run.save()
	_check_saved(run)
	run.lose()


## The rules of items in an engine game, the ones a short check can see: Свисток Финна,
## Варежки Ледяного короля, Забор Древесного, Желание Призмо. Then fights between random
## players with every rule on both sides: each must end.
func _check_item_rules(games: int) -> void:
	var g := Game.new()
	g.chooser = RandomAgent.new(5)
	g.setup(["finn", "jake"], 0, 77)
	g.train.set_stats(0, {"first_free": 1, "no_freeze": 1, "last_stand": 1, "edge_def": 2})
	await g.start_game()
	if g.phase == "handoff":
		await g.cmd_start_turn()
	var pig = g._make_card("the_pig", 0)
	_expect(g.cost_of(0, pig) == 0, "Свисток Финна: the first creature costs %d" % g.cost_of(0, pig))
	g.players[0].item_state["first_free"] = true
	_expect(g.cost_of(0, pig) == 1, "Свисток Финна: the second creature costs %d" % g.cost_of(0, pig))
	await g.freeze(0, 1)
	_expect(not g.is_frozen(0, 1), "Варежки Ледяного короля: the land froze")
	await g._put_creature(0, pig, 0)
	_expect(g.def_of(0, 0) == 6, "Забор Древесного: DEF %d on the edge" % g.def_of(0, 0))
	await g.damage_player(0, 100)
	_expect(g.players[0].hp == 1 and g.phase != "over", "Желание Призмо: hp %d, %s" % [g.players[0].hp, g.phase])
	await g.damage_player(0, 100)
	_expect(g.phase == "over", "Желание Призмо works twice")
	var t := Game.new()
	t.chooser = RandomAgent.new(5)
	t.setup(["finn", "jake"], 0, 77)
	t.train.set_stats(0, {"revive": 1})
	await t.start_game()
	if t.phase == "handoff":
		await t.cmd_start_turn()
	await t.damage_player(0, 100)
	_expect(t.players[0].hp == 1 and t.phase != "over" and t.players[0].item_state.get("revive", false),
		"Слеза Принцессы Пламени: hp %d, %s" % [t.players[0].hp, t.phase])
	await t.damage_player(0, 100)
	_expect(t.phase == "over", "Слеза Принцессы Пламени works once")

	var all := {}
	for key: String in TrainRun.ITEM_RULES:
		all[key] = 1
	var decks: Array = CardDB.hero_ids()
	var t0 := Time.get_ticks_msec()
	var turns := 0
	for k in games * 4:
		var agent := RandomAgent.new(k * 37 + 3)
		g = Game.new()
		g.chooser = agent
		var a: String = decks[(k * 3) % decks.size()]
		var b: String = decks[(k * 5 + 2) % decks.size()]
		g.setup([a, b], k % 2, 2000 + k)
		g.train.set_stats(0, all)
		g.train.set_stats(1, all if k % 2 == 0 else {})
		await g.start_game()
		var steps := 0
		while g.phase != "over" and steps < 3000:
			if g.phase == "handoff":
				await g.cmd_start_turn()
				continue
			var cmds: Array = g.legal_commands(g.turn_player)
			if cmds.is_empty():
				break
			await g.run_command(g.turn_player, agent.pick_command(cmds))
			steps += 1
		_expect(g.phase == "over", "item rules: %s vs %s did not finish (turn %d, hp %d/%d)" % [a, b,
			g.turn_number, g.players[0].hp, g.players[1].hp])
		turns += g.turn_number
	print("item rule fights %d, %.1f turns per fight, %.1f s" % [games * 4, float(turns) / maxi(games * 4, 1),
		(Time.get_ticks_msec() - t0) / 1000.0])


## Every wagon rule in an engine game, the ones a short check can see.
func _check_wagon_rules() -> void:
	for id: String in TrainWagons.WAGONS:
		var wg: Dictionary = TrainWagons.wagon(id)
		_expect(TrainWagons.LEVELS.has(wg["level"]) and String(wg["text"]) != "" and String(wg["name"]) != "",
			"wagon %s: level, name and text" % id)
	for boss: String in TrainRun.BOSSES:
		_expect(TrainWagons.boss_rule(boss) != "", "boss %s has no rule" % boss)
	# Пробка: one action. Жара: a creature needs one land more. Тишина: no spells.
	var g := await _wagon_game("jam")
	_expect(g.players[g.turn_player].actions == 1, "jam: %d actions" % g.players[g.turn_player].actions)
	g = await _wagon_game("heat")
	for c in g.players[0].hand:
		if c.kind() == "creature":
			_expect(g.lands_needed(0, c) == mini(g.cost_of(0, c) + 1, Game.LANES), "heat: lands for %s" % c.id)
	g = await _wagon_game("silence")
	for c in g.players[g.turn_player].hand:
		_expect(c.kind() != "spell" or not g.can_play(g.turn_player, c.uid), "silence: spell %s playable" % c.id)
	# Узкий проход: only the middle lanes.
	g = await _wagon_game("narrow")
	for cmd: Dictionary in g.legal_commands(g.turn_player):
		_expect(cmd["cmd"] != "play" or int(cmd["lane"]) in [-1, 1, 2], "narrow: %s" % cmd)
	# Ярмарка, Сахарный вагон, Фейерверк: set up by the run for both sides.
	for rule: String in ["fair", "sugar", "fireworks"]:
		var run := TrainRun.new()
		run.save_path = SAVE
		run.start("finn", 3)
		run.current = {"kind": "fight", "enemy": "jake", "hp": 10, "level": "novice", "seed": 5,
			"stats": {"dodge": 15}, "wagon": rule}
		g = Game.new()
		g.setup([run.player_pick(), "jake"], 0, 5)
		run.prepare_fight(g)
		match rule:
			"fair":
				_expect(g.players[0].hand.size() == Game.START_HAND + 1 and g.players[1].hand.size() == Game.START_HAND + 1,
					"fair: hands %d, %d" % [g.players[0].hand.size(), g.players[1].hand.size()])
			"sugar":
				_expect(g.players[0].hp == run.hp + 3 and g.players[1].hp == 13 and g.players[1].max_hp == 13,
					"sugar: hp %d, %d" % [g.players[0].hp, g.players[1].hp])
			"fireworks":
				_expect(g.stat(0, "crit") == run.stat("crit") + 20 and g.stat(1, "crit") == 20 and g.stat(1, "dodge") == 0,
					"fireworks: crit %d, %d, dodge %d" % [g.stat(0, "crit"), g.stat(1, "crit"), g.stat(1, "dodge")])
		run.lose()
	# Склеп: a creature destroyed goes back to its owner's hand.
	g = await _wagon_game("crypt")
	var p: int = g.turn_player
	for c in g.players[p].hand:
		if c.kind() == "creature" and g.can_play(p, c.uid, 1):
			await g.run_command(p, {"cmd": "play", "uid": c.uid, "lane": 1})
			if g.players[p].creatures[1] == c:
				await g.destroy_creature(p, 1)
				_expect(g.players[p].hand.has(c), "crypt: %s not back in hand" % c.id)
			break
	# Концерт: +1 ATK, −1 DEF but not below 1.
	g = await _wagon_game("concert")
	p = g.turn_player
	for c in g.players[p].hand:
		if c.kind() == "creature" and g.can_play(p, c.uid, 2):
			await g.run_command(p, {"cmd": "play", "uid": c.uid, "lane": 2})
			if g.players[p].creatures[2] == c:
				_expect(g.atk_of(p, 2) == int(c.def()["atk"]) + 1 and g.def_of(p, 2) == maxi(int(c.def()["def"]) - 1, 1),
					"concert: %s %d/%d" % [c.id, g.atk_of(p, 2), g.def_of(p, 2)])
			break
	print("wagons: %d" % TrainWagons.WAGONS.size())


## A game with a wagon rule after its first turn has started.
func _wagon_game(rule: String) -> Game:
	var g := Game.new()
	g.chooser = RandomAgent.new(11)
	g.setup(["finn", "jake"], 0, 77)
	g.train.set_wagon(rule)
	await g.start_game()
	return g


## Fights under every rule between random players: each must end ("" plays without a
## rule, to compare with).
func _check_wagon_fights(games: int) -> void:
	var decks: Array = CardDB.hero_ids()
	var t0 := Time.get_ticks_msec()
	var turns := 0
	var n := 0
	for rule: String in [""] + TrainWagons.WAGONS.keys():
		for k in games:
			var agent := RandomAgent.new(k * 31 + 7)
			var g := Game.new()
			g.chooser = agent
			var a: String = decks[(k * 3) % decks.size()]
			var b: String = decks[(k * 5 + 1) % decks.size()]
			g.setup([a, b], k % 2, 1000 + k)
			g.train.set_wagon(rule)
			await g.start_game()
			var steps := 0
			while g.phase != "over" and steps < 3000:
				if g.phase == "handoff":
					await g.cmd_start_turn()
					continue
				var cmds: Array = g.legal_commands(g.turn_player)
				if cmds.is_empty():
					break
				var cmd: Dictionary = agent.pick_command(cmds)
				await g.run_command(g.turn_player, cmd)
				steps += 1
				_expect(rule != "narrow" or _closed_lanes_empty(g), "narrow: %s vs %s, %s put a card on a closed lane" % [a, b, cmd])
			_expect(g.phase == "over", "wagon %s: %s vs %s did not finish (turn %d, hp %d/%d)" % [rule, a, b,
				g.turn_number, g.players[0].hp, g.players[1].hp])
			turns += g.turn_number
			n += 1
	print("wagon fights %d, %.1f turns per fight, %.1f s" % [n, float(turns) / maxi(n, 1), (Time.get_ticks_msec() - t0) / 1000.0])


## No card stands on a lane the wagon closed. Only for Узкий проход: the blizzard closes
## a lane with the cards already on it.
func _closed_lanes_empty(g: Game) -> bool:
	for lane in Game.LANES:
		if g.train.lane_open(lane):
			continue
		for ps in g.players:
			if ps.creatures[lane] != null or ps.buildings[lane] != null:
				return false
	return true


## Difficulty: the penalties of every level, where they work, the save and the chronicle.
func _check_difficulty() -> void:
	var known := ["text", "enemy_hp", "rest", "elite_weight", "shop_pct", "elite_stats", "win_heal", "offers", "coins_pct", "ai_level", "start_hp"]
	_expect(TrainRun.DIFFICULTY.size() == TrainRun.MAX_DIFFICULTY, "difficulty: %d penalties for %d levels" % [TrainRun.DIFFICULTY.size(), TrainRun.MAX_DIFFICULTY])
	for lv in TrainRun.DIFFICULTY.size():
		var d: Dictionary = TrainRun.DIFFICULTY[lv]
		_expect(String(d["text"]) != "" and d.size() == 2 and not "(" in String(d["text"]), "difficulty %d: one penalty with a short text, got %s" % [lv + 1, d])
		for key: String in d:
			_expect(known.has(key), "difficulty %d: unknown key %s" % [lv + 1, key])
		_expect(TrainRun.difficulty_lines(lv + 1).size() == lv + 1 and TrainRun.difficulty_text(lv + 1) == String(d["text"]), "difficulty %d: the lines" % (lv + 1))
	_expect(TrainRun.difficulty_text(0) == "" and TrainRun.difficulty_lines(0).is_empty(), "difficulty 0 has a penalty")
	# Level 0 is the plain train.
	var plain := TrainRun.new()
	plain.save_path = SAVE
	plain.start("finn", 77)
	_expect(plain.difficulty == 0 and plain.hp == TrainRun.START_HP and plain.rest_amount() == TrainRun.REST_HEAL and plain.offer_count() == TrainRun.OFFERS
		and plain.shop_price(10) == 10 and plain.coin_reward("fight") == TrainRun.COIN_WIN["fight"], "difficulty 0 changes numbers")
	for key in known.slice(1):
		_expect(plain.penalty(key) == 0, "difficulty 0: penalty %s" % key)
	# Every level, started and looked at in its first doors: the numbers it changes.
	for lv in range(1, TrainRun.MAX_DIFFICULTY + 1):
		var run := TrainRun.new()
		run.save_path = SAVE
		run.start("finn", 77, "", lv)
		_expect(run.difficulty == lv, "difficulty %d: started at %d" % [lv, run.difficulty])
		var sum := {}
		for i in lv:
			for key: String in TrainRun.DIFFICULTY[i]:
				if key != "text":
					sum[key] = int(sum.get(key, 0)) + int(TrainRun.DIFFICULTY[i][key])
		for key in known.slice(1):
			_expect(run.penalty(key) == int(sum.get(key, 0)), "difficulty %d: penalty %s %d, expected %d" % [lv, key, run.penalty(key), int(sum.get(key, 0))])
		_expect(run.hp == run.max_hp and run.hp == TrainRun.START_HP + int(sum.get("start_hp", 0)), "difficulty %d: start hp %d" % [lv, run.hp])
		_expect(run.rest_amount() == TrainRun.REST_HEAL + int(sum.get("rest", 0)), "difficulty %d: rest %d" % [lv, run.rest_amount()])
		_expect(run.offer_count() == TrainRun.OFFERS + int(sum.get("offers", 0)) and run.offer_count() >= 1, "difficulty %d: %d trophies to pick from" % [lv, run.offer_count()])
		_expect(run.shop_price(20) == roundi(20 * (100 + int(sum.get("shop_pct", 0))) / 100.0), "difficulty %d: price %d" % [lv, run.shop_price(20)])
		for kind: String in TrainRun.COIN_WIN:
			var want := roundi(int(TrainRun.COIN_WIN[kind]) * (100 + int(sum.get("coins_pct", 0))) / 100.0)
			_expect(run.coin_reward(kind) == maxi(want, 1) and run.coin_reward(kind) <= int(TrainRun.COIN_WIN[kind]), "difficulty %d: %s gives %d coins" % [lv, kind, run.coin_reward(kind)])
		# The same seed gives the same first doors, the enemies stronger by the penalties.
		var base := TrainRun.new()
		base.save_path = SAVE
		base.start("finn", 77)
		_expect(run.doors.size() == base.doors.size(), "difficulty %d: other doors from the same seed" % lv)
		for i in mini(run.doors.size(), base.doors.size()):
			var a: Dictionary = run.doors[i]
			var b: Dictionary = base.doors[i]
			if not TrainRun.FIGHTS.has(a["kind"]):
				continue
			_expect(a["kind"] == b["kind"] and a["enemy"] == b["enemy"] and int(a["hp"]) == int(b["hp"]) + int(sum.get("enemy_hp", 0)),
				"difficulty %d: door %s, hp %d against %d" % [lv, a["kind"], a["hp"], b["hp"]])
			_expect(TrainRun.LEVELS.find(a["level"]) == mini(TrainRun.LEVELS.find(b["level"]) + int(sum.get("ai_level", 0)), TrainRun.LEVELS.size() - 1),
				"difficulty %d: AI level %s against %s" % [lv, a["level"], b["level"]])
		# Elites: one more stat from the level that asks for it.
		var elite: Dictionary = run._fight_door("elite")
		var elite0: Dictionary = base._fight_door("elite")
		_expect(elite["stats"].size() == mini(1 + int(sum.get("elite_stats", 0)), TrainRun.ENEMY_STATS.size()) and elite0["stats"].size() == 1,
			"difficulty %d: an elite has %d stats against %d" % [lv, elite["stats"].size(), elite0["stats"].size()])
		_expect(run._fight_door("boss")["stats"].size() == base._fight_door("boss")["stats"].size(), "difficulty %d: a boss has other stats" % lv)
		run.save()
		_check_saved(run)
	# Elite doors: the weight grows with the level that asks for it.
	var shares := []
	for lv in [0, 2, 3, 10]:
		var er := TrainRun.new()
		er.save_path = SAVE
		er.start("finn", 5, "", lv)
		var hits := 0
		for k in 4000:
			if er._door_kind(5) == "elite":
				hits += 1
		shares.append(hits)
	_expect(shares[0] > 0 and absi(shares[0] - shares[1]) < 250 and shares[2] > shares[1] + 150 and shares[3] == shares[2], "difficulty: elite doors by level %s" % [shares])
	# A won fight: the heal and the trophies, from a level with both penalties.
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start("finn", 78, "", TrainRun.MAX_DIFFICULTY)
	run.max_hp = 40
	run.phase = "fight"
	run.current = {"kind": "fight", "enemy": "jake", "hp": 8, "level": "novice", "seed": 5, "stats": {}}
	run.fight_won(10)
	_expect(run.hp == 10 + TrainRun.FIGHT_HEAL + run.penalty("win_heal"), "difficulty: hp %d after a won fight" % run.hp)
	_expect(run.offers.size() <= run.offer_count() and run.offers.size() >= 1, "difficulty: %d trophies" % run.offers.size())
	_expect(run.coins == run.coin_reward("fight") and run.bosses == 0 and run.unlocks() == 0, "difficulty: coins %d, bosses %d" % [run.coins, run.bosses])
	# The shop takes the marked-up prices.
	var shop := TrainRun.new()
	shop.save_path = SAVE
	shop.start("finn", 79, "", 4)
	shop.phase = "doors"
	shop.doors = [{"kind": "shop"}]
	shop.coins = 100
	shop.enter(0)
	var id: String = shop.shop["cards"][0]
	var price: int = shop.shop_price(TrainRun.card_price(id))
	_expect(price > TrainRun.card_price(id), "difficulty: the card costs %d, the base %d" % [price, TrainRun.card_price(id)])
	shop.buy_card(id)
	_expect(shop.coins == 100 - price, "difficulty: bought for %d, coins %d" % [price, shop.coins])
	var item: String = shop.shop["items"][0]
	shop.coins = shop.shop_price(TrainRun.item_price(item)) - 1
	shop.buy_item(item)
	_expect(not shop.items.has(item), "difficulty: an item bought one coin short")
	shop.coins = 100
	var coins: int = shop.coins
	shop.shop_upgrade(_find_card(shop, "creature"))
	_expect(shop.coins == coins - shop.shop_price(TrainRun.PRICE_UPGRADE), "difficulty: an improvement cost %d" % (coins - shop.coins))
	# The train of the day is level 0 whatever is asked.
	var day := TrainRun.new()
	day.save_path = SAVE
	day.start("finn", 80, "2026-10-16", 7)
	_expect(day.difficulty == 0 and day.unlocks() == 0, "difficulty: the train of the day has level %d" % day.difficulty)
	day.phase = "fight"
	day.current = {"kind": "boss", "enemy": "lich", "hp": 20, "level": "hard", "seed": 5, "stats": {}}
	day.fight_won(10)
	_expect(day.bosses == 1 and day.unlocks() == 0, "difficulty: the train of the day opens level %d" % day.unlocks())
	# A beaten locomotive opens the next level, the last one stays at the top.
	for lv in [0, 1, 5, 9, 10]:
		var r := TrainRun.new()
		r.save_path = SAVE
		r.start("jake", 81, "", lv)
		_expect(r.unlocks() == 0, "difficulty %d: opens %d before a boss" % [lv, r.unlocks()])
		r.phase = "fight"
		r.current = {"kind": "boss", "enemy": "lich", "hp": 20, "level": "hard", "seed": 5, "stats": {}}
		r.fight_won(10)
		_expect(r.unlocks() == mini(lv + 1, TrainRun.MAX_DIFFICULTY) and r.bosses == 1, "difficulty %d: opens %d" % [lv, r.unlocks()])
		_check_saved(r)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


## The chronicle: every wagon of the whole run, across the trains; what ended the run; old saves.
func _check_chronicle() -> void:
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start("finn", 90, "", 2)
	for k in TrainRun.TRAIN_LEN + 4:
		run.phase = "rest"
		run.current = {"kind": "rest"} if k > 0 else {"kind": "fight", "enemy": "jake", "wagon": "fair", "hp": 8, "level": "novice", "seed": 1, "stats": {}}
		run.rest_heal()
		_expect(run.chronicle.size() == k + 1 and run.passed == k + 1, "chronicle: %d entries after %d wagons" % [run.chronicle.size(), run.passed])
	_expect(run.train == 2 and run.history.size() == 4 and run.chronicle.size() == TrainRun.TRAIN_LEN + 4, "chronicle: the train started over, the chronicle did not")
	_expect(run.chronicle[0]["kind"] == "fight" and run.chronicle[0]["enemy"] == "jake" and run.chronicle[0]["wagon"] == "fair" and run.chronicle[1] == {"kind": "rest", "enemy": "", "wagon": ""},
		"chronicle: first wagons %s" % [run.chronicle.slice(0, 2)])
	# A double wagon writes its second enemy.
	run.phase = "fight"
	run.current = {"kind": "double", "enemy": "jake", "hp": 8, "level": "novice", "seed": 1, "stats": {}, "second": {"enemy": "bmo", "hp": 8, "level": "novice", "stats": {}}}
	run.fight_won(10)
	while run.phase in ["level", "item"]:
		if run.phase == "level":
			run.pick_perk(run.perks[0])
		else:
			run.skip_item()
	run.skip()
	_expect(run.chronicle.back().get("second", "") == "bmo", "chronicle: the second enemy is %s" % [run.chronicle.back()])
	_check_saved(run)
	# The end of the run: a lost fight is kept, giving up is not.
	var lost := TrainRun.new()
	lost.save_path = SAVE
	lost.start("finn", 91)
	lost.phase = "fight"
	lost.current = {"kind": "elite", "enemy": "bmo", "wagon": "sugar", "hp": 8, "level": "novice", "seed": 1, "stats": {}}
	lost.lose(true)
	_expect(lost.phase == "over" and lost.fell == {"kind": "elite", "enemy": "bmo", "wagon": "sugar"} and not FileAccess.file_exists(SAVE), "chronicle: lost fight %s" % [lost.fell])
	var gave_up := TrainRun.new()
	gave_up.save_path = SAVE
	gave_up.start("finn", 92)
	gave_up.lose()
	_expect(gave_up.fell.is_empty() and gave_up.phase == "over", "chronicle: giving up left %s" % [gave_up.fell])
	# Saves of before: no difficulty, the chronicle made of the train going on, the earlier wagons blank.
	var old := TrainRun.new()
	old.save_path = SAVE
	old.start("finn", 93)
	old.train = 3
	old.passed = 23
	old.wagon = 3
	old.history = ["fight", "rest", "shop"]
	old.met = ["jake", "", ""]
	old.wagons = ["fair", "", ""]
	var d: Dictionary = old.to_dict()
	d["format"] = 7
	for key in ["difficulty", "bosses", "chronicle"]:
		d.erase(key)
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var back := TrainRun.new()
	back.save_path = SAVE
	_expect(back.restore(), "chronicle: a save of format 7 does not load")
	_expect(back.difficulty == 0 and back.bosses == 2 and back.chronicle.size() == 23 and back.chronicle[19]["kind"] == "" and back.chronicle[20]["kind"] == "fight"
		and back.chronicle[20]["enemy"] == "jake" and back.chronicle[20]["wagon"] == "fair" and back.chronicle[22]["kind"] == "shop",
		"chronicle: old save gives difficulty %d, bosses %d, %d entries" % [back.difficulty, back.bosses, back.chronicle.size()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


## Leaving the trophies: a hurt hero gets 3 HP back (never above the max), a full one 1 experience.
func _check_skip() -> void:
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start("finn", 94)
	run.phase = "reward"
	run.current = {"kind": "fight", "enemy": "jake", "wagon": "", "hp": 8, "level": "novice", "seed": 1, "stats": {}}
	run.hp = run.max_hp - 2
	run.skip()
	_expect(run.hp == run.max_hp and run.passed == 1, "skip: hurt hero at %d of %d after leaving the trophies" % [run.hp, run.max_hp])
	run.phase = "reward"
	run.current = {"kind": "fight", "enemy": "jake", "wagon": "", "hp": 8, "level": "novice", "seed": 1, "stats": {}}
	run.hp = run.max_hp - 5
	run.skip()
	_expect(run.hp == run.max_hp - 2, "skip: 3 HP back gave %d of %d" % [run.hp, run.max_hp])
	run.phase = "reward"
	run.current = {"kind": "fight", "enemy": "jake", "wagon": "", "hp": 8, "level": "novice", "seed": 1, "stats": {}}
	run.hp = run.max_hp
	run.skip()
	_expect(run.hp == run.max_hp and run.xp == 1 and run.levels_due == 0, "skip: full hero gave xp %d, level %d" % [run.xp, run.level])
	run.phase = "reward"
	run.current = {"kind": "fight", "enemy": "jake", "wagon": "", "hp": 8, "level": "novice", "seed": 1, "stats": {}}
	run.skip()
	_expect(run.xp == 0 and run.level == 2 and run.levels_due == 1, "skip: second xp gave xp %d, level %d, due %d" % [run.xp, run.level, run.levels_due])
	# Train rules 4: the tops are back, only the health has none. A hero with every stat at its top still gets
	# a level-up to pick: the health.
	var maxed := TrainRun.new()
	maxed.save_path = SAVE
	maxed.start("finn", 77)
	for key: String in TrainRun.STATS:
		maxed.stats[key] = int(TrainRun.STATS[key]["max"])
	maxed.max_hp = 1002
	maxed.level = 53
	maxed.phase = "fight"
	maxed.current = {"kind": "fight", "enemy": "jake", "wagon": "", "hp": 8, "level": "novice", "seed": 1, "stats": {}}
	maxed.xp = maxed.xp_needed() - 1
	maxed.fight_won(10)
	_expect(maxed.phase == "level" and maxed.perks == ["max_hp"], "maxed: level-up offers %s in phase %s" % [maxed.perks, maxed.phase])
	var hp_before: int = maxed.max_hp
	maxed.pick_perk("max_hp")
	_expect(maxed.levels_due == 0 and maxed.phase != "level" and maxed.max_hp == hp_before + 5, "maxed: health %d to %d, phase %s" % [hp_before, maxed.max_hp, maxed.phase])
	_expect(maxed.stat_cap("crit") == 61 and maxed.stat("crit") == 61 and maxed.stat_cap("dodge") == 35, "rules 4: the tops are back")
	# Items on top of a full stat do not go past the top (a hundred items made the dodge 100% in build 57).
	maxed.items = ["finn_sword"] if TrainItems.ITEMS.has("finn_sword") else maxed.items
	_expect(maxed.stat("crit") == 61, "rules 4: crit with an item %d" % maxed.stat("crit"))
	maxed.train_rules = 3
	_expect(maxed.stat_cap("crit") == TrainRun.NO_CAP and maxed.stat_cap("max_hp") == TrainRun.NO_CAP, "rules 3: no top")
	maxed.train_rules = 2
	_expect(maxed.stat_cap("max_hp") == 999 and maxed.stat_cap("crit") == 61, "rules 2: the old tops")
	maxed.train_rules = TrainRun.TRAIN_RULES
	_expect(maxed.stat_step("crit") == 2 and maxed.stat_step("lifesteal") == 3 and maxed.stat_step("armor") == 1, "rules 4: slow steps")
	maxed.train_rules = 2
	_expect(maxed.stat_step("crit") == 8 and maxed.stat_step("lifesteal") == 25, "rules 2: the old steps")
	maxed.train_rules = TrainRun.TRAIN_RULES
	# A save written while stuck on the empty screen (rules 2) is offered perks again.
	maxed.phase = "level"
	maxed.levels_due = 1
	maxed.perks = []
	maxed.save()
	var stuck := TrainRun.new()
	stuck.save_path = SAVE
	_expect(stuck.restore() and stuck.perks == ["max_hp"], "maxed: stuck save loaded with perks %s" % [stuck.perks])
	# Late wagons: nothing before wagon 100 and in the old rules, then a step every 50, softer past four steps.
	var late := TrainRun.new()
	late.save_path = ""
	late.start("finn", 78)
	late.passed = 99
	_expect(late.late_tier() == 0 and late._late_stats("fight").is_empty(), "late: wagon 99 is plain")
	late.passed = 100
	_expect(late.late_tier() == 1 and late.late_tier("boss") == 2, "late: wagon 100 tiers %d %d" % [late.late_tier(), late.late_tier("boss")])
	late.passed = 150
	_expect(late.late_tier() == 2, "late: wagon 150 tier %d" % late.late_tier())
	late.passed = 506
	_expect(late.late_tier() == 5, "late: wagon 506 tier %d" % late.late_tier())
	var hp_plain: int = late._enemy_hp("fight")
	var st: Dictionary = late._late_stats("boss")
	_expect(st.has("revive") and st.has("last_stand") and st.has("first_crit") and int(st["atk"]) > 0, "late: a boss at 506 has %s" % [st])
	late.train_rules = 3
	_expect(late.late_tier() == 0 and late._enemy_hp("fight") < hp_plain, "late: the rules 3 have no late wagons")
	late.train_rules = TrainRun.TRAIN_RULES
	late.passed = 330
	var prev := 0
	for w in [100, 150, 200, 250, 300, 350, 400, 450, 500, 550]:
		late.passed = w
		var hp_now: int = late._enemy_hp("fight")
		_expect(hp_now >= prev, "late: hit points never fall at wagon %d" % w)
		prev = hp_now
	_expect(TrainRun.enemy_stat_lines(late._late_stats("boss")).size() == late._late_stats("boss").size(), "late: every enemy line has a name")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", what)


func _check_items(run) -> void:
	var kind := String(run.current.get("kind", ""))
	var most := int(TrainRun.ITEM_OFFERS.get(kind, 1)) + (1 if bool(run.current.get("dark", false)) else 0)     # a dark door: one more
	if run.item_offers.is_empty() or run.item_offers.size() > most:
		_fail(run, "%d items offered after %s" % [run.item_offers.size(), kind])
	for id: String in run.item_offers:
		if run.item_offers.count(id) > 1:
			_fail(run, "item %s offered twice" % id)
		if run.items.has(id) and (TrainItems.is_trophy(id) or not run.copy_useful(id)):
			_fail(run, "item %s offered again but a copy does nothing" % id)
		if kind == "boss" and TrainItems.item(id)["rarity"] == "common":
			_fail(run, "a boss offered the common item %s" % id)


## One fight as an engine game between random players: [won, turns, hp left].
func _fight(run, agent: RandomAgent, seed_value: int) -> Array:
	var door: Dictionary = run.current
	var game := Game.new()
	game.chooser = agent
	game.setup([run.player_pick(), door["enemy"]], int(door["seed"]) % 2, int(door["seed"]))
	run.prepare_fight(game)
	await game.start_game()
	var steps := 0
	while game.phase != "over" and steps < 3000:
		if game.phase == "handoff":
			await game.cmd_start_turn()
			continue
		var p: int = game.turn_player
		var cmds: Array = game.legal_commands(p)
		if cmds.is_empty():
			_fail(run, "no legal commands (seed %d)" % seed_value)
			break
		await game.run_command(p, agent.pick_command(cmds))
		for side in 2:
			if game.players[side].hp > game.players[side].max_hp:
				_fail(run, "hp %d above the maximum %d" % [game.players[side].hp, game.players[side].max_hp])
		steps += 1
	if game.phase != "over":
		_fail(run, "the fight in wagon «%s» did not finish (turn %d, hp %d/%d, decks %d/%d, stats %s / %s)" % [game.train.wagon, game.turn_number,
			game.players[0].hp, game.players[1].hp, game.players[0].deck.size(), game.players[1].deck.size(),
			game.players[0].stats, game.players[1].stats])
	return [game.winner == 0, game.turn_number, game.players[0].hp]


func _balance(runs: int, level: String, base_seed: int) -> void:
	var decks: Array = CardDB.hero_ids()
	var results := []
	var by_kind := {}
	var t0 := Time.get_ticks_msec()
	for r in runs:
		var rng := RandomNumberGenerator.new()
		rng.seed = base_seed + r
		var run := TrainRun.new()
		run.save_path = SAVE
		run.start(decks[(base_seed + r) % decks.size()], base_seed + r)
		while run.phase != "over" and run.passed < 60:
			match run.phase:
				"doors":
					run.enter(_sensible_door(run, rng))
				"fight":
					var door: Dictionary = run.current
					var res: Array = await _ai_fight(run, level)
					var stat: Array = by_kind.get(door["kind"], [0, 0, 0])
					stat[0] += 1
					stat[1] += 1 if res[0] else 0
					stat[2] += run.hp - int(res[1]) if res[0] else run.hp
					by_kind[door["kind"]] = stat
					if res[0]:
						run.fight_won(int(res[1]))
					else:
						run.lose()
				"level":
					run.pick_perk(run.perks[rng.randi() % run.perks.size()])
				"item":
					run.take_item(run.item_offers[rng.randi() % run.item_offers.size()])
				"reward":
					run.take(run.offers[rng.randi() % run.offers.size()])
				"rest":
					run.rest_heal()
				"shop":
					_sensible_shop(run)
				"event":
					_sensible_event(run, rng)
		print("run %d %s: %d wagons, train %d, %d wins, level %d %s, %d items" % [r, run.deck_id, run.passed, run.train, run.wins,
			run.level, run.fight_stats(), run.items.size()])
		results.append(run.passed)
		run.lose()
	results.sort()
	var total := 0
	for x in results:
		total += x
	print("player %s: wagons passed mean %.1f, median %d, best %d" % [level, float(total) / runs, results[runs / 2], results.back()])
	for k in by_kind:
		var stat: Array = by_kind[k]
		print("  %s: %d fights, won %.0f%%, hp lost per fight %.1f" % [k, stat[0], 100.0 * stat[1] / stat[0], float(stat[2]) / stat[0]])
	print("%.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


## Doors the way a careful player picks them: a rest when hurt, an elite only when
## healthy, a chest gladly, otherwise a common fight; ties at random.
func _sensible_door(run, rng: RandomNumberGenerator) -> int:
	var best := -1
	var best_score := -INF
	for i in run.doors.size():
		var score := rng.randf()
		match String(run.doors[i]["kind"]):
			"rest":
				score += 10.0 if run.hp <= 14 else 1.0
			"treasure":
				score += 6.0
			"shop":
				score += 2.0 + minf(run.coins / 20.0, 4.0)
			"event":
				score += 3.0 if run.hp >= 12 else -4.0
			"elite":
				score += 5.0 if run.hp >= 20 else -10.0
			"double":
				score += 4.0 if run.hp >= 18 else -8.0
			"fight":
				score += 3.0
		if score > best_score:
			best_score = score
			best = i
	return best


## A shop the way a careful player uses it: the best items the coins buy, a curse off, an
## improved card, cards; then away.
func _sensible_shop(run) -> void:
	var items: Array = run.shop["items"].duplicate()
	items.sort_custom(func(a, b): return TrainRun.item_price(a) > TrainRun.item_price(b))
	for id: String in items:
		run.buy_item(id)
	for id: String in run.curses.duplicate():
		run.shop_uncurse(id)
	var ups: Array = run.cards.keys().filter(func(id): return run.can_upgrade(id))
	if not ups.is_empty():
		run.shop_upgrade(ups[0])
	for id: String in run.shop["cards"].duplicate():
		run.buy_card(id)
	run.leave_shop()


## An event: one of the options the hero can take (no curses, no HP when hurt), else away.
func _sensible_event(run, rng: RandomNumberGenerator) -> void:
	match String(run.event["stage"]):
		"options":
			var ok: Array = []
			for i in run.event_options().size():
				var cost: Dictionary = run.event_options()[i].get("cost", {})
				var chance: Dictionary = run.event_options()[i].get("chance", {})
				if run.event_block(i) == "" and not cost.has("curse") and chance.is_empty() and not (cost.has("hp") and run.hp <= 14):
					ok.append(i)
			if ok.is_empty():
				run.leave_event()
			else:
				run.choose_event(ok[rng.randi() % ok.size()])
		"pick":
			match String(run.event["pick"]):
				"remove":
					run.event_pick(run.cards.keys()[rng.randi() % run.cards.size()])
				"upgrade":
					run.event_pick(run.cards.keys().filter(func(c): return run.plain_count(c) > 0 and TrainRun.upgradable(c))[0])
				"curse":
					run.event_pick(run.curses[0])
		_:
			run.finish_event()


## One fight with AI players on both sides, like the board plays them: [won, hp left].
func _ai_fight(run, level: String) -> Array:
	var door: Dictionary = run.current
	var picks := [run.player_pick(), String(door["enemy"])]
	var agents := [AILevels.agent(level, picks[0]), AILevels.agent(String(door["level"]), picks[1])]
	var game := Game.new()
	var chooser := SeatChooser.new()
	chooser.game = game
	chooser.agents = agents
	game.chooser = chooser
	game.setup(picks, int(door["seed"]) % 2, int(door["seed"]))
	run.prepare_fight(game)
	for p in 2:
		if agents[p].mulligan(game, p):
			await game.cmd_mulligan(p)
	var second_agent = null
	await game.start_game()
	var steps := 0
	while game.phase != "over" and steps < 3000:
		if game.phase == "handoff":
			await game.cmd_start_turn()
			continue
		var p: int = game.turn_player
		var cmd: Dictionary = agents[p].pick_command(game, p)
		var before := game.state_hash()
		await game.run_command(p, cmd)
		if door.has("second") and game.train.follow.is_empty() and agents[1] != second_agent:    # the second enemy sits down
			second_agent = AILevels.agent(String(door["second"]["level"]), String(door["second"]["enemy"]))
			agents[1] = second_agent
			chooser.agents = agents
		if game.state_hash() == before and game.turn_player == p and (game.phase == "main" or game.phase == "attack"):
			agents[p].ban_command(before, cmd)
		steps += 1
	return [game.winner == 0, game.players[0].hp]


## The save must give back the same run.
func _check_saved(run) -> void:
	var copy := TrainRun.new()
	copy.save_path = SAVE
	if not copy.restore():
		_fail(run, "the save does not load")
		return
	if JSON.stringify(copy.to_dict()) != JSON.stringify(run.to_dict()):
		_fail(run, "the save loads back different:\n%s\n%s" % [JSON.stringify(run.to_dict()), JSON.stringify(copy.to_dict())])


func _fail(run, text: String) -> void:
	failures += 1
	if failures <= 20:
		print("FAIL [%s, train %d wagon %d, %s]: %s" % [run.deck_id, run.train, run.wagon, run.phase, text])


## A rest of a fresh run, for the checks of what a rest can do.
func _rest_run(seed_value: int, pick := "finn"):
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start(pick, seed_value)
	run.phase = "rest"
	run.current = {"kind": "rest"}
	run.doors = []
	return run


## A card of the run's deck of a kind that costs at least min_cost, "" when there is none.
func _find_card(run, kind: String, min_cost := 0) -> String:
	for id: String in run.cards:
		var d := CardDB.get_def(id)
		if d["kind"] == kind and int(d["cost"]) >= min_cost:
			return id
	return ""


## Improved cards: the rest, the marks in the game, the numbers they give, the save.
func _check_upgrades() -> void:
	var run = _rest_run(11)
	var cid := _find_card(run, "creature")
	_expect(cid != "" and run.can_upgrade(cid) and run.has_upgrades(), "upgrade: nothing to improve in a fresh deck")
	var before: int = run.passed
	run.upgrade_card(cid)
	_expect(run.upgrade_count(cid) == 1 and run.phase == "doors" and run.passed == before + 1,
		"upgrade: %d improved, phase %s" % [run.upgrade_count(cid), run.phase])
	_check_saved(run)
	# Only a copy that is not improved yet, and nothing that costs nothing.
	var copies: int = run.cards[cid]
	for k in copies:
		run.phase = "rest"
		run.upgrade_card(cid)
	run.phase = "rest"
	_expect(run.upgrade_count(cid) == copies and not run.can_upgrade(cid), "upgrade: %d improved of %d copies" % [run.upgrade_count(cid), copies])
	var free := ""
	for id: String in CardDB.card_ids():
		if CardDB.get_def(id)["kind"] != "creature" and int(CardDB.get_def(id)["cost"]) == 0:
			free = id
			break
	run.cards[free] = 1
	_expect(free != "" and not run.can_upgrade(free), "upgrade: a free card %s can be improved" % free)
	run.cards.erase(free)
	run.phase = "doors"
	run.upgrade_card(cid)
	_expect(run.upgrade_count(cid) == copies, "upgrade: improved outside a rest")
	# Throwing a copy out: the plain one first, the improved one when asked.
	run = _rest_run(12)
	cid = _find_card(run, "creature")
	run.cards[cid] = 3
	run.upgraded[cid] = 1
	run.remove_card(cid)
	_expect(run.cards[cid] == 2 and run.upgrade_count(cid) == 1, "remove: plain first, %d copies %d improved" % [run.cards[cid], run.upgrade_count(cid)])
	run.phase = "rest"
	run.remove_card(cid, true)
	_expect(run.cards[cid] == 1 and run.upgrade_count(cid) == 0, "remove: improved on request, %d copies %d improved" % [run.cards[cid], run.upgrade_count(cid)])
	run.phase = "rest"
	run.upgraded[cid] = 1
	run.remove_card(cid)        # the last copy is improved: it goes
	_expect(not run.cards.has(cid) and not run.upgraded.has(cid), "remove: the last improved copy stays in %s" % [run.upgraded])
	# The save: the improved copies come back, a format 5 save has none.
	run = _rest_run(13)
	cid = _find_card(run, "creature")
	run.upgraded[cid] = 1
	run.save()
	var copy := TrainRun.new()
	copy.save_path = SAVE
	_expect(copy.restore() and copy.upgraded == {cid: 1}, "save: improved copies lost: %s" % [copy.upgraded])
	var d: Dictionary = run.to_dict()
	d["format"] = 5
	d.erase("upgraded")
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	copy = TrainRun.new()
	copy.save_path = SAVE
	_expect(copy.restore() and copy.upgraded.is_empty(), "save: a format 5 run does not load")
	# In a fight: that many cards of the deck are marked, and the numbers change.
	run = _rest_run(14)
	cid = _find_card(run, "creature")
	var sid := _find_card(run, "spell", 1)
	var bid := _find_card(run, "building", 1)
	run.upgraded[cid] = 1
	if sid != "":
		run.upgraded[sid] = 1
	if bid != "":
		run.upgraded[bid] = 1
	run.phase = "fight"
	run.current = {"kind": "fight", "enemy": "jake", "hp": 10, "level": "novice", "seed": 5, "stats": {}}
	var g := Game.new()
	g.chooser = RandomAgent.new(3)
	g.setup([run.player_pick(), "jake"], 0, 5)
	run.prepare_fight(g)
	var marked := g.all_cards(0).filter(func(c): return c.upgraded)
	var want := 1 + (1 if sid != "" else 0) + (1 if bid != "" else 0)
	_expect(marked.size() == want and g.all_cards(1).filter(func(c): return c.upgraded).is_empty(),
		"fight: %d cards marked, %d improved in the run" % [marked.size(), want])
	await g.start_game()
	for c in marked:
		var d2: Dictionary = c.def()
		var plain := Game.new()
		plain.setup([run.player_pick(), "jake"], 0, 5)
		var twin = plain._make_card(c.id, 0)
		if c.kind() == "creature":
			await g._put_creature(0, c, 0)
			await plain._put_creature(0, twin, 0)
			_expect(g.atk_of(0, 0) == plain.atk_of(0, 0) + 1 and g.def_of(0, 0) == plain.def_of(0, 0) + 1,
				"fight: improved %s is %d/%d, the card %d/%d" % [c.id, g.atk_of(0, 0), g.def_of(0, 0), plain.atk_of(0, 0), plain.def_of(0, 0)])
			_expect(g.clone().card(c.uid).upgraded, "fight: the copy of the game lost the mark")
		else:
			_expect(g.cost_of(0, c) == plain.cost_of(0, twin) - 1 and plain.cost_of(0, twin) >= 1,
				"fight: improved %s costs %d, the card %d" % [c.id, g.cost_of(0, c), plain.cost_of(0, twin)])
	# The mark stays on the card when it changes zones.
	marked[0].reset_board_state()
	_expect(marked[0].upgraded, "fight: the mark is gone with the board state")
	# A card in play that is improved changes the state hash (a plain game's hash is not touched: see replay_test).
	var g2 := Game.new()
	g2.setup([run.player_pick(), "jake"], 0, 5)
	var twin2 = g2._make_card(cid, 0)
	await g2._put_creature(0, twin2, 0)
	var h2: int = g2.state_hash()
	twin2.upgraded = true
	_expect(g2.state_hash() != h2, "fight: the hash does not see an improved card")
	run.lose()


## Changing a land.
func _check_lands() -> void:
	var run = _rest_run(21)
	var old: Array = run.lands.duplicate()
	var other := ""
	for t: String in CardDB.land_types():
		if t != old[1]:
			other = t
			break
	run.change_land(1, old[1])          # the same type: nothing
	run.change_land(9, other)
	run.change_land(1, "rainbow")
	run.change_land(1, "nonsense")
	_expect(run.phase == "rest" and run.lands == old, "lands: a bad change went through: %s" % [run.lands])
	var passed: int = run.passed
	run.change_land(1, other)
	var want := old.duplicate()
	want[1] = other
	_expect(run.lands == want and run.phase == "doors" and run.passed == passed + 1, "lands: %s instead of %s, phase %s" % [run.lands, want, run.phase])
	_check_saved(run)
	run.change_land(2, other)
	_expect(run.lands == want, "lands: changed outside a rest")
	# The deck code, the game and the trophies go by the new lands, in the same order.
	var pick: String = run.player_pick()
	_expect(CardDB.valid_loadout(pick), "lands: the pick %s is not valid" % pick)
	var g := Game.new()
	g.setup([pick, "jake"], 0, 5)
	_expect(g.players[0].lands.map(func(l): return l["type"]) == want, "lands: the game has %s" % [g.players[0].lands.map(func(l): return l["type"])])
	var swapped := want.duplicate()
	swapped.reverse()
	await g.cmd_arrange_lands(0, swapped)       # a fight may still arrange them
	_expect(g.players[0].lands.map(func(l): return l["type"]) == swapped, "lands: arranging after the change")
	for id: String in CardDB.card_ids():
		var d := CardDB.get_def(id)
		var have: int = run.lands.size() if d["land"] == "rainbow" else run.lands.count(d["land"])
		_expect(run.payable(id) == (int(d["cost"]) <= have), "lands: payable %s" % id)
	run.phase = "fight"
	run.current = {"kind": "fight", "enemy": "jake", "hp": 8, "level": "novice", "seed": 5, "stats": {}}
	run.fight_won(5)
	for id: String in run.offers:
		_expect(run.payable(id), "lands: offered %s, the new lands cannot pay for it" % id)
	run.lose()


## One random step in a shop: buy something the coins allow, or leave.
func _shop_step(run, agent: RandomAgent) -> void:
	var shop: Dictionary = run.shop
	_expect(shop.has("cards") and shop["cards"].size() >= 1 and shop["cards"].size() <= TrainRun.SHOP_CARDS and shop["items"].size() <= TrainRun.SHOP_ITEMS,
		"shop stock %s" % [shop])
	for id: String in shop["cards"]:
		_expect(run.payable(id) and shop["cards"].count(id) == 1, "shop: the card %s is not payable or twice" % id)
	for id: String in shop["items"]:
		_expect(not run.items.has(id) and shop["items"].count(id) == 1, "shop: the item %s is taken or twice" % id)
	var coins: int = run.coins
	var deck: int = run.deck_size()
	match agent.rng.randi() % 6:
		0:
			var id: String = shop["cards"][agent.rng.randi() % shop["cards"].size()]
			run.buy_card(id)
			var paid: bool = coins >= run.shop_price(TrainRun.card_price(id))
			_expect(run.coins == coins - (run.shop_price(TrainRun.card_price(id)) if paid else 0) and run.deck_size() == deck + (1 if paid else 0),
				"shop: buying %s with %d coins left %d" % [id, coins, run.coins])
		1:
			if not shop["items"].is_empty():
				var id: String = shop["items"][agent.rng.randi() % shop["items"].size()]
				run.buy_item(id)
				var paid: bool = coins >= run.shop_price(TrainRun.item_price(id))
				_expect(run.coins == coins - (run.shop_price(TrainRun.item_price(id)) if paid else 0) and run.items.has(id) == paid,
					"shop: buying item %s with %d coins" % [id, coins])
		2:
			var ups: Array = run.cards.keys().filter(func(id): return run.can_upgrade(id))
			if not ups.is_empty():
				run.shop_upgrade(ups[agent.rng.randi() % ups.size()])
		3:
			var ids: Array = run.cards.keys()
			run.shop_remove(ids[agent.rng.randi() % ids.size()], agent.rng.randf() < 0.5)
		_:
			if agent.rng.randf() < 0.7:
				run.leave_shop()
	_expect(run.coins >= 0, "shop: %d coins" % run.coins)


## Coins and the shop: what a fight gives, what the shelf offers, what every purchase does.
func _check_shop() -> void:
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start("finn", 41)
	_expect(run.coins == 0, "shop: a new run has %d coins" % run.coins)
	for kind: String in TrainRun.COIN_WIN:
		_expect(run.coin_reward(kind) > 0, "shop: a won %s gives no coins" % kind)
	_expect(run.coin_reward("boss") > run.coin_reward("elite") and run.coin_reward("elite") > run.coin_reward("fight"),
		"shop: the coins of a boss, an elite and a fight")
	run.phase = "fight"
	run.current = {"kind": "elite", "enemy": "jake", "hp": 8, "level": "novice", "seed": 5, "stats": {}}
	run.fight_won(5)
	_expect(run.coins == TrainRun.COIN_WIN["elite"], "shop: %d coins after an elite" % run.coins)
	_check_saved(run)
	# The door and the shop itself.
	run.phase = "doors"
	run.doors = [{"kind": "shop"}, {"kind": "rest"}]
	run.coins = 100
	run.enter(0)
	_expect(run.phase == "shop" and run.shop["cards"].size() >= 2 and run.shop["items"].size() == TrainRun.SHOP_ITEMS,
		"shop: phase %s, shelf %s" % [run.phase, run.shop])
	_check_saved(run)
	var id: String = run.shop["cards"][0]
	var price := TrainRun.card_price(id)
	_expect(price == TrainRun.PRICE_CARD + TrainRun.PRICE_PER_COST * int(CardDB.get_def(id)["cost"]), "shop: the price of %s is %d" % [id, price])
	var had: int = int(run.cards.get(id, 0))
	run.buy_card(id)
	_expect(run.coins == 100 - price and int(run.cards.get(id, 0)) == had + 1 and not run.shop["cards"].has(id),
		"shop: bought %s, coins %d" % [id, run.coins])
	run.buy_card(id)
	_expect(run.coins == 100 - price, "shop: the same card bought twice")
	var item: String = run.shop["items"][0]
	var more := int(TrainItems.item(item)["mods"].get("max_hp", 0))
	var max_before: int = run.max_hp
	run.buy_item(item)
	_expect(run.items.has(item) and run.coins == 100 - price - TrainRun.item_price(item) and run.max_hp == maxi(max_before + more, 1),
		"shop: item %s, coins %d" % [item, run.coins])
	_check_saved(run)
	# Improving and throwing out: once each, with the min_deck in mind.
	var cid := _find_card(run, "creature")
	var coins: int = run.coins
	run.shop_upgrade(cid)
	_expect(run.upgrade_count(cid) == 1 and run.coins == coins - TrainRun.PRICE_UPGRADE and not run.shop["upgrade"], "shop: improving %s" % cid)
	run.shop_upgrade(cid)
	_expect(run.coins == coins - TrainRun.PRICE_UPGRADE, "shop: improved twice in one visit")
	var deck: int = run.deck_size()
	run.shop_remove(cid, true)
	_expect(run.deck_size() == deck - 1 and run.upgrade_count(cid) == 0 and run.coins == coins - TrainRun.PRICE_UPGRADE - TrainRun.PRICE_REMOVE
		and not run.shop["remove"], "shop: throwing %s out, deck %d, coins %d" % [cid, run.deck_size(), run.coins])
	run.shop_remove(cid)
	_expect(run.deck_size() == deck - 1, "shop: two cards thrown out in one visit")
	_check_saved(run)
	# Rolling the shelf again: each roll costs more than the last, and a new shop starts at the first price.
	run.coins = 100
	var rolled := []
	for i in 3:
		rolled.append(run.reroll_price())
		run.shop_reroll()
	var spent := 0
	for i in 3:
		spent += run.shop_price(TrainRun.PRICE_REROLL + i)
	_expect(rolled == [run.shop_price(2), run.shop_price(3), run.shop_price(4)] and run.coins == 100 - spent and int(run.shop["rerolls"]) == 3,
		"shop: rolls cost %s, coins %d" % [rolled, run.coins])
	_check_saved(run)
	run.coins = 0
	run.shop_reroll()
	_expect(int(run.shop["rerolls"]) == 3, "shop: rolled without coins")
	run.leave_shop()
	run.phase = "doors"
	run.doors = [{"kind": "shop"}]
	run.coins = 100
	run.enter(0)
	_expect(int(run.shop["rerolls"]) == 0 and run.reroll_price() == run.shop_price(TrainRun.PRICE_REROLL),
		"shop: a new shop starts its rolls again")
	var passed: int = run.passed
	run.leave_shop()
	_expect(run.phase == "doors" and run.passed == passed + 1 and run.shop.is_empty() and run.history.back() == "shop",
		"shop: left, phase %s" % run.phase)
	# Not enough coins, or a deck at its minimum: nothing is bought.
	run.phase = "doors"
	run.doors = [{"kind": "shop"}]
	run.enter(0)
	run.coins = 3
	var n: int = run.deck_size()
	run.buy_card(run.shop["cards"][0])
	run.shop_upgrade(_find_card(run, "creature"))
	run.shop_remove(_find_card(run, "creature"))
	_expect(run.coins == 3 and run.deck_size() == n and run.upgraded.is_empty(), "shop: bought with 3 coins")
	run.coins = 100
	while run.deck_size() > run.min_deck():
		var some: String = run.cards.keys()[0]
		run.cards[some] = int(run.cards[some]) - 1
		if int(run.cards[some]) <= 0:
			run.cards.erase(some)
			run.upgraded.erase(some)
	run.shop_remove(run.cards.keys()[0])
	_expect(run.deck_size() == run.min_deck() and run.coins == 100 and run.shop["remove"], "shop: thinned the deck below the minimum")
	# Outside a shop nothing is sold.
	run.phase = "doors"
	run.buy_item("chocolate")
	run.shop_remove(run.cards.keys()[0])
	_expect(run.coins == 100 and not run.items.has("chocolate"), "shop: sold outside a shop")
	# A format 6 save has no coins and no shop.
	run = _rest_run(42)
	var d: Dictionary = run.to_dict()
	d["format"] = 6
	d.erase("coins")
	d.erase("shop")
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var copy := TrainRun.new()
	copy.save_path = SAVE
	_expect(copy.restore() and copy.coins == 0 and copy.shop.is_empty(), "save: a format 6 run does not load")
	run.lose()
	print("shop checked")


# ---------------------------------------------------------------- events

const EFFECTS := ["hp", "coins", "max_hp", "curse", "remove", "item", "item_rare", "card", "stat", "upgrade", "uncurse"]
const PICKS := ["remove", "upgrade", "uncurse"]


## Every event: its data and what its options may do.
func _check_event_data() -> void:
	_expect(TrainEvents.EVENTS.size() >= 5 and TrainEvents.has("magic_man") and TrainEvents.has("mint_butler"), "events: %d of them" % TrainEvents.EVENTS.size())
	for id: String in TrainEvents.EVENTS:
		var ev: Dictionary = TrainEvents.EVENTS[id]
		_expect(String(ev["name"]) != "" and String(ev["text"]) != "" and String(ev["look"]) != "", "event %s: name, text or look" % id)
		_expect(ev["art"] == "" or CardDB.has_hero_card(String(ev["art"])), "event %s: art %s" % [id, ev["art"]])
		_expect(int(ev["from"]) >= TrainRun.EVENT_FROM and ev["needs"] in ["", "curse"], "event %s: from or needs" % id)
		var options: Array = ev["options"]
		_expect(options.size() >= 2 and options.size() <= 3, "event %s: %d options" % [id, options.size()])
		for opt: Dictionary in options:
			_expect(String(opt["text"]) != "" and String(opt["text"]).length() <= 22, "event %s: option text %s" % [id, opt.get("text")])
			var sets: Array = []
			if opt.has("chance"):
				var ch: Dictionary = opt["chance"]
				_expect(int(ch["p"]) > 0 and int(ch["p"]) < 100 and not ch["win"].is_empty() and not ch["lose"].is_empty()
					and String(opt.get("win_result", "")) != "" and String(opt.get("lose_result", "")) != "", "event %s: chance of %s" % [id, opt["text"]])
				sets = [ch["win"], ch["lose"]]
			else:
				_expect(String(opt.get("result", "")) != "" and (not opt.get("cost", {}).is_empty() or not opt.get("gain", {}).is_empty()),
					"event %s: %s has no result, cost or gain" % [id, opt["text"]])
				sets = [opt.get("cost", {}), opt.get("gain", {})]
			var picks := 0
			for fx: Dictionary in sets:
				for key: String in fx:
					_expect(EFFECTS.has(key) and int(fx[key]) > 0, "event %s: effect %s" % [id, key])
					picks += 1 if key in PICKS else 0
			_expect(picks <= 1, "event %s: %s has %d picks" % [id, opt["text"], picks])
			_expect(not String(opt.get("result", "")).contains("(") and not String(opt["text"]).contains("("), "event %s: brackets" % id)
	print("events: %d" % TrainEvents.EVENTS.size())


## A run at the door of an event with what an option may need: coins, HP, a deck.
func _event_run(id: String, seed_value: int, curses := []):
	var run = _rest_run(seed_value)
	run.coins = 100
	run.hp = 20
	run.max_hp = 25
	for c: String in curses:
		run.add_curse(c)
	run.phase = "doors"
	run.current = {}
	run.doors = [{"kind": "event", "event": id}]
	run.enter(0)
	return run


## The numbers an option must change, taken before and compared after.
func _snap(run) -> Dictionary:
	return {"hp": run.hp, "coins": run.coins, "max_hp": run.max_hp, "items": run.items.size(), "curses": run.curses.size(), "deck": run.deck_size()}


## What a set of effects does to the numbers of a snapshot (the ones that can be told ahead).
func _after(snap: Dictionary, fx: Dictionary, cost: bool, run) -> Dictionary:
	var out := snap.duplicate()
	for key: String in fx:
		var n := int(fx[key])
		match key:
			"hp":
				out["hp"] = maxi(out["hp"] - n, 1) if cost else mini(out["hp"] + n, out["max_hp"])
			"coins":
				out["coins"] += -n if cost else n
			"max_hp":
				out["max_hp"] = maxi(out["max_hp"] + (-n if cost else n), 1)
				out["hp"] = clampi(out["hp"] + (0 if cost else n), 1, out["max_hp"])
			"curse":
				out["curses"] += mini(n, TrainItems.CURSES.size() - snap["curses"])
				out["curse_mod"] = true
			"item", "item_rare":
				out["items"] += n
			"card":
				out["deck"] += n
			"remove":
				out["deck"] -= 1
	return out


## Every option of every event taken: the price and the reward come out as written, a
## pick follows when there is one, the result closes the wagon, the save always loads back.
func _check_events() -> void:
	var taken := 0
	for id: String in TrainEvents.EVENTS:
		var options: Array = TrainEvents.options(id)
		for i in options.size():
			for seed_value in (6 if options[i].has("chance") else 1):
				var run = _event_run(id, 50 + seed_value, ["lich_chill"] if TrainEvents.event(id)["needs"] == "curse" or id == "lich" else [])
				_expect(run.phase == "event" and run.event["id"] == id and run.event["stage"] == "options" and run.seen_events.has(id), "event %s: phase %s" % [id, run.phase])
				_check_saved(run)
				var opt: Dictionary = options[i]
				_expect(run.event_block(i) == "", "event %s: option %s is blocked with plenty: %s" % [id, opt["text"], run.event_block(i)])
				var before := _snap(run)
				run.choose_event(i)
				taken += 1
				_check_saved(run)
				var stage := String(run.event["stage"])
				var pick_key := ""
				var wins: Array = [{}]
				if opt.has("chance"):
					wins = [_after(before, opt["chance"]["win"], false, run), _after(before, opt["chance"]["lose"], true, run)]
				else:
					wins = [_after(_after(before, opt.get("cost", {}), true, run), opt.get("gain", {}), false, run)]
				var now := _snap(run)
				now.erase("deck")        # a pick still changes the deck
				var matched := false
				for w: Dictionary in wins:
					var w2: Dictionary = w.duplicate()
					w2.erase("deck")
					if w2.has("curse_mod"):         # a curse may take max HP with it (the rusty chain)
						w2.erase("curse_mod")
						w2.erase("hp")
						w2.erase("max_hp")
						var now2 := now.duplicate()
						now2.erase("hp")
						now2.erase("max_hp")
						matched = matched or w2 == now2
					else:
						matched = matched or w2 == now
				_expect(matched, "event %s option %s: %s but wanted %s" % [id, opt["text"], now, wins])
				_expect(run.event["got"].size() > 0 or stage != "result", "event %s: nothing got" % id)
				if stage == "pick":
					pick_key = String(run.event["pick"])
					_expect(pick_key in ["remove", "upgrade", "curse"], "event %s: pick %s" % [id, pick_key])
					run.event_pick("nonsense")      # a wrong card changes nothing
					_expect(run.event["stage"] == "pick", "event %s: a wrong pick went through" % id)
					match pick_key:
						"remove":
							run.event_pick(run.cards.keys()[0])
						"upgrade":
							var ups: Array = run.cards.keys().filter(func(c): return run.plain_count(c) > 0 and TrainRun.upgradable(c))
							run.event_pick(ups[0])
							_expect(run.upgrade_count(ups[0]) == 1, "event %s: the card is not improved" % id)
						"curse":
							var c: String = run.curses[0]
							run.event_pick(c)
							_expect(not run.curses.has(c), "event %s: the curse is still on" % id)
					_expect(run.event["stage"] == "result", "event %s: stage %s after the pick" % [id, run.event["stage"]])
					_check_saved(run)
				var passed: int = run.passed
				run.finish_event()
				_expect(run.phase == "doors" and run.passed == passed + 1 and run.event.is_empty() and run.history.back() == "event", "event %s: the wagon is not finished" % id)
				run.lose()
	# Leaving gives nothing, and a blocked option does nothing.
	var run = _event_run("mint_butler", 61)
	var snap := _snap(run)
	run.leave_event()
	_expect(run.phase == "doors" and _snap(run) == snap and run.history.back() == "event", "event: leaving changed %s" % [_snap(run)])
	run = _event_run("mint_butler", 62)
	run.hp = 4
	_expect(run.event_block(0) != "" and run.event_block(2) != "" and run.event_block(1) == "", "event: blocks %s %s %s" % [run.event_block(0), run.event_block(1), run.event_block(2)])
	run.choose_event(0)
	_expect(run.event["stage"] == "options" and run.hp == 4, "event: a blocked offer went through")
	run.choose_event(9)
	run.finish_event()
	run.event_pick("the_pig")
	_expect(run.phase == "event" and run.event["stage"] == "options", "event: steps out of order")
	run.coins = 0
	run.hp = 20
	var prismo = _event_run("prismo", 63)
	prismo.coins = 5
	_expect(prismo.event_block(0) != "" and prismo.event_block(1) == "", "event: prismo with 5 coins")
	run.lose()
	prismo.lose()
	# Not enough cards to give away, curses all on, no curses to take off.
	run = _event_run("mint_butler", 64)
	while run.deck_size() > run.min_deck():
		var some: String = run.cards.keys()[0]
		run.cards[some] = int(run.cards[some]) - 1
		if int(run.cards[some]) <= 0:
			run.cards.erase(some)
			run.upgraded.erase(some)
	_expect(run.event_block(0) != "" and run.event_block(1) != "", "event: cards given away from a deck at its minimum")
	run.lose()
	run = _event_run("lich", 65, TrainItems.CURSES.keys())
	_expect(run.event_block(0) != "" and run.event_block(1) != "" and run.event_block(2) == "", "event: a curse given when the hero has them all")
	run.lose()
	# The event door: an event that needs a curse comes only with one, the first wagons have none.
	var seen := {}
	for k in 120:
		var r = _rest_run(200 + k)
		r.wagon = 3 + k % 5
		r.passed = r.wagon
		if k % 2 == 0:
			r.add_curse("black_mark")
		r._make_doors()
		for d: Dictionary in r.doors:
			if d["kind"] == "event":
				seen[d["event"]] = true
				_expect(TrainEvents.event(d["event"])["needs"] != "curse" or not r.curses.is_empty(), "event: %s without a curse" % d["event"])
		var early = _rest_run(300 + k)
		early.wagon = 0
		early._make_doors()
		_expect(not early.doors.any(func(d): return d["kind"] == "event"), "event: in the first wagon")
		r.lose()
		early.lose()
	_expect(seen.size() >= 4, "event: only %s came in 120 wagons" % [seen.keys()])
	# The save in the middle of an event (every stage) and a format 6 save without events.
	run = _event_run("magic_man", 66)
	run.choose_event(1)
	_check_saved(run)
	var copy := TrainRun.new()
	copy.save_path = SAVE
	_expect(copy.restore() and copy.phase == "event" and copy.event == run.event and copy.seen_events == run.seen_events, "event: the save lost the event")
	var d: Dictionary = run.to_dict()
	d["format"] = 6
	for key in ["event", "seen_events", "curses", "coins", "shop"]:
		d.erase(key)
	d["phase"] = "doors"
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	copy = TrainRun.new()
	copy.save_path = SAVE
	_expect(copy.restore() and copy.event.is_empty() and copy.seen_events.is_empty() and copy.curses.is_empty(), "save: a format 6 run does not load")
	d["phase"] = "event"
	f = FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	copy = TrainRun.new()
	copy.save_path = SAVE
	_expect(copy.restore() and copy.phase == "rest", "save: an event that is gone leaves phase %s" % copy.phase)
	run.lose()
	print("events checked: %d options" % taken)


## One random step in an event, with the checks of the stage.
func _event_step(run, agent: RandomAgent) -> void:
	var options: Array = run.event_options()
	match String(run.event["stage"]):
		"options":
			var i: int = agent.rng.randi() % (options.size() + 1)
			if i == options.size():
				run.leave_event()
				return
			var blocked: String = run.event_block(i)
			var before := _snap(run)
			run.choose_event(i)
			if blocked != "":
				_expect(run.event["stage"] == "options" and _snap(run) == before, "event: a blocked option %d went through" % i)
			_expect(run.hp >= 1 and run.coins >= 0 and run.hp <= run.max_hp, "event: hp %d/%d, coins %d" % [run.hp, run.max_hp, run.coins])
		"pick":
			match String(run.event["pick"]):
				"remove":
					var ids: Array = run.cards.keys()
					run.event_pick(ids[agent.rng.randi() % ids.size()], agent.rng.randf() < 0.5)
				"upgrade":
					var ups: Array = run.cards.keys().filter(func(c): return run.plain_count(c) > 0 and TrainRun.upgradable(c))
					_expect(not ups.is_empty(), "event: an improvement with nothing to improve")
					run.event_pick(ups[agent.rng.randi() % ups.size()])
				"curse":
					_expect(not run.curses.is_empty(), "event: a curse to take off with none on")
					run.event_pick(run.curses[agent.rng.randi() % run.curses.size()])
		_:
			run.finish_event()


# ---------------------------------------------------------------- curses

## A dark door: the wagon behind it is hidden, the door shows "?". Its reward is bigger: a dark fight of
## an elite gives DARK_COINS of the coins and one more item to take; a dark fight with no items to take
## gives one more trophy instead. The dark doors come from the run's random numbers (the same train, the
## same doors), and the save keeps them; a save without the field has none.
func _check_dark() -> void:
	var dark_doors := 0
	for seed_value in range(1, 41):
		var run := TrainRun.new()
		run.save_path = SAVE
		run.start("finn", seed_value)
		run.wagon = TrainRun.DARK_FROM - 1
		run._make_doors()
		var first := JSON.stringify(run.doors)
		var again := TrainRun.new()
		again.save_path = SAVE
		again.start("finn", seed_value)
		again.wagon = TrainRun.DARK_FROM - 1
		again._make_doors()
		_expect(JSON.stringify(again.doors) == first, "dark: the doors of seed %d differ" % seed_value)
		for d: Dictionary in run.doors:
			if not d.get("dark", false):
				continue
			dark_doors += 1
			_expect(TrainRun.DARK_KINDS.has(String(d["kind"])) and not d.has("second"), "dark: a %s door hides %s" % [d["kind"], d])
		run.save()
		_check_saved(run)
		run.lose()
	_expect(dark_doors > 0, "dark: no dark doors in 40 trains")
	# A dark elite pays a half more coins and one more item; a plain one the usual.
	for dark in [false, true]:
		var e := TrainRun.new()
		e.save_path = SAVE
		e.start("finn", 96)
		var door := e._fight_door("elite")
		door["dark"] = dark
		e.doors = [door]
		e.enter(0)
		e.fight_won(5)
		var want_coins := roundi(TrainRun.COIN_WIN["elite"] * (TrainRun.DARK_COINS if dark else 1.0))
		_expect(e.coins == want_coins and e.item_offers.size() == int(TrainRun.ITEM_OFFERS["elite"]) + (1 if dark else 0),
			"dark: elite dark %s gives %d coins, items %s" % [dark, e.coins, e.item_offers])
		e.lose()
	# A dark fight: one more item when it offers some, one more trophy when it offers none.
	var empty := 0
	var with_items := 0
	for s in range(40):
		var f := TrainRun.new()
		f.save_path = SAVE
		f.start("finn", 200 + s)
		var fight := f._fight_door("fight")
		fight["dark"] = true
		f.doors = [fight]
		f.enter(0)
		f.fight_won(5)
		if f.item_offers.is_empty():
			empty += 1
			_expect(f.picks_left == int(TrainRun.PICKS.get("fight", 1)) + 1, "dark: no items, %d trophies" % f.picks_left)
		else:
			with_items += 1
			_expect(f.item_offers.size() == 2, "dark: %d items offered after a fight with one" % f.item_offers.size())
		f.lose()
	_expect(empty > 0 and with_items > 0, "dark: %d fights with no items, %d with" % [empty, with_items])
	# A dark chest: one more item in the offer.
	var t := TrainRun.new()
	t.save_path = SAVE
	t.start("finn", 97)
	t.doors = [{"kind": "treasure", "dark": true}]
	t.enter(0)
	_expect(t.phase == "item" and t.item_offers.size() == int(TrainRun.ITEM_OFFERS["treasure"]) + 1, "dark: chest offers %s" % [t.item_offers])
	t.lose()
	# A save from before the field: the door is an ordinary one.
	_expect(not bool(TrainRun.new()._door_ints({"kind": "fight", "enemy": "jake", "hp": 8, "level": "novice", "seed": 1, "stats": {}}).get("dark", false)),
		"dark: an old door is dark")


## The curse sale of a shop: a random curse for the hero and every price of the shelf halved (rounded
## up, at least 1), once a visit; with every curse on there is no sale.
func _check_sale() -> void:
	var run := TrainRun.new()
	run.save_path = SAVE
	run.start("finn", 93)
	run.coins = 100
	run.doors = [{"kind": "shop"}]
	run.enter(0)
	_expect(run.can_sale() and not bool(run.shop["sale"]) and run.shop_price(10) == 10, "sale: not on yet")
	run.shop_sale()
	_expect(run.curses.size() == 1 and bool(run.shop["sale"]), "sale: curses %s" % [run.curses])
	_expect(run.shop_price(10) == 5 and run.shop_price(5) == 3 and run.shop_price(1) == 1 and run.reroll_price() == 1,
		"sale: prices %d %d %d, reroll %d" % [run.shop_price(10), run.shop_price(5), run.shop_price(1), run.reroll_price()])
	_expect(run.coins == 100, "sale: coins %d" % run.coins)
	var id: String = run.shop["cards"][0]
	var price := run.shop_price(TrainRun.card_price(id))
	_expect(price == maxi(ceili(TrainRun.card_price(id) / 2.0), 1), "sale: %s costs %d" % [id, price])
	run.buy_card(id)
	_expect(run.coins == 100 - price and not run.shop["cards"].has(id), "sale: bought %s, coins %d" % [id, run.coins])
	_expect(not run.can_sale(), "sale: twice in one visit")
	run.shop_sale()
	_expect(run.curses.size() == 1, "sale: a second curse in one visit")
	_check_saved(run)
	var copy := TrainRun.new()
	copy.save_path = SAVE
	_expect(copy.restore() and bool(copy.shop["sale"]) and copy.shop_price(10) == 5, "sale: the save lost it")
	# A shop of a format 8 save has no sale.
	_expect(not bool(run._shop_from({"cards": [], "items": [], "upgrade": true, "remove": true}).get("sale", true)), "sale: an old shop has a sale")
	run.lose()
	# Every curse on: nothing to give, the prices stay.
	run = TrainRun.new()
	run.save_path = SAVE
	run.start("finn", 94)
	run.coins = 10
	run.doors = [{"kind": "shop"}]
	run.enter(0)
	for cid: String in TrainItems.CURSES:
		run.curses.append(cid)
	_expect(not run.can_sale(), "sale: offered with every curse on")
	run.shop_sale()
	_expect(not bool(run.shop["sale"]) and run.shop_price(10) == 10 and run.curses.size() == TrainItems.CURSES.size(), "sale: with every curse on")
	run.lose()


## The curses of the Lich: each one at work in a fight, in a shop, in the save.
func _check_curses() -> void:
	var run = _rest_run(71)
	run.hp = run.max_hp
	var base_hp: int = run.max_hp
	# max HP: on, and off again.
	run.add_curse("rusty_chain")
	_expect(run.max_hp == base_hp - 8 and run.hp == base_hp - 8 and run.curses == ["rusty_chain"], "curse: rusty chain %d/%d" % [run.hp, run.max_hp])
	run.add_curse("rusty_chain")
	_expect(run.curses.size() == 1, "curse: the same curse twice")
	run.remove_curse("rusty_chain")
	_expect(run.max_hp == base_hp and run.curses.is_empty(), "curse: max HP %d after it was taken off" % run.max_hp)
	# Stats and rules of a fight.
	run.add_curse("lich_chill")
	run.add_curse("black_mark")
	run.add_curse("ghost_tax")
	var fs: Dictionary = run.fight_stats()
	_expect(fs.get("hand", 0) == -1 + int(run.stats.get("hand", 0)) and fs.get("bleed", 0) == 1 and fs.get("spell_tax", 0) == 1, "curse: fight stats %s" % [fs])
	var g := Game.new()
	g.chooser = RandomAgent.new(3)
	g.setup([run.player_pick(), "jake"], 0, 5)
	run.phase = "fight"
	run.current = {"kind": "fight", "enemy": "jake", "hp": 10, "level": "novice", "seed": 5, "stats": {}}
	run.prepare_fight(g)
	_expect(g.players[0].hand.size() == Game.START_HAND - 1 and g.hand_size(0) == Game.START_HAND - 1, "curse: hand of %d" % g.players[0].hand.size())
	var spell = g._make_card(_find_card(run, "spell", 1) if _find_card(run, "spell", 1) != "" else "the_pig", 0)
	var plain := Game.new()
	plain.setup([run.player_pick(), "jake"], 0, 5)
	var twin = plain._make_card(spell.id, 0)
	_expect(spell.kind() != "spell" or g.cost_of(0, spell) == plain.cost_of(0, twin) + 1, "curse: spell tax %d against %d" % [g.cost_of(0, spell), plain.cost_of(0, twin)])
	await g.start_game()
	if g.phase == "handoff":
		await g.cmd_start_turn()
	run.lose()
	# Enemies: HP and crit, the second enemy of a double wagon too.
	run = _rest_run(72)
	run.add_curse("bone_collar")
	run.add_curse("dead_gaze")
	run.phase = "fight"
	run.current = {"kind": "double", "enemy": "jake", "hp": 10, "level": "novice", "seed": 5, "stats": {"crit": 20},
		"second": {"enemy": "marceline", "hp": 12, "level": "novice", "stats": {}}}
	g = Game.new()
	g.setup([run.player_pick(), "jake"], 0, 5)
	run.prepare_fight(g)
	_expect(g.players[1].hp == 12 and g.players[1].max_hp == 12 and g.stat(1, "crit") == 35 and g.stat(0, "crit") == run.stat("crit"), "curse: enemy %d hp, crit %d" % [g.players[1].hp, g.stat(1, "crit")])
	_expect(int(g.train.follow["hp"]) == 14 and int(g.train.follow["stats"].get("crit", 0)) == 15, "curse: the second enemy %s" % [g.train.follow])
	run.lose()
	# Junk: a card in the deck the hero cannot play.
	run = _rest_run(73)
	var deck_before: int = run.deck_size()
	run.add_curse("dead_weight")
	var junk: String = run.junk_card()
	_expect(TrainRun.JUNK.has(junk) and run.lands.count(CardDB.get_def(junk)["land"]) < int(CardDB.get_def(junk)["cost"]), "curse: junk %s with lands %s" % [junk, run.lands])
	run.phase = "fight"
	run.current = {"kind": "fight", "enemy": "jake", "hp": 10, "level": "novice", "seed": 5, "stats": {}}
	g = Game.new()
	g.setup([run.player_pick(), "jake"], 0, 5)
	var cards_before: int = g.all_cards(0).size()
	run.prepare_fight(g)
	var junk_cards: Array = g.all_cards(0).filter(func(c): return c.id == junk)
	_expect(g.all_cards(0).size() == cards_before + 1 and run.deck_size() == deck_before and g.players[0].deck.has(junk_cards.back()), "curse: junk cards %d, deck %d" % [junk_cards.size(), run.deck_size()])
	_expect(not g.clone().card(junk_cards.back().uid) == null, "curse: the copy of the game lost the junk card")
	# After a won fight: the HP lost.
	run = _rest_run(74)
	run.add_curse("grave_dust")
	run.phase = "fight"
	run.current = {"kind": "fight", "enemy": "jake", "hp": 8, "level": "novice", "seed": 5, "stats": {}}
	run.fight_won(10)
	_expect(run.hp == 10 + TrainRun.FIGHT_HEAL - 3, "curse: grave dust left %d hp" % run.hp)
	run.hp = 2
	run.phase = "fight"
	run.fight_won(1)
	_expect(run.hp >= 1, "curse: grave dust killed")
	run.lose()
	# The shop takes one off, once, for coins.
	run = _rest_run(75)
	run.add_curse("lich_chill")
	run.add_curse("rusty_chain")
	run.coins = 40
	run.phase = "doors"
	run.doors = [{"kind": "shop"}]
	run.enter(0)
	var m: int = run.max_hp
	run.shop_uncurse("rusty_chain")
	_expect(run.coins == 40 - TrainRun.PRICE_UNCURSE and run.curses == ["lich_chill"] and run.max_hp == m + 8, "curse: shop uncurse, coins %d, curses %s" % [run.coins, run.curses])
	run.shop_uncurse("lich_chill")
	_expect(run.curses == ["lich_chill"], "curse: two curses taken off in one visit")
	_check_saved(run)
	var copy := TrainRun.new()
	copy.save_path = SAVE
	_expect(copy.restore() and copy.curses == ["lich_chill"], "curse: the save lost them")
	run.lose()
	run = _rest_run(76)
	run.add_curse("lich_chill")
	run.coins = 5
	run.phase = "doors"
	run.doors = [{"kind": "shop"}]
	run.enter(0)
	run.shop_uncurse("lich_chill")
	_expect(run.curses == ["lich_chill"] and run.coins == 5, "curse: taken off with 5 coins")
	run.lose()
	# Fights of random players with every curse on: each must end.
	var agent := RandomAgent.new(9)
	var fights := 0
	for k in 6:
		run = _rest_run(80 + k)
		for id: String in TrainItems.CURSES:
			run.curses.append(id)
		run.phase = "fight"
		run.current = {"kind": "fight" if k % 2 == 0 else "double", "enemy": "jake", "hp": 8, "level": "novice", "seed": 20 + k, "stats": {}}
		if k % 2 == 1:
			run.current["second"] = {"enemy": "lich", "hp": 8, "level": "novice", "stats": {}}
		var res: Array = await _fight(run, agent, 80 + k)
		fights += 1
		_expect(res[1] > 0, "curse fight %d" % k)
		run.lose()
	print("curses checked, %d fights with all of them" % fights)


## The cards of a hero deck.
func _deck_cards(deck: String) -> int:
	var n := 0
	for id: String in CardDB.hero(deck)["deck"]:
		n += int(CardDB.hero(deck)["deck"][id])
	return n


## A double wagon in the engine: the second enemy walks in, the player keeps everything.
func _check_double() -> void:
	# The first enemy falls in the player's turn.
	var g := Game.new()
	g.chooser = RandomAgent.new(5)
	g.setup(["finn", "jake"], 0, 77)
	g.train.set_stats(0, {"crit": 5})
	g.train.set_follow("marceline", 9, {"crit": 20, "hand": 1})
	await g.start_game()
	if g.phase == "handoff":
		await g.cmd_start_turn()
	var pig = g._make_card("the_pig", 0)
	await g._put_creature(0, pig, 2)
	var theirs = g._make_card("the_pig", 1)
	await g._put_creature(1, theirs, 1)
	var old_uids: Array = g.all_cards(1).map(func(c): return c.uid)
	var mine_hand: Array = g.players[0].hand.map(func(c): return c.uid)
	var mine_deck: Array = g.players[0].deck.map(func(c): return c.uid)
	var my_hp: int = g.players[0].hp
	await g.damage_player(1, 100)
	var e = g.players[1]
	_expect(g.phase != "over" and g.winner == -1, "double: the game ended with the first enemy (%s)" % g.phase)
	_expect(e.hero == "marceline" and e.hp == 9 and e.max_hp == 9 and g.train.follow.is_empty(), "double: the second is %s with %d hp" % [e.hero, e.hp])
	_expect(e.hand.size() == Game.START_HAND + 1 and g.stat(1, "crit") == 20, "double: hand %d, crit %d" % [e.hand.size(), g.stat(1, "crit")])
	_expect(e.deck.size() == _deck_cards("marceline") - Game.START_HAND - 1, "double: the second's deck has %d cards" % e.deck.size())
	_expect(e.creatures.all(func(c): return c == null) and e.discard.is_empty(), "double: the second's field is not empty")
	_expect(g.players[0].hp == my_hp and g.players[0].creatures[2] == pig and g.players[0].hand.map(func(c): return c.uid) == mine_hand
		and g.players[0].deck.map(func(c): return c.uid) == mine_deck, "double: the player's side changed")
	_expect(old_uids.all(func(u): return g.card(u) == null) and g.all_cards(1).size() == _deck_cards("marceline"),
		"double: cards of the first enemy are still in the game")
	_expect(g.clone().state_hash() == g.state_hash(), "double: the copy of the game hashes differently")
	await g.damage_player(1, 100)
	_expect(g.phase == "over" and g.winner == 0, "double: beaten twice, phase %s winner %d" % [g.phase, g.winner])
	# The player falls first, or both at once with a second enemy to come: the player loses.
	for both in [false, true]:
		g = Game.new()
		g.chooser = RandomAgent.new(5)
		g.setup(["finn", "jake"], 0, 77)
		g.train.set_follow("marceline", 9, {})
		await g.start_game()
		if g.phase == "handoff":
			await g.cmd_start_turn()
		g.players[0].hp = 0
		g.players[1].hp = 0 if both else 5
		await g._check_win()
		_expect(g.phase == "over" and g.winner == 1, "double: the player lost (both %s) but %s, winner %d" % [both, g.phase, g.winner])
	# Cards that changed sides go home or vanish with the enemy.
	g = Game.new()
	g.chooser = RandomAgent.new(5)
	g.setup(["finn", "jake"], 0, 77)
	g.train.set_follow("marceline", 9, {})
	await g.start_game()
	if g.phase == "handoff":
		await g.cmd_start_turn()
	var held = g._make_card("the_pig", 0)
	await g._put_creature(1, held, 3)
	var taken = g._make_card("the_pig", 1)
	await g._put_creature(0, taken, 0)
	var taken_uid: int = taken.uid
	await g.damage_player(1, 100)
	_expect(g.players[0].discard.has(held) and g.players[1].creatures[3] == null, "double: the player's card the enemy held did not go home")
	_expect(g.players[0].creatures[0] == null and g.card(taken_uid) == null, "double: the enemy's card the player held stayed")
	_expect(g.clone().state_hash() == g.state_hash(), "double: the copy hashes differently after the swap of held cards")
	# The enemy falls in its own turn (Горящий вагон) and the fight goes on to the end.
	g = Game.new()
	var agent := RandomAgent.new(9)
	g.chooser = agent
	g.setup(["finn", "jake"], 1, 78)
	g.train.set_wagon("burning")
	g.train.set_follow("marceline", 9, {})
	g.players[1].hp = 1
	await g.start_game()
	_expect(g.phase != "over" and g.players[1].hero == "marceline" and g.train.follow.is_empty(),
		"double: the enemy that burned down in its turn: %s, %s" % [g.phase, g.players[1].hero])
	var steps := 0
	while g.phase != "over" and steps < 3000:
		if g.phase == "handoff":
			await g.cmd_start_turn()
			continue
		var cmds: Array = g.legal_commands(g.turn_player)
		if cmds.is_empty():
			break
		await g.run_command(g.turn_player, agent.pick_command(cmds))
		steps += 1
	_expect(g.phase == "over", "double: the fight after a swap in the enemy's turn did not finish")
	# The run sets it up: the second enemy gets the wagon's rule, too.
	for rule: String in ["", "sugar", "fair", "fireworks"]:
		var run = _rest_run(31)
		run.phase = "fight"
		run.current = {"kind": "double", "enemy": "jake", "hp": 10, "level": "novice", "seed": 5, "stats": {},
			"second": {"enemy": "marceline", "hp": 12, "level": "novice", "stats": {}}}
		if rule != "":
			run.current["wagon"] = rule
		g = Game.new()
		g.chooser = RandomAgent.new(3)
		g.setup([run.player_pick(), "jake"], 0, 5)
		run.prepare_fight(g)
		var f: Dictionary = g.train.follow
		_expect(f.get("pick", "") == "marceline" and int(f.get("hp", 0)) == 12 + (3 if rule == "sugar" else 0), "double %s: follow %s" % [rule, f])
		if rule == "fair":
			_expect(int(f["stats"].get("hand", 0)) == 1, "double fair: second's stats %s" % [f["stats"]])
		if rule == "fireworks":
			_expect(int(f["stats"].get("crit", 0)) == 20, "double fireworks: second's stats %s" % [f["stats"]])
		_expect(g.train.wagon == rule, "double %s: the wagon is %s" % [rule, g.train.wagon])
		run.lose()
	# Random fights: every one ends, and a win means both enemies fell.
	var swaps := 0
	var n := 0
	var decks: Array = CardDB.hero_ids()
	for k in 24:
		var a2 := RandomAgent.new(k * 13 + 1)
		var first_deck: String = decks[(k * 3) % decks.size()]
		var second_deck: String = decks[(k * 5 + 2) % decks.size()]
		if second_deck == first_deck:
			second_deck = decks[(k * 5 + 3) % decks.size()]
		g = Game.new()
		g.chooser = a2
		g.setup([decks[(k * 7 + 4) % decks.size()], first_deck], k % 2, 3000 + k)
		g.train.set_stats(0, {"crit": 5})
		g.train.set_stats(1, {})
		g.train.set_wagon(["", "burning", "jam", "crypt", "lich_dice", "concert"][k % 6])
		g.train.set_follow(second_deck, 6 + k % 5, {"thorns": 1} if k % 3 == 0 else {})
		await g.start_game()
		steps = 0
		var seen_second := false
		while g.phase != "over" and steps < 4000:
			if g.phase == "handoff":
				await g.cmd_start_turn()
				continue
			var cmds2: Array = g.legal_commands(g.turn_player)
			if cmds2.is_empty():
				break
			await g.run_command(g.turn_player, a2.pick_command(cmds2))
			if g.players[1].hero == second_deck and not seen_second:
				seen_second = true
				swaps += 1
				_expect(g.clone().state_hash() == g.state_hash(), "double fight %d: the copy hashes differently" % k)
			steps += 1
		n += 1
		_expect(g.phase == "over", "double fight %d did not finish (turn %d)" % [k, g.turn_number])
		_expect(g.winner != 0 or (g.train.follow.is_empty() and g.players[1].hero == second_deck), "double fight %d won with the second enemy still to come" % k)
	print("double fights %d, the second enemy came in %d" % [n, swaps])
