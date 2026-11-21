extends RefCounted
## One physical card. `owner` never changes; control is implied by the lane
## the card sits in.

const CardDB = preload("res://scripts/core/card_db.gd")

var uid := 0
var id := ""
var owner := 0

# Board state; cleared whenever the card leaves play.
var damage := 0
var exhausted := false          # turned sideways: attacked or flooped
var flooped := false            # turned by a floop ("флюпнутое")
var moved_this_turn := false
var temp_atk := 0               # "в этом ходу" modifiers
var temp_def := 0
var perm_atk := 0               # "навсегда" counters while in play
var perm_def := 0
var lost_abilities := false     # Школа
var granted_floop := ""         # Школа: borrowed floop ability id
var act_uses := 0               # activations this turn
var under: Array = []           # cards lying under this one
var flags: Dictionary = {}      # per-card ability state while in play

# Survives leaving play.
var used_life := false          # Мурррузрак has used its extra life
var no_return := false          # may never come back from the discard pile
var upgraded := false           # «Бесконечный поезд»: improved at a rest, creature +1/+1, others cost 1 less


func _init(p_uid := 0, p_id := "", p_owner := 0) -> void:
	uid = p_uid
	id = p_id
	owner = p_owner


func def() -> Dictionary:
	return CardDB.get_def(id)


## Ability id: a few cards are reprints that work exactly like another card.
func ab() -> String:
	return def().get("as", id)


func kind() -> String:
	return def()["kind"]


func card_name() -> String:
	return def()["name"]


func reset_board_state() -> void:
	damage = 0
	exhausted = false
	flooped = false
	moved_this_turn = false
	temp_atk = 0
	temp_def = 0
	perm_atk = 0
	perm_def = 0
	lost_abilities = false
	granted_floop = ""
	act_uses = 0
	under = []
	flags = {}
