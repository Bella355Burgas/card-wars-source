extends SceneTree
## Headless fuzz test for the rules engine:
##   godot --headless --path . -s res://tests/sim.gd -- [games] [seed] [hero_a] [hero_b]
##   … -- [games] [seed] pool [set]   random own decks from the whole card pool (or from one set)
## Plays random games between random heroes and hero cards (or the two given
## picks, "deck" or "deck@hero card") and checks
## invariants after every command.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")


class EventCounter:
	var game
	var counts := {}
	func play(ev: Dictionary) -> void:
		var key: String = ev["type"]
		if ev.has("uid") and ev["uid"] is int and ev["uid"] > 0 and game.card(ev["uid"]) != null:
			key += ":" + game.card(ev["uid"]).id
		elif key == "hero_power":
			key += ":" + game.players[ev["p"]].hero_card
		counts[key] = counts.get(key, 0) + 1


var failures := 0
var pool_set := ""          # "pool" mode: random own decks ("*" = every set)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 300
	var base_seed := int(args[1]) if args.size() > 1 else 1
	var fixed := args.slice(2, 4)
	if not fixed.is_empty() and fixed[0] == "pool":
		pool_set = fixed[1] if fixed.size() > 1 else "*"
		fixed = []
	var heroes: Array = CardDB.hero_ids()
	var hero_cards: Array = CardDB.hero_card_ids()
	var wins := {}
	var turns_total := 0
	var counter := EventCounter.new()
	var t0 := Time.get_ticks_msec()
	for g in games:
		var seed_value := base_seed + g
		var game := Game.new()
		var agent := RandomAgent.new(seed_value * 7919)
		counter.game = game
		game.animator = counter
		game.chooser = agent
		var pair: Array = fixed.duplicate()
		if pool_set != "":
			pair = [_pool_deck(agent.rng, pool_set, hero_cards), _pool_deck(agent.rng, pool_set, hero_cards)]
		elif pair.size() != 2:
			pair = []
			for i in 2:
				# Half of the seats play a random hero card with their deck.
				var deck: String = heroes[agent.rng.randi() % heroes.size()]
				var card: String = hero_cards[agent.rng.randi() % hero_cards.size()] if agent.rng.randf() < 0.5 else deck
				pair.append(CardDB.loadout(deck, card))
		game.setup(pair, seed_value % 2, seed_value)
		for p in 2:
			var types: Array = game.players[p].lands.map(func(l): return l["type"])
			if agent.rng.randf() < 0.5:
				types.reverse()
				await game.cmd_arrange_lands(p, types)
			if agent.rng.randf() < 0.3:
				await game.cmd_mulligan(p)
		await game.start_game()
		var steps := 0
		while game.phase != "over" and steps < 3000:
			if game.phase == "handoff":
				await game.cmd_start_turn()
				continue
			var p: int = game.turn_player
			var cmds: Array = game.legal_commands(p)
			if cmds.is_empty():
				_fail(seed_value, pair, "no legal commands in phase %s" % game.phase)
				break
			await game.run_command(p, agent.pick_command(cmds))
			_check(game, seed_value, pair)
			steps += 1
		if game.phase != "over":
			_fail(seed_value, pair, "game did not finish (turn %d)" % game.turn_number)
		else:
			var w: String = pair[game.winner]
			wins[w] = wins.get(w, 0) + 1
		turns_total += game.turn_number
	if not fail_kinds.is_empty():
		print("failure kinds: ", fail_kinds)
	print("games=%d  avg_turns=%.1f  failures=%d  time=%.1fs" % [games, float(turns_total) / games, failures,
		(Time.get_ticks_msec() - t0) / 1000.0])
	print("wins: ", wins)
	if args.has("--events"):
		var keys := counter.counts.keys()
		keys.sort()
		for k: String in keys:
			print("  %-44s %d" % [k, counter.counts[k]])
	_report_unused(counter)
	quit(1 if failures > 0 else 0)


## Lists cards whose floop/activation/spell never resolved (a sign of a broken condition).
func _report_unused(counter: EventCounter) -> void:
	var seen := {}
	for k: String in counter.counts.keys():
		var parts := k.split(":")
		if parts.size() == 2 and parts[0] in ["floop", "activate", "spell"]:
			seen[parts[1]] = true
	var missing := []
	var lists: Array = CardDB.hero_ids().map(func(h): return CardDB.hero(h)["deck"].keys())
	if pool_set != "":
		lists = [CardDB.pool_ids().filter(func(id): return pool_set == "*" or CardDB.get_def(id).get("set", "") == pool_set)]
	for list in lists:
		for id: String in list:
			var d := CardDB.get_def(id)
			var active: bool = d.get("floop", false) or d.has("activated") or d["kind"] == "spell"
			if active and not seen.has(id) and not missing.has(id):
				missing.append(id)
	print("never used: ", missing)
	var idle := []
	for id: String in CardDB.hero_card_ids():
		if CardDB.hero_card(id).has("power") and not counter.counts.has("hero_power:" + id):
			idle.append(id)
	print("hero powers never used: ", idle)


func _count_card(c, owned: Array) -> void:
	owned[c.owner] += 1
	for u in c.under:
		_count_card(u, owned)


func _check(game, seed_value: int, pair: Array) -> void:
	var owned := [0, 0]
	for ps in game.players:
		for zone in [ps.deck, ps.hand, ps.discard, ps.removed, ps.hero_state.get("notes", [])]:
			for c in zone:
				owned[c.owner] += 1
		if ps.teamwork != null:
			_count_card(ps.teamwork, owned)
		for lane in 4:
			if ps.creatures[lane] != null:
				_count_card(ps.creatures[lane], owned)
			for e in game.buildings_at(ps.index, lane):
				_count_card(e[0], owned)
		if ps.actions < 0:
			_fail(seed_value, pair, "%s has negative actions" % ps.name)
	var total := [game.all_cards(0).size(), game.all_cards(1).size()]
	if owned != total:
		_fail(seed_value, pair, "card count %s after turn %d" % [owned, game.turn_number])
	if game.phase != "over":
		for side in 2:
			for lane in 4:
				var c = game.players[side].creatures[lane]
				if c != null and c.damage >= game.def_of(side, lane):
					_fail(seed_value, pair, "«%s» survives with lethal damage" % c.card_name())


var fail_kinds := {}


func _fail(seed_value: int, pair: Array, msg: String) -> void:
	failures += 1
	var kind := msg.get_slice(" after", 0)
	if not fail_kinds.has(kind):
		fail_kinds[kind] = 0
		printerr("seed %d %s: %s" % [seed_value, pair, msg])
	fail_kinds[kind] += 1


## A random own deck: two land types, 40 cards of those types and Rainbow, from the whole pool
## or one set ("*" = all), and a random hero card.
func _pool_deck(rng: RandomNumberGenerator, set_code: String, hero_cards: Array) -> String:
	var types: Array = CardDB.land_types()
	var a: String = types[rng.randi() % types.size()]
	var b: String = types[rng.randi() % types.size()]
	var lands := [a, b, a, b]
	var ids: Array = CardDB.pool_ids().filter(func(id):
		var d: Dictionary = CardDB.get_def(id)
		return d["kind"] != "teamwork" and (set_code == "*" or d.get("set", "") == set_code) and (d["land"] == a or d["land"] == b or d["land"] == "rainbow"))
	var deck := {}
	var n := 0
	var guard := 0
	while n < 40 and guard < 2000 and not ids.is_empty():
		guard += 1
		var id: String = ids[rng.randi() % ids.size()]
		if int(deck.get(id, 0)) < 3:
			deck[id] = int(deck.get(id, 0)) + 1
			n += 1
	var code := CardDB.custom_code("Пул", lands, deck)
	return CardDB.loadout(code, hero_cards[rng.randi() % hero_cards.size()])
