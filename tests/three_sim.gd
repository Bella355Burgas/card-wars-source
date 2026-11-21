extends SceneTree
## На троих fuzz test:
##   godot --headless --path . -s res://tests/three_sim.gd -- [games] [seed]
## Three random decks and hero cards, random legal moves and choices. Checks what the engine
## must keep: turns round the table without the seat that dropped out, no floops or fights in
## the first two turns, every card stays somewhere, the spot across a lane is symmetric and
## never the player's own or a dropped out one's, nothing of the dropped out player stays in
## play, the winner is the last one standing, and each game's replay plays back to the same state.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")
const Replay = preload("res://scripts/core/replay.gd")

var failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 200
	var base_seed := int(args[1]) if args.size() > 1 else 1
	var heroes: Array = CardDB.hero_ids()
	var hero_cards: Array = CardDB.hero_card_ids()
	var t0 := Time.get_ticks_msec()
	var wins := [0, 0, 0]
	var unfinished := 0
	var dropped := 0
	var dropped_in_turn := 0
	var turns_total := 0
	_check_geometry()
	for n in games:
		var seed_value := base_seed + n
		var agent := RandomAgent.new(seed_value * 31)
		var picks := []
		for i in 3:
			var deck: String = heroes[agent.rng.randi() % heroes.size()]
			var card: String = hero_cards[agent.rng.randi() % hero_cards.size()] if agent.rng.randf() < 0.5 else deck
			picks.append(CardDB.loadout(deck, card))
		var game := Game.new()
		game.chooser = agent
		game.setup(picks, seed_value % 3)
		game.journal = []
		for p in 3:
			if agent.rng.randf() < 0.3:
				await game.cmd_mulligan(p)
		await game.start_game()
		var cards_at_start := _card_count(game)      # after the start: Бетти makes her notes then
		var steps := 0
		var last_turn := -1
		var last_player := -1
		var out_seat := -1
		while game.phase != "over" and steps < 4000:
			if game.phase == "handoff":
				await game.cmd_start_turn()
				continue
			var p: int = game.turn_player
			if game.is_out(p):
				_fail(seed_value, "seat %d is out but has the turn" % p)
				break
			if game.turn_number != last_turn:
				if last_player >= 0 and p != game.next_seat(last_player):
					_fail(seed_value, "turn went from seat %d to %d" % [last_player, p])
				last_turn = game.turn_number
				last_player = p
			var cmds: Array = game.legal_commands(p)
			if cmds.is_empty():
				_fail(seed_value, "no commands in phase %s" % game.phase)
				break
			if game.turn_number <= 2:
				for c in cmds:
					if c["cmd"] in ["floop", "attack", "begin_attack"]:
						_fail(seed_value, "%s in turn %d" % [c["cmd"], game.turn_number])
			var was_turn := game.turn_player
			await game.run_command(p, agent.pick_command(cmds))
			steps += 1
			for s in 3:
				if game.is_out(s) and out_seat < 0:
					out_seat = s
					dropped += 1
					if s == was_turn:
						dropped_in_turn += 1
			if _card_count(game) != cards_at_start:
				_fail(seed_value, "cards went missing: %d of %d %s" % [_card_count(game), cards_at_start, picks])
				break
			if out_seat >= 0 and not _out_clean(game, out_seat):
				_fail(seed_value, "seat %d dropped out but still has cards in play" % out_seat)
				break
			if not _across_ok(game):
				_fail(seed_value, "the spots across the lanes are wrong (out: %d)" % out_seat)
				break
		turns_total += game.turn_number
		if game.phase != "over":
			unfinished += 1
		else:
			var w: int = game.winner
			if w < 0 or w > 2 or game.is_out(w):
				_fail(seed_value, "winner %d" % w)
			elif game.players[w].hp <= 0 and w != game.turn_player:
				_fail(seed_value, "the winner has no hit points and it is not their turn")
			else:
				wins[w] += 1
		var data := Replay.from_game(game, "hotseat", 0, "test")
		var back := Replay.parse(JSON.stringify(data))
		if back.is_empty():
			_fail(seed_value, "the replay does not parse")
		else:
			var err: String = await Replay.verify(back)
			if err != "":
				_fail(seed_value, "replay: " + err)
	print("three games=%d  wins=%s  dropped out=%d (in own turn %d)  unfinished=%d  avg turns=%.1f  failures=%d  time=%.1fs" % [
		games, wins, dropped, dropped_in_turn, unfinished, turns_total / float(maxi(games, 1)), failures,
		(Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failures > 0 else 0)


## Every card of the game is in exactly one place.
func _card_count(game) -> int:
	var seen := {}
	for ps in game.players:
		for zone in [ps.deck, ps.hand, ps.discard, ps.removed, ps.hero_state.get("notes", [])]:
			for c in zone:
				seen[c.uid] = int(seen.get(c.uid, 0)) + 1
		if ps.teamwork != null:
			seen[ps.teamwork.uid] = int(seen.get(ps.teamwork.uid, 0)) + 1
		for lane in 4:
			for c in [ps.creatures[lane], ps.buildings[lane]] + ps.extra_buildings[lane]:
				if c != null:
					seen[c.uid] = int(seen.get(c.uid, 0)) + 1
					for u in c.under:
						seen[u.uid] = int(seen.get(u.uid, 0)) + 1
	for uid in seen:
		if seen[uid] != 1:
			return -1
	return seen.size()


func _out_clean(game, s: int) -> bool:
	var ps = game.players[s]
	for lane in 4:
		if ps.creatures[lane] != null or ps.buildings[lane] != null or not ps.extra_buildings[lane].is_empty():
			return false
	return true


## Each landscape faces one of a live opponent's, both ways.
func _across_ok(game) -> bool:
	for p in game.sides():
		for lane in 4:
			var a: Array = game.across(p, lane)
			if a[0] == p or game.is_out(a[0]) or game.across(a[0], a[1]) != [p, lane]:
				return false
	return true


func _check_geometry() -> void:
	var game := Game.new()
	game.setup(["finn", "jake", "bmo"], 0, 1)
	if not game.three() or game.teams():
		_fail(0, "three picks do not make a game на троих")
	for p in 3:
		if game.players[p].hp != Game.START_HP:
			_fail(0, "seat %d starts with %d HP" % [p, game.players[p].hp])
		if game.foes(p).size() != 2:
			_fail(0, "foes of seat %d" % p)
	if game.across(0, 0) != [1, 3] or game.across(0, 3) != [2, 0] or game.across(1, 1) != [2, 2]:
		_fail(0, "across on the triangle")
	if not _across_ok(game):
		_fail(0, "across is not symmetric")
	game.players[1].out = true
	if game.across(0, 2) != [2, 1] or game.across(2, 0) != [0, 3] or not _across_ok(game) or game.next_seat(0) != 2 or game.foes(0) != [2]:
		_fail(0, "1 на 1 after seat 1 dropped out")
	if game.sides() != [0, 2]:
		_fail(0, "sides after seat 1 dropped out: %s" % [game.sides()])


func _fail(seed_value: int, msg: String) -> void:
	failures += 1
	if failures <= 30:
		printerr("seed %d: %s" % [seed_value, msg])
