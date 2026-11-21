extends RefCounted
## «Песочница»: a game where the table is set up by hand, to see how a card or a deck works.
##
## Every change here is a call of its own, never a command of run_command: the journal does
## not get it, an online table never sends or takes it (board.gd _remote_cmd_ok knows only the
## real commands), so a sandbox game can't leak into replays, the rating or a match.
##
## The changes go round the rules on purpose (a card simply appears on its spot, a land just
## turns) and write a line to the game log, so the log shows what was set up and what the
## cards did on their own. Undo is a stack of copies of the whole state (Game.clone), so any
## step can be taken back, the hidden ones too, and the table can go back to its start.

const CardDB = preload("res://scripts/core/card_db.gd")
const CardInst = preload("res://scripts/core/card_inst.gd")

## The actions a player with «Бесконечные действия» has after every step.
const INF_ACTIONS := 9
## Steps kept for «Шаг назад».
const HISTORY_MAX := 60
const TAG := "✎ "

var g                               # the game (scripts/core/game.gd)
var infinite: Dictionary = {}       # seat -> true: its actions are refilled after every step
var history: Array = []             # copies of the state before each step, the newest last
var deck_names: Dictionary = {}     # seat -> the name of its deck, for a game without a hero
var _start: Dictionary = {}         # the table as it was set up at first


func _init(game) -> void:
	g = game
	g.journal = null      # nothing of a sandbox goes to the replays


# ================================================================ undo

## The table as it is now becomes the one «Сначала» goes back to.
func mark_start() -> void:
	_start = _point()
	history.clear()


func _point() -> Dictionary:
	return {"copy": g.clone(), "log": g.log_lines.size(), "journal": 0, "h": g.state_hash()}


## Before a step: the state to go back to.
func push() -> void:
	history.append(_point())
	if history.size() > HISTORY_MAX:
		history.pop_front()


## After a step: a step that changed nothing is no step to take back.
func settle() -> void:
	if not history.is_empty() and history[-1]["h"] == g.state_hash() and g.log_lines.size() == history[-1]["log"]:
		history.pop_back()


func can_undo() -> bool:
	return not history.is_empty()


func undo() -> bool:
	if history.is_empty():
		return false
	g.undo_to(history.pop_back())
	return true


## The table as it was at first.
func reset() -> void:
	if _start.is_empty():
		return
	g.undo_to(_start)
	history.clear()


## «Бесконечные действия»: the seats that have them get their actions back.
func refill() -> void:
	for p in infinite:
		if infinite[p] and p < g.players.size():
			g.players[p].actions = maxi(g.players[p].actions, INF_ACTIONS)


func set_infinite(p: int, on: bool) -> void:
	infinite[p] = on
	await _say("%s: бесконечные действия %s." % [_n(p), "включены" if on else "выключены"])
	if on:
		refill()
	elif g.players[p].actions > g.ACTIONS_PER_TURN:
		g.players[p].actions = g.ACTIONS_PER_TURN
	await g.emit_event({"type": "actions", "p": p})


# ================================================================ cards

## Puts a new copy of card `id` for player p: "hand", "deck" (on top), "bottom" (under the deck),
## "discard", or on the table: "creature" / "building" on `lane` (what lies there goes to the discard
## pile). Nothing of the card happens: it just is there. Returns the card, null when it can't go there.
func add_card(p: int, id: String, dest: String, lane := -1) -> CardInst:
	if p < 0 or p >= g.players.size() or not CardDB.has_def(id):
		return null
	var kind: String = CardDB.get_def(id)["kind"]
	if (dest == "creature" or dest == "building") and (kind != dest or lane < 0 or lane >= g.LANES):
		return null
	var ps = g.players[p]
	var c: CardInst = g._make_card(id, p)
	var where := ""
	match dest:
		"hand":
			ps.hand.append(c)
			where = "в руку"
		"deck":
			ps.deck.append(c)
			where = "наверх колоды"
		"bottom":
			ps.deck.push_front(c)
			where = "под низ колоды"
		"discard":
			ps.discard.append(c)
			where = "в сброс"
		"creature":
			var old: CardInst = ps.creatures[lane]
			if old != null:
				ps.creatures[lane] = null
				_to_pile(old, "discard")
			ps.creatures[lane] = c
			where = "на стол, зона %d" % (lane + 1)
		"building":
			var old: CardInst = ps.buildings[lane]
			if old != null:
				ps.buildings[lane] = null
				_to_pile(old, "discard")
			ps.buildings[lane] = c
			where = "на стол, зона %d" % (lane + 1)
		_:
			g._cards.erase(c.uid)
			return null
	await _say("«%s» %s: %s." % [c.card_name(), where, _n(p)])
	if dest == "creature" or dest == "building":
		await g.emit_event({"type": "play", "p": p, "lane": lane, "uid": c.uid, "kind": dest})
		await g._check_state()
	return c


## Takes card uid from where it is: "discard" (to its owner's pile), "hand" (its owner's hand),
## "deck" (on top of its owner's deck), "removed" (out of the game), "destroy" (the rules destroy
## it: its effects of leaving play happen). The quiet ways run no effect of the card.
func move_card(uid: int, dest: String) -> bool:
	var c: CardInst = g.card(uid)
	if c == null:
		return false
	var w: Dictionary = g.where(uid)
	var zone: String = w["zone"]
	if dest == "destroy":
		match zone:
			"creature":
				await _say("«%s» уничтожается." % c.card_name())
				await g.destroy_creature(w["p"], w["lane"])
				await g._check_state()
				return true
			"building":
				await _say("«%s» уничтожается." % c.card_name())
				await g.destroy_building(w["p"], w["lane"], w["kind"])
				await g._check_state()
				return true
		return false
	if not ["discard", "hand", "deck", "removed"].has(dest) or zone == dest or zone == "limbo" or zone == "under":
		return false
	var from := ""
	match zone:
		"creature":
			g.players[w["p"]].creatures[w["lane"]] = null
			from = "со стола"
		"building":
			var ps = g.players[w["p"]]
			if w["kind"] == "building":
				ps.buildings[w["lane"]] = null
				if not ps.extra_buildings[w["lane"]].is_empty():
					ps.buildings[w["lane"]] = ps.extra_buildings[w["lane"]].pop_front()
			else:
				ps.extra_buildings[w["lane"]].erase(c)
			from = "со стола"
		"teamwork":
			g.players[w["p"]].teamwork = null
			from = "со стола"
		"hand":
			from = "из руки"
		"deck":
			from = "из колоды"
		"discard":
			from = "из сброса"
		"removed":
			from = "из удалённых"
	g._take_from_zones(c)
	var on_table := zone == "creature" or zone == "building" or zone == "teamwork"
	_to_pile(c, dest)
	var to: String = {"discard": "в сброс", "hand": "в руку", "deck": "наверх колоды", "removed": "из игры"}[dest]
	await _say("«%s» %s %s." % [c.card_name(), from, to])
	if on_table:
		await g.emit_event({"type": "leave", "p": w["p"], "uid": uid, "dest": "removed" if dest == "deck" else dest, "reason": "sandbox"})
		await g._check_state()
	return true


## A card that is out of every zone goes to its owner's pile, with its table state gone
## (the cards under it go to their owners' discard piles).
func _to_pile(c: CardInst, dest: String) -> void:
	for u: CardInst in c.under:
		u.reset_board_state()
		g.players[u.owner].discard.append(u)
	c.reset_board_state()
	var ps = g.players[c.owner]
	match dest:
		"hand":
			ps.hand.append(c)
		"deck":
			ps.deck.append(c)
		"removed":
			ps.removed.append(c)
		_:
			ps.discard.append(c)


# ================================================================ creatures

## Damage to the creature on (side, lane), as an effect of no card: it may destroy it.
func damage(side: int, lane: int, n: int) -> void:
	var c: CardInst = g.players[side].creatures[lane]
	if c == null or n <= 0:
		return
	await _say("«%s» получает %d урона." % [c.card_name(), n])
	await g.damage_creature(side, lane, n, {"kind": "effect"})
	await g._check_state()


## Takes n damage off the creature; n < 0: all of it.
func heal(side: int, lane: int, n: int) -> void:
	var c: CardInst = g.players[side].creatures[lane]
	if c == null or c.damage <= 0:
		return
	var amount: int = c.damage if n < 0 else mini(n, c.damage)
	c.damage -= amount
	await _say("С «%s» снято %d урона." % [c.card_name(), amount])
	await g.emit_event({"type": "heal", "p": side, "lane": lane, "uid": c.uid, "amount": amount})


## Attack and defence of the creature change for good (while it stays in play).
func boost(side: int, lane: int, atk: int, def: int) -> void:
	var c: CardInst = g.players[side].creatures[lane]
	if c == null or (atk == 0 and def == 0):
		return
	c.perm_atk += atk
	c.perm_def += def
	var parts := PackedStringArray()
	if atk != 0:
		parts.append("атака %+d" % atk)
	if def != 0:
		parts.append("защита %+d" % def)
	await _say("«%s»: %s." % [c.card_name(), ", ".join(parts)])
	await g.emit_event({"type": "buff", "uid": c.uid, "text": "%+d" % (atk if atk != 0 else def), "good": atk + def > 0})
	await g._check_state()


## The card on the table turns sideways (as after a floop or an attack) or back up.
func toggle_exhausted(uid: int) -> void:
	var c: CardInst = g.card(uid)
	var w: Dictionary = g.where(uid)
	if c == null or not (w["zone"] == "creature" or w["zone"] == "building"):
		return
	c.exhausted = not c.exhausted
	if not c.exhausted:
		c.flooped = false
	await _say("«%s» %s." % [c.card_name(), "повёрнута" if c.exhausted else "снова готова"])


# ================================================================ lands

func set_land(side: int, lane: int, type: String) -> void:
	if not CardDB.land_types().has(type):
		return
	var l: Dictionary = g.players[side].lands[lane]
	if l["type"] == type and l["override"] == "":
		return
	l["type"] = type
	l["override"] = ""
	l["override_until"] = -1
	await _say("%s: в зоне %d теперь %s." % [_n(side), lane + 1, CardDB.land_name(type)])
	await g.emit_event({"type": "land", "p": side, "lane": lane})


func flip_land(side: int, lane: int) -> void:
	var l: Dictionary = g.players[side].lands[lane]
	l["flipped"] = not l["flipped"]
	l["flip_until"] = -1
	await _say("%s: земля в зоне %d %s." % [_n(side), lane + 1, "лицом вниз" if l["flipped"] else "лицом вверх"])
	await g.emit_event({"type": "flip_land", "p": side, "lane": lane, "flipped": l["flipped"]})


## Freezes the land of (side, lane) or takes its frost off, as the rules do it (the cards that
## watch the frost see it).
func toggle_frozen(side: int, lane: int) -> void:
	if g.is_frozen(side, lane):
		await _say("%s: лёд в зоне %d снят." % [_n(side), lane + 1])
		await g.thaw(side, lane)
	else:
		await _say("%s: земля в зоне %d замораживается." % [_n(side), lane + 1])
		await g.freeze(side, lane)
	await g._check_state()


# ================================================================ players

## The hero card of player p: `card` ("" none: the deck plays alone, no ability of a hero).
## What the old hero remembered goes; the name is the hero's, or the deck's without one.
## quiet: before the game starts (no log line).
func set_hero(p: int, card: String, quiet := false) -> void:
	var ps = g.players[p]
	if card != "" and not CardDB.has_hero_card(card):
		return
	if not deck_names.has(p):
		deck_names[p] = _deck_name(p)
	ps.hero_card = card
	ps.hero_state = {}
	if card == "":
		ps.name = deck_names[p]
	elif card == ps.hero:
		ps.name = String(CardDB.hero(ps.hero)["name"])
	else:
		ps.name = String(CardDB.hero_card(card)["name"])
	if not quiet:
		await _say("%s: %s." % [ps.name, "играет без героя" if card == "" else "герой «%s»" % CardDB.hero_card(card)["name"]])
		await g.emit_event({"type": "actions", "p": p})


## The name of p's deck when it plays without a hero (a run deck stands for its ready deck: Своя колода).
func _deck_name(p: int) -> String:
	var ps = g.players[p]
	var d := CardDB.parse_custom(ps.hero)
	if ps.hero.begins_with(CardDB.CUSTOM_PREFIX) and not d.is_empty():
		return String(d["name"])
	if ps.hero.begins_with(CardDB.RUN_PREFIX):
		return "Своя колода"
	return String(CardDB.hero(ps.hero)["name"])


## Before the game starts: p's deck and hand go (an empty deck from the deck builder).
func clear_cards(p: int) -> void:
	var ps = g.players[p]
	for c: CardInst in ps.deck + ps.hand:
		g._cards.erase(c.uid)
	ps.deck.clear()
	ps.hand.clear()


## Hit points of player p (2 на 2: of the team). A game won by hit points comes back when
## nobody is at 0 any more.
func set_hp(p: int, hp: int) -> void:
	g.players[p].hp = maxi(hp, 0)
	await _say("%s: жизни %d." % [_n(p), g.players[p].hp])
	await g.emit_event({"type": "actions", "p": p})
	if g.phase == "over" and g.players.all(func(ps): return ps.out or ps.hp > 0):
		g.phase = "main"
		g.winner = -1
		await _say("Игра продолжается.")
	await g._check_win()


func set_actions(p: int, n: int) -> void:
	g.players[p].actions = clampi(n, 0, 99)
	await _say("%s: действий %d." % [_n(p), g.players[p].actions])
	await g.emit_event({"type": "actions", "p": p})


func draw(p: int) -> void:
	await _say("%s берёт карту." % _n(p))
	await g._draw(p)


func shuffle(p: int) -> void:
	await _say("%s перемешивает колоду." % _n(p))
	await g.shuffle_deck(p)


func clear_hand(p: int) -> void:
	var ps = g.players[p]
	if ps.hand.is_empty():
		return
	var n: int = ps.hand.size()
	for c: CardInst in ps.hand.duplicate():
		ps.hand.erase(c)
		ps.discard.append(c)
	await _say("%s: рука в сброс, карт %d." % [_n(p), n])


## The turn goes on: the turn player ends it as with the button, the next one begins.
func pass_turn() -> void:
	if g.phase == "over":
		return
	var p: int = g.turn_player
	await _say("%s передаёт ход." % _n(p))
	if g.phase == "main" or g.phase == "attack":
		await g.cmd_end_turn(p)


# ================================================================ helpers

func _n(p: int) -> String:
	return g.players[p].name


func _say(text: String) -> void:
	await g.log_msg(TAG + text)
