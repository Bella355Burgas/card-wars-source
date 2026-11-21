extends SceneTree
## Batched headless worker for RL self-play and evaluation.
##
## One worker process holds several games ("slots") and answers a whole batch
## of requests in one round trip, so the Python side never waits per command.
## The worker reads and writes blocking, so it does not depend on the frame rate.
## Start it with:
##   godot --headless --path . -s res://scripts/ai/rl_worker.gd -- --port 25000 --slots 16
##
## Frames: a 4-byte little-endian length, then the JSON body (both ways).
## Request:  {"slots": [{"i": 3, "a": 7}, {"i": 4, "new": {...}}]}
##   "a"   answers the decision the slot is waiting on (index of a candidate);
##   "new" starts a game in the slot (a game still running there is dropped).
##         Spec: heroes ["deck" or "deck@card", ...], first (0/1), seed,
##         bot ("none" | "heuristic" | "random"), bot_seat (-1 when both seats
##         are the agent's own), log (keep the text log).
## Reply:    {"r": [...]} with one entry per slot:
##   {"i", "st": "dec", "p", "s": view}  seat p must decide (view: scripts/ai/ai_view.gd);
##   {"i", "st": "done", "w", "hp", "t", "cap", "log"?}  the game is over (w = winner
##        seat, -1 draw; cap = it was cut by TURN_CAP / STEP_CAP and decided on HP);
##   {"i", "st": "err", "msg"}  the spec or the game is broken.
##
## The agent seats decide everything: the starting hand, the turn's commands and
## every choice a card asks for. Bot seats keep their hand, pick commands by
## rules of thumb and answer choices with AIHelper. A command that changes
## nothing (a hero ability whose choice was declined, say) is not offered again
## until the game state changes, so no seat can stall a game with it.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")
const AIHelper = preload("res://scripts/ai/ai_helper.gd")
const AIView = preload("res://scripts/ai/ai_view.gd")

## The game ends on HP after this turn, as in the RL bridge.
const TURN_CAP := 60
## Decisions per game before it is ended on HP (guards against endless loops).
const STEP_CAP := 1500
## Commands that always change the game, so they are never checked for doing nothing.
const ALWAYS_CHANGE := ["end_turn", "begin_attack", "attack"]

var server: TCPServer
var slots: Array = []


class Chooser extends RefCounted:
	## Card choices. Bot seats answer at once; an agent seat's request waits
	## (the engine is suspended) until the agent's answer arrives.
	signal answered(value)
	var game_ref: WeakRef           # weak: the game holds this chooser
	var agent_seat := [true, true]
	var pending = null              # the request an agent seat has to answer

	func choose(req: Dictionary):
		var g = game_ref.get_ref()
		var p := int(req.get("player", g.turn_player))
		if p < 0 or p > 1 or not agent_seat[p]:
			return AIHelper.choose(g, req)
		pending = req
		return await answered

	func answer(value) -> void:
		pending = null
		answered.emit(value)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var port := 25000
	var n := 16
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		if args[i] == "--slots" and i + 1 < args.size():
			n = int(args[i + 1])
	slots.resize(n)
	for i in n:
		slots[i] = {}
	server = TCPServer.new()
	var err := server.listen(port, "127.0.0.1")
	if err != OK:
		printerr("rl_worker: cannot listen on %d (%d)" % [port, err])
		quit(1)
		return
	print("rl_worker listening on 127.0.0.1:%d with %d slots" % [port, n])
	await _run()


## Serves one connection after another until the client sends "close".
func _run() -> void:
	while true:
		while not server.is_connection_available():
			OS.delay_msec(1)
		var peer := server.take_connection()
		peer.set_no_delay(true)
		while true:
			var head := peer.get_data(4)
			if head[0] != OK:
				break
			var size := (head[1] as PackedByteArray).decode_u32(0)
			var body := peer.get_data(size)
			if body[0] != OK:
				break
			var msg = JSON.parse_string((body[1] as PackedByteArray).get_string_from_utf8())
			if not msg is Dictionary:
				break
			if msg.get("cmd", "") == "close":
				quit(0)
				return
			var reply := JSON.stringify({"r": await _serve(msg)}).to_utf8_buffer()
			var frame := PackedByteArray()
			frame.resize(4)
			frame.encode_u32(0, reply.size())
			frame.append_array(reply)
			peer.put_data(frame)


func _serve(msg: Dictionary) -> Array:
	var replies := []
	for item: Dictionary in msg.get("slots", []):
		var i := int(item["i"])
		if item.has("new"):
			_start(i, item["new"])
		else:
			await _apply(i, int(item["a"]))
		replies.append(_advance(i))
	return replies


# ---------------------------------------------------------------- games

func _start(i: int, spec: Dictionary) -> void:
	_release(i)
	var heroes: Array = spec["heroes"]
	for pick in heroes:
		if not CardDB.valid_loadout(pick):
			slots[i] = {"error": "illegal pick %s" % pick}
			return
	var bot_seat := int(spec.get("bot_seat", -1))
	var g := Game.new()
	g.fast_mode = not bool(spec.get("log", false))
	var chooser := Chooser.new()
	chooser.game_ref = weakref(g)
	for p in 2:
		chooser.agent_seat[p] = p != bot_seat
	g.chooser = chooser
	var first := int(spec["first"])
	g.setup(heroes, first, int(spec["seed"]))
	slots[i] = {
		"game": g,
		"chooser": chooser,
		"bot": String(spec.get("bot", "none")),
		"bot_seat": bot_seat,
		"rng": RandomAgent.new(int(spec["seed"]) * 7919 + 17),
		"steps": 0,
		"capped": false,
		"started": false,
		"running": false,       # an engine call has not finished: it waits for a choice
		"mull": [first, 1 - first].filter(func(p): return p != bot_seat),
		"dec": "",              # what the slot waits for: "cmd", "choice" or "mull"
		"values": [],           # the decision's options
		"ban_hash": 0,          # state in which the commands of "ban" did nothing
		"ban": [],
		"probe": {},            # the command being checked for doing nothing
	}


## Drops a slot's game. A game waiting for an answer is ended first, so its
## suspended engine call finishes and nothing keeps the game alive.
func _release(i: int) -> void:
	var s: Dictionary = slots[i]
	if s.has("game"):
		var g: Game = s["game"]
		var ch: Chooser = s["chooser"]
		g.phase = "over"
		var guard := 0
		while ch.pending != null and guard < 1000:
			ch.answer(null)
			guard += 1
		g.chooser = null
	slots[i] = {}


func _apply(i: int, a: int) -> void:
	var s: Dictionary = slots[i]
	if not s.has("game"):
		return
	var values: Array = s["values"]
	if a < 0 or a >= values.size():
		s["error"] = "answer %d out of range (%d)" % [a, values.size()]
		return
	var g: Game = s["game"]
	var value = values[a]
	var dec: String = s["dec"]
	s["dec"] = ""
	s["values"] = []
	s["steps"] += 1
	match dec:
		"mull":
			var p: int = s["mull"].pop_front()
			if value:
				await g.cmd_mulligan(p)
		"choice":
			# The engine resumes here and runs until the next choice or the end of the call.
			(s["chooser"] as Chooser).answer(value)
		"cmd":
			_command(s, g.turn_player, value)


## Starts a command; it finishes at once or stops at an agent seat's choice.
func _command(s: Dictionary, p: int, cmd: Dictionary) -> void:
	var g: Game = s["game"]
	if not ALWAYS_CHANGE.has(cmd["cmd"]):
		s["probe"] = {"hash": g.state_hash(), "cmd": cmd, "p": p}
	_launch(s, func(): await g.run_command(p, cmd))


## Runs an engine call without waiting for it: it returns when the call is
## done or suspended at a choice ("running" tells which).
func _launch(s: Dictionary, call: Callable) -> void:
	s["running"] = true
	await call.call()
	s["running"] = false


## A command that changed nothing is not offered again in the same state.
func _check_probe(s: Dictionary) -> void:
	var probe: Dictionary = s["probe"]
	if probe.is_empty():
		return
	s["probe"] = {}
	var g: Game = s["game"]
	if g.phase == "over" or g.turn_player != int(probe["p"]):
		return
	var h := g.state_hash()
	if h != int(probe["hash"]):
		return
	if int(s["ban_hash"]) != h:
		s["ban_hash"] = h
		s["ban"] = []
	s["ban"].append(probe["cmd"])


func _allowed(s: Dictionary, g: Game, p: int) -> Array:
	var cmds := g.legal_commands(p)
	var ban: Array = s["ban"]
	if ban.is_empty():
		return cmds
	if g.state_hash() != int(s["ban_hash"]):
		s["ban"] = []
		return cmds
	return cmds.filter(func(c): return not ban.has(c))


## Plays bot seats and forced moves and hands the next agent decision (or the result) back.
func _advance(i: int) -> Dictionary:
	var s: Dictionary = slots[i]
	if s.has("error"):
		var msg: String = s["error"]
		_release(i)
		return {"i": i, "st": "err", "msg": msg}
	if not s.has("game"):
		return {"i": i, "st": "err", "msg": "empty slot"}
	var g: Game = s["game"]
	var ch: Chooser = s["chooser"]
	while true:
		if ch.pending != null:
			if int(s["steps"]) > 2 * STEP_CAP:
				_release(i)
				return {"i": i, "st": "err", "msg": "endless choices"}
			var req: Dictionary = ch.pending
			var cv := AIView.choice_view(g, req)
			var values: Array = cv["values"]
			if values.size() == 1:
				s["steps"] += 1
				ch.answer(values[0])
				continue
			s["dec"] = "choice"
			s["values"] = values
			return {"i": i, "st": "dec", "p": int(req.get("player", g.turn_player)), "s": cv["view"]}
		if s["running"]:
			_release(i)
			return {"i": i, "st": "err", "msg": "engine call suspended without a choice"}
		_check_probe(s)
		if not s["started"]:
			var mull: Array = s["mull"]
			if not mull.is_empty():
				s["dec"] = "mull"
				s["values"] = [false, true]
				return {"i": i, "st": "dec", "p": mull[0], "s": AIView.mulligan_view(g, mull[0])}
			s["started"] = true
			_launch(s, func(): await g.start_game())
			continue
		if g.phase != "over" and (g.turn_number > TURN_CAP or int(s["steps"]) > STEP_CAP):
			_finish_by_hp(g)
			s["capped"] = true
		if g.phase == "over":
			return _done(i)
		if g.phase == "handoff":
			_launch(s, func(): await g.cmd_start_turn())
			continue
		var p := g.turn_player
		var cmds := _allowed(s, g, p)
		if cmds.is_empty():
			_release(i)
			return {"i": i, "st": "err", "msg": "no legal commands in phase %s" % g.phase}
		# A single legal command is no choice: play it without asking the agent.
		if cmds.size() == 1:
			s["steps"] += 1
			_command(s, p, cmds[0])
			continue
		if p == int(s["bot_seat"]):
			s["steps"] += 1
			_command(s, p, _bot_pick(s, cmds))
			continue
		s["dec"] = "cmd"
		s["values"] = cmds
		return {"i": i, "st": "dec", "p": p, "s": AIView.command_view(g, p, cmds)}
	return {}


func _finish_by_hp(g: Game) -> void:
	g.phase = "over"
	if g.players[0].hp > g.players[1].hp:
		g.winner = 0
	elif g.players[1].hp > g.players[0].hp:
		g.winner = 1
	else:
		g.winner = -1


func _done(i: int) -> Dictionary:
	var s: Dictionary = slots[i]
	var g: Game = s["game"]
	var r := {"i": i, "st": "done", "w": g.winner, "t": g.turn_number,
		"hp": [g.players[0].hp, g.players[1].hp], "cap": 1 if s["capped"] else 0}
	if not g.fast_mode:
		r["log"] = "\n".join(PackedStringArray(g.log_lines))
	_release(i)
	return r


func _bot_pick(s: Dictionary, cmds: Array) -> Dictionary:
	if s["bot"] == "heuristic":
		return _pick_heuristic(cmds)
	return s["rng"].pick_command(cmds)


## The same rules of thumb as the RL bridge's heuristic opponent.
func _pick_heuristic(cmds: Array) -> Dictionary:
	var attacks := cmds.filter(func(c): return c["cmd"] == "attack")
	if not attacks.is_empty():
		return attacks[0]
	var plays := cmds.filter(func(c): return c["cmd"] == "play")
	if not plays.is_empty():
		return plays[0]
	var floops := cmds.filter(func(c): return c["cmd"] == "floop" or c["cmd"] == "activate")
	if not floops.is_empty():
		return floops[0]
	var begin_atk := cmds.filter(func(c): return c["cmd"] == "begin_attack")
	if not begin_atk.is_empty():
		return begin_atk[0]
	return cmds[cmds.size() - 1]
