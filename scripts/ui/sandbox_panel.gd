extends PanelContainer
## The panel of «Песочница» at the left of the table (board.gd): it changes the table through
## the Sandbox (scripts/core/sandbox.gd), every change by board.sb_do so «Шаг назад» takes it back.
##
## Tabs: «Карты» finds any card by its name, type, land, cost and deck and puts it for the chosen
## player into the hand, the deck, the discard pile or onto a spot of the table; «Стол» works with
## the card or land last tapped on the table (damage, healing, stats, frost, the land's type...);
## «Игроки» sets hit points and actions, draws, shuffles, clears the hand; «Журнал» is the log of
## the game in big letters. Under them: the turn goes on, the AI of the other seats on or off.
## Built for a finger: every button is at least ROW high. Fixed sizes: the panel lies on the
## 1920x1080 table and is scaled with it.

const CardDB = preload("res://scripts/core/card_db.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")

const W := 560.0
const H := 1064.0
const KINDS := ["", "creature", "building", "spell", "teamwork"]
const KIND_NAMES := {"": "все", "creature": "существа", "building": "здания", "spell": "заклинания", "teamwork": "командные"}
const COSTS := [-1, 0, 1, 2, 3, 4]
const LIST_MAX := 80               # rows shown at once; the search narrows the rest
const RAINBOW := "rainbow"

var b                              # the board
var _row := 58.0                   # button height: bigger on a phone
var _fs := 22
var _tab := "cards"
var _seat := 0
var _query := ""
var _kind := ""
var _land := ""                    # "" all, a land type or RAINBOW
var _cost := -1                    # -1 all, 4 means 4 and more
var _deck := ""                    # "" all, "@seat" the chosen player's deck, else a deck id
var _decks_open := false           # the results list shows the decks to filter by
var _card_id := ""                 # the card picked in the search
var _target := {}                  # what was tapped on the table: {"uid"} or {"side", "lane"}
var _log_shown := -1
var _ai_wait := false
var _heroes_open := false           # «Игроки» lists the hero cards to pick from

var _box: VBoxContainer
var _undo: Button
var _reset: Button
var _seats: HBoxContainer
var _tabs := {}
var _pages := {}
var _search: LineEdit
var _filter_btns := {}
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _found: Label
var _pick_box: Control
var _table_page: VBoxContainer
var _player_page: VBoxContainer
var _log: RichTextLabel
var _pass: Button
var _ai: Button
var _all_ids: Array = []


func setup(board) -> void:
	b = board
	_all_ids = CardDB.pool_ids()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", WoodUI.window(16, 14))
	_build()
	place(Vector2(8, 8), false)
	refresh()


## Where the panel lies on the table and how big its buttons are (a phone: bigger).
func place(pos: Vector2, phone: bool) -> void:
	position = pos
	var row := 116.0 if phone else 58.0      # a phone: a finger high (docs/MOBILE_UI.md)
	if row != _row:
		_row = row
		_fs = 30 if phone else 22
		for ch in get_children():
			ch.queue_free()
		_build()
		refresh()
	custom_minimum_size = Vector2(W + (260.0 if phone else 0.0), H)
	size = custom_minimum_size


# ================================================================ building

func _build() -> void:
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_box.add_child(head)
	var title := WoodUI.label_fixed("Песочница", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	_undo = _btn("Шаг назад", UI.PURPLE, func(): b.sb_undo(), 150)
	head.add_child(_undo)
	_reset = _btn("Сначала", UI.RED, func(): b.sb_reset(), 120)
	head.add_child(_reset)
	head.add_child(_btn("✕", WoodUI.BACK, func(): visible = false, _row))

	_seats = HBoxContainer.new()
	_seats.add_theme_constant_override("separation", 6)
	_box.add_child(_seats)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_box.add_child(tabs)
	for t in [["cards", "Карты"], ["table", "Стол"], ["players", "Игроки"], ["log", "Журнал"]]:
		var key: String = t[0]
		var tb := WoodUI.button_fixed(t[1], WoodUI.PAPER, _fs, Vector2(0, _row))
		tb.add_theme_constant_override("outline_size", 0)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.focus_mode = Control.FOCUS_NONE
		tb.pressed.connect(func(): show_tab(key))
		tabs.add_child(tb)
		_tabs[key] = tb

	var pages := Control.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.clip_contents = true
	_box.add_child(pages)
	# A phone (rows a finger high): the page of cards scrolls as a whole, its list keeps 3 rows.
	_pages["cards"] = _scrolled(_cards_page()) if _row > 100.0 else _cards_page()
	_table_page = _page()
	_pages["table"] = _scrolled(_table_page)
	_player_page = _page()
	_pages["players"] = _scrolled(_player_page)
	_pages["log"] = _log_page()
	for key in _pages:
		var p: Control = _pages[key]
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pages.add_child(p)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	_box.add_child(foot)
	_pass = _btn("Передать ход", UI.GREEN, func(): b.sb_do(func(): await b.sandbox.pass_turn()))
	_pass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_pass)
	_ai = _btn("ИИ: нет", UI.BLUE, _toggle_ai)
	_ai.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_ai)
	show_tab(_tab)


## A page longer than the panel scrolls (a finger moving over its buttons scrolls it).
func _scrolled(page: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 14
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(page)
	return sc


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	return v


func _cards_page() -> Control:
	var v := _page()
	_search = LineEdit.new()
	WoodUI.edit(_search, _fs)
	_search.add_theme_font_size_override("font_size", _fs)
	_search.placeholder_text = "Название карты"
	_search.custom_minimum_size = Vector2(0, _row)
	_search.clear_button_enabled = true
	_search.text = _query
	_search.text_changed.connect(func(t: String):
		_query = t
		_decks_open = false
		_fill_list())
	v.add_child(_search)
	var grid := GridContainer.new()
	grid.columns = 4 if _row > 100.0 else 2       # a phone: one row of filters, the list gets the height
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for key in ["kind", "land", "cost", "deck"]:
		var f: String = key
		var fb := _btn("", WoodUI.PAPER_DARK, func(): _filter(f))
		fb.add_theme_constant_override("outline_size", 0)
		for st in ["font_color", "font_hover_color", "font_pressed_color"]:
			fb.add_theme_color_override(st, WoodUI.INK)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.clip_text = true
		grid.add_child(fb)
		_filter_btns[f] = fb
	_found = WoodUI.label_fixed("", 26 if _row > 100.0 else 18, UI.CREAM, 5, UI.UI_FONT)
	v.add_child(_found)
	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _row > 100.0:
		_list_scroll.custom_minimum_size.y = 3.0 * (_row + 4.0)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.scroll_deadzone = 14       # a finger moving over the rows scrolls them
	_list_scroll.add_theme_stylebox_override("panel", WoodUI.inset(3, 6, 6))
	v.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_list_scroll.add_child(_list)
	_pick_box = VBoxContainer.new()
	_pick_box.add_theme_constant_override("separation", 6)
	v.add_child(_pick_box)
	_fill_list()
	_fill_pick()
	return v


func _log_page() -> Control:
	var v := _page()
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", WoodUI.inset(5, 12, 8))
	v.add_child(panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = false
	_log.add_theme_font_override("normal_font", WoodUI.REGULAR)
	_log.add_theme_font_size_override("normal_font_size", _fs - 2)
	_log.add_theme_color_override("default_color", Color(0.94, 0.92, 0.86))
	panel.add_child(_log)
	_log_shown = -1
	return v


## A paper button of the panel: its height is the row's, a finger fits on it.
func _btn(text: String, color: Color, on_press: Callable, width := 0.0) -> Button:
	var bt := WoodUI.button_fixed(text, color, _fs, Vector2(width, _row))
	bt.focus_mode = Control.FOCUS_NONE
	bt.pressed.connect(on_press)
	return bt


func _label(text: String, size := 0, color := UI.CREAM) -> Label:
	var l := WoodUI.label_fixed(text, size if size > 0 else _fs, color, 6, UI.UI_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _row_box(sep := 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _grid(cols: int) -> GridContainer:
	var gr := GridContainer.new()
	gr.columns = cols
	gr.add_theme_constant_override("h_separation", 6)
	gr.add_theme_constant_override("v_separation", 6)
	return gr


func _wide(bt: Button) -> Button:
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return bt


# ================================================================ state

func show_tab(key: String) -> void:
	_tab = key
	for k in _tabs:
		WoodUI.set_tab(_tabs[k], k == key)
		_pages[k].visible = k == key
	refresh()


## The card under a finger on the table: the «Стол» tab works with it.
func pick_card(uid: int) -> void:
	_target = {"uid": uid}
	var w: Dictionary = b.game.where(uid)
	if w["p"] >= 0:
		_seat = w["p"]
	show_tab("table")


func pick_land(side: int, lane: int) -> void:
	_target = {"side": side, "lane": lane}
	_seat = side
	show_tab("table")


## The state went back (undo): the log is written again; the card picked stays while it is there.
func forget_target() -> void:
	_log_shown = -1


func refresh() -> void:
	if b == null or b.game == null or _box == null:
		return
	var g = b.game
	if _seat >= g.players.size():
		_seat = 0
	_undo.disabled = not b._can_undo()
	_reset.disabled = b._busy
	_pass.disabled = b._busy or g.phase == "over" or b._choice != null
	_ai.text = "ИИ…" if _ai_wait else ("ИИ: да" if b.sb_ai_on() else "ИИ: нет")
	_ai.disabled = _ai_wait
	_fill_seats()
	match _tab:
		"cards":
			_fill_filters()
			_fill_pick()
		"table":
			_fill_table()
		"players":
			_fill_players()
		"log":
			_fill_log()


func _fill_seats() -> void:
	var g = b.game
	if _seats.get_child_count() != g.players.size():
		for ch in _seats.get_children():
			ch.queue_free()
		for p in g.players.size():
			var seat: int = p
			var sb := _btn("", UI.hero_color(g.players[p].hero), func():
				_seat = seat
				refresh())
			sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sb.clip_text = true
			sb.custom_minimum_size.x = 60
			_seats.add_child(sb)
	for p in g.players.size():
		var sb: Button = _seats.get_child(p)
		var ps = g.players[p]
		sb.text = ps.name + (" · ИИ" if b._is_ai_seat(p) else "")
		sb.modulate = Color.WHITE if p == _seat else Color(1, 1, 1, 0.5)
		sb.disabled = ps.out


func _toggle_ai() -> void:
	if _ai_wait:
		return
	if b.sb_ai_on():
		b.sandbox_ai.emit(false)
		return
	_ai_wait = true
	refresh()
	b.sandbox_ai.emit(true)


## main.gd: the agents are ready (or the switch is off again).
func ai_done() -> void:
	_ai_wait = false
	refresh()


# ================================================================ «Карты»

func _filter(key: String) -> void:
	match key:
		"kind":
			_kind = KINDS[(KINDS.find(_kind) + 1) % KINDS.size()]
		"land":
			var lands: Array = [""] + CardDB.land_types() + [RAINBOW]
			_land = lands[(lands.find(_land) + 1) % lands.size()]
		"cost":
			_cost = COSTS[(COSTS.find(_cost) + 1) % COSTS.size()]
		"deck":
			_decks_open = not _decks_open
	_fill_filters()
	_fill_list()


func _fill_filters() -> void:
	_filter_btns["kind"].text = "Тип: " + KIND_NAMES[_kind]
	_filter_btns["land"].text = "Земля: " + ("все" if _land == "" else CardDB.land_name(_land))
	_filter_btns["cost"].text = "Цена: " + ("все" if _cost < 0 else ("%d+" % _cost if _cost == COSTS[-1] else str(_cost)))
	_filter_btns["deck"].text = "Колода: " + _deck_name(_deck)


func _deck_name(d: String) -> String:
	if d == "":
		return "все"
	if d.begins_with("@"):
		return "игрока"
	return String(CardDB.hero(d).get("name", d))


func _deck_ids(d: String) -> Dictionary:
	if d.begins_with("@"):
		var g = b.game
		var p: int = clampi(int(d.substr(1)), 0, g.players.size() - 1)
		return CardDB.hero(g.players[p].hero).get("deck", {})
	return CardDB.hero(d).get("deck", {})


func _matches(id: String) -> bool:
	var d := CardDB.get_def(id)
	if _kind != "" and d["kind"] != _kind:
		return false
	if _land != "" and d["land"] != _land:
		return false
	if _cost >= 0 and (int(d["cost"]) < _cost if _cost == COSTS[-1] else int(d["cost"]) != _cost):
		return false
	if _deck != "" and not _deck_ids(_deck).has(id):
		return false
	var q := _query.strip_edges().to_lower()
	if q != "" and not String(d["name"]).to_lower().contains(q) and not String(d.get("en", "")).to_lower().contains(q):
		return false
	return true


func _fill_list() -> void:
	if _list == null:
		return
	for ch in _list.get_children():
		ch.queue_free()
	if _decks_open:
		_found.text = "Карты какой колоды показать"
		var choices: Array = ["", "@%d" % _seat] + CardDB.hero_ids()
		for d: String in choices:
			var deck: String = d
			var label: String = "Все колоды" if d == "" else ("Колода игрока: " + b.game.players[_seat].name if d.begins_with("@") else _deck_name(d))
			var row := _list_row(label, null, deck == _deck)
			row.pressed.connect(func():
				_deck = deck
				_decks_open = false
				_fill_filters()
				_fill_list())
			_list.add_child(row)
		return
	var ids := _all_ids.filter(_matches)
	ids.sort_custom(func(x, y): return String(CardDB.get_def(x)["name"]) < String(CardDB.get_def(y)["name"]))
	_found.text = "Найдено: %d" % ids.size() if ids.size() <= LIST_MAX else "Найдено: %d, уточни поиск" % ids.size()
	for i in mini(ids.size(), LIST_MAX):
		var id: String = ids[i]
		var d := CardDB.get_def(id)
		var row := _list_row("%s · %d" % [d["name"], int(d["cost"])], _symbol(d["land"]), id == _card_id)
		row.pressed.connect(func():
			_card_id = id
			_fill_list()
			_fill_pick())
		_list.add_child(row)


func _list_row(text: String, icon: Texture2D, on: bool) -> Button:
	var row := Button.new()
	row.text = text
	row.icon = icon
	row.expand_icon = false
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, _row if _row > 100.0 else _row - 6)
	row.add_theme_font_override("font", WoodUI.BOLD)
	row.add_theme_font_size_override("font_size", _fs - 1)
	row.add_theme_constant_override("icon_max_width", 34)
	row.add_theme_constant_override("h_separation", 10)
	var col := Color(0.98, 0.8, 0.42) if on else Color(0.94, 0.92, 0.86)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		row.add_theme_color_override(st, WoodUI.INK if on else col)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.98, 0.84, 0.5) if on else Color(1, 1, 1, 0.1 if st == "hover" else 0.04)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		row.add_theme_stylebox_override(st, sb)
	return row


func _symbol(land: String) -> Texture2D:
	return b._symbols.get(land)


## The card picked in the list: its picture and where it goes.
func _fill_pick() -> void:
	if _pick_box == null:
		return
	for ch in _pick_box.get_children():
		ch.queue_free()
	if _card_id == "":
		_pick_box.add_child(_label("Выбери карту в списке", _fs - 2))
		return
	var d := CardDB.get_def(_card_id)
	var top := _row_box(10)
	_pick_box.add_child(top)
	top.add_child(_picture(_card_id, Vector2(96, 134)))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	top.add_child(info)
	var name_l := _label("%s → %s" % [d["name"], b.game.players[_seat].name], _fs)
	info.add_child(name_l)
	var places := _grid(2)
	info.add_child(places)
	var id := _card_id
	for it in [["В руку", "hand"], ["Наверх колоды", "deck"], ["В сброс", "discard"]]:
		var dest: String = it[1]
		places.add_child(_wide(_btn(it[0], UI.ORANGE if dest == "hand" else WoodUI.BLUE, func(): _add(id, dest, -1))))
	var kind: String = d["kind"]
	if kind == "creature" or kind == "building":
		var lanes := _row_box(6)
		_pick_box.add_child(lanes)
		var l := _label("На стол:", _fs - 2)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lanes.add_child(l)
		for lane in b.game.LANES:
			var ln: int = lane
			var lb := _btn(str(lane + 1), UI.GREEN, func(): _add(id, kind, ln))
			lb.icon = _symbol(b.game.land_type(_seat, lane))
			lb.add_theme_constant_override("icon_max_width", 30)
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var taken: bool = b.game.slot(_seat, kind, lane) != null
			lb.tooltip_text = "Занято: карта уйдёт в сброс" if taken else ""
			lanes.add_child(lb)


func _add(id: String, dest: String, lane: int) -> void:
	var seat := _seat
	b.sb_do(func(): await b.sandbox.add_card(seat, id, dest, lane))


func _picture(id: String, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.custom_minimum_size = sz
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.material = CardView.SHARP
	r.texture = CardView.texture_for(id)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			b._open_inspect(id))
	return r


# ================================================================ «Стол»

func _clear(box: Control) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()


func _fill_table() -> void:
	_clear(_table_page)
	var g = b.game
	var side := -1
	var lane := -1
	if _target.has("uid"):
		var c = g.card(int(_target["uid"]))
		var w: Dictionary = g.where(int(_target["uid"])) if c != null else {"zone": "limbo"}
		if c != null and ["creature", "building", "hand", "teamwork"].has(w["zone"]):
			_card_tools(c, w)
			side = w["p"]
			lane = w["lane"]
		else:
			_target = {}
	elif _target.has("side"):
		side = _target["side"]
		lane = _target["lane"]
	if side >= 0 and lane >= 0:
		_land_tools(side, lane)
	if _target.is_empty():
		_table_page.add_child(_label("Нажми на карту или землю на столе"))


func _card_tools(c, w: Dictionary) -> void:
	var g = b.game
	var zone: String = w["zone"]
	var top := _row_box(10)
	_table_page.add_child(top)
	top.add_child(_picture(c.id, Vector2(110, 154)))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(_label(c.card_name(), _fs + 2, Color(1.0, 0.86, 0.5)))
	var where_text := "%s · рука" % g.players[w["p"]].name
	if zone == "creature" or zone == "building":
		where_text = "%s · зона %d" % [g.players[w["p"]].name, w["lane"] + 1]
	elif zone == "teamwork":
		where_text = "%s · командная" % g.players[w["p"]].name
	info.add_child(_label(where_text, _fs - 2))
	if zone == "creature":
		info.add_child(_label("Атака %d · Защита %d · Урон %d" % [g.atk_of(w["p"], w["lane"]), g.def_of(w["p"], w["lane"]), c.damage], _fs - 2))
	if (zone == "creature" or zone == "building") and c.exhausted:
		info.add_child(_label("Повёрнута", _fs - 2, Color(1.0, 0.7, 0.45)))
	var uid: int = c.uid
	var side: int = w["p"]
	var lane: int = w["lane"]
	var sb = b.sandbox
	var stats := _grid(3)
	_table_page.add_child(stats)
	var grid := _grid(2)
	_table_page.add_child(grid)
	var items := []
	if zone == "creature":
		items += [["Урон 1", UI.RED, func(): await sb.damage(side, lane, 1)],
			["Лечить 1", UI.GREEN, func(): await sb.heal(side, lane, 1)],
			["Атака +1", UI.ORANGE, func(): await sb.boost(side, lane, 1, 0)],
			["Атака −1", UI.ORANGE, func(): await sb.boost(side, lane, -1, 0)],
			["Защита +1", WoodUI.BLUE, func(): await sb.boost(side, lane, 0, 1)],
			["Защита −1", WoodUI.BLUE, func(): await sb.boost(side, lane, 0, -1)]]
	if zone == "creature" or zone == "building":
		items += [["Развернуть" if c.exhausted else "Повернуть", UI.PURPLE, func(): await sb.toggle_exhausted(uid)],
			["Уничтожить", UI.RED, func(): await sb.move_card(uid, "destroy")],
			["В руку", UI.ORANGE, func(): await sb.move_card(uid, "hand")]]
	items.append(["В сброс", WoodUI.BACK, func(): await sb.move_card(uid, "discard")])
	items += [["Наверх колоды", WoodUI.BLUE, func(): await sb.move_card(uid, "deck")],
		["Убрать из игры", WoodUI.VIOLET, func(): await sb.move_card(uid, "removed")]]
	for i in items.size():
		var it: Array = items[i]
		var op: Callable = it[2]
		# Damage, healing and the stats: three in a row, the rest two.
		(stats if zone == "creature" and i < 6 else grid).add_child(_wide(_btn(it[0], it[1], func(): b.sb_do(op))))


func _land_tools(side: int, lane: int) -> void:
	var g = b.game
	var l: Dictionary = g.players[side].lands[lane]
	var text := "Земля %s · зона %d: %s" % [g.players[side].name, lane + 1, CardDB.land_name(String(l["override"]) if l["override"] != "" else String(l["type"]))]
	if l["flipped"]:
		text += ", лицом вниз"
	if g.is_frozen(side, lane):
		text += ", лёд"
	_table_page.add_child(_label(text, _fs - 2, Color(0.75, 0.95, 1.0)))
	var types := _row_box(4)
	_table_page.add_child(types)
	var sb = b.sandbox
	for t: String in CardDB.land_types():
		var type := t
		var tb := _btn("", UI.GREEN if t == l["type"] else WoodUI.PAPER_DARK, func(): b.sb_do(func(): await sb.set_land(side, lane, type)))
		tb.icon = _symbol(t)
		tb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tb.add_theme_constant_override("icon_max_width", 36)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size.x = 40
		tb.tooltip_text = CardDB.land_name(t)
		types.add_child(tb)
	var row := _row_box(6)
	_table_page.add_child(row)
	row.add_child(_wide(_btn("Перевернуть", UI.PURPLE, func(): b.sb_do(func(): await sb.flip_land(side, lane)))))
	row.add_child(_wide(_btn("Растопить" if g.is_frozen(side, lane) else "Заморозить", WoodUI.BLUE,
		func(): b.sb_do(func(): await sb.toggle_frozen(side, lane)))))


# ================================================================ «Игроки»

func _fill_players() -> void:
	_clear(_player_page)
	var g = b.game
	var p := _seat
	var ps = g.players[p]
	var sb = b.sandbox
	_player_page.add_child(_label("%s · рука %d · колода %d · сброс %d" % [ps.name, ps.hand.size(), ps.deck.size(), ps.discard.size()], _fs - 2))
	_player_page.add_child(_stepper("Жизни", ps.hp, [-5, -1, 1, 5], func(n: int): await sb.set_hp(p, ps.hp + n)))
	_player_page.add_child(_stepper("Действия", ps.actions, [-1, 1], func(n: int): await sb.set_actions(p, ps.actions + n)))
	var inf: bool = sb.infinite.get(p, false)
	_player_page.add_child(_wide(_btn("Бесконечные действия: да" if inf else "Бесконечные действия: нет",
		UI.ORANGE if inf else WoodUI.PAPER_DARK, func(): b.sb_do(func(): await sb.set_infinite(p, not inf)))))
	var grid := _grid(2)
	_player_page.add_child(grid)
	grid.add_child(_wide(_btn("Взять карту", WoodUI.BLUE, func(): b.sb_do(func(): await sb.draw(p)))))
	grid.add_child(_wide(_btn("Перемешать колоду", WoodUI.BLUE, func(): b.sb_do(func(): await sb.shuffle(p)))))
	grid.add_child(_wide(_btn("Очистить руку", UI.RED, func(): b.sb_do(func(): await sb.clear_hand(p)))))
	var look := _wide(_btn("Стол к игроку", UI.PURPLE, func():
		b.set_viewer(p)
		refresh()))
	look.disabled = b.viewer == p or ps.out
	grid.add_child(look)
	_hero_tools(p)


## The hero of player p: its name, «Сменить» (the list of hero cards) and «Без героя».
func _hero_tools(p: int) -> void:
	var g = b.game
	var ps = g.players[p]
	var sb = b.sandbox
	var has: bool = CardDB.has_hero_card(ps.hero_card)
	_player_page.add_child(_label("Герой: " + (String(CardDB.hero_card(ps.hero_card)["name"]) if has else "нет"), _fs, Color(1.0, 0.86, 0.5)))
	var row := _row_box(6)
	_player_page.add_child(row)
	row.add_child(_wide(_btn("Закрыть список" if _heroes_open else "Сменить героя", UI.PURPLE, func():
		_heroes_open = not _heroes_open
		refresh())))
	var none := _wide(_btn("Без героя", UI.RED, func(): b.sb_do(func(): await sb.set_hero(p, ""))))
	none.disabled = not has
	row.add_child(none)
	if not _heroes_open:
		return
	var ids: Array = CardDB.hero_card_ids().duplicate()
	ids.sort_custom(func(x, y): return String(CardDB.hero_card(x)["name"]) < String(CardDB.hero_card(y)["name"]))
	for id: String in ids:
		var card := id
		var r := _list_row(String(CardDB.hero_card(id)["name"]), null, id == ps.hero_card)
		r.pressed.connect(func():
			_heroes_open = false
			b.sb_do(func(): await sb.set_hero(p, card)))
		_player_page.add_child(r)


## A number with buttons that change it: «Жизни  [−5][−1] 25 [+1][+5]».
func _stepper(title: String, value: int, steps: Array, change: Callable) -> Control:
	var row := _row_box(6)
	var l := _label(title, _fs)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size.x = 120
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var add_step := func(n: int):
		var sbtn := _btn("%+d" % n if n > 0 else "−%d" % -n, UI.GREEN if n > 0 else UI.RED,
			func(): b.sb_do(func(): await change.call(n)))
		sbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sbtn)
	for n: int in steps.filter(func(x): return x < 0):
		add_step.call(n)
	var val := _label(str(value), _fs + 6, Color(1.0, 0.86, 0.5))
	val.autowrap_mode = TextServer.AUTOWRAP_OFF
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.custom_minimum_size.x = 64
	row.add_child(val)
	for n: int in steps.filter(func(x): return x > 0):
		add_step.call(n)
	return row


# ================================================================ «Журнал»

func _fill_log() -> void:
	var lines: Array = b.game.log_lines
	if lines.size() == _log_shown:
		return
	if lines.size() < _log_shown or _log_shown < 0:
		_log.clear()
		_log_shown = 0
	for i in range(_log_shown, lines.size()):
		var text: String = String(lines[i]).replace("[", "[lb]")
		var col := "#f6efe0"
		if text.begins_with("✎"):
			col = "#ffd27a"
		elif text.begins_with("—"):
			col = "#9fe7ff"
		_log.append_text("[color=%s]%s[/color]\n" % [col, text])
	_log_shown = lines.size()


func _process(_delta: float) -> void:
	if visible and _tab == "log" and b != null and b.game != null and b.game.log_lines.size() != _log_shown:
		_fill_log()
