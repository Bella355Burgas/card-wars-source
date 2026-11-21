extends RefCounted
## Replays: the seed, both picks and every step the engine was given (Game.journal),
## so a match can be played again move by move. A replay is a JSON file
## (*.cwreplay): the game keeps the latest ones in user://replays, and players
## can send them to each other.
##
## Steps: {"t": "lands", "p", "types"}, {"t": "mull", "p"}, {"t": "start"},
## {"t": "turn"}, {"t": "end", "p"}, {"t": "cmd", "p", "c"} with "h", the state
## hash right before the step; {"t": "pick", "i"} answers the last choice
## (its place among the options, -1 = skipped); {"t": "over", "w"} is a surrender.

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")

const EXT := "cwreplay"
const DIR := "user://replays"
const KEEP := 50
const FORMAT := 1
## The rules the engine plays by: a replay of other rules can't be played again move by move.
## 2: the corrected Russian cards (sets 1–18).
## 3: Акула buffs herself, not the entering creature.
## 4: a burn token deals 1 damage as soon as it is put on a creature.
## 5: no spell or ability without its chosen target; rainbow cards have no land type; Хрум keeps tokens.
## 6: frozen lands can be frozen again; Финн's floop or the card's own; start of turn in the player's order.
## 7: a card Синюшный чудила made Rainbow stays Rainbow in play until the end of the turn.
## 8: a card of a land type costing 0 needs one face-up land of its type.
## 10: Акула gives +1 ATK to the entering Sandy creature again; Костяной дворец silences watchers too.
## 12: Рентгеновские очки keep the top card open and playable till the end of the turn;
##     two or more enter effects at once: the turn player picks the order.
## 14: Зелье удара may hit its own player.
## 15: Глотиус Химик repeats Хрустальный шар itself, not the spell it played; heals may pick
##     undamaged targets; a stolen Пляжный мяч goes to the thief's opponent.
## 16: a card that counts as Rainbow too (Крошечный слон), also one played free, counts as a
##     Rainbow card played this turn (Грамотей-младенец).
## 17: на троих after a player dropped out the lanes keep facing as before (mirrored), so the
##     creatures that faced each other stay face to face. Светлячок-фонарщик keeps the top card
##     of the deck open like Рентгеновские очки (played with "play", no more an activated ability).
##     Док Смерть and Промышленный убийца may destroy themselves to pay for their floop.
##     At the end of the turn a creature that moved onto a lane already passed still attacks.
##     New hero card Король вампиров: a heal of his player may become as much damage instead.
##     Card audit (docs/CARDS_AUDIT.md): Жнец asks which creature of its lane to move (itself too).
##     Пёс-бизнесмен no more counts «Песчаный», «Песнь», «Пёстрые»; Осмелевший ретривер asks
##     whether to draw. Мимимимик bites every foe with no cards in hand (2 на 2, на троих).
##     Кристалл силы may give the 5 cards to the teammate in 2 на 2.
##     Мушка-хлопушка and Болотный босяк hit every foe; Ведьмак and Мертвополь count only the
##     foes' discards (2 на 2: not the teammate's).
##     Напёрсток пустоты: the 2 hit points are lost, not dealt as damage.
##     Лавиногепард Ледяной Клык and Бычья печать ask whether to draw. Призрачный мимимимик's
##     bottom card is a draw (Пень с золотым топором, Синий огр see it).
##     Всевидящее око asks which card of a land type to take when it came up twice; Пухлый
##     пингвин counts only heals by its own side. Энергия вечеринки: the player
##     picks each creature's new lane (it was random) and the moves count as lane changes.
##     Замороженный лимонад heals each creature once; Сглаз lets the player pick the two players.
##     Мяу-Мяу works once a turn for each opposing creature (not once a turn in all); Джейк
##     (Парный турнир) hits only a creature of his player's lanes.
##     Лужица обнимашек: the +1 of friendly creatures counts for its damage only, no lasting buff.
##     Пушистый лис ignores the first 2 damage a turn from opposing creatures (fights and their
##     abilities, not spells or buildings), not 2 of each hit.
##     Пекло: an opposing creature leaving its lane in any way (moved, swapped, taken) counts.
const RULES := 17


## The replay of a game recorded with game.journal. mode: "hotseat" | "ai" |
## "aivsai" | "net"; seat: the side of the player who recorded it.
static func from_game(g, mode: String, seat: int, version: String) -> Dictionary:
	var heroes := []
	var names := []
	for ps in g.players:
		heroes.append(CardDB.pick_of(ps.hero, ps.hero_card))     # "deck@": played without a hero
		names.append(ps.name)
	return {"cardwars": "replay", "format": FORMAT, "rules": RULES, "version": version,
		"date": Time.get_datetime_string_from_system(false, true).substr(0, 16),
		"mode": mode, "seat": maxi(seat, 0), "heroes": heroes, "names": names,
		"first": g.first_player, "seed": g.rng_seed, "over": g.phase == "over", "winner": g.winner,
		"turns": g.turn_number, "hash": g.state_hash(), "steps": g.journal.duplicate(true)}


## Parses a replay file's text. {} when it is not a replay this game can show.
static func parse(text: String) -> Dictionary:
	var d = JSON.parse_string(text)
	if not (d is Dictionary) or d.get("cardwars", "") != "replay" or not (d.get("steps") is Array):
		return {}
	d = _ints(d)
	if int(d.get("rules", 1)) != RULES:
		return {}
	var heroes = d.get("heroes")
	if not (heroes is Array) or not heroes.size() in [2, 3, 4]:
		return {}
	for h in heroes:
		if not (h is String) or not CardDB.valid_loadout(h):
			return {}
	for st in d["steps"]:
		if not (st is Dictionary):
			return {}
	return d


static func read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	return parse(f.get_as_text())


static func write(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	return true


## Keeps a replay among the game's own (the oldest go once there are more than KEEP).
static func keep(data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var path := "%s/%s_%d.%s" % [DIR, stamp, randi() % 1000, EXT]
	if not write(path, data):
		return ""
	var files := _files()
	while files.size() > KEEP:
		DirAccess.remove_absolute(files.pop_front())
	return path


## The game's own replays, newest first: [{path, data}].
static func saved() -> Array:
	var out := []
	var files := _files()
	files.reverse()
	for path in files:
		var d := read(path)
		if not d.is_empty():
			out.append({"path": path, "data": d})
	return out


static func _files() -> Array:
	var out := []
	for name in DirAccess.get_files_at(DIR):
		if name.get_extension() == EXT:
			out.append(DIR + "/" + name)
	out.sort()
	return out


## "Финн против Джейка"-style title (2 на 2: "Финн и Бимо против Джейка и Марселин",
## на троих: "Финн, Джейк и Бимо").
static func title(d: Dictionary) -> String:
	var names: Array = d.get("names", ["?", "?"])
	if names.size() == 3:
		return "%s, %s и %s" % names
	if names.size() == 4:
		return "%s и %s против %s и %s" % [names[0], names[2], names[1], names[3]]
	return "%s против %s" % [names[0], names[1]]


## Short result line from the recording player's side.
static func result(d: Dictionary) -> String:
	if not d.get("over", false):
		return "не доиграна"
	var w := int(d.get("winner", -1))
	if w < 0:
		return "ничья"
	var names: Array = d["names"]
	if d.get("mode", "") in ["ai", "net"]:
		# 2 на 2 the winner is a team: seats 0 and 2 or 1 and 3.
		var seat := int(d.get("seat", 0))
		var won: bool = w % 2 == seat % 2 if names.size() == 4 else w == seat
		return "победа" if won else "поражение"
	if names.size() == 4:
		return "победили %s и %s" % [names[w % 2], names[w % 2 + 2]]
	return "победил " + String(names[w])


## A new game set up as the recorded one (steps not applied yet).
static func new_game(d: Dictionary):
	var g := Game.new()
	g.setup(d["heroes"], int(d.get("first", 0)), int(d.get("seed", 0)))
	return g


## Applies one recorded step (not "pick": the chooser answers those).
static func apply(g, st: Dictionary) -> void:
	match String(st.get("t", "")):
		"lands":
			await g.cmd_arrange_lands(int(st.get("p", 0)), st.get("types", []))
		"mull":
			await g.cmd_mulligan(int(st.get("p", 0)))
		"start":
			await g.start_game()
		"turn":
			await g.cmd_start_turn()
		"end":
			await g.cmd_end_turn(int(st.get("p", 0)))
		"cmd":
			if st.get("c") is Dictionary and st["c"].has("cmd"):
				await g.run_command(int(st.get("p", 0)), st["c"])
		"over":
			g.phase = "over"
			g.winner = int(st.get("w", -1))


## The option a recorded "pick" step chose in this request.
static func answer(req: Dictionary, st: Dictionary):
	return Player.answer(req, st)


## Plays a replay through the engine alone. "" when it ends in the recorded state,
## otherwise what went wrong. Used by tests; the table plays replays with animations.
static func verify(d: Dictionary) -> String:
	return (await check(d))["err"]


## The same, with the game it played: {"err", "game"}. The room server takes the winner of a
## tournament game from it (tools/replay_check.gd).
static func check(d: Dictionary) -> Dictionary:
	var g = new_game(d)
	var player := Player.new(d["steps"])
	g.chooser = player
	var steps: Array = d["steps"]
	while player.pos < steps.size():
		var st: Dictionary = steps[player.pos]
		player.pos += 1
		if st.get("t") == "pick":
			return {"err": "a choice nobody asked for at step %d" % (player.pos - 1), "game": g}
		if st.has("h") and int(st["h"]) != g.state_hash():
			return {"err": "state differs before step %d (%s)" % [player.pos - 1, st.get("t")], "game": g}
		await apply(g, st)
		if player.broken != "":
			return {"err": player.broken, "game": g}
	if int(d.get("hash", 0)) != g.state_hash():
		return {"err": "final state differs", "game": g}
	return {"err": "", "game": g}


## Where the turns begin, for jumping to them: [{"pos": index of the step that starts
## the turn, "n": turn number, "p": whose turn}]. Stops where the recording stops matching.
static func turn_marks(d: Dictionary) -> Array:
	var marks := []
	await _play(d, -1, marks)
	return marks


## A game of the replay with its first `pos` steps played (engine only), for jumping
## there. The picks of those steps are answered from the recording.
static func play_to(d: Dictionary, pos: int):
	return await _play(d, pos, [])


static func _play(d: Dictionary, pos: int, marks: Array):
	var g = new_game(d)
	var player := Player.new(d["steps"])
	g.chooser = player
	var steps: Array = d["steps"]
	while player.pos < steps.size() and (pos < 0 or player.pos < pos):
		var at := player.pos
		var st: Dictionary = steps[at]
		player.pos += 1
		if st.get("t") == "pick" or (st.has("h") and int(st["h"]) != g.state_hash()):
			break
		await apply(g, st)
		if player.broken != "":
			break
		if st.get("t") in ["start", "turn"]:
			marks.append({"pos": at, "n": g.turn_number, "p": g.turn_player})
	g.chooser = null
	return g


## Chooser that answers from the recorded steps (engine-only playback).
class Player extends RefCounted:
	var steps: Array
	var pos := 0
	var broken := ""

	func _init(s: Array) -> void:
		steps = s

	func choose(req: Dictionary):
		if pos >= steps.size() or steps[pos].get("t") != "pick":
			broken = "no recorded answer for a choice at step %d" % pos
			return null
		pos += 1
		return answer(req, steps[pos - 1])

	static func answer(req: Dictionary, st: Dictionary):
		var options: Array = req.get("options", [])
		var i := int(st.get("i", -1))
		if i >= 0 and i < options.size():
			return options[i]
		return st.get("r") if i == -2 else null


## JSON keeps every number as a float: whole numbers become ints again.
static func _ints(v):
	if v is float and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	if v is Array:
		return v.map(func(x): return _ints(x))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _ints(v[k])
		return out
	return v
