class_name PPOAgent
extends RefCounted
## Standalone GDScript PPO Neural Network Inference Engine.
## Runs forward pass on trained MaskablePPO weights without Python or external dependencies.

const AIEncoder = preload("res://scripts/ai/ai_encoder.gd")
const MODEL_PATH := "res://data/ai_model.json"

static var _loaded := false
static var _w1: Array = []  # 128 rows of 181 floats
static var _b1: PackedFloat32Array = PackedFloat32Array()
static var _w2: Array = []  # 128 rows of 128 floats
static var _b2: PackedFloat32Array = PackedFloat32Array()
static var _w_out: Array = []  # 64 rows of 128 floats
static var _b_out: PackedFloat32Array = PackedFloat32Array()

var rng := RandomNumberGenerator.new()


func _init() -> void:
	ensure_loaded()
	rng.randomize()


static func ensure_loaded() -> void:
	if _loaded:
		return
	
	AIEncoder.init()
	var f := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if f == null:
		push_error("PPOAgent: Model file not found at " + MODEL_PATH)
		return
	
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	if data.is_empty():
		push_error("PPOAgent: Failed to parse model JSON")
		return
	
	# Load Layer 1: [128, 181]
	_w1.clear()
	for row in data["l1_w"]:
		_w1.append(PackedFloat32Array(row))
	_b1 = PackedFloat32Array(data["l1_b"])
	
	# Load Layer 2: [128, 128]
	_w2.clear()
	for row in data["l2_w"]:
		_w2.append(PackedFloat32Array(row))
	_b2 = PackedFloat32Array(data["l2_b"])
	
	# Load Output Layer: [64, 128]
	_w_out.clear()
	for row in data["out_w"]:
		_w_out.append(PackedFloat32Array(row))
	_b_out = PackedFloat32Array(data["out_b"])
	
	_loaded = true
	print("PPOAgent: Neural network model loaded successfully!")


static func is_available() -> bool:
	ensure_loaded()
	return _loaded


func predict_action(game, p: int, deterministic := true) -> int:
	ensure_loaded()
	if not _loaded:
		return 58 # end_turn fallback
	
	var obs: PackedFloat32Array = AIEncoder.encode_state(game, p)
	var mask: Array = AIEncoder.get_action_mask(game, p)
	
	# Layer 1: h1 = tanh(W1 @ obs + b1)
	var h1 := PackedFloat32Array()
	h1.resize(128)
	var obs_size := obs.size()
	for i in 128:
		var sum := _b1[i]
		var w_row: PackedFloat32Array = _w1[i]
		for j in obs_size:
			sum += w_row[j] * obs[j]
		h1[i] = tanh(sum)
	
	# Layer 2: h2 = tanh(W2 @ h1 + b2)
	var h2 := PackedFloat32Array()
	h2.resize(128)
	for i in 128:
		var sum := _b2[i]
		var w_row: PackedFloat32Array = _w2[i]
		for j in 128:
			sum += w_row[j] * h1[j]
		h2[i] = tanh(sum)
	
	# Layer 3: logits = W_out @ h2 + b_out
	var logits := PackedFloat32Array()
	logits.resize(64)
	var best_action := 58
	var best_val := -1e20
	
	for i in 64:
		if not mask[i]:
			logits[i] = -1e20
			continue
		var sum := _b_out[i]
		var w_row: PackedFloat32Array = _w_out[i]
		for j in 128:
			sum += w_row[j] * h2[j]
		logits[i] = sum
		if sum > best_val:
			best_val = sum
			best_action = i
	
	if deterministic:
		return best_action
	
	# Softmax sampling if not deterministic
	var exp_sum := 0.0
	var exps := PackedFloat32Array()
	exps.resize(64)
	for i in 64:
		if mask[i]:
			var e := exp(clampf(logits[i] - best_val, -20.0, 0.0))
			exps[i] = e
			exp_sum += e
		else:
			exps[i] = 0.0
	
	if exp_sum <= 0.0:
		return best_action
	
	var r := rng.randf() * exp_sum
	var acc := 0.0
	for i in 64:
		if mask[i]:
			acc += exps[i]
			if r <= acc:
				return i
	
	return best_action


func pick_command(game, p: int) -> Dictionary:
	var act := predict_action(game, p, true)
	return AIEncoder.action_to_command(game, p, act)


func choose(req: Dictionary):
	var options: Array = req.get("options", [])
	if options.is_empty():
		return null
	if req.get("optional", false) and rng.randf() < 0.2:
		return null
	return options[0]
