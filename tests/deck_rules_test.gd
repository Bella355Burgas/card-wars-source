extends SceneTree
## Own deck rules, pick codes and storage, headless:
##   godot --headless --path . -s res://tests/deck_rules_test.gd

const CardDB = preload("res://scripts/core/card_db.gd")
const CustomDecks = preload("res://scripts/core/custom_decks.gd")
const Game = preload("res://scripts/core/game.gd")

const TEST_NAME := "__rules_test__"

var failures := 0


func _initialize() -> void:
	check_builtin_decks()
	check_rules()
	check_codes()
	check_picks()
	check_game_setup()
	check_storage()
	print("deck rules tests: %d checks failed" % failures)
	quit(1 if failures > 0 else 0)


func expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## A deck of `total` cards from the pool, each taken `copies` times at most.
func pool_deck(total: int, copies := 1) -> Dictionary:
	var deck := {}
	var ids := CardDB.card_ids()
	var sum := 0
	var i := 0
	while sum < total:
		var n := mini(copies, total - sum)
		deck[ids[i]] = n
		sum += n
		i += 1
	return deck


func with_copies(deck: Dictionary, id: String, copies: int) -> Dictionary:
	var out := deck.duplicate()
	out[id] = copies
	return out


func plain4() -> Array:
	return ["plain", "plain", "plain", "plain"]


func check_builtin_decks() -> void:
	for hero in CardDB.hero_ids():
		var h := CardDB.hero(hero)
		var errors := CardDB.deck_errors(h["lands"], h["deck"])
		expect(errors.is_empty(), "built-in deck %s breaks the rules: %s" % [hero, errors])


func check_rules() -> void:
	expect(CardDB.deck_errors(plain4(), pool_deck(40)).is_empty(), "40 cards, one land type: legal")
	expect(CardDB.deck_errors(plain4(), pool_deck(60)).is_empty(), "no upper limit on deck size")
	expect(not CardDB.deck_errors(plain4(), pool_deck(39)).is_empty(), "39 cards: illegal")
	expect(CardDB.deck_errors(plain4(), pool_deck(40, 3)).is_empty(), "every card 3 times: legal")
	var first_card: String = CardDB.card_ids()[0]
	expect(not CardDB.deck_errors(plain4(), with_copies(pool_deck(40), first_card, 4)).is_empty(),
		"a card 4 times: illegal")
	expect(not CardDB.deck_errors(plain4(), with_copies(pool_deck(40), first_card, 0)).is_empty(),
		"a card 0 times: illegal")
	expect(CardDB.deck_errors(["corn", "sandy", "swamp", "plain"], pool_deck(40)).is_empty(),
		"four different lands: legal")
	expect(CardDB.deck_errors(["ice", "ice", "ice", "ice"], pool_deck(40)).is_empty(),
		"four identical lands: legal")
	expect(not CardDB.deck_errors(["plain", "plain", "plain"], pool_deck(40)).is_empty(), "three lands: illegal")
	expect(not CardDB.deck_errors(["plain"].slice(0, 1) + plain4(), pool_deck(40)).is_empty(), "five lands: illegal")
	expect(not CardDB.deck_errors(["rainbow", "plain", "plain", "plain"], pool_deck(40)).is_empty(),
		"rainbow is not a land")
	expect(not CardDB.deck_errors(["nope", "plain", "plain", "plain"], pool_deck(40)).is_empty(), "unknown land")
	var with_dog := with_copies(pool_deck(40), "fire_dog", 1)
	expect(not CardDB.deck_errors(plain4(), with_dog).is_empty(), "cost 0 card without its land: illegal")
	expect(CardDB.deck_errors(["lava", "plain", "plain", "plain"], with_dog).is_empty(), "cost 0 card with its land: legal")
	expect(CardDB.deck_errors(plain4(), with_dog, true).is_empty(), "run deck: cost 0 card without its land is fine")
	var with_unknown := pool_deck(39)
	with_unknown["no_such_card"] = 1
	expect(not CardDB.deck_errors(plain4(), with_unknown).is_empty(), "unknown card")


func check_codes() -> void:
	var deck := pool_deck(40, 2)
	var lands := ["corn", "sandy", "plain", "ice"]
	var deck_name := "Тест: «Ё» @,=*;%"
	var code := CardDB.custom_code(deck_name, lands, deck)
	expect(CardDB.is_custom(code), "code has the custom prefix")
	expect(not code.contains("@"), "code has no hero-card separator")
	var parsed := CardDB.parse_custom(code)
	expect(parsed.get("name") == deck_name, "name survives the round trip")
	expect(parsed.get("lands") == lands, "lands keep their lane order")
	expect(parsed.get("deck") == deck, "deck survives the round trip")

	var reversed := {}
	var ids := deck.keys()
	ids.reverse()
	for id in ids:
		reversed[id] = deck[id]
	expect(CardDB.custom_code(deck_name, lands, reversed) == code, "same deck, same code")

	for bad in ["finn", "custom:", "custom:a:b", "custom:n:plain:x=1,x=2", "custom:n:plain:x=y", "custom:a:b:c:d"]:
		expect(CardDB.parse_custom(bad).is_empty(), "malformed code rejected: " + bad)


func check_picks() -> void:
	var legal := CardDB.custom_code("Легальная", plain4(), pool_deck(40))
	var short := CardDB.custom_code("Короткая", plain4(), pool_deck(39))
	expect(CardDB.has_hero(legal), "legal own deck is a hero")
	expect(not CardDB.has_hero(short), "own deck of 39 cards is not a hero")
	expect(CardDB.hero(legal)["deck"] == pool_deck(40), "hero dict carries the deck")
	expect(CardDB.hero(legal)["lands"] == plain4(), "hero dict carries the lands")
	expect(CardDB.hero(CardDB.custom_code("", plain4(), pool_deck(40)))["name"] == "Своя колода",
		"an unnamed deck gets the default name")
	expect(CardDB.valid_loadout(CardDB.loadout(legal, "finn")), "legal own deck with a hero card is a valid pick")
	expect(not CardDB.valid_loadout(CardDB.loadout(short, "finn")), "illegal own deck is not a valid pick")
	expect(CardDB.loadout_deck(CardDB.loadout(legal, "jake")) == legal, "pick splits back into deck and card")
	expect(CardDB.loadout_card(CardDB.loadout(legal, "jake")) == "jake", "pick keeps the hero card")
	expect(CardDB.hero_color(legal) == Color("#c7a6ff"), "own deck has its colour")
	# Малыши Финн и Джейк: no creature with attack above 3 in the deck.
	expect(CardDB.hero_deck_error("charlie@baby_finn_and_jake").contains("Очаровательный слон"),
		"Малыши Финн и Джейк: Чарли с Очаровательным слоном 4/4 закрыт")
	expect(CardDB.hero_deck_error("finn@baby_finn_and_jake") == "", "Малыши Финн и Джейк: колода Финна подходит")
	expect(CardDB.hero_deck_error("charlie") == "", "other hero cards have no attack limit")
	var big := pool_deck(40)
	big["husker_worm"] = 1
	expect(CardDB.hero_deck_error(CardDB.loadout(CardDB.custom_code("Большая", ["corn", "corn", "corn", "corn"], big), "baby_finn_and_jake")) != "",
		"Малыши Финн и Джейк: своя колода с атакой 5 закрыта")


func check_game_setup() -> void:
	var lands := ["ice", "corn", "lava", "plain"]
	var deck := pool_deck(40, 3)
	var code := CardDB.custom_code("Игровая", lands, deck)
	var first := Game.new()
	first.setup([code, "jake"], 0, 11)
	var p: RefCounted = first.players[0]
	expect(p.deck.size() + p.hand.size() == 40, "own deck: 40 cards in play at setup")
	var types: Array = p.lands.map(func(l): return l["type"])
	expect(types == lands, "own deck: lands placed in lane order")
	var second := Game.new()
	second.setup([code, "jake"], 0, 11)
	expect(first.state_hash() == second.state_hash(), "same code and seed: identical setup on both machines")


func check_storage() -> void:
	var code := CardDB.custom_code(TEST_NAME, plain4(), pool_deck(40))
	var entry := {"name": TEST_NAME, "lands": plain4(), "deck": pool_deck(40)}
	expect(CustomDecks.put(entry), "saving a deck writes the file")
	expect(CustomDecks.codes().has(code), "a saved legal deck is offered for play")
	expect(CustomDecks.put({"name": TEST_NAME, "lands": plain4(), "deck": pool_deck(10)}),
		"saving a draft writes the file")
	expect(not CustomDecks.codes().has(code), "a draft replaces the saved deck and is not offered")
	CustomDecks.remove(TEST_NAME)
	expect(not CustomDecks.load_all().any(func(e): return e.get("name", "") == TEST_NAME),
		"the test deck is removed from storage")
	check_deck_files()


## Deck files (*.cwdeck): written, read back, added to the saved decks without
## overwriting a different deck of the same name.
func check_deck_files() -> void:
	var path := "user://__deck_file_test.cwdeck"
	var entry := {"name": TEST_NAME, "lands": ["plain", "corn", "plain", "corn"], "deck": pool_deck(40)}
	expect(CustomDecks.write_file(path, entry), "a deck file is written")
	var back := CustomDecks.read_file(path)
	expect(CustomDecks.code_of(back) == CustomDecks.code_of(entry), "a deck file reads back as the same deck")
	expect(CustomDecks.add(back) == TEST_NAME, "a new deck is added under its own name")
	expect(CustomDecks.add(back) == TEST_NAME, "adding the same deck again does not make a copy")
	var other := {"name": TEST_NAME, "lands": plain4(), "deck": pool_deck(41)}
	var other_name := CustomDecks.add(other)
	expect(other_name == TEST_NAME + " (2)", "another deck with a taken name gets a number: '%s'" % other_name)
	expect(CustomDecks.codes().has(CustomDecks.code_of(back)), "the added deck is offered for play")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"cardwars\": \"replay\", \"steps\": []}")
	f.close()
	expect(CustomDecks.read_file(path).is_empty(), "a file that is not a deck is refused")
	CustomDecks.remove(TEST_NAME)
	CustomDecks.remove(other_name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
