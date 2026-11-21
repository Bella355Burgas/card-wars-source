extends SceneTree
## «Бесконечный поезд»: balance simulations, no screens.
##   godot --headless --path . -s tools/train_balance.gd -- runs=200 seed=1 diff=0 policy=greedy trains=4 level=medium out=D:/scratch/bal tag=a shard=0 shards=1 [immortal=1]
## Plays whole runs: the doors, the rewards, the shop, the events and the perks are chosen by a simple
## policy, every fight is a real game of two AI players (the player's AI of `level`, the enemy's AI of the
## door's level), like tests/run_test.gd balance.
##   runs      how many runs in all (run r has the seed `seed` + r and the ready deck r % decks)
##   policy    random | greedy (see the _door/_shop/_event/_rest functions)
##   trains    a run stops when this many trains are passed (the cap is trains * TRAIN_LEN wagons)
##   level     AI level of the player: novice | easy | medium | hard | impossible
##   immortal  1: a lost fight is counted but the run goes on (the hero is put back to half of the HP):
##             for the numbers of the late trains, which a mortal run never reaches
##   mode=bench  not whole runs: one thing at a time on a standard hero (see _bench): items=all|id,id  rules=all|id,id  perks=1
##               n=fights per thing, pass=the wagon of the run the hero stands at (12 = the third wagon of the second train)
##   shard/shards  this process plays the runs r with r % shards == shard (many processes, one folder)
## Writes out/tag_shard.jsonl: one line per run (see _play_run); tools/train_balance_report.py reads them.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const TrainRun = preload("res://scripts/train/train_run.gd")
const TrainItems = preload("res://scripts/train/train_items.gd")
const TrainEvents = preload("res://scripts/train/train_events.gd")
const TrainWagons = preload("res://scripts/train/train_wagons.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const STEP_CAP := 2500
const PERK_ORDER := {"max_hp": 5.0, "crit": 4.0, "crit_dmg": 3.5, "lifesteal": 3.0, "armor": 3.0, "regen": 3.0, "draw": 2.0,
	"hand": 2.0, "dodge": 2.0, "luck": 1.5, "thorns": 1.0}

var rec: Dictionary = {}
var rng := RandomNumberGenerator.new()
var pol := "greedy"


## Choice requests go to the AI of the seat that answers.
class SeatChooser:
	var game
	var agents := []
	func choose(req: Dictionary):
		return agents[int(req.get("player", game.turn_player))].pick_choice(game, req)


## The animator of the game: it only counts what happens to the heroes.
class Sink:
	var dmg: Array = [{}, {}]       # side -> kind (card | fatigue | other) -> HP lost
	var hits: Array = [[], []]      # side -> amounts of the creature hits on its hero
	var last: Array = ["", ""]      # the kind of the last damage to each side
	var tired: Array = [false, false]
	var draw_fails: Array = [0, 0]
	var game
	var turn_dmg: Array = [{}, {}]  # side -> turn number -> HP lost in that turn
	var peak: Array = [0, 0]        # side -> the most HP lost in one turn
	func play(ev: Dictionary) -> void:
		match String(ev.get("type", "")):
			"hero_text":
				if String(ev.get("text", "")) == "Усталость":
					tired[int(ev["p"])] = true
			"player_damage":
				var p := int(ev["p"])
				var amount := int(ev["amount"])
				var kind := "card"
				if int(ev.get("uid", -1)) < 0:
					kind = "fatigue" if tired[p] else "other"
				tired[p] = false
				if game != null:
					var t := int(game.turn_number)
					turn_dmg[p][t] = int(turn_dmg[p].get(t, 0)) + amount
					peak[p] = maxi(int(peak[p]), int(turn_dmg[p][t]))
				dmg[p][kind] = int(dmg[p].get(kind, 0)) + amount
				last[p] = kind
				if kind == "card":
					hits[p].append(amount)
			"draw_fail":
				draw_fails[int(ev["p"])] += 1


func _initialize() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() == 2:
			a[kv[0]] = kv[1]
	var runs := int(a.get("runs", "20"))
	var base_seed := int(a.get("seed", "1"))
	var diff := int(a.get("diff", "0"))
	pol = String(a.get("policy", "greedy"))
	var trains := int(a.get("trains", "4"))
	var level := String(a.get("level", "medium"))
	var immortal := String(a.get("immortal", "0")) == "1"
	var shard := int(a.get("shard", "0"))
	var shards := maxi(int(a.get("shards", "1")), 1)
	var out_dir := String(a.get("out", "user://balance"))
	var tag := String(a.get("tag", "run"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var f := FileAccess.open("%s/%s_%d.jsonl" % [out_dir, tag, shard], FileAccess.WRITE)
	if f == null:
		print("cannot write to ", out_dir)
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var done := 0
	if String(a.get("mode", "")) == "bench":
		await _bench(f, a, shard, shards)
		f.close()
		print("shard %d: bench, %.1f s" % [shard, (Time.get_ticks_msec() - t0) / 1000.0])
		quit()
		return
	for r in range(shard, runs, shards):
		var res: Dictionary = await _play_run(base_seed + r, diff, level, trains, immortal, "")
		res["policy"] = pol
		res["tag"] = tag
		f.store_line(JSON.stringify(res))
		f.flush()
		done += 1
	f.close()
	print("shard %d: %d runs, %.1f s" % [shard, done, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()


## One whole run. The line it gives: {seed, deck, diff, level, immortal, passed, train, wins, died: {...} | null,
## fights: [...], snaps: [one per door chosen], ev: [rests, events, shops, skips, perks, item picks], eco: [[passed, what, coins]],
## items, curses, stats, ...}.
func _play_run(seed_value: int, diff: int, level: String, trains: int, immortal: bool, save: String) -> Dictionary:
	rng.seed = seed_value * 7 + 3
	var decks: Array = CardDB.hero_ids()
	var run := TrainRun.new()
	run.save_path = save
	run.start(String(decks[seed_value % decks.size()]), seed_value, "", diff)
	rec = {"seed": seed_value, "deck": run.deck_id, "diff": diff, "level": level, "immortal": immortal,
		"fights": [], "snaps": [], "ev": [], "eco": [], "died": null}
	var cap: int = trains * TrainRun.TRAIN_LEN
	var guard := 0
	while run.phase != "over" and run.passed < cap and guard < 6000:
		guard += 1
		match run.phase:
			"doors":
				var i := _door(run)
				rec["snaps"].append({"p": run.passed, "tr": run.train, "w": run.wagon + 1, "hp": run.hp, "mhp": run.max_hp, "coins": run.coins,
					"deck": run.deck_size(), "kind": String(run.doors[i]["kind"]), "dark": bool(run.doors[i].get("dark", false)),
					"n_doors": run.doors.size(), "kinds": run.doors.map(func(d): return String(d["kind"])), "items": run.items.size(), "curses": run.curses.size(), "lv": run.level})
				run.enter(i)
			"fight":
				var coins0: int = run.coins
				var fr: Dictionary = await _fight(run, level)
				var won: bool = fr["won"]
				if not won and not immortal:
					rec["died"] = {"p": run.passed, "tr": run.train, "w": run.wagon + 1, "kind": fr["kind"], "enemy": fr["enemy"], "rule": fr["rule"],
						"cause": fr["cause"], "turns": fr["turns"]}
					fr["hp_after"] = 0
					rec["fights"].append(fr)
					run.lose(true)
					break
				if not won:
					fr["forced"] = true
				run.fight_won(int(fr["hp_left"]) if won else maxi(run.max_hp / 2, 1), bool(fr["revived"]))
				fr["hp_after"] = run.hp
				fr["mhp_after"] = run.max_hp
				fr["coins_gain"] = run.coins - coins0
				_eco(run, "fight", run.coins - coins0)
				rec["fights"].append(fr)
			"level":
				var key := _perk(run)
				rec["ev"].append({"t": "perk", "p": run.passed, "key": key, "offered": run.perks.duplicate()})
				run.pick_perk(key)
			"item":
				_item(run)
			"reward":
				_reward(run)
			"rest":
				_rest(run)
			"shop":
				_shop(run)
			"event":
				_event(run)
			_:
				break
	rec["passed"] = run.passed
	rec["train"] = run.train
	rec["wins"] = run.wins
	rec["items"] = run.items.duplicate()
	rec["curses"] = run.curses.duplicate()
	rec["stats"] = run.fight_stats()
	rec["deck_size"] = run.deck_size()
	rec["max_hp"] = run.max_hp
	rec["level_end"] = run.level
	rec["coins_end"] = run.coins
	rec["guard"] = guard
	if run.phase != "over":
		run.lose()
	return rec


# ---------------------------------------------------------------- fights

## One fight with AI players on both sides, like the board plays them (the same as run_test._ai_fight).
## Returns what happened: the numbers the report is made of.
func _fight(run, level: String) -> Dictionary:
	var door: Dictionary = run.current
	var picks := [run.player_pick(), String(door["enemy"])]
	var agents := [AILevels.agent(level, picks[0]), AILevels.agent(String(door["level"]), picks[1])]
	var game := Game.new()
	var sink := Sink.new()
	game.animator = sink
	sink.game = game
	game.heal_log_on = true
	var chooser := SeatChooser.new()
	chooser.game = game
	chooser.agents = agents
	game.chooser = chooser
	var first := int(door["seed"]) % 2
	game.setup(picks, first, int(door["seed"]))
	var hp0: int = run.hp
	run.prepare_fight(game)
	var ehp := int(game.players[1].hp)
	var edeck := int(game.players[1].deck.size())
	var pdeck := int(game.players[0].deck.size())
	for p in 2:
		if agents[p].mulligan(game, p):
			await game.cmd_mulligan(p)
	var second_agent = null
	await game.start_game()
	var steps := 0
	while game.phase != "over" and steps < STEP_CAP:
		if game.phase == "handoff":
			await game.cmd_start_turn()
			continue
		var p: int = game.turn_player
		var cmd: Dictionary = agents[p].pick_command(game, p)
		var before := game.state_hash()
		await game.run_command(p, cmd)
		if door.has("second") and game.train.follow.is_empty() and agents[1] != second_agent:
			second_agent = AILevels.agent(String(door["second"]["level"]), String(door["second"]["enemy"]))
			agents[1] = second_agent
			chooser.agents = agents
		if game.state_hash() == before and game.turn_player == p and (game.phase == "main" or game.phase == "attack"):
			agents[p].ban_command(before, cmd)
		steps += 1
	var won: bool = game.phase == "over" and game.winner == 0
	var heals := [{}, {}]
	for h: Array in game.heal_log:
		var side := int(h[0])
		heals[side][String(h[2])] = int(heals[side].get(String(h[2]), 0)) + int(h[1])
	var cause := "won"
	if not won:
		cause = "stuck" if game.phase != "over" else String(sink.last[0])
	var out := {"kind": String(door["kind"]), "enemy": String(door["enemy"]), "rule": String(door.get("wagon", "")), "dark": bool(door.get("dark", false)),
		"lv": String(door["level"]), "p": run.passed, "tr": run.train, "w": run.wagon + 1, "double": door.has("second"),
		"ehp": ehp, "estats": door.get("stats", {}), "hp0": hp0, "mhp": run.max_hp, "hp_left": int(game.players[0].hp), "won": won, "revived": bool(game.players[0].item_state.get("revive", false)),
		"first": first, "turns": game.turn_number, "steps": steps, "cause": cause,
		"dmg": sink.dmg, "last": sink.last, "peak": sink.peak, "hits": [_hit_stats(sink.hits[0]), _hit_stats(sink.hits[1])], "heals": heals, "draw_fails": sink.draw_fails,
		"edeck": edeck, "pdeck": pdeck, "deck_end": [game.players[0].deck.size(), game.players[1].deck.size()],
		"items": run.items.duplicate(), "curses": run.curses.duplicate(), "sets": TrainItems.SETS.keys().filter(func(s): return run.set_done(s)),
		"perks": run.stats.duplicate(), "lvl": run.level, "coins": run.coins, "deck": run.deck_size(), "fstats": run.fight_stats()}
	return out


func _hit_stats(a: Array) -> Array:
	var best := 0
	var total := 0
	for x in a:
		best = maxi(best, int(x))
		total += int(x)
	return [a.size(), total, best]


func _eco(run, what: String, amount: int) -> void:
	if amount != 0:
		rec["eco"].append([run.passed, what, amount])


# ---------------------------------------------------------------- policies

func _hurt(run) -> float:
	return 1.0 - float(run.hp) / maxf(run.max_hp, 1.0)


## The door: random, or the way a careful player picks (a rest when hurt, an elite only when healthy, a chest gladly,
## the shop with coins; a dark door is a gamble at the wagon's kind, the real kind is not looked at).
func _door(run) -> int:
	if pol == "random":
		return rng.randi() % run.doors.size()
	var best := 0
	var best_score := -INF
	var f := 1.0 - _hurt(run)
	for i in run.doors.size():
		var score := rng.randf()
		var d: Dictionary = run.doors[i]
		if bool(d.get("dark", false)):
			score += 2.5 if f > 0.6 else -2.0
		else:
			match String(d["kind"]):
				"rest":
					score += 10.0 if f < 0.55 else 1.5
				"treasure":
					score += 6.0
				"shop":
					score += 4.0 if run.coins >= 20 else 0.5
				"event":
					score += 3.0 if f > 0.6 else -3.0
				"elite":
					score += 5.0 if f > 0.7 else -5.0
				"double":
					score += 4.0 if f > 0.65 else -4.0
				"fight":
					score += 3.0
		if score > best_score:
			best_score = score
			best = i
	return best


func _perk(run) -> String:
	if pol == "random":
		return String(run.perks[rng.randi() % run.perks.size()])
	var best := String(run.perks[0])
	var best_score := -INF
	for key: String in run.perks:
		var s: float = float(PERK_ORDER.get(key, 1.0)) + rng.randf() * 0.5
		if s > best_score:
			best_score = s
			best = key
	return best


func _item_score(run, id: String) -> float:
	var s: float = {"common": 1.0, "rare": 2.0, "legend": 3.0}[TrainItems.item(id)["rarity"]]
	for set_id: String in TrainItems.SETS:
		if TrainItems.SETS[set_id]["items"].has(id) and run.set_count(set_id) >= 1:
			s += 1.5
	return s + rng.randf() * 0.4


func _item(run) -> void:
	var offered: Array = run.item_offers.duplicate()
	var pick := String(offered[rng.randi() % offered.size()])
	if pol != "random":
		var best := -INF
		for id: String in offered:
			var s := _item_score(run, id)
			if s > best:
				best = s
				pick = id
	rec["ev"].append({"t": "item", "p": run.passed, "kind": String(run.current.get("kind", "")), "offered": offered, "pick": pick})
	run.take_item(pick)


func _card_score(id: String) -> float:
	var d := CardDB.get_def(id)
	if d["kind"] == "creature":
		return 1.0 + float(d.get("atk", 0)) + float(d.get("def", 0)) * 0.5 - float(d["cost"]) * 0.4 + rng.randf() * 0.5
	return 0.8 + rng.randf() * 0.6


func _best_card(ids: Array) -> String:
	var best := String(ids[0])
	var best_score := -INF
	for id: String in ids:
		var s := _card_score(id)
		if s > best_score:
			best_score = s
			best = id
	return best


func _reward(run) -> void:
	if run.offers.is_empty():
		run.skip()
		return
	if pol == "random":
		run.take(String(run.offers[rng.randi() % run.offers.size()]))
	else:
		run.take(_best_card(run.offers))


func _upgradable(run) -> Array:
	return run.cards.keys().filter(func(id): return run.can_upgrade(id))


func _best_upgrade(run) -> String:
	var ups := _upgradable(run)
	var best := String(ups[0])
	var best_score := -INF
	for id: String in ups:
		var s := _card_score(id) + (2.0 if CardDB.get_def(id)["kind"] == "creature" else 0.0)
		if s > best_score:
			best_score = s
			best = id
	return best


func _rest(run) -> void:
	var hp0: int = run.hp
	var choice := "heal"
	if pol == "random":
		var opts := ["heal", "heal"]
		if not _upgradable(run).is_empty():
			opts.append("upgrade")
		if run.can_remove():
			opts.append("remove")
		opts.append("land")
		choice = String(opts[rng.randi() % opts.size()])
	elif _hurt(run) < 0.4 and not _upgradable(run).is_empty():
		choice = "upgrade"
	match choice:
		"upgrade":
			run.upgrade_card(_best_upgrade(run))
		"remove":
			run.remove_card(String(run.cards.keys()[rng.randi() % run.cards.size()]))
		"land":
			var types: Array = CardDB.land_types()
			run.change_land(rng.randi() % run.lands.size(), String(types[rng.randi() % types.size()]))
			if run.phase == "rest":
				run.rest_heal()
		_:
			run.rest_heal()
	rec["ev"].append({"t": "rest", "p": run.passed - 1, "choice": choice, "hp0": hp0, "mhp": run.max_hp, "heal": run.rest_amount()})


func _shop(run) -> void:
	var bought: Array = []
	if pol == "random":
		for _i in 8:
			var opts: Array = []
			for id: String in run.shop["items"]:
				if run.can_pay(run.shop_price(TrainRun.item_price(id))):
					opts.append(["item", id])
			for id: String in run.shop["cards"]:
				if run.can_pay(run.shop_price(TrainRun.card_price(id))):
					opts.append(["card", id])
			if run.shop["upgrade"] and run.can_pay(run.shop_price(TrainRun.PRICE_UPGRADE)) and not _upgradable(run).is_empty():
				opts.append(["upgrade", ""])
			if run.shop["uncurse"] and not run.curses.is_empty() and run.can_pay(run.shop_price(TrainRun.PRICE_UNCURSE)):
				opts.append(["uncurse", ""])
			if opts.is_empty() or rng.randf() < 0.25:
				break
			var o: Array = opts[rng.randi() % opts.size()]
			bought.append(_buy(run, String(o[0]), String(o[1])))
	else:
		for id: String in run.curses.duplicate():
			if run.shop["uncurse"] and run.can_pay(run.shop_price(TrainRun.PRICE_UNCURSE)):
				bought.append(_buy(run, "uncurse", id))
		var items: Array = run.shop["items"].duplicate()
		items.sort_custom(func(x, y): return TrainRun.item_price(x) > TrainRun.item_price(y))
		for id: String in items:
			if run.can_pay(run.shop_price(TrainRun.item_price(id))):
				bought.append(_buy(run, "item", id))
		if run.shop["upgrade"] and run.can_pay(run.shop_price(TrainRun.PRICE_UPGRADE)) and not _upgradable(run).is_empty():
			bought.append(_buy(run, "upgrade", _best_upgrade(run)))
		var cards: Array = run.shop["cards"].duplicate()
		cards.sort_custom(func(x, y): return _card_score(x) > _card_score(y))
		for id: String in cards:
			if run.can_pay(run.shop_price(TrainRun.card_price(id))):
				bought.append(_buy(run, "card", id))
	rec["ev"].append({"t": "shop", "p": run.passed, "bought": bought, "coins_left": run.coins})
	run.leave_shop()


func _buy(run, what: String, id: String) -> String:
	var c0: int = run.coins
	match what:
		"item":
			run.buy_item(id)
		"card":
			run.buy_card(id)
		"upgrade":
			run.shop_upgrade(id)
		"uncurse":
			run.shop_uncurse(id)
	_eco(run, "shop_" + what, run.coins - c0)
	return "%s:%s" % [what, id]


## Value of the effects of an event option as the greedy player sees it.
func _fx_score(run, fx: Dictionary, cost: bool) -> float:
	var s := 0.0
	var need := _hurt(run)
	for key: String in fx:
		var n := float(fx[key])
		var v := 0.0
		match key:
			"hp":
				v = n * (0.5 + need * 1.5) if not cost else n * (0.5 + (1.0 - need) * 0.0 + need * 2.0)
			"coins":
				v = n * 0.18
			"max_hp":
				v = n * 0.8
			"curse":
				v = 5.0 * n
			"item":
				v = 4.0 * n
			"item_rare":
				v = 6.0 * n
			"stat":
				v = 4.0 * n
			"card":
				v = 1.5 * n
			"upgrade":
				v = 3.0 * n
			"remove":
				v = (-2.5 if cost else 2.0) * n
			"uncurse":
				v = 4.0 * n if not run.curses.is_empty() else 0.0
		s += -v if cost else v
	return s


func _event(run) -> void:
	var snap := {"hp": run.hp, "mhp": run.max_hp, "coins": run.coins, "curses": run.curses.size(), "items": run.items.size()}
	match String(run.event["stage"]):
		"options":
			var best := -1
			var best_score := 0.0
			var ok: Array = []
			for i in run.event_options().size():
				if run.event_block(i) != "":
					continue
				ok.append(i)
				var opt: Dictionary = run.event_options()[i]
				var s := 0.0
				if opt.has("chance"):
					var ch: Dictionary = opt["chance"]
					s = (float(ch["p"]) * _fx_score(run, ch["win"], false) + (100.0 - float(ch["p"])) * _fx_score(run, ch["lose"], false)) / 100.0
					s += rng.randf() * 0.1
				else:
					s = _fx_score(run, opt.get("cost", {}), true) + _fx_score(run, opt.get("gain", {}), false)
				if s > best_score:
					best_score = s
					best = i
			if pol == "random":
				best = -1 if ok.is_empty() or rng.randf() < 0.2 else int(ok[rng.randi() % ok.size()])
			if best < 0:
				rec["ev"].append({"t": "event", "p": run.passed, "id": String(run.event["id"]), "opt": -1})
				run.leave_event()
				return
			rec["ev"].append(snap.merged({"t": "event", "p": run.passed, "id": String(run.event["id"]), "opt": best,
				"label": String(run.event_options()[best]["text"])}))
			var c0: int = run.coins
			run.choose_event(best)
			_eco(run, "event", run.coins - c0)
			rec["ev"][-1]["hp1"] = run.hp
			rec["ev"][-1]["mhp1"] = run.max_hp
		"pick":
			match String(run.event["pick"]):
				"remove":
					var worst := String(run.cards.keys()[0])
					var worst_score := INF
					for id: String in run.cards:
						var s := _card_score(id) if pol != "random" else rng.randf()
						if s < worst_score:
							worst_score = s
							worst = id
					run.event_pick(worst)
				"upgrade":
					var ups := _upgradable(run)
					run.event_pick(_best_upgrade(run) if pol != "random" else String(ups[rng.randi() % ups.size()]))
				"curse":
					run.event_pick(String(run.curses[0]))
		_:
			run.finish_event()


# ---------------------------------------------------------------- bench

## One thing at a time: the same hero (a ready deck, perks chosen as a greedy player would) at wagon `pass`
## meets the same n enemies (fight and elite doors in turn, seeds fixed), once with nothing added and once for
## every item / wagon rule / perk asked for. One line per fight: {what, j, kind, won, hp_lost, turns, ...}.
func _bench(f: FileAccess, a: Dictionary, shard: int, shards: int) -> void:
	var n := int(a.get("n", "60"))
	var pass_at := int(a.get("pass", "12"))
	var level := String(a.get("level", "medium"))
	var base_seed := int(a.get("seed", "1"))
	var diff := int(a.get("diff", "0"))
	var things: Array = [["none", ""]]
	var want_items := String(a.get("items", ""))
	if want_items != "":
		for id: String in (TrainItems.ITEMS.keys() if want_items == "all" else want_items.split(",")):
			things.append(["item", id])
	var want_rules := String(a.get("rules", ""))
	if want_rules != "":
		for id: String in (TrainWagons.WAGONS.keys() if want_rules == "all" else want_rules.split(",")):
			things.append(["rule", id])
	if String(a.get("perks", "0")) == "1":
		for id: String in TrainRun.STATS.keys():
			things.append(["perk", id])
	for sid: String in TrainItems.SETS if String(a.get("sets", "0")) == "1" else []:
		things.append(["set", sid])
	var jobs: Array = []
	for t in things:
		for j in n:
			jobs.append([t, j])
	for k in range(shard, jobs.size(), shards):
		var t: Array = jobs[k][0]
		var j: int = jobs[k][1]
		var seed_value := base_seed + j
		rng.seed = seed_value * 11 + 5
		var decks: Array = CardDB.hero_ids()
		var run := TrainRun.new()
		run.save_path = ""
		run.train_rules = int(a.get("train_rules", str(TrainRun.TRAIN_RULES)))     # to compare the rules of the train
		run.start(String(decks[seed_value % decks.size()]), seed_value, "", diff)
		run.passed = pass_at
		run.train = 1 + pass_at / TrainRun.TRAIN_LEN
		run.wagon = pass_at % TrainRun.TRAIN_LEN
		run.level = 1 + pass_at / 3
		pol = "greedy"
		for _i in pass_at / 4:        # the perks of a hero who has played so far
			run.phase = "level"
			run.levels_due = 1
			run._offer_perks()
			run.pick_perk(_perk(run))
		run.rng.seed = seed_value * 3 + 1
		var avoid := String(t[1]) if String(t[0]) == "item" else ""
		for id: String in run._roll_items(pass_at / 4 + 1, false):      # and the items such a hero has picked up
			if id != avoid and not (String(t[0]) == "set" and TrainItems.SETS[t[1]]["items"].has(id)):
				run._add_item(id)
		run.coins = 0
		match String(t[0]):
			"item":
				run._add_item(String(t[1]))
			"set":
				for id: String in TrainItems.SETS[t[1]]["items"]:
					run._add_item(id)
			"perk":
				run.stats[t[1]] = mini(int(run.stats.get(t[1], 0)) + run.stat_step(t[1]) * (1 if t[1] != "max_hp" else 0), run.stat_cap(t[1]))
				if t[1] == "max_hp":
					run._grow_max_hp(int(TrainRun.STATS["max_hp"]["step"]))
		run.hp = run.max_hp
		var kind: String = "elite" if j % 3 == 2 else "fight"
		run.rng.seed = seed_value * 3 + 1
		run.doors = []
		run.current = run._fight_door(kind)
		if String(t[0]) == "rule":
			run.current["wagon"] = String(t[1])
		run.phase = "fight"
		var fr: Dictionary = await _fight(run, level)
		fr["what"] = "%s:%s" % [t[0], t[1]]
		fr["j"] = j
		f.store_line(JSON.stringify({"what": fr["what"], "j": j, "kind": kind, "won": fr["won"], "hp_lost": fr["hp0"] - fr["hp_left"], "mhp": fr["mhp"],
			"turns": fr["turns"], "first": fr["first"], "dmg": fr["dmg"], "heals": fr["heals"], "draw_fails": fr["draw_fails"], "ehp": fr["ehp"], "enemy": fr["enemy"],
			"cause": fr["cause"], "hits": fr["hits"], "rule": fr["rule"]}))
		f.flush()
