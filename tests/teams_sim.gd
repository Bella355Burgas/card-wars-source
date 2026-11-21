extends SceneTree
## 2 на 2 fuzz test:
##   godot --headless --path . -s res://tests/teams_sim.gd -- [games] [seed]
## Four random decks and hero cards, random legal moves and choices. Checks the rules of
## the Doubles Tournament rulebook the engine must keep (shared team hit points, turns
## round the table alternating teams, no floops or fights in the first three turns, every
## card stays somewhere, the opposite spot of a lane is symmetric) and that each game's
## replay plays back to the same state.

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
	var wins := [0, 0]
	var unfinished := 0
	var turns_total := 0
	_check_geometry()
	for n in games:
		var seed_value := base_seed + n
		var agent := RandomAgent.new(seed_value * 31)
		var picks := []
		for i in 4:
			var deck: String = heroes[agent.rng.randi() % heroes.size()]
			var card: String = hero_cards[agent.rng.randi() % hero_cards.size()] if agent.rng.randf() < 0.5 else deck
			picks.append(CardDB.loadout(deck, card))
		var game := Game.new()
		game.chooser = agent
		game.setup(picks, seed_value % 4)
		game.journal = []
		var cards_at_start := _card_count(game)
		for p in 4:
			if agent.rng.randf() < 0.3:
				await game.cmd_mulligan(p)
		await game.start_game()
		var steps := 0
		var last_turn := -1
		var last_player := -1
		while game.phase != "over" and steps < 4000:
			if game.phase == "handoff":
				await game.cmd_start_turn()
				continue
			var p: int = game.turn_player
			if game.turn_number != last_turn:
				if last_player >= 0 and p != (last_player + 1) % 4:
					_fail(seed_value, "turn went from seat %d to %d" % [last_player, p])
				last_turn = game.turn_number
				last_player = p
			var cmds: Array = game.legal_commands(p)
			if cmds.is_empty():
				_fail(seed_value, "no commands in phase %s" % game.phase)
				break
			if game.turn_number <= 3:
				for c in cmds:
					if c["cmd"] in ["floop", "attack", "begin_attack"]:
						_fail(seed_value, "%s in turn %d" % [c["cmd"], game.turn_number])
			await game.run_command(p, agent.pick_command(cmds))
			steps += 1
			if game.players[0].hp != game.players[2].hp or game.players[1].hp != game.players[3].hp:
				_fail(seed_value, "teammates' hit points differ")
				break
			if _card_count(game) != cards_at_start:
				_fail(seed_value, "cards went missing: %d of %d" % [_card_count(game), cards_at_start])
				break
		turns_total += game.turn_number
		if game.phase != "over":
			unfinished += 1
		else:
			if not game.winner in [0, 1]:
				_fail(seed_value, "winner %d is not a team" % game.winner)
			elif game.players[game.winner].hp <= 0 and game.players[1 - game.winner].hp > 0:
				_fail(seed_value, "the team with hit points left lost")
			else:
				wins[game.winner] += 1
		var data := Replay.from_game(game, "hotseat", 0, "test")
		var back := Replay.parse(JSON.stringify(data))
		if back.is_empty():
			_fail(seed_value, "the replay does not parse")
		else:
			var err: String = await Replay.verify(back)
			if err != "":
				_fail(seed_value, "replay: " + err)
	print("teams games=%d  wins=%s  unfinished=%d  avg turns=%.1f  failures=%d  time=%.1fs" % [games, wins,
		unfinished, turns_total / float(maxi(games, 1)), failures, (Time.get_ticks_msec() - t0) / 1000.0])
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


## The table of the rulebook: each landscape faces one of a neighbour's, both ways, and
## never a teammate's.
func _check_geometry() -> void:
	var game := Game.new()
	game.setup(["finn", "jake", "bmo", "marceline"], 0, 1)
	for p in 4:
		for lane in 4:
			var a: Array = game.across(p, lane)
			if game.across(a[0], a[1]) != [p, lane]:
				_fail(0, "across(%d, %d) is not symmetric" % [p, lane])
			if not game.is_foe(p, a[0]):
				_fail(0, "lane %d of seat %d faces a teammate" % [lane, p])
		if game.foes(p).size() != 2 or game.foes(p).any(func(q): return not game.is_foe(p, q)):
			_fail(0, "foes of seat %d" % p)
	if game.players[0].hp != Game.TEAM_HP:
		_fail(0, "a team starts with %d HP" % game.players[0].hp)
	game.players[0].hp -= 5
	if game.players[2].hp != Game.TEAM_HP - 5:
		_fail(0, "damage to a player does not reach the teammate")


func _fail(seed_value: int, msg: String) -> void:
	failures += 1
	if failures <= 30:
		printerr("seed %d: %s" % [seed_value, msg])
