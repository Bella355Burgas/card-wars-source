extends RefCounted
## «Песочница» from the main screen (main.gd): the «Играть» menu asks for the table (1 на 1,
## 2 на 2, на троих), then the heroes and decks as for any game; the deck builder starts it with
## the deck on it and its hero against the last opponent. The game itself: board.gd enable_sandbox,
## scripts/core/sandbox.gd. Nothing of it counts anywhere: no journal (no replay, nothing for the
## server to check), no rating, no train, no network.

const Main = preload("res://scripts/ui/main.gd")
const Game = preload("res://scripts/core/game.gd")
const Sandbox = preload("res://scripts/core/sandbox.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")

## The hero select modes of the sandbox and their seats.
const MODES := {"sandbox": 2, "sandbox_teams": 4, "sandbox_three": 3}

var m: Main
var heroes: Array = []             # the picks of the game on the table
var builder_back := {}             # started from the deck builder: {"code", "hero"} to go back to it
var _ai_try := 0                   # bumped by every switch of the AI: a late answer is dropped


func _init(main: Main) -> void:
	m = main


static func is_mode(mode: String) -> bool:
	return MODES.has(mode)


## «Песочница» of the «Играть» menu: which table.
func show_tables() -> void:
	m._close_play_menu()
	if m._overlay_open:
		return
	var root := m._overlay_root(Color(0.02, 0.01, 0.05, 0.6))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", m._panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(m._title("Песочница"))
	for it in [["1 на 1", "sandbox", UI.ORANGE], ["2 на 2", "sandbox_teams", UI.BLUE], ["На троих", "sandbox_three", UI.GREEN]]:
		var mode: String = it[1]
		var bt := WoodUI.button(it[0], it[2], 30, Vector2(380, 70))
		bt.pressed.connect(func():
			m._close_overlay(root)
			m.show_hero_select(mode))
		v.add_child(bt)
	var back := WoodUI.button("Назад", WoodUI.BACK, 26, Vector2(380, 60))
	back.pressed.connect(func():
		m._close_overlay(root)
		m._back_to_play())
	v.add_child(back)
	m._pop_in(v)


## The first picks the hero select shows for a sandbox mode.
func start_picks(mode: String) -> Array:
	var n: int = MODES[mode]
	if n == 2:
		return m._last_heroes.duplicate()
	return m.seat_state("teams" if n == 4 else "three")["heroes"].duplicate()


## From the deck builder: the deck on it (any, even one that breaks the rules: a run deck has
## no limits; an empty one starts with no cards) against the opponent of the last game. A window
## asks first whether the deck plays with the hero chosen in the builder or alone.
func from_builder(deck_name: String, lands: Array, deck: Dictionary, hero: String) -> String:
	lands = _good_lands(lands)
	var empty := deck.is_empty()
	var cards: Dictionary = {"evil_eye": 1} if empty else deck      # a card to set up with, taken away at once
	var pick := CardDB.custom_code(deck_name, lands, cards)
	if not CardDB.has_hero(pick):
		var base := String(CardDB.hero_card(hero).get("deck", "")) if CardDB.has_hero_card(hero) else ""
		if base == "" or not CardDB.has_hero(base):
			base = "finn"
		pick = CardDB.run_code(base, lands, cards)
	var card := hero if CardDB.has_hero_card(hero) else ""
	var me := CardDB.loadout(pick, card if card != "" else base_of(pick))
	if not CardDB.valid_loadout(me):
		return "Эту колоду не получается открыть"
	_ask_hero(me, card, deck_name.strip_edges() if deck_name.strip_edges() != "" else "Своя колода", empty,
		{"code": CardDB.custom_code(deck_name, lands, deck), "hero": hero})
	return ""


## Four known land types: a deck from a file may have fewer or unknown ones.
static func _good_lands(lands: Array) -> Array:
	var out := []
	for i in CardDB.LANE_COUNT:
		var t := String(lands[i]) if i < lands.size() else ""
		out.append(t if CardDB.land_types().has(t) else "plain")
	return out


## The window over the builder: the hero of the deck or none, then «Начать».
func _ask_hero(pick: String, card: String, deck_name: String, empty: bool, back: Dictionary) -> void:
	var root := m._overlay_root(Color(0.02, 0.01, 0.05, 0.7))
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", m._panel_box())
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(m._title("Песочница"))
	var state := {"hero": card != ""}
	var pic_box := CenterContainer.new()
	pic_box.custom_minimum_size = Vector2(0, 300)
	# A phone: the hero card at the left, the name and the buttons at its right (the screen is low).
	var col: VBoxContainer = v
	if m.phone_layout:
		var body := HBoxContainer.new()
		body.add_theme_constant_override("separation", 24)
		v.add_child(body)
		body.add_child(pic_box)
		col = VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 16)
		body.add_child(col)
	else:
		v.add_child(pic_box)
	var name_l := WoodUI.label("", 30, UI.CREAM, 6)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_l)
	var toggle := _hero_toggle(card, state)
	col.add_child(toggle)
	var show := func():
		for ch in pic_box.get_children():
			ch.queue_free()
		pic_box.visible = card != ""
		if card != "":
			# Without the hero its card stays pale, as in the hero select.
			var pic := m._hero_card_rect(card, Vector2(218, 300))
			pic.modulate = Color.WHITE if state["hero"] else Color(1, 1, 1, 0.35)
			pic_box.add_child(pic)
		name_l.text = "%s · %s" % [CardDB.hero_card(card)["name"], deck_name] if state["hero"] else deck_name
	toggle.pressed.connect(show)
	show.call()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	var cancel := WoodUI.button("Назад", WoodUI.BACK, 26, Vector2(200, 64))
	cancel.pressed.connect(func(): m._close_overlay(root))
	row.add_child(cancel)
	var go := WoodUI.button("Начать", WoodUI.GO, 30, Vector2(240, 64))
	go.set_meta("kn_primary", true)
	go.pressed.connect(func():
		builder_back = back
		for ch in m.overlay.get_children():
			m._close_overlay(ch)
		start([pick, m._last_heroes[1]], [not state["hero"], false], [empty, false], {0: deck_name}))
	row.add_child(go)
	m._pop_in(v)


## «С героем» / «Без героя»: a switch of the seat's state["hero"]; with no hero card it stays off.
func _hero_toggle(card: String, state: Dictionary) -> Button:
	var bt := WoodUI.button("", UI.ORANGE, 26, Vector2(460, 64))
	var paint := func():
		bt.text = "С героем" if state["hero"] else "Без героя"
	bt.pressed.connect(func():
		state["hero"] = not state["hero"] and card != ""
		paint.call())
	bt.disabled = card == ""
	paint.call()
	return bt


## The hero card for a deck built with none: Finn, or the ready deck a run deck stands for.
static func base_of(pick: String) -> String:
	var d := CardDB.parse_custom(pick)
	if pick.begins_with(CardDB.RUN_PREFIX) and not d.is_empty() and CardDB.has_hero_card(String(d["name"])):
		return String(d["name"])
	return "finn"


## A sandbox game: two, three or four seats, everything played from here, the first player first.
## no_hero: seats that play their deck without the hero card; empty: seats that start with no
## cards at all; names: seat -> the name of its deck (shown without a hero).
func start(picks: Array, no_hero := [], empty := [], names := {}) -> void:
	m._clear_title()
	m._end_game()
	heroes = picks.duplicate()
	m.online = false
	m.ai_mode = false
	m._ai_vs_ai_mode = false
	m.seat = 0
	m._mode = "sandbox"
	m.game = Game.new()
	var my_game = m.game
	m.game.setup(heroes, 0)
	var sb = Sandbox.new(m.game)
	sb.deck_names = names.duplicate()
	for p in heroes.size():
		if p < empty.size() and empty[p]:
			sb.clear_cards(p)
		if p < no_hero.size() and no_hero[p]:
			await sb.set_hero(p, "", true)
	m._new_board()
	m.board.enable_sandbox(sb)
	m.board.sandbox_ai.connect(_on_ai)
	await m.board.run_engine(func(): await m.game.start_game())
	if m.game != my_game:
		return
	# No first turn without floops and attacks: everything can be tried at once.
	m.game.turn_number = m.game.players.size()
	m.board.sync()
	m.board._update_hud()
	sb.mark_start()


## The AI of the other seats on or off (the switch of the panel). Its networks are read first.
func _on_ai(on: bool) -> void:
	_ai_try += 1
	var my_try := _ai_try
	var board = m.board
	if not on:
		board.sb_set_ai({})
		board.sb_panel.ai_done()
		return
	var pairs := []
	for p in range(1, heroes.size()):
		pairs.append([m._ai_levels[1], heroes[p]])
	if not await m._wait_ai(pairs) or my_try != _ai_try or m.board != board:
		return
	var agents := {}
	for p in range(1, heroes.size()):
		agents[p] = AILevels.agent(m._ai_levels[1], heroes[p])
	board.sb_set_ai(agents)
	board.sb_panel.ai_done()


## The pause menu of a sandbox: back to the deck builder when it came from there.
func back_to_builder() -> void:
	var back := builder_back
	builder_back = {}
	m._end_game()
	m.show_title()
	m.show_deck_builder(String(back["code"]), Callable(), "", String(back["hero"]))
