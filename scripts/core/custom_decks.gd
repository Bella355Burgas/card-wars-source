extends RefCounted
## Own decks kept on this PC: user://custom_decks.json holds [{name, lands, deck}].
## Drafts (decks that break the rules) can be saved too, but only legal decks
## are offered for play (codes).

const CardDB = preload("res://scripts/core/card_db.gd")
const PATH := "user://custom_decks.json"


static func load_all() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return []
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Array else []


static func save_all(decks: Array) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(decks, "\t"))
	return true


## Saves a deck under its name, replacing the saved deck with the same name.
static func put(entry: Dictionary) -> bool:
	var decks := load_all()
	var at := -1
	for i in decks.size():
		if decks[i].get("name", "") == entry["name"]:
			at = i
	if at >= 0:
		decks[at] = entry
	else:
		decks.append(entry)
	return save_all(decks)


static func remove(name: String) -> bool:
	var decks := load_all()
	decks = decks.filter(func(e): return e.get("name", "") != name)
	return save_all(decks)


## Pick code of a saved entry (see CardDB.custom_code).
static func code_of(entry: Dictionary) -> String:
	return CardDB.custom_code(String(entry.get("name", "")), entry.get("lands", []), entry.get("deck", {}))


## Pick codes of the saved decks that are legal right now.
static func codes() -> Array:
	var out := []
	for e in load_all():
		var code := code_of(e)
		if CardDB.has_hero(code):
			out.append(code)
	return out


# ---------------------------------------------------------------- deck files

## A deck as a file to send to other players (*.cwdeck, JSON).
const EXT := "cwdeck"


static func write_file(path: String, entry: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var data := {"cardwars": "deck", "name": entry["name"], "lands": entry["lands"], "deck": entry["deck"]}
	if String(entry.get("hero", "")) != "":
		data["hero"] = entry["hero"]       # the hero card the deck is built for
	f.store_string(JSON.stringify(data, "\t"))
	return true


## {name, lands, deck} of a deck file, {} when the file is not a deck.
## Unknown cards and lands are kept: such a deck opens as a draft.
static func read_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or d.get("cardwars", "") != "deck" or not (d.get("lands") is Array) \
			or not (d.get("deck") is Dictionary):
		return {}
	var lands := []
	for t in d["lands"]:
		lands.append(str(t))
	var deck := {}
	for id in d["deck"]:
		var n = d["deck"][id]
		if (n is float or n is int) and int(n) > 0:
			deck[str(id)] = int(n)
	var deck_name := str(d.get("name", "")).strip_edges().left(CardDB.CUSTOM_NAME_MAX)
	var out := {"name": deck_name if deck_name != "" else "Колода", "lands": lands, "deck": deck}
	if CardDB.has_hero_card(str(d.get("hero", ""))):
		out["hero"] = str(d["hero"])
	return out


## Adds a deck from a file to the saved ones and returns the name it has there
## ("" when the file of decks can't be written). A different saved deck with the
## same name stays: the new one becomes "Name (2)", "Name (3)"...
static func add(entry: Dictionary) -> String:
	var decks := load_all()
	var base: String = entry["name"]
	var deck_name := base
	var n := 1
	while true:
		var same = null
		for e in decks:
			if e.get("name", "") == deck_name:
				same = e
		if same == null:
			break
		if code_of(same) == code_of({"name": deck_name, "lands": entry["lands"], "deck": entry["deck"]}):
			return deck_name        # this very deck is already there
		n += 1
		deck_name = "%s (%d)" % [base.left(CardDB.CUSTOM_NAME_MAX - 5), n]
	var copy := entry.duplicate()
	copy["name"] = deck_name
	return deck_name if put(copy) else ""
