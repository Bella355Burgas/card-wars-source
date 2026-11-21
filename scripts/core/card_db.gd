extends RefCounted
## Card definitions and deck lists, loaded once from data/cards.json.

const DATA_PATH := "res://data/cards.json"
const INT_KEYS := ["cost", "atk", "def", "activated", "act_limit"]

## Official deck rules («Собери свою колоду», rulebook p.11): at least 40 cards
## with no upper limit, each card at most 3 times. Four lands, any land types,
## repeats allowed. Rainbow is a card colour, not a land.
const DECK_MIN := 40
const DECK_MAX_COPIES := 3
## No deck is bigger than this, an own deck (no upper limit by the rules) or a run deck (no
## copy limit): a pick code from the network or a file can't make the game build millions of cards.
const DECK_HARD_MAX := 2500
const LANE_COUNT := 4
## Own decks: the pick is "custom:<name>:<lands>:<card>=<copies>,..." (see custom_code).
const CUSTOM_PREFIX := "custom:"
const RUN_PREFIX := "run:"          # a run deck of «Бесконечный поезд», see run_code
const CUSTOM_NAME_MAX := 40

static var _defs: Dictionary = {}
static var _heroes: Dictionary = {}
static var _hero_order: Array = []
static var _hero_cards: Dictionary = {}
static var _hero_card_order: Array = []
static var _lands: Dictionary = {}
static var _items: Dictionary = {}
static var _item_order: Array = []
static var _custom_heroes: Dictionary = {}    # pick code -> hero dict, {} when illegal
static var _thumbs: Dictionary = {}           # small picture path -> whether it is there


static func ensure_loaded() -> void:
	if not _defs.is_empty():
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	assert(f != null, "cards.json not found")
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for c: Dictionary in data["cards"]:
		# JSON numbers arrive as floats; the rules engine works with ints.
		for k in INT_KEYS:
			if c.has(k):
				c[k] = int(c[k])
		_defs[c["id"]] = c
	_heroes = data["heroes"]
	_hero_order = data.get("hero_order", _heroes.keys())
	_hero_cards = data["hero_cards"]
	_hero_card_order = data.get("hero_card_order", _hero_cards.keys())
	_lands = data["lands"]
	for it: Dictionary in data.get("items", []):
		_items[it["id"]] = it
		_item_order.append(it["id"])


static func get_def(id: String) -> Dictionary:
	ensure_loaded()
	return _defs[id]


static func has_def(id: String) -> bool:
	ensure_loaded()
	return _defs.has(id)


static func hero(id: String) -> Dictionary:
	ensure_loaded()
	if is_custom(id):
		return _custom_hero(id)
	return _heroes[id]


static func has_hero(id: String) -> bool:
	ensure_loaded()
	if is_custom(id):
		return not _custom_hero(id).is_empty()
	return _heroes.has(id)


## Hero ids in the order the selection screen shows them.
static func hero_ids() -> Array:
	ensure_loaded()
	return _hero_order


static func hero_color(id: String) -> Color:
	if not has_hero(id):
		return Color.WHITE
	return Color(hero(id).get("color", "#ffffff"))


## Hero cards: {name, image, text, note?, power?, deck?}. A deck's own hero
## card has the deck's id; the other cards come without a deck.
static func hero_card(id: String) -> Dictionary:
	ensure_loaded()
	if id == NO_HERO:
		return NO_HERO_CARD
	return _hero_cards[id]


static func has_hero_card(id: String) -> bool:
	ensure_loaded()
	return _hero_cards.has(id)


static func hero_card_ids() -> Array:
	ensure_loaded()
	return _hero_card_order


## A small copy of a hero card's picture (tools/make_thumbs.gd) for the places that
## show it small: it loads many times faster than the full one. The full one when there is none.
static func hero_thumb(id: String) -> String:
	if id == NO_HERO:
		return NO_HERO_PICTURE
	var thumb := thumb_path(hero_card(id)["image"])
	return thumb if _has_thumb(thumb) else hero_image(id)


## A player's pick is a deck plus a hero card, written "deck" when the deck
## plays its own hero card and "deck@card" otherwise. "deck@" (no card after the @) plays
## the deck without a hero (no_hero): no hero ability at all.
static func loadout(deck: String, card: String) -> String:
	return deck if card == "" or card == deck else "%s@%s" % [deck, card]


## The hero card of a pick without a hero (loadout_card of "deck@").
const NO_HERO := ""
## What the screens show for it: a name, a line of text, the back of a card for its picture.
const NO_HERO_PICTURE := "res://assets/cards/sharp/_back.res"
const NO_HERO_CARD := {"name": "Без героя", "text": "Колода играет без карты героя.", "image": NO_HERO_PICTURE}


## The deck of a pick played without a hero.
static func no_hero(pick: String) -> String:
	return loadout_deck(pick) + "@"


static func is_no_hero(pick: String) -> bool:
	return pick.contains("@") and loadout_card(pick) == NO_HERO


## The pick of a player that plays `deck` with hero card `card` (NO_HERO: "deck@").
static func pick_of(deck: String, card: String) -> String:
	return deck + "@" if card == NO_HERO else loadout(deck, card)


## The same pick with its hero card back: the one it had, else the deck's own.
static func with_hero(pick: String, card := "") -> String:
	var deck := loadout_deck(pick)
	if card == "" or not has_hero_card(card):
		card = deck if has_hero_card(deck) else "finn"
	return loadout(deck, card)


static func loadout_deck(pick: String) -> String:
	return pick.get_slice("@", 0)


static func loadout_card(pick: String) -> String:
	return pick.get_slice("@", 1) if pick.contains("@") else pick


static func valid_loadout(pick: String) -> bool:
	return has_hero(loadout_deck(pick)) and (has_hero_card(loadout_card(pick)) or is_no_hero(pick))


## The deck limit printed on a hero card: the highest attack a creature in its deck may have.
const HERO_MAX_ATK := {"baby_finn_and_jake": 3}


## How a pick breaks the deck limit of its hero card, in Russian; "" when it keeps it.
## Not part of valid_loadout: self-play and old replays still play any deck with any card.
static func hero_deck_error(pick: String) -> String:
	var card := loadout_card(pick)
	if not HERO_MAX_ATK.has(card) or not has_hero(loadout_deck(pick)):
		return ""
	var top: int = HERO_MAX_ATK[card]
	var names := PackedStringArray()
	for id: String in hero(loadout_deck(pick)).get("deck", {}):
		var d: Dictionary = _defs.get(id, {})
		if d.get("kind", "") == "creature" and int(d.get("atk", 0)) > top:
			names.append("«%s»" % d["name"])
	if names.is_empty():
		return ""
	return "%s: в колоде не может быть существ с атакой больше %d — %s" % [hero_card(card)["name"], top, ", ".join(names)]


## The distinct land types of a hero's four landscapes, in first-seen order.
static func hero_land_types(id: String) -> Array:
	var out := []
	for t in hero(id)["lands"]:
		if not out.has(t):
			out.append(t)
	return out


static func land_name(land: String) -> String:
	ensure_loaded()
	return _lands[land]["name"]


## Landscape types a land can be (everything except "rainbow").
static func land_types() -> Array:
	ensure_loaded()
	return _lands.keys().filter(func(k): return k != "rainbow")


static func type_line(def: Dictionary) -> String:
	ensure_loaded()
	return _lands[def["land"]][def["kind"]]


## The picture a card is drawn with: the copy tools/make_sharp.gd makes of its scan.
static func image_path(id: String) -> String:
	return sharp_path(scan_path(id))


## A card's scan, the source of its pictures (the game itself does not load it).
static func scan_path(id: String) -> String:
	return "res://assets/cards/%s.webp" % id


## Where tools/make_sharp.gd puts the copy of a scan (a card's, a hero card's or the back).
static func sharp_path(scan: String) -> String:
	return scan.get_base_dir().path_join("sharp").path_join(scan.get_file().get_basename() + ".res")


## The picture a hero card is drawn with.
static func hero_image(id: String) -> String:
	if id == NO_HERO:
		return NO_HERO_PICTURE
	return sharp_path(hero_card(id)["image"])


## Where tools/make_thumbs.gd puts a card's small copy.
static func card_thumb_path(id: String) -> String:
	return thumb_path(scan_path(id))


## Where tools/make_thumbs.gd puts the small copy of a scan.
static func thumb_path(scan: String) -> String:
	return scan.get_base_dir().path_join("thumbs").path_join(scan.get_file().get_basename() + ".res")


## A card's picture for a place that shows it small: the small copy when there is one.
static func card_thumb(id: String) -> String:
	var thumb := card_thumb_path(id)
	return thumb if _has_thumb(thumb) else image_path(id)


static func _has_thumb(path: String) -> bool:
	if not _thumbs.has(path):
		_thumbs[path] = ResourceLoader.exists(path)
	return _thumbs[path]


# ---------------------------------------------------------------- own decks

static func is_custom(id: String) -> bool:
	return id.begins_with(CUSTOM_PREFIX) or id.begins_with(RUN_PREFIX)


## Every card id, in cards.json order.
static func card_ids() -> Array:
	ensure_loaded()
	return _defs.keys()


## The cards to pick from in the deck builder: without other printings of a card ("as": the same card
## with another translation, such as Кровавая крепость of the Lich's deck).
static func pool_ids() -> Array:
	ensure_loaded()
	return _defs.keys().filter(func(id): return not _defs[id].has("as"))


## Items of «Бесконечный поезд» ("ВЛАДЕНИЕ >>>" cards): {name, rarity, flavor, text}.
## Kept apart from card_ids(), so decks, trophies and the AI never see them.
static func item(id: String) -> Dictionary:
	ensure_loaded()
	return _items[id]


static func item_ids() -> Array:
	ensure_loaded()
	return _item_order


## Rules broken by a deck, in Russian. Empty when the deck is legal.
## free: a run deck, without the deck size and copy limits (one card is enough).
static func deck_errors(lands: Array, deck: Dictionary, free := false) -> Array:
	ensure_loaded()
	var errors := []
	if lands.size() != LANE_COUNT:
		errors.append("нужно ровно %d земли" % LANE_COUNT)
	for t in lands:
		if not land_types().has(t):
			errors.append("неизвестная земля «%s»" % t)
	var total := 0
	for id in deck:
		var copies := int(deck[id])
		if copies > DECK_HARD_MAX:
			errors.append("карт %d, можно не больше %d" % [copies, DECK_HARD_MAX])
			continue
		if not _defs.has(id):
			errors.append("нет карты «%s»" % id)
			continue
		if copies < 1 or (copies > DECK_MAX_COPIES and not free):
			errors.append("«%s»: от 1 до %d копий" % [_defs[id]["name"], DECK_MAX_COPIES])
		# Cards of printed cost 0 (Lands of Legend): only with a land of their type in the deck.
		var land: String = _defs[id]["land"]
		if int(_defs[id]["cost"]) == 0 and land != "rainbow" and not free and not lands.has(land):
			errors.append("«%s»: нужна земля «%s»" % [_defs[id]["name"], land_name(land)])
		total += copies
	if total < (1 if free else DECK_MIN):
		errors.append("карт %d, нужно не меньше %d" % [total, 1 if free else DECK_MIN])
	if total > DECK_HARD_MAX:
		errors.append("карт %d, можно не больше %d" % [total, DECK_HARD_MAX])
	return errors


## Pick code of an own deck. Cards are sorted so one deck has one code; lands
## keep their lane order. The name is percent-encoded, so the code has no
## separators inside it and can travel over the network as it is.
static func custom_code(name: String, lands: Array, deck: Dictionary) -> String:
	var ids := deck.keys()
	ids.sort()
	var entries := PackedStringArray()
	for id in ids:
		entries.append("%s=%d" % [id, int(deck[id])])
	return "%s%s:%s:%s" % [CUSTOM_PREFIX, name.uri_encode(),
		",".join(PackedStringArray(lands)), ",".join(entries)]


## Pick code of a run deck («Бесконечный поезд»): written like an own deck, with the
## ready deck the run started from in place of the name. The deck grows with the
## run, so it is free of the deck size and copy limits; it looks like that ready deck.
static func run_code(base: String, lands: Array, deck: Dictionary) -> String:
	return RUN_PREFIX + custom_code(base, lands, deck).trim_prefix(CUSTOM_PREFIX)


## {name, lands, deck} of a pick code, {} when the text is malformed.
## The rules are not checked here; see deck_errors.
static func parse_custom(code: String) -> Dictionary:
	if not is_custom(code):
		return {}
	var parts := code.trim_prefix(RUN_PREFIX if code.begins_with(RUN_PREFIX) else CUSTOM_PREFIX).split(":")
	if parts.size() != 3:
		return {}
	var lands := []
	for t in parts[1].split(",", false):
		lands.append(t)
	var deck := {}
	for entry in parts[2].split(",", false):
		var kv := entry.split("=")
		if kv.size() != 2 or not kv[1].is_valid_int() or deck.has(kv[0]):
			return {}
		deck[kv[0]] = int(kv[1])
	return {"name": parts[0].uri_decode(), "lands": lands, "deck": deck}


## Hero dict of a pick code: a legal own deck plays like a hero deck (its lands
## and cards). {} when the code is malformed or breaks the rules.
static func _custom_hero(code: String) -> Dictionary:
	if not _custom_heroes.has(code):
		if _custom_heroes.size() >= 512:
			_custom_heroes.clear()      # self-play makes a new random deck every game
		var d := parse_custom(code)
		var run := code.begins_with(RUN_PREFIX)
		var legal := not d.is_empty() and deck_errors(d["lands"], d["deck"], run).is_empty()
		if not legal:
			_custom_heroes[code] = {}
		else:
			_custom_heroes[code] = _run_hero_dict(d) if run else _custom_hero_dict(d)
	return _custom_heroes[code]


## A run deck shows as the ready deck it started from.
static func _run_hero_dict(d: Dictionary) -> Dictionary:
	if not _heroes.has(d["name"]):
		return {}
	var h: Dictionary = _heroes[d["name"]].duplicate()
	h["lands"] = d["lands"]
	h["deck"] = d["deck"]
	h["custom"] = true
	return h


static func _custom_hero_dict(d: Dictionary) -> Dictionary:
	var name := String(d["name"]).strip_edges()
	if name.is_empty():
		name = "Своя колода"
	return {"name": name, "full": name, "lands": d["lands"], "deck": d["deck"],
		"color": "#c7a6ff", "bg": ["#2a2140", "#8a6cc4"], "letter": name.substr(0, 1).to_upper(), "custom": true}
