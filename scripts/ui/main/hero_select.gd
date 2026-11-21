extends RefCounted
## Hero selection (main.gd): the seats, the hero card grid, the deck tiles, the info panel.
## Its functions work on the main screen `m`, which keeps all the state.

const Main = preload("res://scripts/ui/main.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const CustomDecks = preload("res://scripts/core/custom_decks.gd")
const DeckBuilder = preload("res://scripts/ui/deck_builder.gd")
const DeckTiles = preload("res://scripts/ui/deck_tiles.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const SandboxStart = preload("res://scripts/ui/main/sandbox_start.gd")
const Phone = preload("res://scripts/ui/phone.gd")

var m: Main
var _net_root: Control = null     # the window of mode "net" while it is open


func _init(main: Main) -> void:
	m = main


## The window of mode "net" is closed when the online game starts or the other player goes.
func close_net() -> void:
	if _net_root != null and is_instance_valid(_net_root):
		m._close_overlay(_net_root)
	_net_root = null


## mode: "hotseat" | "ai" | "aivsai" | "net" (one slot: your own hero).
## Each seat picks in two steps: a hero card (its ability), then a deck. A deck's
## own hero card comes with it, the other cards play with any deck.
## The window fills the screen: with a bigger interface scale its cards and texts grow and the
## grids take fewer columns; only a screen smaller than its minimum scales it down (_fill_screen).
func show_hero_select(mode: String) -> void:
	m._close_play_menu()
	if m._overlay_open and mode != "net":
		return
	if mode == "net":
		close_net()
	var root := m._overlay_root(Color(0.03, 0.02, 0.07, 0.0))
	if mode == "net":
		_net_root = root
	# Finn and Jake's Card Wars table: the seats, the mat with the cards and a note on it.
	root.add_child(WoodUI.table())
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	var v := HBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 22)
	frame.add_child(v)
	var titles := {"hotseat": "Выбор героев", "ai": "Игра против ИИ", "aivsai": "ИИ против ИИ", "net": "Твой герой",
		"run": "Бесконечный поезд", "teams": "2 на 2", "three": "На троих",
		"sandbox": "Песочница", "sandbox_teams": "Песочница 2 на 2", "sandbox_three": "Песочница на троих"}
	var teams := mode == "teams" or mode == "sandbox_teams"
	# 2 на 2 and на троих: every seat played by the AI or a person, as main.gd seat_state keeps it.
	var seated := teams or mode == "three"
	var ss: Dictionary = m.seat_state(mode) if seated else {}

	# Left: the title and the seats; right: the steps, the cards and the text of the card.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2((430 if Phone.active else Main.SEAT_W) * WoodUI.font_scale, 0)
	left.add_theme_constant_override("separation", 12)
	v.add_child(left)
	var t := WoodUI.title_tag(titles[mode], 34)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(t)
	var seats_box := VBoxContainer.new()
	seats_box.alignment = BoxContainer.ALIGNMENT_CENTER
	seats_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	seats_box.add_theme_constant_override("separation", 6 if teams or Phone.active else 14)
	if Phone.active:
		# A phone: the seats scroll under the finger (2 на 2 has four of them).
		var seats_scroll := ScrollContainer.new()
		seats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		seats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		seats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seats_scroll.add_child(seats_box)
		left.add_child(seats_scroll)
	else:
		left.add_child(seats_box)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	v.add_child(right)

	var slot_names: Array
	match mode:
		"hotseat":
			slot_names = ["Игрок 1", "Игрок 2"]
		"ai":
			slot_names = ["Ты", "ИИ"]
		"aivsai":
			slot_names = ["ИИ 1", "ИИ 2"]
		"teams":
			slot_names = Main.TEAMS_SLOTS
		"three", "sandbox_three":
			slot_names = Main.THREE_SLOTS
		"sandbox_teams":
			slot_names = Main.TEAMS_SLOTS
		"sandbox":
			slot_names = ["Ты", "Соперник"]
		_:
			slot_names = ["Ты"]
	var picks: Array = []
	var randoms: Array = []
	for i in slot_names.size():
		var start_pick: String = m.my_hero if mode == "net" else (ss["heroes"][i] if seated else m._last_heroes[i])
		if mode == "run":
			start_pick = m._run_hero()
		elif SandboxStart.is_mode(mode):
			start_pick = m.sandbox_start.start_picks(mode)[i]
		picks.append(_legal_pick(start_pick))
		randoms.append(ss["random"][i] if seated else false)
	# hover: the card or deck under the pointer, shown in the text panel ("" = the active seat's).
	var state := {"active": 0, "step": "hero", "shown": "", "hover": ""}

	var slot_ui: Array = []
	slot_ui.resize(slot_names.size())
	# 2 на 2: your team first, the opponents below.
	for i: int in ([0, 2, 1, 3] if teams else range(slot_names.size())):
		if teams and i == 1:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 4)
			seats_box.add_child(gap)
		slot_ui[i] = _hero_slot(seats_box, slot_names[i], Main.SLOT_COLORS[i], teams)
	if mode == "run" and m._run_open() > 0:
		var diff := m._difficulty_picker(roundi((Main.SEAT_W - 140) * WoodUI.font_scale))
		diff.alignment = BoxContainer.ALIGNMENT_CENTER
		seats_box.add_child(diff)
	var ai_slots: Array = {"ai": [1], "aivsai": [0, 1], "teams": [0, 1, 2, 3], "three": [0, 1, 2]}.get(mode, [])
	var levels: Array = ss["levels"] if seated else m._ai_levels
	# «С героем» / «Без героя»: a seat may play its deck without a hero card ("deck@"). Not in a
	# run of the train: it has its own hero. The card a seat had comes back with the switch.
	var hero_switch := mode != "run"
	var last_card := {}

	# Steps: 1 hero card, 2 deck; the seat that picks is named in its colour.
	var steps := HBoxContainer.new()
	steps.alignment = BoxContainer.ALIGNMENT_CENTER
	steps.add_theme_constant_override("separation", 14)
	# The «Онлайн» button of the corner lies over the top right: the steps go left of it, and where
	# they do not fit there, under it.
	var steps_room := MarginContainer.new()
	steps_room.add_child(steps)
	right.add_child(steps_room)
	var fit_steps := func():
		var corner: Vector2 = Vector2.ZERO if Phone.active else m.social_ui.corner_room()     # a phone hides it
		var beside: bool = steps.get_combined_minimum_size().x + corner.x <= right.size.x
		steps_room.add_theme_constant_override("margin_right", roundi(corner.x) if beside else 0)
		steps_room.add_theme_constant_override("margin_top", 0 if beside else roundi(corner.y))
	right.resized.connect(func(): fit_steps.call_deferred())
	steps.minimum_size_changed.connect(func(): fit_steps.call_deferred())
	var who := WoodUI.text("", 28, Color.WHITE, true, 7)
	who.visible = slot_ui.size() > 1
	steps.add_child(who)
	var who_gap := Control.new()
	who_gap.custom_minimum_size = Vector2(8, 0)
	who_gap.visible = who.visible
	steps.add_child(who_gap)
	var step_hero := WoodUI.tab("1  Герой", 26, Vector2(210, 52))
	steps.add_child(step_hero)
	var arrow := WoodUI.text("›", 40, WoodUI.PAPER, true, 6)
	steps.add_child(arrow)
	var step_deck := WoodUI.tab("2  Колода", 26, Vector2(210, 52))
	steps.add_child(step_deck)

	# Both steps take the same place, so the screen does not jump between them.
	var pages_panel := PanelContainer.new()
	pages_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages_panel.custom_minimum_size = Vector2(560, 150) if Phone.active else Vector2(560, 240)
	pages_panel.add_theme_stylebox_override("panel", WoodUI.mat())
	right.add_child(pages_panel)
	var pages := Control.new()
	pages.clip_contents = true
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages_panel.add_child(pages)
	var hero_page := _picker_page(pages)
	var grid := GridContainer.new()
	grid.name = "HeroGrid"
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	hero_page.get_child(0).add_child(grid)
	var tiles := {}

	var deck_page := _picker_page(pages)
	var deck_grid := GridContainer.new()
	deck_grid.name = "DeckGrid"
	deck_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	deck_grid.add_theme_constant_override("h_separation", 12)
	deck_grid.add_theme_constant_override("v_separation", 12)
	deck_page.get_child(0).add_child(deck_grid)
	var deck_tiles := {}
	var faces := DeckTiles.new()
	var face_timer := Timer.new()
	face_timer.wait_time = 0.05
	root.add_child(face_timer)
	face_timer.timeout.connect(func():
		if faces.poll():
			face_timer.stop())
	root.tree_exiting.connect(faces.drain)
	# As many columns as the page's width takes.
	var fit_columns := func():
		var room: float = pages.size.x - 2.0 * Main.PAGE_MARGIN - 20.0     # and the scroll bar
		for g: GridContainer in [grid, deck_grid]:
			if g.get_child_count() == 0:
				continue
			var tile_w: float = g.get_child(0).get_combined_minimum_size().x
			var gap: float = g.get_theme_constant("h_separation")
			g.columns = maxi(1, floori((room + gap) / (tile_w + gap)))
	# Deferred: a tile's new frame changes its size only after this frame's layout.
	pages.resized.connect(func(): fit_columns.call_deferred())

	# The text of the card under the pointer, or of the active seat's card: always the same
	# size, a long text takes a smaller font instead of more room.
	var info := _info_panel()
	# A phone: the note and, at its right, the two buttons one over the other.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	if Phone.active:
		info["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(info["panel"])
		right.add_child(bottom)
	else:
		right.add_child(info["panel"])
	var show_info := func():
		var a: int = state["active"]
		var hover: String = state["hover"]
		for ch in info["lands"].get_children():
			ch.queue_free()
		if hover.begins_with("deck:"):
			var d := hover.substr(5)
			if d == "":
				_set_info(info, "Новая колода", WoodUI.PAPER_DARK, "", "Собрать свою колоду")
				return
			var broken := CardDB.hero_deck_error(CardDB.loadout(d, CardDB.loadout_card(picks[a])))
			var own: bool = CardDB.hero_card(CardDB.loadout_card(picks[a])).get("deck", "") == d
			var tag: String = "Колода героя" if own else ("Своя колода" if CardDB.is_custom(d) else ("Фан-колода" if CardDB.hero(d).get("fan", false) else ""))
			info["lands"].add_child(_land_row(d, 26))
			var counts := DeckTiles.summary(d).get_slice(": ", 1)
			_set_info(info, CardDB.hero(d)["name"], CardDB.hero_color(d), tag,
				counts.left(1).to_upper() + counts.substr(1) + ("\n" + broken if broken != "" else ""))
			return
		var card := hover.substr(5) if hover.begins_with("card:") else ""
		if card == "" and randoms[a]:
			_set_info(info, "Случайный", WoodUI.VIOLET, "", "Случайная колода со своей картой героя.")
			return
		if card == "":
			card = CardDB.loadout_card(picks[a])
		var hc := CardDB.hero_card(card)
		var deck: String = hc.get("deck", "")
		var tag: String = "Фан-карта" if hc.get("fan", false) else ("Колода: " + CardDB.hero(deck)["name"] if deck != "" else "Любая колода")
		var col := CardDB.hero_color(deck if deck != "" else CardDB.loadout_deck(picks[a]))
		_set_info(info, hc["name"], col, tag, hc["text"])

	var refresh := func():
		var a: int = state["active"]
		for i in slot_ui.size():
			_fill_hero_slot(slot_ui[i], picks[i], randoms[i], a == i and slot_ui.size() > 1)
			if not randoms[i]:
				m._warm_hero_pic(CardDB.loadout_card(picks[i]))
		for i in slot_ui.size():
			if slot_ui[i].has("hero_btn"):
				var none: bool = CardDB.is_no_hero(picks[i]) and not randoms[i]
				slot_ui[i]["hero_btn"].text = "Без героя" if none else "С героем"
				slot_ui[i]["card"].modulate = Color(1, 1, 1, 0.35) if none else Color.WHITE
		for i in ai_slots:
			AILevels.warm(levels[i], picks[i])      # read while the player picks, not after «В бой!»
			var lv := AILevels.level(levels[i])
			slot_ui[i]["level"].text = lv["name"]
			slot_ui[i]["level"].label_settings.font_color = lv["color"]
			if seated:
				slot_ui[i]["level_box"].visible = ss["ai"][i]
				if slot_ui[i].has("who"):
					slot_ui[i]["who"].text = "ИИ" if ss["ai"][i] else "Человек"
		for id in tiles:
			var marks := []
			for i in picks.size():
				if CardDB.loadout_card(picks[i]) == id and not randoms[i]:
					marks.append(i)
			_style_hero_tile(tiles[id], marks)
		var own_deck: String = CardDB.hero_card(CardDB.loadout_card(picks[a])).get("deck", "")
		for id: String in deck_tiles:
			var marks := []
			for i in picks.size():
				if CardDB.loadout_deck(picks[i]) == id and not randoms[i]:
					marks.append(i)
			DeckTiles.style(deck_tiles[id], marks, Main.SLOT_COLORS)
			deck_tiles[id]["ribbon"].visible = id == own_deck and not randoms[a]
			# Decks the hero card does not allow stay dim and do not take a click.
			var broken := CardDB.hero_deck_error(CardDB.loadout(id, CardDB.loadout_card(picks[a]))) != ""
			deck_tiles[id]["panel"].modulate = Color(0.4, 0.4, 0.46) if broken else Color.WHITE
		who.text = slot_names[a] + ":"
		who.label_settings.font_color = Main.SLOT_COLORS[a]
		who_gap.visible = who.visible
		var on_deck: bool = state["step"] == "deck"
		WoodUI.set_tab(step_hero, not on_deck)
		WoodUI.set_tab(step_deck, on_deck)
		hero_page.visible = not on_deck
		deck_page.visible = on_deck
		if state["shown"] != state["step"]:
			state["shown"] = state["step"]
			state["hover"] = ""
			fit_columns.call_deferred()
			var page: Control = deck_page if on_deck else hero_page
			page.modulate.a = 0.0
			page.position.y = 24
			var tw := page.create_tween().set_parallel()
			tw.tween_property(page, "modulate:a", 1.0, 0.18)
			tw.tween_property(page, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		show_info.call()
	var hover := func(what: String):
		state["hover"] = what
		show_info.call()
	var go_step := func(step: String):
		if state["step"] != step:
			UI.sfx("select")
		state["step"] = step
		refresh.call()
	step_hero.pressed.connect(func(): go_step.call("hero"))
	step_deck.pressed.connect(func(): go_step.call("deck"))

	for id: String in CardDB.hero_card_ids():
		var tile := _hero_tile(id)
		grid.add_child(tile)
		tiles[id] = tile
		tile.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
				hover.call("card:" + id)
				return
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				var a: int = state["active"]
				var deck: String = CardDB.hero_card(id).get("deck", CardDB.loadout_deck(picks[a]))
				picks[a] = _legal_pick(CardDB.loadout(deck, id))
				randoms[a] = false
				UI.sfx("select")
				state["step"] = "deck"
				refresh.call())
		tile.mouse_entered.connect(func(): hover.call("card:" + id))
		tile.mouse_exited.connect(func():
			if state["hover"] == "card:" + id:
				hover.call(""))

	# A deck goes to the picking seat; then the next seat picks its hero.
	var take_deck := func(deck: String):
		var a: int = state["active"]
		var pick := CardDB.no_hero(deck) if CardDB.is_no_hero(picks[a]) else CardDB.loadout(deck, CardDB.loadout_card(picks[a]))
		if CardDB.hero_deck_error(pick) != "":
			hover.call("deck:" + deck)       # the text says why the deck does not go
			return
		picks[a] = pick
		randoms[a] = false
		if a + 1 < slot_ui.size():
			state["active"] = a + 1
			state["step"] = "hero"
		refresh.call()
	var from_builder := func(code: String, hero: String):
		state["build"].call()
		var a: int = state["active"]
		if hero != "" and not randoms[a]:
			picks[a] = CardDB.loadout(CardDB.loadout_deck(picks[a]), hero)
		take_deck.call(code)
	var build_decks := func():
		for ch in deck_grid.get_children():
			deck_grid.remove_child(ch)
			ch.queue_free()
		deck_tiles.clear()
		var decks: Array = CardDB.hero_ids() if mode == "run" else _deck_choices()
		for d: String in decks + ([] if mode == "run" else [""]):
			var dt := faces.tile(d, false)
			deck_grid.add_child(dt["panel"])
			if d != "":
				deck_tiles[d] = dt
			else:
				DeckTiles.style(dt, [], Main.SLOT_COLORS)
			dt["panel"].gui_input.connect(func(e):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
					hover.call("deck:" + d)
					return
				if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
					return
				UI.sfx("select")
				if d != "":
					take_deck.call(d)
					return
				# A new own deck: the builder, then the finished deck goes to the seat
				# with the hero it was built for.
				show_deck_builder("", from_builder, "", CardDB.loadout_card(picks[state["active"]])))
			if dt["edit"] != null:
				dt["edit"].pressed.connect(func():
					show_deck_builder(d, from_builder, "", CardDB.loadout_card(picks[state["active"]])))
			dt["panel"].mouse_entered.connect(func(): hover.call("deck:" + d))
			dt["panel"].mouse_exited.connect(func():
				if state["hover"] == "deck:" + d:
					hover.call(""))
		fit_columns.call_deferred()
		face_timer.start()
	state["build"] = build_decks
	build_decks.call()

	for i in slot_ui.size():
		var idx := i
		slot_ui[i]["panel"].gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				state["active"] = idx
				refresh.call())
		slot_ui[i]["deck_row"].gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				state["active"] = idx
				go_step.call("deck"))
		slot_ui[i]["card"].gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				state["active"] = idx
				go_step.call("hero"))
		slot_ui[i]["random"].pressed.connect(func():
			randoms[idx] = not randoms[idx]
			if slot_ui.size() > 1 and randoms[idx]:
				state["active"] = (idx + 1) % slot_ui.size()
				state["step"] = "hero"
			refresh.call())
		if seated and i > 0:
			# 2 на 2 and на троих: a seat is played by the AI or by a person at this PC.
			var who_btn := WoodUI.button("", WoodUI.BLUE, 17, Vector2(112, 34))
			slot_ui[i]["ctrl"].add_child(who_btn)
			slot_ui[i]["ctrl"].move_child(who_btn, 0)
			slot_ui[i]["ctrl"].visible = true
			slot_ui[i]["who"] = who_btn
			who_btn.pressed.connect(func():
				ss["ai"][idx] = not ss["ai"][idx]
				m._save_setting(mode, "ai_%d" % idx, ss["ai"][idx])
				UI.sfx("select")
				refresh.call())
		if hero_switch:
			var hero_btn := WoodUI.button("С героем", WoodUI.ORANGE, 17, Vector2(0, 34))
			var head: Control = slot_ui[i]["random"].get_parent()
			head.add_child(hero_btn)
			head.move_child(hero_btn, slot_ui[i]["random"].get_index())
			slot_ui[i]["hero_btn"] = hero_btn
			hero_btn.pressed.connect(func():
				if CardDB.is_no_hero(picks[idx]):
					picks[idx] = _legal_pick(CardDB.with_hero(picks[idx], last_card.get(idx, "")))
				else:
					last_card[idx] = CardDB.loadout_card(picks[idx])
					picks[idx] = CardDB.no_hero(picks[idx])
				randoms[idx] = false
				state["active"] = idx
				UI.sfx("select")
				refresh.call())
		if ai_slots.has(i):
			slot_ui[i]["level_box"].visible = true
			slot_ui[i]["ctrl"].visible = not seated or i > 0
			for dir in [-1, 1]:
				var step: int = dir
				slot_ui[i]["level_prev" if dir < 0 else "level_next"].pressed.connect(func():
					levels[idx] = AILevels.shift(levels[idx], step)
					m._save_setting(mode if seated else "ai", "level_%d" % idx, levels[idx])
					UI.sfx("select")
					refresh.call())

	var buttons: BoxContainer = VBoxContainer.new() if Phone.active else HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10 if Phone.active else 16)
	if Phone.active:
		bottom.add_child(buttons)
	else:
		right.add_child(buttons)
	var back := WoodUI.button("Назад", WoodUI.BACK, 28, Vector2(190, 60))
	back.pressed.connect(func():
		m._close_overlay(root)
		if root == _net_root:
			_net_root = null
		if mode != "net":
			m._back_to_play())
	buttons.add_child(back)
	var go := WoodUI.button({"net": "Готово", "run": "В путь!", "sandbox": "Начать", "sandbox_teams": "Начать",
		"sandbox_three": "Начать"}.get(mode, "В бой!"), WoodUI.GO, 32, Vector2(280, 60))
	buttons.add_child(go)
	go.set_meta("kn_primary", true)     # E presses it (key_nav.gd)
	go.pressed.connect(func():
		m._close_overlay(root)
		if root == _net_root:
			_net_root = null
		_hero_select_done(mode, picks, randoms))
	m._fill_screen(root, frame)
	refresh.call()
	m._pop_in(v)


## A page of the hero selection: a scroll over the whole place; its grid goes in get_child(0).
func _picker_page(pages: Control) -> ScrollContainer:
	var page := ScrollContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Not DISABLED: then the scroll is as wide as its grid and keeps a width it once had.
	# The grid takes the columns that fit, so there is nothing to scroll sideways.
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	pages.add_child(page)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, Main.PAGE_MARGIN)
	page.add_child(m)
	return page


## The note with the text of a card: paper on the table, the name underlined with a marker
## of the hero's colour.
func _info_panel() -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, (170 if Phone.active else Main.INFO_H) * WoodUI.font_scale)
	var sb := WoodUI.card(WoodUI.PAPER, 0.0, 9)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_box)
	var name_l := WoodUI.text("", 24 if Phone.active else 30, WoodUI.INK, true)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_box.add_child(name_l)
	var line := WoodUI.squiggle(Color.WHITE)
	name_box.add_child(line)
	var lands := HBoxContainer.new()
	lands.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(lands)
	var tag_box := PanelContainer.new()
	tag_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tb := WoodUI.paper(WoodUI.PAPER_DARK, 0.0, 4, 2.0)
	tb.radius = 10.0
	tb.content_margin_left = 12
	tb.content_margin_right = 12
	tb.content_margin_top = 3
	tb.content_margin_bottom = 4
	tag_box.add_theme_stylebox_override("panel", tb)
	head.add_child(tag_box)
	var tag_l := WoodUI.text("", 18)
	tag_box.add_child(tag_l)
	# The text keeps the room it has: a long one takes a smaller font (_fit_info_text).
	var room := Control.new()
	room.name = "TextRoom"
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(room)
	# Dark on light without outline or shadow: a shadow is drawn even with a zero size.
	var text_l := WoodUI.text("", 26)
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room.add_child(text_l)
	# A hidden copy measures the texts for the note's height (_size_note).
	var probe := WoodUI.text("", 15 if Phone.active else Main.NOTE_MIN_FONT)     # a phone: its least font
	probe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	probe.visible = false
	room.add_child(probe)
	var info := {"panel": panel, "head": head, "name": name_l, "line": line, "lands": lands, "tag": tag_l,
		"tag_box": tag_box, "text": text_l, "room": room, "probe": probe}
	room.resized.connect(func():
		_size_note(info)
		_fit_info_text(text_l, room))
	return info


## The note is as high as the longest hero card's text needs at NOTE_MIN_FONT for the note's
## width (a narrow screen with a big scale and big letters needs more than INFO_H). It only
## grows while the window is open: the note does not jump between cards.
func _size_note(info: Dictionary) -> void:
	var w: float = info["room"].size.x
	if w < 1.0:
		return
	var probe: Label = info["probe"]
	var need := 0.0
	for id: String in CardDB.hero_card_ids():
		probe.text = CardDB.hero_card(id)["text"]
		probe.size = Vector2(w, 0)
		need = maxf(need, probe.get_minimum_size().y)
	var h: float = need + 4.0 + info["head"].get_combined_minimum_size().y + 4.0 + 24.0     # spare, head, gap, margins
	if Phone.active:
		h = minf(h, 240.0)       # a phone: the note leaves the cards their room on the low screen
	if h > info["panel"].custom_minimum_size.y + 0.5:
		info["panel"].custom_minimum_size.y = ceilf(h)


func _set_info(info: Dictionary, title: String, color: Color, tag: String, text: String) -> void:
	info["name"].text = title
	# The marker line runs under the name only.
	var w: float = WoodUI.BOLD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, info["name"].label_settings.font_size).x
	info["line"].custom_minimum_size.x = clampf(w, 40.0, 360.0)
	info["line"].set_meta("color", color)
	info["line"].queue_redraw()
	info["tag"].text = tag
	info["tag_box"].visible = tag != ""
	info["text"].text = text
	_fit_info_text(info["text"], info["room"])


## The largest font of the text that fits its room.
func _fit_info_text(l: Label, room: Control) -> void:
	if room.size.x < 1.0:
		return
	# Measured by the label itself, with a few pixels to spare: the letters of Balsamiq Sans
	# reach a little past their lines, and nothing clips them.
	for fs in ([24, 22, 20, 18, 16, 15] if Phone.active else [26, 24, 22, 20, 18, 16, 14]):
		l.label_settings.font_size = WoodUI.fs(fs)
		l.label_settings.font = WoodUI.letters(false, WoodUI.fs(fs), Phone.active)     # room for the tails at this size
		l.size = Vector2(room.size.x, 0)
		if l.get_minimum_size().y <= room.size.y - 4.0:
			break
	l.size = Vector2(room.size.x, 0)     # again: the first time it took the old font's size
	l.position = Vector2(0, 1)


func _hero_select_done(mode: String, picks: Array, randoms: Array) -> void:
	var heroes := []
	for i in picks.size():
		heroes.append(_random_hero() if randoms[i] else picks[i])
	if mode == "net":
		var old := m.my_hero
		m.my_hero = heroes[0]
		m._save_setting("game", "hero", m.my_hero)
		m._refresh_lobby_hero()
		m.lobby.net_hero_picked()
		if m.online and not m.net.team and m.game != null and m.game.phase == "over" and m.my_hero != old:
			# After an online match: the rematch is played with the new deck.
			m.net.send({"t": "hero", "hero": m.my_hero})
			m._deck_changed["me"] = true
			m._show_rematch_note()
		return
	if SandboxStart.is_mode(mode):
		# The picks are kept as those of the games for as many seats.
		if picks.size() == 2:
			m._last_heroes = heroes.duplicate()
		else:
			var ss: Dictionary = m.seat_state("teams" if picks.size() == 4 else "three")
			for i in picks.size():
				ss["heroes"][i] = picks[i]
		m.sandbox_start.start(heroes)
		return
	if mode == "run":
		m._save_setting("run", "hero", heroes[0])
		m.start_run(heroes[0], m._run_level())
		return
	if mode == "teams" or mode == "three":
		var ss: Dictionary = m.seat_state(mode)
		for i in picks.size():
			ss["heroes"][i] = picks[i]
			ss["random"][i] = randoms[i]
			m._save_setting(mode, "hero_%d" % i, picks[i])
		if mode == "three":
			m.start_three_game(heroes)
		else:
			m.start_teams_game(heroes)
		return
	m._last_heroes = heroes
	m._ai_random = randoms.duplicate()
	m._ai_series = [0, 0]
	_start_mode(mode)


## Starts a new local game of the given mode with the last chosen heroes.
func _start_mode(mode: String) -> void:
	match mode:
		"teams":
			m.start_teams_game()
		"three":
			m.start_three_game()
		"aivsai":
			m.start_ai_vs_ai_game()
		"ai":
			m.start_ai_game()
		_:
			m.start_new_game()


## A random deck with its own hero card.
func _random_hero() -> String:
	var ids: Array = CardDB.hero_ids()
	return ids[randi() % ids.size()]


## Decks the hero selection cycles through: the built-in ones, then own decks that pass the rules.
func _deck_choices() -> Array:
	return CardDB.hero_ids() + CustomDecks.codes()


## The pick, or its hero card with the first deck that keeps the card's deck limit.
func _legal_pick(pick: String) -> String:
	if CardDB.hero_deck_error(pick) == "":
		return pick
	var card := CardDB.loadout_card(pick)
	for deck: String in _deck_choices():
		if CardDB.hero_deck_error(CardDB.loadout(deck, card)) == "":
			return CardDB.loadout(deck, card)
	return CardDB.loadout_deck(pick)


## Own deck builder over the current screen. Opened from hero selection (on_pick
## set) the finished deck goes into the slot; from the title it is only saved.
## hero: the hero card the deck is built for. on_pick takes the deck's pick code, and the
## hero card chosen in the builder too when it takes two arguments.
func show_deck_builder(start_code: String, on_pick := Callable(), note := "", hero := "") -> void:
	var root := m._overlay_root(Color(0.03, 0.02, 0.07, 0.95))
	var builder := DeckBuilder.new()
	root.add_child(builder)
	builder.setup(start_code, on_pick.is_valid(), note, hero)
	m._fill_screen(root, builder)
	builder.closed.connect(func(): m._close_overlay(root))
	builder.sandbox_wanted.connect(func(deck_name: String, lands: Array, deck: Dictionary, hero: String):
		var err: String = m.sandbox_start.from_builder(deck_name, lands, deck, hero)
		if err != "":
			builder.say(err, true))
	builder.picked.connect(func(code: String):
		m._close_overlay(root)
		if on_pick.is_valid() and on_pick.get_argument_count() >= 2:
			on_pick.call(code, builder.hero_card())
		elif on_pick.is_valid():
			on_pick.call(code))


func _hero_tile(id: String) -> PanelContainer:
	var hc := CardDB.hero_card(id)
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(col)
	var pic := m._hero_card_rect(id, Main.HERO_TILE)
	col.add_child(pic)
	var name_l := WoodUI.text(hc["name"], 17)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size = Vector2(Main.HERO_TILE.x, 0)
	col.add_child(name_l)
	tile.mouse_entered.connect(func():
		tile.scale = Vector2.ONE * 1.05
		UI.sfx("hover"))
	tile.mouse_exited.connect(func(): tile.scale = Vector2.ONE)
	tile.resized.connect(func(): tile.pivot_offset = tile.size * 0.5)
	return tile


func _style_hero_tile(tile: PanelContainer, marks: Array) -> void:
	var sb := WoodUI.card(WoodUI.PAPER, 0.0, tile.get_index())
	sb.radius = 10.0
	sb.line_width = 2.0
	if not marks.is_empty():
		sb.line = Main.SLOT_COLORS[marks[0]] if marks.size() == 1 else Color(0.95, 0.95, 1.0)
		sb.line_width = 5.0
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", sb)


## Row of land symbols for a deck (4 lands).
func _land_row(id: String, size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in CardDB.hero(id)["lands"]:
		var r := TextureRect.new()
		r.texture = load("res://assets/ui/symbol_%s.png" % t)
		r.custom_minimum_size = Vector2(size, size)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(r)
	return row


## A seat of the hero selection: its hero card, name and deck. compact: smaller (2 на 2 shows four).
func _hero_slot(parent: Control, title: String, color: Color, compact := false) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var card := TextureRect.new()
	card.custom_minimum_size = Vector2(84, 116) if compact or Phone.active else Vector2(120, 165)
	card.rotation_degrees = -2.0         # laid on the paper by hand
	card.resized.connect(func(): card.pivot_offset = card.size * 0.5)
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.material = CardView.SHARP
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_child(card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2 if compact else 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var title_l := WoodUI.text(title, 20, color.darkened(0.35), true)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title_l)
	var random := WoodUI.button("Случайно", WoodUI.VIOLET, 17, Vector2(0, 34))
	var name_l := WoodUI.text("", 26 if compact or Phone.active else 32, WoodUI.INK, true)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var buttons := head
	if Phone.active:
		# A phone: the seat's name and its hero on one line, the buttons (a finger high) under the deck.
		title_l.size_flags_horizontal = Control.SIZE_FILL
		title_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(name_l)
		buttons = HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 8)
	else:
		col.add_child(name_l)
	buttons.add_child(random)
	# The deck: a click opens the deck step for this seat.
	var deck_row := PanelContainer.new()
	deck_row.mouse_filter = Control.MOUSE_FILTER_STOP
	deck_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var deck_box := WoodUI.paper(WoodUI.PAPER_DARK, 0.0, title.hash() % 50, 2.0)
	deck_box.radius = 10.0
	deck_box.content_margin_left = 12
	deck_box.content_margin_right = 12
	deck_box.content_margin_top = 2
	deck_box.content_margin_bottom = 3
	deck_row.add_theme_stylebox_override("panel", deck_box)
	col.add_child(deck_row)
	if Phone.active:
		deck_row.custom_minimum_size.y = Phone.TOUCH
		col.add_child(buttons)
	var deck_line := HBoxContainer.new()
	deck_line.add_theme_constant_override("separation", 10)
	deck_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deck_row.add_child(deck_line)
	var deck_l := WoodUI.text("", 18, WoodUI.INK, true)
	deck_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	deck_line.add_child(deck_l)
	var lands_box := HBoxContainer.new()
	lands_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deck_line.add_child(lands_box)
	deck_row.mouse_entered.connect(func(): deck_row.modulate = Color(1.15, 1.15, 1.15))
	deck_row.mouse_exited.connect(func(): deck_row.modulate = Color.WHITE)
	# Who plays the seat and the AI's level, on the seats that have them.
	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 8)
	ctrl.visible = false
	col.add_child(ctrl)
	var level_box := HBoxContainer.new()
	level_box.add_theme_constant_override("separation", 4)
	level_box.visible = false
	ctrl.add_child(level_box)
	var level_prev := WoodUI.button("◀", WoodUI.BLUE, 16, Vector2(38, 34))
	level_box.add_child(level_prev)
	var level_l := WoodUI.text("", 18, Color.WHITE, true, 6)
	level_l.custom_minimum_size = Vector2((96 if Phone.active else 130) * WoodUI.font_scale, 0)
	level_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_box.add_child(level_l)
	var level_next := WoodUI.button("▶", WoodUI.BLUE, 16, Vector2(38, 34))
	level_box.add_child(level_next)
	return {"panel": panel, "card": card, "name": name_l, "deck": deck_l, "lands": lands_box,
		"deck_row": deck_row, "random": random, "color": color, "ctrl": ctrl, "seed": title.hash() % 89,
		"level_box": level_box, "level": level_l, "level_prev": level_prev, "level_next": level_next}


func _fill_hero_slot(ui: Dictionary, pick: String, random: bool, active: bool) -> void:
	var sb := WoodUI.card(WoodUI.PAPER, 0.0, ui["seed"])
	sb.radius = 16.0
	if active:
		sb.line = ui["color"]
		sb.line_width = 5.0
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	ui["panel"].add_theme_stylebox_override("panel", sb)
	for ch in ui["lands"].get_children():
		ch.queue_free()
	if random:
		ui["card"].texture = null
		ui["name"].text = "Случайный"
		ui["name"].label_settings.font_color = WoodUI.VIOLET.darkened(0.3)
		ui["deck"].text = "Колода: ?"
		ui["random"].text = "Вручную"
		return
	var deck := CardDB.loadout_deck(pick)
	var hc := CardDB.hero_card(CardDB.loadout_card(pick))
	ui["random"].text = "Случайно"
	ui["card"].texture = load(CardDB.hero_thumb(CardDB.loadout_card(pick)))
	ui["name"].text = hc["name"]
	ui["name"].label_settings.font_color = WoodUI.INK
	ui["deck"].text = "Колода: " + CardDB.hero(deck)["name"]
	ui["lands"].add_child(_land_row(deck, 22))
