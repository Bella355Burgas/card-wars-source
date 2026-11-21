extends RefCounted
## The server's check of a train of the day (the table of the relay, tools/run_check.gd): the run's
## journal (TrainRun.journal_path) is played again from its date, so the score is the server's own
## and not a number the client sent. Nothing in the journal is taken on trust:
##   - the run's steps are the actions of TrainRun (ACTIONS, with the types of their arguments), which
##     do nothing where the run does not allow them; the phase, the wagons, the coins and the HP the
##     journal saw before a step must be what the check sees;
##   - a fight is set up from the run (the wagon's door, its seed, TrainRun.prepare_fight) and played
##     step by step. The player's commands must be legal ones (Game.legal_commands), the answers must
##     be among the options; every move and answer of the enemy is asked of the enemy's own network
##     (PolicyAgent.agrees_*, whose decisions depend on the game's state only, see seed_base) and must
##     be what it plays. The fight's end is the engine's: fight_won takes the HP the check has left.
## check() answers {"err": "" or what went wrong, "score", "wins", "hero", "deck", "restarts": fights
## started over after the game was closed}.

const TrainRun = preload("res://scripts/train/train_run.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const Game = preload("res://scripts/core/game.gd")
const Replay = preload("res://scripts/core/replay.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const AIHelper = preload("res://scripts/ai/ai_helper.gd")

const MAX_STEPS := 8000     # of one fight
const ACTIONS := {
	"enter": [TYPE_INT], "pick_perk": [TYPE_STRING], "take_item": [TYPE_STRING], "skip_item": [],
	"take": [TYPE_STRING], "skip": [], "rest_heal": [], "remove_card": [TYPE_STRING, TYPE_BOOL],
	"upgrade_card": [TYPE_STRING], "change_land": [TYPE_INT, TYPE_STRING], "shop_sale": [],
	"choose_event": [TYPE_INT], "event_pick": [TYPE_STRING, TYPE_BOOL], "leave_event": [], "finish_event": [],
	"shop_reroll": [], "buy_card": [TYPE_STRING], "buy_item": [TYPE_STRING], "shop_upgrade": [TYPE_STRING],
	"shop_remove": [TYPE_STRING, TYPE_BOOL], "shop_uncurse": [TYPE_STRING], "leave_shop": [],
}
## Commands of the player the engine judges itself (they are not in legal_commands).
const FREE_CMDS := ["undo", "concede"]


## The journal as its lines of text.
static func parse(text: String) -> Array:
	var out := []
	for line in text.split("\n", false):
		out.append(Replay._ints(JSON.parse_string(line)))
	return out


## date: the train of that day; "" an ordinary run (a record), started from the pick, the seed and
## the difficulty of its first step.
static func check(lines: Array, date: String) -> Dictionary:
	var head = lines[0] if not lines.is_empty() else null
	# Journals before build 57 do not say their train rules: the newest first, then the older ones
	# (clients that have not updated yet). Each set is honest, so trying them gives a forger nothing.
	var tries: Array = range(TrainRun.TRAIN_RULES, 0, -1)
	if head is Dictionary and head.has("train_rules"):
		tries = [head["train_rules"]] if head["train_rules"] is int and head["train_rules"] in tries else []
	if tries.is_empty():
		return {"err": "another version of the game", "score": 0, "wins": 0, "hero": "", "deck": "", "restarts": 0}
	var first := {}
	for v: int in tries:
		var out := await _check(lines, date, v)
		if out["err"] == "":
			return out
		if first.is_empty():
			first = out
	return first


static func _check(lines: Array, date: String, train_rules: int) -> Dictionary:
	var out := {"err": "", "score": 0, "wins": 0, "hero": "", "deck": "", "restarts": 0}
	var head = lines[0] if not lines.is_empty() else null
	if not head is Dictionary or head.get("a") != "start" or head.get("date") != date:
		out["err"] = "no start of the train of %s" % date if date != "" else "no start of an ordinary run"
		return out
	if head.get("rules") != Replay.RULES or head.get("format") != TrainRun.FORMAT:
		out["err"] = "another version of the game"
		return out
	var run := TrainRun.new()
	run.save_path = ""
	run.train_rules = train_rules
	if date != "":
		run.start_daily(date)
	else:
		var pick = head.get("pick")
		var seed_value = head.get("seed")
		var level = head.get("difficulty")
		if not (pick is String and seed_value is int and level is int) or not CardDB.valid_loadout(pick) 				or CardDB.is_custom(CardDB.loadout_deck(pick)) or CardDB.is_no_hero(pick) or seed_value < 0 or level < 0 or level > TrainRun.MAX_DIFFICULTY:
			out["err"] = "a wrong start of the run"
			return out
		run.start(pick, seed_value, "", level)
	var fight := {}             # the fight played, until its fight_won / lose
	var started := 0
	var played := 0
	for i in range(1, lines.size()):
		var st = lines[i]
		var why := ""
		if not st is Dictionary:
			why = "not a step"
		elif run.phase == "over":
			why = "a step after the end"
		else:
			why = await _step(run, st, fight)
			match String(st.get("a", "")):
				"go":
					started += 1
				"fight":
					played += 1
		if why != "":
			out["err"] = "step %d, wagon %d: %s" % [i, run.passed + 1, why]
			return out
	if run.phase != "over":
		out["err"] = "the run is not over"
		return out
	out.merge({"score": run.passed, "wins": run.wins, "hero": run.deck_id, "deck": run.deck_code(),
		"restarts": maxi(started - played, 0)}, true)
	return out


## One step of the run; "" when it is right.
static func _step(run, st: Dictionary, fight: Dictionary) -> String:
	var a := String(st.get("a", ""))
	if a == "go":
		return "" if run.phase == "fight" and fight.is_empty() else "a fight out of place"
	if a == "load":
		if not fight.is_empty():
			return "a load out of place"
		# A run read after an update goes on by the new train rules: the load says which.
		var tr = st.get("tr")
		if tr is int and tr >= run.train_rules and tr <= TrainRun.TRAIN_RULES:
			run.train_rules = tr
		run.reload()
		return ""
	if a == "fight":
		if run.phase != "fight" or not fight.is_empty() or not st.get("steps") is Array:
			return "a fight out of place"
		fight.merge(await play_fight(run, st["steps"]))
		return String(fight["err"])
	if st.get("ph") != run.phase or st.get("n") != run.passed or st.get("c") != run.coins or st.get("hp") != run.hp:
		return "the run differs before %s: %s %s %s %s, the journal %s %s %s %s" % [a, run.phase, run.passed, run.coins, run.hp,
			st.get("ph"), st.get("n"), st.get("c"), st.get("hp")]
	var args = st.get("x")
	if not args is Array:
		return "no arguments"
	if a == "fight_won":
		if fight.is_empty() or not fight["won"]:
			return "a win that was not played"
		run.fight_won(int(fight["hp"]), bool(fight["revived"]))
		fight.clear()
		return ""
	if a == "lose":
		var by_fight: bool = args.size() == 1 and args[0] is bool and args[0]
		if not fight.is_empty() and fight["won"] or by_fight and fight.is_empty():
			return "a loss that was not played"
		run.lose(by_fight)
		return ""
	if not fight.is_empty():
		return "a step between the fight and its end"
	var types: Array = ACTIONS.get(a, [])
	if not ACTIONS.has(a) or args.size() != types.size():
		return "no such step: %s" % a
	for k in types.size():
		if typeof(args[k]) != types[k]:
			return "a wrong argument of %s" % a
	run.callv(a, args)
	return ""


## The agent of the enemy of the door (the second one of a double wagon: second), as the game makes it.
static func _agent(door: Dictionary, second: bool):
	var d: Dictionary = door["second"] if second else door
	var agent = AILevels.agent(String(d["level"]), String(d["enemy"]))
	if not "seed_base" in agent:
		return null
	agent.seed_base = int(door["seed"]) + (1 if second else 0)
	return agent


## Plays the fight of the run's wagon from its steps: {"err", "won", "hp", "revived"}.
static func play_fight(run, steps: Array) -> Dictionary:
	var out := {"err": "", "won": false, "hp": 0, "revived": false}
	var door: Dictionary = run.current
	var seed_value := int(door["seed"])
	var g := Game.new()
	g.setup([run.player_pick(), String(door["enemy"])], seed_value % 2, seed_value)
	run.prepare_fight(g)
	var agents := [_agent(door, false), _agent(door, true) if door.has("second") else null]
	if agents[0] == null or door.has("second") and agents[1] == null:
		out["err"] = "no network for the enemy"
		return out
	var judge := Judge.new(g, steps, agents, door.has("second"))
	g.chooser = judge
	out["err"] = await judge.play()
	if out["err"] == "" and g.phase != "over":
		out["err"] = "the fight is not over"
	if out["err"] == "":
		out["won"] = g.winner == 0
		out["hp"] = g.players[0].hp
		out["revived"] = bool(g.players[0].item_state.get("revive", false))
	return out


## Plays the steps of a fight and answers the engine's choices from them, judging both sides.
class Judge extends RefCounted:
	var g
	var steps: Array
	var agents: Array
	var double := false
	var pos := 0
	var broken := ""
	var idle := false           # the player's last command is not one the engine offers: it must change nothing

	func _init(game, p_steps: Array, p_agents: Array, p_double: bool) -> void:
		g = game
		steps = p_steps
		agents = p_agents
		double = p_double

	## The enemy's agent now: the second one once it sat down.
	func agent():
		return agents[1] if double and g.train.follow.is_empty() else agents[0]

	func play() -> String:
		if steps.size() > MAX_STEPS:
			return "a fight too long"
		var started := false
		var mulled := [false, false]
		while pos < steps.size():
			var st = steps[pos]
			pos += 1
			if not st is Dictionary:
				return "not a step of a fight"
			var t := String(st.get("t", ""))
			var p := int(st.get("p", 0))
			var why := ""
			if p < 0 or p > 1:
				return "fight step %d: no such seat" % (pos - 1)
			match t:
				"lands":
					if started or p != 0:
						why = "lands out of place"
				"mull":
					if started or mulled[p] or mulled[1] or p == 1 and not agent().agrees_mulligan(g, 1, true):
						why = "a new hand out of place"
					mulled[p] = true
				"start":
					if started or not mulled[1] and not agent().agrees_mulligan(g, 1, false):
						why = "the enemy would change its hand"
					started = true
				"turn":
					if g.phase != "handoff":
						why = "a turn out of place"
				"end":
					if g.phase != "attack" or p != g.turn_player or not g.attackers_left(p).is_empty():
						why = "an end of the turn out of place"
				"cmd":
					why = _cmd_ok(p, st.get("c"))
				"over":
					if int(st.get("w", -1)) != 1:
						why = "the enemy does not give up"
				_:
					why = "no such step: %s" % t
			if why == "" and t != "lands" and t != "start" and t != "mull" and not started:
				why = "the game has not started"
			if why == "" and st.has("h") and int(st["h"]) != g.state_hash():
				why = "the game differs before %s" % t
			if why != "":
				return "fight step %d: %s" % [pos - 1, why]
			var before: int = g.state_hash()
			await Replay.apply(g, st)
			if broken != "":
				return "fight step %d: %s" % [pos - 1, broken]
			if t == "cmd" and idle and g.state_hash() != before:
				return "fight step %d: not a legal command: %s" % [pos - 1, str(st.get("c"))]
			if t == "cmd" and p == 1:
				# A command that changed nothing is banned in that state, as at the table (board.gd).
				if g.state_hash() == before and g.turn_player == 1 and (g.phase == "main" or g.phase == "attack"):
					agent().ban_command(before, st["c"])
				AIHelper.clear_plan(g)
			if g.phase == "over" and pos < steps.size():
				return "steps after the end of the fight"
		return ""

	func _cmd_ok(p: int, c) -> String:
		idle = false
		if not c is Dictionary or not c.get("cmd") is String or p != g.turn_player or not (g.phase == "main" or g.phase == "attack"):
			return "a command out of place"
		if p == 1:
			return "" if agent().agrees_command(g, 1, c) else "the enemy would not play %s" % str(c)
		if FREE_CMDS.has(c["cmd"]) or g.legal_commands(0).has(c) or _attack_from_main(c) or _hero_floop(c):
			return ""
		# Not a move the engine offers: taken only if it changes nothing (a button pressed at the
		# wrong moment, the engine does nothing); play() looks at the state after it.
		idle = true
		return ""

	## «Атаковать» from the card's menu in the main phase: the engine goes into battle and attacks
	## (cmd_attack), legal_commands offers only begin_attack there.
	func _attack_from_main(c: Dictionary) -> bool:
		return g.phase == "main" and c.size() == 2 and c["cmd"] == "attack" and c.get("lane") is int \
			and g.can_attack(0, c["lane"])

	## «ФЛЮП героя» from the card's menu (Финн) on a card with no floop of its own: the engine does
	## the hero's floop (cmd_floop), legal_commands offers the plain floop there, "hero" only when
	## the card has both.
	func _hero_floop(c: Dictionary) -> bool:
		return c.size() == 4 and c["cmd"] == "floop" and c.get("hero") is bool and c["hero"] \
			and c.get("kind") is String and c.get("lane") is int \
			and g.can_floop(0, c["kind"], c["lane"]) and g.hero_floop_ok(0, c["kind"], c["lane"])

	## The engine asks: the next step is the answer.
	func choose(req: Dictionary):
		if pos >= steps.size() or not steps[pos] is Dictionary or steps[pos].get("t") != "pick":
			broken = "no answer for a choice"
			return null
		var st: Dictionary = steps[pos]
		pos += 1
		var options: Array = req.get("options", [])
		var i := int(st.get("i", -1))
		if i < -1 or i >= options.size() or i == -1 and not req.get("optional", false):
			broken = "an answer that is not among the options"
			return null
		var r = options[i] if i >= 0 else null
		if int(req.get("player", 0)) == 1 and not agent().agrees_choice(g, req, r):
			broken = "the enemy would not answer that"
		return r
