extends RefCounted
const CardDB = preload("res://scripts/core/card_db.gd")

## AI difficulty levels: which exported network plays (an earlier snapshot of the
## training run is a weaker player) and how freely it picks its moves (a
## temperature above 0 sometimes takes a move it scores lower, see
## policy_agent.gd). Measured against each other with rl_training/tournament.py;
## the networks are exported with rl_training/export_model.py --out.
##
## Run 20261014_060002 (Elo on the run's scale; each level beats the one below it
## in 59-76% of the games, Невозможный beats Новичок in 90%): Невозможный 271
## (970k games), Сложный 192 (150k), Средний 124 (50k at T 1), Лёгкий 15 (50k at
## T 2), Новичок -160 (50k at T 4). Card Wars has a lot of luck in it: the random
## bot wins 4% against Новичок.

const LEVELS := [
	{"id": "novice", "name": "Новичок", "model": "res://data/ai_policy_50k.json", "temperature": 4.0,
		"color": Color(0.45, 0.85, 0.5)},
	{"id": "easy", "name": "Лёгкий", "model": "res://data/ai_policy_50k.json", "temperature": 2.0,
		"color": Color(0.65, 0.9, 0.35)},
	{"id": "medium", "name": "Средний", "model": "res://data/ai_policy_50k.json", "temperature": 1.0,
		"color": Color(1.0, 0.85, 0.3)},
	{"id": "hard", "name": "Сложный", "model": "res://data/ai_policy_150k.json", "temperature": 0.0,
		"color": Color(1.0, 0.55, 0.2)},
	{"id": "impossible", "name": "Невозможный", "model": "res://data/ai_policy.json", "temperature": 0.0,
		"color": Color(1.0, 0.32, 0.3), "deck_model": true},
]
const DEFAULT := "medium"
const MAIN_MODEL := "res://data/ai_policy.json"


static func ids() -> Array:
	return LEVELS.map(func(l): return l["id"])


static func level(id: String) -> Dictionary:
	for l in LEVELS:
		if l["id"] == id:
			return l
	return level(DEFAULT)


## The level `step` places after `id` (wraps around).
static func shift(id: String, step: int) -> String:
	var all := ids()
	var k := all.find(id)
	if k < 0:
		k = all.find(DEFAULT)
	return all[(k + step + all.size()) % all.size()]


## The agent for a level: its network, or the strongest one when the level's file
## is missing, or the old Finn-and-Jake network when there is no exported one at all.
## pick: the seat's deck pick ("marceline", "marceline@prismo", "custom:…"). A level with
## deck_model plays the network trained for that ready deck when there is one.
static func agent(id: String, pick: String = "") -> Object:
	var PolicyAgent = load("res://scripts/ai/policy_agent.gd")
	var l := level(id)
	for path in [model_path(id, pick), MAIN_MODEL]:
		if PolicyAgent.is_available(path):
			return PolicyAgent.new(path, float(l["temperature"]), l.get("search", {}))
	return load("res://scripts/ai/ppo_agent.gd").new()


## The network file the level plays with this pick.
static func model_path(id: String, pick: String = "") -> String:
	var l := level(id)
	var path: String = l["model"]
	if l.get("deck_model", false):
		path = deck_model_path(pick, path)
	return path if FileAccess.file_exists(path) else MAIN_MODEL


## Starts reading the level's network in the background (policy_agent.gd preload_model),
## so that making the AI later does not stop the window.
static func warm(id: String, pick: String = "") -> void:
	load("res://scripts/ai/policy_agent.gd").preload_model(model_path(id, pick))


## True when agent(id, pick) will not wait for a network to be read.
static func is_ready(id: String, pick: String = "") -> bool:
	return load("res://scripts/ai/policy_agent.gd").is_ready(model_path(id, pick))


## The network trained for a ready deck (rl_training/train_selfplay.py --deck X):
## data/ai_policy_deck_X.json. `fallback` for own decks and decks without one.
static func deck_model_path(pick: String, fallback: String) -> String:
	var deck := CardDB.loadout_deck(pick)
	if deck == "" or CardDB.is_custom(deck) or not deck in CardDB.hero_ids():
		return fallback
	var path := "res://data/ai_policy_deck_%s.json" % deck
	return path if FileAccess.file_exists(path) else fallback
