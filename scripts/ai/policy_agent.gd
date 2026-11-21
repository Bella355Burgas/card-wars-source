extends RefCounted
## The self-play network (rl_training/policy.py) for the AI seats of the game.
##
## Weights come from data/ai_policy.json (rl_training/export_model.py). The
## network sees the same views as in training (ai_view.gd), encoded the way
## rl_training/cw_data.py encodes them, and it decides the same things: the
## starting hand, every command (hero abilities included) and every choice a
## card asks for. A command that changed nothing is banned in that state, as in
## training (ban_command). rl_training/check_parity.py checks this file
## against the PyTorch model.
##
## With temperature 0 the agent takes the best-scored option; above 0 it draws
## from the softmax of the scores divided by the temperature (the weaker
## levels in ai_levels.gd), with its own RNG, never the game's.

const AIView = preload("res://scripts/ai/ai_view.gd")
const Search = preload("res://scripts/ai/search.gd")
const AIHelper = preload("res://scripts/ai/ai_helper.gd")
const CardDB = preload("res://scripts/core/card_db.gd")

const MODEL_PATH := "res://data/ai_policy.json"
const FORMAT := 1
const VALUE_HIDDEN := 128

# Must match rl_training/cw_data.py.
const LANDS := ["plain", "corn", "cute", "swamp", "sandy", "ice", "dead", "rainbow"]
const LANE_COUNT := 4
const NUM_SLOTS := 29
const DYN_DIM := 8
const GLOB_DIM := 117
const NUM_CODES := 24
const SIDES := 3
const OPTION_IDX := 5
const POOLS := 3
const POOL_MAX := 60
const CHOICE_KINDS := 7
const HAND_SLOTS := 10
const LANE_SLOTS := [0, 4, 8, 12]      # own creature, own building, opponent's creature, opponent's building

static var _models := {}               # path -> Model (or null when the file is missing or broken)
static var _jobs := {}                 # path -> WorkerThreadPool task reading it (preload_model)
static var _borrowed := {}             # hash of a network's card ids -> {unknown card: row}, see _borrow_rows
static var _lock := Mutex.new()        # _models and _borrowed are filled from the reading threads

var model: Model
var temperature := 0.0
var rng := RandomNumberGenerator.new()
var ban_hash := 0
var ban: Array = []
## Set to an Array to collect {"s": view, "l": logits, "v": value} of every decision (parity test).
var trace = null
## Turn search (scripts/ai/search.gd); null when the level plays the network's own choice.
var search = null
## Seed of the search's determinizations; -1 draws a new one for every decision.
var search_seed := -1
## «Бесконечный поезд»: >= 0 seeds the RNG before every decision from this, the game's state hash and
## what is decided, so a decision depends on the state only (not on the decisions before it or
## an undo): the server asks the same network about a recorded run and gets the same answers
## (scripts/train/run_check.gd).
var seed_base := -1
## The run check: >= 0 is the option the recorded game took. _decide returns it and sets `strayed`
## when the network would have taken another one, unless the two are so close that the rounding of
## another CPU could tell them apart (LOGIT_TOL, DRAW_TOL).
var expect := -1
var strayed := false
const LOGIT_TOL := 0.001
const DRAW_TOL := 0.0001


class Model extends RefCounted:
	var cd: int                 # card embedding size
	var sd: int                 # slot feature size
	var hid: int
	var ch: int                 # option hidden size
	var enc_h: int
	var state_in: int
	var cand_in: int
	var index := {}             # card id -> row of emb
	var vocab := {}             # word stem -> column of enc1_w
	var vocab_n: int
	var emb: PackedFloat32Array
	var enc1_w: PackedFloat32Array
	var enc1_b: PackedFloat32Array
	var enc2_w: PackedFloat32Array
	var enc2_b: PackedFloat32Array
	var slot_w: PackedFloat32Array
	var state_w: PackedFloat32Array
	var state_b: PackedFloat32Array
	var state2_w: PackedFloat32Array
	var state2_b: PackedFloat32Array
	var cstate_w: PackedFloat32Array
	var cstate_b: PackedFloat32Array
	var cfeat_w: PackedFloat32Array
	var cfc_w: PackedFloat32Array
	var cfc_b: PackedFloat32Array
	var cout_w: PackedFloat32Array
	var cout_b: float
	var has_value := false      # the value head is exported (needed by the search)
	var value1_w: PackedFloat32Array
	var value1_b: PackedFloat32Array
	var value2_w: PackedFloat32Array
	var value2_b: PackedFloat32Array
	var slot_card: Array = []   # per card row: slot_w (card part) * emb + bias
	var cand_card: Array = []   # per card row: cfeat_w (card part) * emb
	var card_col: int           # first column of the card block in cfeat_w


## search_cfg: how the level searches (see scripts/ai/search.gd); empty for none.
## Searching needs the value head and a greedy level (temperature 0).
func _init(path := MODEL_PATH, temp := 0.0, search_cfg: Dictionary = {}) -> void:
	model = _load(path)
	temperature = temp
	rng.randomize()
	if model == null:
		push_error("PolicyAgent: no usable model at " + path)
	elif not search_cfg.is_empty() and temp <= 0.0 and model.has_value:
		search = Search.new(self, search_cfg)


## True when the exported network is there (the game falls back to the old agent otherwise).
static func is_available(path := MODEL_PATH) -> bool:
	return _load(path) != null


## Starts reading the network in a background thread: it takes a few tenths of a second,
## and the window should not stand still for them (ai_levels.gd warm). Main thread only.
static func preload_model(path := MODEL_PATH) -> void:
	_lock.lock()
	var known := _models.has(path)
	_lock.unlock()
	if known or _jobs.has(path):
		return
	CardDB.ensure_loaded()      # the thread only reads it
	_jobs[path] = WorkerThreadPool.add_task(_read.bind(path), false, "AI network")


## True when the network can be had without waiting for its thread. Main thread only.
static func is_ready(path := MODEL_PATH) -> bool:
	if _jobs.has(path):
		if not WorkerThreadPool.is_task_completed(_jobs[path]):
			return false
		WorkerThreadPool.wait_for_task_completion(_jobs[path])
		_jobs.erase(path)
	return true


# ---------------------------------------------------------------- decisions

func pick_command(game, p: int) -> Dictionary:
	var cmds := allowed(game, p)
	if cmds.size() == 1:
		return cmds[0]
	_reseed(game, "c%d" % ban.size())
	return cmds[_decide(AIView.command_view(game, p, cmds))]


## seed_base: the RNG of the next decision from the state (what: what is decided there).
func _reseed(game, what: String) -> void:
	if seed_base >= 0:
		rng.seed = ("%d:%d:%s" % [seed_base, game.state_hash(), what]).hash()


## The command to play: with a search, it looks ahead first. A coroutine, so call it
## with await (it yields a frame now and then while it searches).
func pick_command_async(game, p: int) -> Dictionary:
	if search == null or game.three():      # the search plays a game for two
		return pick_command(game, p)
	var seed_value := search_seed if search_seed >= 0 else rng.randi()
	return await search.pick(game, p, seed_value)


## Legal commands minus those that did nothing in this very state.
func allowed(game, p: int) -> Array:
	var cmds: Array = game.legal_commands(p)
	if ban.is_empty():
		return cmds
	if game.state_hash() != ban_hash:
		ban = []
		return cmds
	return cmds.filter(func(c): return not ban.has(c))


## The command left the game exactly as it was (state hash `before`): it is not
## offered again until something changes.
func ban_command(before: int, cmd: Dictionary) -> void:
	if before != ban_hash:
		ban_hash = before
		ban = []
	ban.append(cmd)


## Answer to a choice request of the engine (null declines an optional choice).
func pick_choice(game, req: Dictionary):
	req = AIHelper.without_own_players(game, req)
	var plain: Array = AIHelper.obvious(game, req)
	if not plain.is_empty():
		return plain[0]
	var cv := AIView.choice_view(game, req)
	var values: Array = cv["values"]
	if values.is_empty():
		return null
	if values.size() == 1:
		return values[0]
	_reseed(game, "q%d:%s" % [values.size(), str(req.get("prompt", ""))])
	return values[_decide(cv["view"])]


## The run check (scripts/train/run_check.gd): would this agent have played `cmd`, answered `answer`,
## changed its starting hand (`yes`)? The same steps as pick_command, pick_choice and mulligan.
func agrees_command(game, p: int, cmd: Dictionary) -> bool:
	var cmds := allowed(game, p)
	var k := cmds.find(cmd)
	if k < 0 or cmds.size() == 1:
		return k == 0
	_reseed(game, "c%d" % ban.size())
	return _agrees(AIView.command_view(game, p, cmds), k)


func agrees_choice(game, req: Dictionary, answer) -> bool:
	req = AIHelper.without_own_players(game, req)
	var plain: Array = AIHelper.obvious(game, req)
	if not plain.is_empty():
		return answer == plain[0]
	var cv := AIView.choice_view(game, req)
	var values: Array = cv["values"]
	if values.size() <= 1:
		return answer == (values[0] if values.size() == 1 else null)
	var k := values.find(answer)
	if k < 0:
		return false
	_reseed(game, "q%d:%s" % [values.size(), str(req.get("prompt", ""))])
	return _agrees(cv["view"], k)


func agrees_mulligan(game, p: int, yes: bool) -> bool:
	_reseed(game, "m%d" % p)
	return _agrees(AIView.mulligan_view(game, p), 1 if yes else 0)


func _agrees(view: Dictionary, k: int) -> bool:
	expect = k
	strayed = false
	_decide(view)
	expect = -1
	return not strayed


## True: change the starting hand.
func mulligan(game, p: int) -> bool:
	_reseed(game, "m%d" % p)
	return _decide(AIView.mulligan_view(game, p)) == 1


func _decide(view: Dictionary) -> int:
	var l := logits(view)
	if trace != null:
		trace.append({"s": view, "l": Array(l), "v": value(view) if model.has_value else 0.0})
	var best := 0
	for k in l.size():
		if l[k] > l[best]:
			best = k
	if temperature <= 0.0:
		if expect >= 0 and expect != best and not (expect < l.size() and l[best] - l[expect] < LOGIT_TOL):
			strayed = true
		return best if expect < 0 else expect
	# The draw by hand (not rng.rand_weighted): the run check needs to know where it fell.
	var sums := PackedFloat64Array()      # sums[k]: the weights before option k
	var total := 0.0
	for k in l.size():
		sums.append(total)
		total += exp((l[k] - l[best]) / temperature)
	var r := rng.randf() * total
	var pick := l.size() - 1
	for k in range(1, l.size()):
		if r < sums[k]:
			pick = k - 1
			break
	if expect < 0:
		return pick
	if expect != pick:
		# The neighbour across a border the draw nearly touched is as good as the pick.
		var border: float = sums[expect] if expect == pick + 1 else (sums[pick] if expect == pick - 1 else -1.0)
		if border < 0.0 or absf(r - border) > DRAW_TOL * total:
			strayed = true
	return expect


# ---------------------------------------------------------------- forward pass

## Scores of a view's options (policy.py CardWarsPolicy.forward for one decision).
func logits(v: Dictionary) -> PackedFloat32Array:
	var t := _trunk(v)
	return _option_scores(v, t[0], t[1])


## Expected result for the player who decides in v: -1 loss .. +1 win (policy.py value
## head, the same state summary as the options use).
func value(v: Dictionary) -> float:
	return _value_of(_trunk(v)[0])


## The state summary h of a view (policy.py CardWarsPolicy.forward up to state_fc2), and
## the slot features x that the options read too: [h, x].
func _trunk(v: Dictionary) -> Array:
	var m := model
	var ids := PackedInt32Array()
	ids.resize(NUM_SLOTS)
	var dyn := PackedFloat32Array()
	dyn.resize(NUM_SLOTS * DYN_DIM)
	_encode_slots(v, ids, dyn)

	# Slots: relu(slot_proj([embedding, dyn])).
	var sd := m.sd
	var row_w := m.cd + DYN_DIM
	var x := PackedFloat32Array()
	x.resize(NUM_SLOTS * sd)
	for s in NUM_SLOTS:
		var pre: PackedFloat32Array = m.slot_card[ids[s]]
		for r in sd:
			var acc: float = pre[r]
			for k in DYN_DIM:
				var dv := dyn[s * DYN_DIM + k]
				if dv != 0.0:
					acc += m.slot_w[r * row_w + m.cd + k] * dv
			x[s * sd + r] = maxf(acc, 0.0)

	var inp := PackedFloat32Array(x)
	inp.append_array(_glob(v))
	inp.append_array(_prompt(v.get("prompt", [])))
	inp.append_array(_pools(v["pools"]))
	var h := _affine(m.state_w, m.state_b, inp, m.hid, true)
	return [_affine(m.state2_w, m.state2_b, h, m.hid, true), x]


## Scores of the options of v from the state summary h and the slot features x.
func _option_scores(v: Dictionary, h: PackedFloat32Array, x: PackedFloat32Array) -> PackedFloat32Array:
	var m := model
	var cs := _affine(m.cstate_w, m.cstate_b, h, m.ch, false)

	var cands: Array = v["cands"]
	var out := PackedFloat32Array()
	out.resize(cands.size())
	var cache := {}             # [block, slot] -> cfeat_w block * x[slot]
	var ci := m.cand_in
	for k in cands.size():
		var cand: Array = cands[k]
		var code := int(cand[0])
		var lane := int(cand[2])
		var lane_col := lane if lane >= 0 else LANE_COUNT
		var slot := int(cand[3])
		var cols := [code, NUM_CODES + lane_col, NUM_CODES + LANE_COUNT + 1 + int(cand[4]),
			NUM_CODES + LANE_COUNT + 1 + SIDES + int(cand[5])]
		var f := PackedFloat32Array(cs)
		var card_pre: PackedFloat32Array = m.cand_card[m.index.get(String(cand[1]), 0)]
		for r in m.ch:
			var acc: float = f[r] + card_pre[r]
			for c: int in cols:
				acc += m.cfeat_w[r * ci + c]
			f[r] = acc
		var refs := [slot]
		for base: int in LANE_SLOTS:
			refs.append(base + lane if lane >= 0 else -1)
		for j in refs.size():
			var s: int = refs[j]
			if s < 0 or s >= NUM_SLOTS:
				continue
			var key := j * NUM_SLOTS + s
			if not cache.has(key):
				cache[key] = _block(m, x, j, s)
			var add: PackedFloat32Array = cache[key]
			for r in m.ch:
				f[r] += add[r]
		for r in m.ch:
			f[r] = maxf(f[r], 0.0)
		var h2 := _affine(m.cfc_w, m.cfc_b, f, m.ch, true)
		var logit := m.cout_b
		for r in m.ch:
			logit += m.cout_w[r] * h2[r]
		out[k] = logit
	return out


## Value head: Linear 256 -> 128, ReLU, Linear 128 -> 1 on the state summary h.
func _value_of(h: PackedFloat32Array) -> float:
	var m := model
	var a := _affine(m.value1_w, m.value1_b, h, VALUE_HIDDEN, true)
	return _affine(m.value2_w, m.value2_b, a, 1, false)[0]


## cfeat_w columns of slot block j (0: the option's own slot, 1..4: its lane) times x[s].
static func _block(m: Model, x: PackedFloat32Array, j: int, s: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(m.ch)
	var col0 := m.card_col + m.cd + j * m.sd
	for r in m.ch:
		var acc := 0.0
		var base := r * m.cand_in + col0
		for c in m.sd:
			acc += m.cfeat_w[base + c] * x[s * m.sd + c]
		out[r] = acc
	return out


func _encode_slots(v: Dictionary, ids: PackedInt32Array, dyn: PackedFloat32Array) -> void:
	var idx: Dictionary = model.index
	for side in 2:
		var cr: Array = v["cr"][side]
		var bd: Array = v["bd"][side]
		for lane in LANE_COUNT:
			var c = cr[lane]
			if c != null:
				var s := (0 if side == 0 else 8) + lane
				ids[s] = idx.get(String(c[0]), 0)
				_set_dyn(dyn, s, [float(c[1]) / 15.0, float(c[2]) / 20.0, float(c[3]) / 20.0,
					float(c[4]), float(c[5]), float(c[6]), 1.0, float(c[7])])
			var b = bd[lane]
			if b != null:
				var s2 := (4 if side == 0 else 12) + lane
				ids[s2] = idx.get(String(b[0]), 0)
				_set_dyn(dyn, s2, [0.0, 0.0, 0.0, float(b[1]), float(b[2]), 0.0, 1.0, float(b[3])])
	var hand: Array = v["hand"]
	for k in mini(hand.size(), HAND_SLOTS):
		var h: Array = hand[k]
		ids[16 + k] = idx.get(String(h[0]), 0)
		_set_dyn(dyn, 16 + k, [float(h[1]) / 3.0, float(h[2]), float(h[3]), 0.0, 0.0, 0.0, 1.0, 0.0])
	var hd: Array = v["hero_dyn"]
	ids[26] = idx.get(String(v["hero"][0]), 0)
	ids[27] = idx.get(String(v["hero"][1]), 0)
	_set_dyn(dyn, 26, [float(hd[0]), float(hd[1]), 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	_set_dyn(dyn, 27, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	if String(v["src"]) != "":
		ids[28] = idx.get(String(v["src"]), 0)
		_set_dyn(dyn, 28, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])


static func _set_dyn(dyn: PackedFloat32Array, s: int, values: Array) -> void:
	for k in DYN_DIM:
		dyn[s * DYN_DIM + k] = values[k]


static func _glob(v: Dictionary) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	var hp: Array = v["hp"]
	var act: Array = v["act"]
	g.append_array([float(hp[0]) / 25.0, float(hp[1]) / 25.0, float(act[0]) / 2.0, float(act[1]) / 2.0,
		float(v["t"]) / 30.0, float(v["first"]), float(v["mine"])])
	g.append_array(_onehot(3, int(v["ph"])))
	g.append_array(_onehot(3, int(v["mode"])))
	g.append_array(_onehot(CHOICE_KINDS, int(v["ck"])))
	g.append(float(v["opt"]))
	var hd: Array = v["hero_dyn"]
	g.append_array([float(v["deck"][0]) / 40.0, float(v["deck"][1]) / 40.0,
		float(v["disc"][0]) / 40.0, float(v["disc"][1]) / 40.0,
		float(v["hand_n"][0]) / 10.0, float(v["hand_n"][1]) / 10.0, float(hd[0]), float(hd[1])])
	for side in 2:
		for l: Array in v["lands"][side]:
			var li := LANDS.find(String(l[0]))
			g.append_array(_onehot(LANDS.size() + 1, li if li >= 0 else LANDS.size()))
			g.append(float(l[1]))
			g.append(float(l[2]))
	return g


static func _onehot(n: int, k: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	if k >= 0 and k < n:
		a[k] = 1.0
	return a


## The prompt's words through the card encoder (a card row with only word features).
func _prompt(words: Array) -> PackedFloat32Array:
	var m := model
	var h := PackedFloat32Array(m.enc1_b)
	for w in words:
		var j: int = m.vocab.get(String(w), -1)
		if j < 0:
			continue
		for r in m.enc_h:
			h[r] += m.enc1_w[r * m.vocab_n + j]
	for r in m.enc_h:
		h[r] = maxf(h[r], 0.0)
	return _affine(m.enc2_w, m.enc2_b, h, m.cd, false)


## Sums of the card embeddings of each pile.
func _pools(pools: Array) -> PackedFloat32Array:
	var m := model
	var out := PackedFloat32Array()
	out.resize(POOLS * m.cd)
	for k in POOLS:
		var ids: Array = pools[k]
		for j in mini(ids.size(), POOL_MAX):
			var row: int = m.index.get(String(ids[j]), 0)
			if row == 0:
				continue
			for c in m.cd:
				out[k * m.cd + c] += m.emb[row * m.cd + c]
	return out


## w * x + b (w is rows x x.size(), row-major); zero inputs are skipped.
static func _affine(w: PackedFloat32Array, b: PackedFloat32Array, x: PackedFloat32Array, rows: int,
		relu: bool) -> PackedFloat32Array:
	var cols := x.size()
	var acc := PackedFloat64Array()
	acc.resize(rows)
	for r in rows:
		acc[r] = b[r]
	for c in cols:
		var xc := x[c]
		if xc == 0.0:
			continue
		for r in rows:
			acc[r] += w[r * cols + c] * xc
	var out := PackedFloat32Array()
	out.resize(rows)
	for r in rows:
		out[r] = maxf(acc[r], 0.0) if relu else acc[r]
	return out


# ---------------------------------------------------------------- loading

## The network at path (null when it is missing or broken): read once, then kept.
## Main thread only; a read started by preload_model is waited for.
static func _load(path: String) -> Model:
	if _jobs.has(path):
		WorkerThreadPool.wait_for_task_completion(_jobs[path])
		_jobs.erase(path)
	_lock.lock()
	var known := _models.has(path)
	_lock.unlock()
	if not known:
		_read(path)
	_lock.lock()
	var m: Model = _models[path]
	_lock.unlock()
	return m


## Reads the network into _models (from the main thread or a WorkerThreadPool task).
static func _read(path: String) -> void:
	var m := _parse(path)
	_lock.lock()
	_models[path] = m
	_lock.unlock()


static func _parse(path: String) -> Model:
	if not FileAccess.file_exists(path):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("format", 0)) != FORMAT:
		push_error("PolicyAgent: %s is not a model of format %d" % [path, FORMAT])
		return null
	var c: Dictionary = data["const"]
	if int(c["num_slots"]) != NUM_SLOTS or int(c["glob_dim"]) != GLOB_DIM or int(c["num_codes"]) != NUM_CODES \
			or int(c["dyn_dim"]) != DYN_DIM or int(c["pools"]) != POOLS:
		push_error("PolicyAgent: %s was exported for other inputs; update policy_agent.gd" % path)
		return null
	var m := Model.new()
	var dims: Dictionary = data["dims"]
	m.cd = int(dims["card_dim"])
	m.sd = int(dims["slot_dim"])
	m.hid = int(dims["hidden"])
	m.ch = int(dims["cand_hidden"])
	var ids: Array = data["ids"]
	for k in ids.size():
		if k > 0:
			m.index[String(ids[k])] = k
	_borrow_rows(m)
	var vocab: Array = data["vocab"]
	for k in vocab.size():
		m.vocab[String(vocab[k])] = k
	m.vocab_n = vocab.size()
	m.emb = _arr(data["emb"])
	m.enc1_w = _arr(data["enc1_w"])
	m.enc1_b = _arr(data["enc1_b"])
	m.enc_h = int(data["enc1_w"]["rows"])
	m.enc2_w = _arr(data["enc2_w"])
	m.enc2_b = _arr(data["enc2_b"])
	m.slot_w = _arr(data["slot_w"])
	var slot_b := _arr(data["slot_b"])
	m.state_w = _arr(data["state_w"])
	m.state_b = _arr(data["state_b"])
	m.state_in = int(data["state_w"]["cols"])
	m.state2_w = _arr(data["state2_w"])
	m.state2_b = _arr(data["state2_b"])
	m.cstate_w = _arr(data["cstate_w"])
	m.cstate_b = _arr(data["cstate_b"])
	m.cfeat_w = _arr(data["cfeat_w"])
	m.cand_in = int(data["cfeat_w"]["cols"])
	m.cfc_w = _arr(data["cfc_w"])
	m.cfc_b = _arr(data["cfc_b"])
	m.cout_w = _arr(data["cout_w"])
	m.cout_b = _arr(data["cout_b"])[0]
	if data.has("value1_w") and data.has("value2_w"):
		m.has_value = true
		m.value1_w = _arr(data["value1_w"])
		m.value1_b = _arr(data["value1_b"])
		m.value2_w = _arr(data["value2_w"])
		m.value2_b = _arr(data["value2_b"])
	m.card_col = NUM_CODES + LANE_COUNT + 1 + SIDES + OPTION_IDX
	if m.state_in != NUM_SLOTS * m.sd + GLOB_DIM + m.cd + POOLS * m.cd \
			or m.cand_in != m.card_col + m.cd + m.sd * (1 + LANE_SLOTS.size()):
		push_error("PolicyAgent: %s has unexpected layer sizes" % path)
		return null
	# Card parts that do not depend on the game: computed once per card.
	var n_ids := ids.size()
	var row_w := m.cd + DYN_DIM
	for k in n_ids:
		var sc := PackedFloat32Array()
		sc.resize(m.sd)
		for r in m.sd:
			var acc: float = slot_b[r]
			for c2 in m.cd:
				acc += m.slot_w[r * row_w + c2] * m.emb[k * m.cd + c2]
			sc[r] = acc
		m.slot_card.append(sc)
		var cc := PackedFloat32Array()
		cc.resize(m.ch)
		for r in m.ch:
			var acc2 := 0.0
			for c2 in m.cd:
				acc2 += m.cfeat_w[r * m.cand_in + m.card_col + c2] * m.emb[k * m.cd + c2]
			cc[r] = acc2
		m.cand_card.append(cc)
	print("PolicyAgent: loaded %s (%d training games)" % [path, int(data.get("games", 0))])
	return m


## Cards the model was not trained on borrow the row of the most alike card it knows
## (kind, land, cost, ATK, DEF, floop), so the AI plays them like that card. The networks
## of the levels know the same cards, so the search is done once for all of them.
static func _borrow_rows(m: Model) -> void:
	var key := str(m.index.keys()).hash()
	_lock.lock()
	var rows: Dictionary = _borrowed.get(key, {})
	_lock.unlock()
	if rows.is_empty():
		rows = _find_borrowed(m)
		_lock.lock()
		_borrowed[key] = rows
		_lock.unlock()
	for id in rows:
		m.index[id] = rows[id]


## {card the model does not know: row of the most alike card it knows}.
static func _find_borrowed(m: Model) -> Dictionary:
	var rows := {}
	var known := []
	for id in m.index:
		if CardDB.has_def(id):
			known.append(id)
	for id in CardDB.card_ids():
		if m.index.has(id):
			continue
		var d: Dictionary = CardDB.get_def(id)
		var best := ""
		var best_score := INF
		for k in known:
			var e: Dictionary = CardDB.get_def(k)
			var score := 0.0
			score += 0.0 if e["kind"] == d["kind"] else 100.0
			score += 0.0 if e["land"] == d["land"] else 3.0
			score += absf(float(e["cost"]) - float(d["cost"])) * 4.0
			score += absf(float(e.get("atk", 0)) - float(d.get("atk", 0))) * 1.0
			score += absf(float(e.get("def", 0)) - float(d.get("def", 0))) * 0.5
			score += 0.0 if bool(e.get("floop", false)) == bool(d.get("floop", false)) else 2.0
			if score < best_score:
				best_score = score
				best = k
		if best != "":
			rows[id] = m.index[best]
	return rows


static func _arr(d: Dictionary) -> PackedFloat32Array:
	return PackedFloat32Array(d["data"])
