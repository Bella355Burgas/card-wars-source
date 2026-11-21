extends RefCounted
## Turn search for the strongest AI level (policy_agent.gd, `pick_command_async`).
##
## The network picks one command at a time. The search looks a few commands ahead:
## it plays the commands on copies of the game (Game.clone) and scores the positions
## it reaches with the network's value head plus a count of HP and of the damage that
## can reach empty lanes. Nothing the AI cannot see is used:
##  - the opponent's hand and deck are redealt from the cards the AI can assume the
##    opponent holds (their deck list when it is a standard deck, minus the cards in
##    sight; the AI's own list when it is a custom deck), and the AI's own deck is
##    reshuffled; the order and the split between hand and deck are random;
##  - the copies run on the search's own rng, never on the game's rng.
## The network answers the choices inside the copies (greedy).
##
## Config (ai_levels.gd): "samples" determinizations per decision, "width" how many
## commands are tried at each depth (the root first; end_turn is always tried),
## "time_ms" a soft limit per decision (0: none), "yield" false in tests.

const AIView = preload("res://scripts/ai/ai_view.gd")
const CardDB = preload("res://scripts/core/card_db.gd")

const WIN := 5.0            # score of a won or lost game (positions score about -1..1)
const REPLY_MAX := 40       # commands the opponent may play in its answer (see "reply")

## The PolicyAgent with temperature 0. Held weakly: the agent owns this search.
var agent:
	get:
		return _agent_ref.get_ref() if _agent_ref != null else null
	set(value):
		_agent_ref = weakref(value)

var _agent_ref: WeakRef = null
var samples := 3
var width: Array = [8, 3, 2]
var time_ms := 0
var yield_frames := true
var hp_weight := 0.5       # per 25 HP of difference
var open_weight := 0.5     # per 25 ATK on open lanes (ours minus theirs)
var value_weight := 1.0    # the value head's share of a leaf's score
## Leaves after the search's end_turn are scored after the opponent's answer: its turn is
## played on the copy by the network (greedy) before the value is read. Slower.
var reply := false
## Counts of the last decision: positions expanded, positions scored, milliseconds.
var stats := {"nodes": 0, "leaves": 0, "ms": 0}

var _rng := RandomNumberGenerator.new()
var _deadline := 0
var _memo := {}
var _last_yield := 0


class Chooser extends RefCounted:
	var pa                  # PolicyAgent
	var game_ref: WeakRef

	func choose(req: Dictionary):
		return pa.pick_choice(game_ref.get_ref(), req)


func _init(policy_agent, cfg: Dictionary) -> void:
	agent = policy_agent
	samples = int(cfg.get("samples", samples))
	width = cfg.get("width", width)
	time_ms = int(cfg.get("time_ms", time_ms))
	yield_frames = bool(cfg.get("yield", yield_frames))
	hp_weight = float(cfg.get("hp_weight", hp_weight))
	open_weight = float(cfg.get("open_weight", open_weight))
	value_weight = float(cfg.get("value_weight", value_weight))
	reply = bool(cfg.get("reply", reply))


## The command p should play now. Each legal command (bans included) is judged by its
## best continuation, averaged over the determinizations; the best one wins.
func pick(game, p: int, seed_value: int) -> Dictionary:
	var cmds: Array = agent.allowed(game, p)
	if cmds.size() == 1:
		return cmds[0]
	_rng.seed = seed_value
	var t0 := Time.get_ticks_msec()
	stats = {"nodes": 0, "leaves": 0, "ms": 0}
	_deadline = t0 + time_ms if time_ms > 0 else 0
	_last_yield = t0
	var total := PackedFloat64Array()
	total.resize(cmds.size())
	var counted := PackedInt32Array()
	counted.resize(cmds.size())
	for s in samples:
		if s > 0 and _late():
			break
		var world = _determinize(game, p)
		_memo = {}
		for k: int in _order(world, p, cmds, int(width[0])):
			var child = world.clone()
			child.chooser = _chooser(child)
			var before: int = world.state_hash()
			await child.run_command(p, cmds[k])
			if child.state_hash() == before:
				continue
			total[k] += await _node(child, p, 1)
			counted[k] += 1
	var best := -1
	for k in cmds.size():
		if counted[k] == 0:
			continue
		if best < 0 or total[k] / counted[k] > total[best] / counted[best]:
			best = k
	stats["ms"] = Time.get_ticks_msec() - t0
	if best < 0:
		return agent.pick_command(game, p)
	return cmds[best]


## Best score for p over the continuations of g, a position in the middle of p's turn
## after `level` commands of the search.
func _node(g, p: int, level: int) -> float:
	stats["nodes"] += 1
	if g.phase == "over":
		return _terminal(g, p)
	if g.turn_player != p or level >= width.size() or _late():
		return await _leaf(g, p)
	var key := hash([g.state_hash(), level])
	if _memo.has(key):
		return _memo[key]
	var cmds: Array = g.legal_commands(p)
	var best := -INF
	for k: int in _order(g, p, cmds, int(width[level])):
		var child = g.clone()
		child.chooser = _chooser(child)
		var before: int = g.state_hash()
		await child.run_command(p, cmds[k])
		if child.state_hash() == before:
			continue
		best = maxf(best, await _node(child, p, level + 1))
		await _yield_now()
	if best == -INF:
		best = await _leaf(g, p)
	_memo[key] = best
	return best


## Indices of the commands worth a look: the `count` best by the network, and end_turn.
func _order(g, p: int, cmds: Array, count: int) -> Array:
	var scores: PackedFloat32Array = agent.logits(AIView.command_view(g, p, cmds))
	var ranked := []
	var end := -1
	for k in cmds.size():
		if cmds[k]["cmd"] == "end_turn":
			end = k
		ranked.append([scores[k] if k < scores.size() else -INF, k])
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for e in ranked:
		if out.size() >= count:
			break
		if e[1] != end:
			out.append(e[1])
	if end >= 0:
		out.append(end)
	return out


## Score of an undecided position for p: the value head's view of the player to move
## (flipped when that is the opponent) plus the count.
func _leaf(g, p: int) -> float:
	stats["leaves"] += 1
	if reply and g.phase != "over" and g.turn_player != p:
		g = await _reply(g, p)
	if g.phase == "over":
		return _terminal(g, p)
	var mover: int = g.turn_player
	var v := 0.0
	if value_weight != 0.0:
		v = value_weight * agent.value(AIView.state_view(g, mover))
	if mover != p:
		v = -v
	return v + _count(g, p)


## The copy of g after the opponent's turn, played by the network: each command is its
## best by the logits, and the turn ends when the network has nothing to change.
func _reply(g, p: int):
	var c = g.clone()
	c.chooser = _chooser(c)
	var o: int = c.turn_player
	for _i in REPLY_MAX:
		if c.phase == "over" or c.turn_player != o:
			break
		var cmd: Dictionary = agent.pick_command(c, o)
		var before: int = c.state_hash()
		await c.run_command(o, cmd)
		if c.state_hash() == before:
			await c.run_command(o, {"cmd": "end_turn"})
			break
	return c


## HP and open-lane damage of p against the opponent, in the value's units.
func _count(g, p: int) -> float:
	var o := 1 - p
	var ours := 0
	var theirs := 0
	for lane in 4:
		var mine = g.players[p].creatures[lane]
		var foe = g.players[o].creatures[lane]
		if mine != null and foe == null:
			ours += g.atk_of(p, lane)
		elif foe != null and mine == null:
			theirs += g.atk_of(o, lane)
	var hp_diff := float(g.players[p].hp - g.players[o].hp) / 25.0
	return hp_weight * hp_diff + open_weight * float(ours - theirs) / 25.0


func _terminal(g, p: int) -> float:
	return WIN if g.winner == p else -WIN


func _late() -> bool:
	return _deadline > 0 and Time.get_ticks_msec() >= _deadline


## Gives the frame back every ~10 ms, so the game keeps drawing while the AI thinks.
func _yield_now() -> void:
	if not yield_frames or Time.get_ticks_msec() - _last_yield < 10:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.process_frame
	_last_yield = Time.get_ticks_msec()


func _chooser(g) -> Chooser:
	var c := Chooser.new()
	c.pa = agent
	c.game_ref = weakref(g)
	return c


## A copy of the game in which everything the AI cannot see is redealt.
func _determinize(game, p: int):
	var world = game.clone()
	world.rng.seed = _rng.randi()
	_redeal_opponent(world, p)
	world.reshuffle(p)
	return world


## The opponent's hand and deck get the cards the AI can assume they hold: their deck
## list minus every card in sight. The cards are dealt by place (the hand first, then
## the deck), so the outcome depends on the sizes and the cards in sight, never on
## which hidden card is where.
func _redeal_opponent(w, p: int) -> void:
	var o := 1 - p
	var ps = w.players[o]
	var assumed := _assumed_ids(w, p)
	var left := {}
	for id: String in assumed:
		left[id] = int(left.get(id, 0)) + 1
	for c in w.all_cards(o):
		var zone: String = w.where(c.uid)["zone"]
		if zone != "hand" and zone != "deck" and int(left.get(c.id, 0)) > 0:
			left[c.id] -= 1
	var pool := []
	var ids: Array = left.keys()
	ids.sort()
	for id: String in ids:
		for n in int(left[id]):
			pool.append(id)
	_shuffle(pool)
	var hidden: Array = ps.hand + ps.deck
	while pool.size() < hidden.size() and not assumed.is_empty():
		pool.append(assumed[_rng.randi() % assumed.size()])
	for i in mini(hidden.size(), pool.size()):
		hidden[i].id = pool[i]
		hidden[i].used_life = false
		hidden[i].no_return = false


## The cards the AI may assume the opponent started with: a standard deck is public;
## for a custom deck the AI's own list stands in.
func _assumed_ids(w, p: int) -> Array:
	var hero: String = w.players[1 - p].hero
	var out := []
	if CardDB.is_custom(hero):
		for c in w.all_cards(p):
			out.append(c.id)
	else:
		var deck: Dictionary = CardDB.hero(hero)["deck"]
		for id: String in deck:
			for n in int(deck[id]):
				out.append(id)
	return out


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
