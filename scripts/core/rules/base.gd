extends RefCounted
## Base for the per-deck card rules. The engine (`g`) finds methods by name
## and calls them; `<id>` is the card's ability id.
##
## Static modifiers (plain functions, must not await):
##   atk_<id>(c, p, lane) -> int             ATK bonus of the creature itself
##   def_<id>(c, p, lane) -> int             DEF bonus of the creature itself
##   aura_atk_<id>(src, sp, slane, c, p, lane) -> int   bonus src gives to creature c
##   aura_def_<id>(src, sp, slane, c, p, lane) -> int
##   aura_dmg_<id>(src, sp, slane, c, p, lane, amount, info) -> int  extra damage c takes
##   dmg_in_<id>(c, p, lane, amount, info) -> int     damage c really takes
##   vs_<id>(c, p, lane, other, olane, attacking) -> int  fight-only ATK bonus
##   cost_<id>(c, p) -> int                  cost change of the card
##   playable_<id>(c, p) -> bool             extra condition to play the card
##   floop_ok_<id>(c, p, kind, lane) -> bool / act_ok_<id>(...) -> bool
##
## Effects (may await):
##   enter_<id>(c, p, lane)                  creature/building entered play
##   leave_<id>(c, p, lane, reason, info)    left play (info: state before leaving)
##   floop_<id>(c, p, kind, lane) / act_<id>(c, p, kind, lane) / spell_<id>(c, p)
##   start_<id>(c, p, kind, lane) / after_draw_<id>(...) / battle_<id>(...)
##   attack_<id>(c, p, lane)                 this creature declared an attack
##   dealt_<id>(c, p, lane, amount, target)  it dealt fight damage ("creature"/"player")
##   hurt_<id>(c, p, lane, amount, by)       it took fight damage and survived
##   killed_<id>(c, p, lane, victim, vp, vlane)   it destroyed a creature in a fight
##   slain_<id>(c, p, lane, killer)          it was destroyed (killer may be null)
##   moved_<id>(c, p, from, to)              it changed lanes
##   discarded_<id>(c)                       the card landed in a discard pile
##   on_enter_<id>(src, sp, skind, slane, c, p, lane)       a creature entered play
##   on_leave_<id>(src, sp, skind, slane, c, p, lane, reason)
##   on_discard_<id>(src, sp, skind, slane, victim, card)   a player discarded from hand
##   on_freeze_<id>(src, sp, skind, slane, side, lane)      a land became frozen

const LANES := 4
const CardDB = preload("res://scripts/core/card_db.gd")

## The game. Held weakly: the game owns its rules objects, and a strong
## reference back would keep every finished game alive.
var g:
	get:
		return _game_ref.get_ref() if _game_ref != null else null
	set(value):
		_game_ref = weakref(value)

var _game_ref: WeakRef = null


func players(p: int):
	return g.players[p]


func creature(p: int, lane: int):
	return g.players[p].creatures[lane]


## Lanes adjacent to `lane`.
func adj(lane: int) -> Array:
	return g.adjacent(lane)


## Lanes of p's creatures that p's building on `lane` works on: the creature on its own lane and
## a Вязаный котик next door («На Вязаного котика действуют строения на соседних землях»).
func bld_targets(p: int, lane: int) -> Array:
	var out := []
	if creature(p, lane) != null:
		out.append(lane)
	for a in adj(lane):
		var k = creature(p, a)
		if k != null and g.has_text(k, p, "creature", a, "knit_kitty"):
			out.append(a)
	return out


## One of them (p picks when there are several), -1 when there is none.
func bld_target(p: int, lane: int, prompt: String) -> int:
	var t := bld_targets(p, lane)
	if t.size() <= 1:
		return -1 if t.is_empty() else int(t[0])
	var pick = await g.pick_creature(p, [p], prompt, func(_x, _s, l): return t.has(l))
	return -1 if pick == null else int(pick["lane"])


## Damage to a creature from an ability or spell.
func hit(p: int, lane: int, amount: int, source_side := -1) -> int:
	return await g.damage_creature(p, lane, amount, {"kind": "effect", "p": source_side})


func hit_all(p: int, amount: int, pred := Callable()) -> void:
	for lane in LANES:
		var c = creature(p, lane)
		if c != null and (not pred.is_valid() or pred.call(c, p, lane)):
			await hit(p, lane, amount, g.opp(p))
	await g._check_state()


## Damage to every creature p's opponents control (2 на 2: both opponents').
func hit_foes(p: int, amount: int, pred := Callable()) -> void:
	for o in g.foes(p):
		await hit_all(o, amount, pred)


## The creature across the lane from (p, lane), null when the spot is empty.
func opposite(p: int, lane: int):
	return g.foe_creature(p, lane)


## The creature across the lane as a choice option (none when the spot is empty or hidden).
func opposite_opts(p: int, lane: int) -> Array:
	var a: Array = g.across(p, lane)
	return g.creature_opts(p, [a[0]], func(_x, _s, l): return l == a[1])


## The opposite creature is there and may be targeted (Пещера одиночества hides it).
func opposite_open(p: int, lane: int) -> bool:
	var a: Array = g.across(p, lane)
	return creature(a[0], a[1]) != null and not g.shielded(a[0], a[1])


## Moves one of p's creatures to one of p's empty lanes.
func move_own_creature(p: int, prompt: String) -> void:
	var pick = await g.pick_creature(p, [p], prompt)
	if pick == null:
		return
	var dest: int = await g.pick_lane(p, p, g.empty_lanes(p), "Выбери пустую зону")
	if dest >= 0:
		await g.move_creature(p, pick["lane"], dest)


## Moves creature (p, lane) to an empty lane of p's choosing; false if there is none.
func relocate(p: int, lane: int, prompt: String) -> bool:
	var lanes: Array = g.empty_lanes(p)
	if lanes.is_empty():
		return false
	var dest: int = await g.pick_lane(p, p, lanes, prompt)
	if dest < 0:
		return false
	await g.move_creature(p, lane, dest)
	return true


## Heal-or-damage choice used by several cute cards.
func heal_or_hit(p: int, side: int, lane: int, prompt: String) -> void:
	var c = creature(side, lane)
	if c == null:
		return
	var opts := ["Восстановить 1", "Нанести 1 урон"]
	var pick = await g.pick_option(p, opts + ["Ничего"], prompt)
	if pick == "Восстановить 1":
		await g.heal_creature(side, lane, 1, p)
	elif pick == "Нанести 1 урон":
		await hit(side, lane, 1, p)


## Removes one token that is not damage from creature c (p picks the kind when there are two).
## Returns the kind removed, "" when it has none.
func take_token(p: int, c) -> String:
	var kinds: Array = g.TOKEN_KINDS.filter(func(k): return g.tokens(c, k) > 0)
	if kinds.is_empty():
		return ""
	var kind: String = kinds[0]
	if kinds.size() > 1:
		var names := {"burn": "Жетон огня", "atk_tok": "Жетон атаки"}
		var pick = await g.pick_option(p, kinds.map(func(k): return names[k]), "Какой жетон убрать с «%s»?" % c.card_name())
		kind = kinds[maxi(kinds.map(func(k): return names[k]).find(pick), 0)]
	await g.remove_token(c, kind)
	return kind


func say(text: String) -> void:
	await g.log_msg(text)


func flash(c, text: String, good := true) -> void:
	if c != null:
		await g.emit_event({"type": "buff", "uid": c.uid, "text": text, "good": good})
