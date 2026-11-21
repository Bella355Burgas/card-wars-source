extends SceneTree
## Shared helpers of the card audit tests (tests/cards_audit_<deck>.gd), see docs/CARDS_AUDIT.md.
## Each audit file extends this one and has t_* methods:
##   godot --headless --path . -s res://tests/cards_audit_<deck>.gd [-- <test name part>]

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")


## Answers choice requests from a queue; with an empty queue it picks the
## first option (or skips optional ones when `skip_optional`).
class Scripted:
	var answers: Array = []
	var skip_optional := false
	var asked: Array = []
	func choose(req: Dictionary):
		asked.append(req)
		if not answers.is_empty():
			var a = answers.pop_front()
			if a is Callable:
				return a.call(req)
			return a
		if req.get("optional", false) and skip_optional:
			return null
		var opts: Array = req.get("options", [])
		return null if opts.is_empty() else opts[0]


var failures := 0
var checks := 0
var g
var bot: Scripted


func _initialize() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		only = args[0]
	var tests := []
	for m in get_method_list():
		var n: String = m["name"]
		if n.begins_with("t_") and (only == "" or n.contains(only)):
			tests.append(n)
	tests.sort()
	for t in tests:
		_fresh()
		await call(t)
	print("%s: %d tests, %d checks, %d failed" % [get_script().resource_path.get_file(), tests.size(), checks, failures])
	quit(1 if failures > 0 else 0)


func _fresh(heroes := ["finn", "jake"]) -> void:
	g = Game.new()
	bot = Scripted.new()
	g.chooser = bot
	g.setup(heroes, 0, 7)
	for ps in g.players:
		ps.hero_card = ""
		ps.deck.append_array(ps.hand)
		ps.hand.clear()
	g.turn_number = 3
	g.turn_player = 0
	g.phase = "main"
	g.players[0].actions = 2


func ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("ok   ", what)
	else:
		failures += 1
		printerr("FAIL ", what)
		printerr("     log: ", g.log_lines.slice(-6))
		printerr("     asked: ", bot.asked.slice(-3).map(func(r): return String(r.get("prompt", ""))))


func lands(p: int, type: String) -> void:
	for l in 4:
		g.players[p].lands[l]["type"] = type


func mk(id: String, owner := 0):
	return g._make_card(id, owner)


func put(p: int, id: String, lane: int, owner := -1):
	var c = mk(id, p if owner < 0 else owner)
	await g._put_creature(p, c, lane)
	return c


func build(p: int, id: String, lane: int):
	var c = mk(id, p)
	await g._put_building(p, c, lane)
	return c


func hand(p: int, id: String):
	var c = mk(id, p)
	g.players[p].hand.append(c)
	return c


func top(p: int, id: String):
	var c = mk(id, p)
	g.players[p].deck.append(c)
	return c


func dis(p: int, id: String):
	var c = mk(id, p)
	g.players[p].discard.append(c)
	return c


func play(p: int, c, lane := -1) -> void:
	await g.cmd_play(p, c.uid, lane)


func floop(p: int, lane: int, kind := "creature") -> void:
	await g.cmd_floop(p, kind, lane)


func spot(p: int, lane: int) -> Dictionary:
	return {"p": p, "lane": lane}


func atk(p: int, lane: int) -> int:
	return g.atk_of(p, lane)


func df(p: int, lane: int) -> int:
	return g.def_of(p, lane)


## Ends p's turn without attacks (end_ hooks and cleanup) and starts the next player's.
func pass_turn(p: int) -> void:
	await g._trigger_own(p, "end_")
	await g._end_turn_cleanup(p)
	var n: int = g.next_seat(p)
	g.turn_player = n
	g.turn_number += 1
	await g._start_turn(n)
	g.phase = "main"
