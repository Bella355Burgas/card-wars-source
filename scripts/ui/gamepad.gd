extends CanvasLayer
## Play with a gamepad: any pad SDL knows (Xbox, PlayStation, Switch Pro, cheap ones) by the
## standard layout of Godot (JOY_BUTTON_*, JOY_AXIS_*). The buttons are actions of the InputMap
## (pad_*); they turn into the keys of KeyNav (key_nav.gd): the cross and the left stick are the
## arrows (with a dead zone and a repeat while held), A is Enter, B is Esc, the others the keys
## of their actions. So everything the keys do (the frame over the windows, the frame of the
## table in board.gd) the pad does too. Start is the pause, Select the log of the game, the
## shoulders page lists and tabs, the right stick scrolls.
## The hints at the bottom show only while the pad is used, with the pictures of its make
## (Input.get_joy_name). A mouse or a finger hides them. main.gd adds this node as /root/Gamepad.

const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const SETTINGS_PATH := "user://settings.cfg"
const PAD_DEVICE := 7700          # keys made of the pad carry this device: they keep the pad on
const REPEAT_FIRST := 0.36
const REPEAT_NEXT := 0.09
const DEAD_ZONES := [0.6, 0.5, 0.4, 0.3, 0.2]   # «Чувствительность стика» steps, low to high
const DEFAULT_SENSE := 2

## id, name, default bindings. A binding is "b<button>" or "a<axis>+" / "a<axis>-".
## `to`: the KeyNav action it presses, "esc" or a special (pause, log, prev, next).
const ACTIONS := [
	["pad_accept", "Нажать", ["b%d" % JOY_BUTTON_A], "press"],
	["pad_back", "Назад", ["b%d" % JOY_BUTTON_B], "esc"],
	["pad_card", "Карта крупно", ["b%d" % JOY_BUTTON_Y], "card"],
	["pad_draw", "Взять карту", ["b%d" % JOY_BUTTON_X], "draw"],
	["pad_end", "Завершить ход", ["a%d+" % JOY_AXIS_TRIGGER_RIGHT], "main"],
	["pad_hero", "Способность героя", ["a%d+" % JOY_AXIS_TRIGGER_LEFT], "hero"],
	["pad_prev", "Листать назад", ["b%d" % JOY_BUTTON_LEFT_SHOULDER], "prev"],
	["pad_next", "Листать вперёд", ["b%d" % JOY_BUTTON_RIGHT_SHOULDER], "next"],
	["pad_pause", "Пауза", ["b%d" % JOY_BUTTON_START], "pause"],
	["pad_log", "Лог, кнопки", ["b%d" % JOY_BUTTON_BACK], "log"],
	["pad_undo", "Отменить ход", ["b%d" % JOY_BUTTON_RIGHT_STICK], "undo"],
	["pad_items", "Предметы в поезде", ["b%d" % JOY_BUTTON_LEFT_STICK], "items"],
]
## The cross and the left stick: not changed in the settings.
const DIR_ACTIONS := {
	"pad_left": [Vector2.LEFT, JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0],
	"pad_right": [Vector2.RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0],
	"pad_up": [Vector2.UP, JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0],
	"pad_down": [Vector2.DOWN, JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0],
}
const ARROWS := {Vector2.LEFT: KEY_LEFT, Vector2.RIGHT: KEY_RIGHT, Vector2.UP: KEY_UP, Vector2.DOWN: KEY_DOWN}

signal changed                     # the pad came or went, or its buttons changed

var active := false                # the last input was the pad: hints shown
var kind := "generic"              # xbox, ps, nintendo, generic: the pictures of the buttons
var pad_name := ""
var device := -1                   # the pad used last
var binds := {}                    # action -> [binding, ...]
var sense := DEFAULT_SENSE         # index of DEAD_ZONES
var capture := Callable()          # the settings: the next button goes here
var _held := {}                    # action -> {source: strength}
var _pressed := {}                 # action -> pressed now (edges of the triggers)
var sent := 0                      # keys made of the pad (tests)
var _dir := Vector2.ZERO
var _repeat := 0.0
var _scroll_y := 0.0               # the right stick
var _bar: HFlowContainer
var _bar_box: PanelContainer
var _bar_mode := ""
var _note: Label
var _note_time := 0.0


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_binds()
	Input.joy_connection_changed.connect(_on_joy_connection)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		_set_device(pads[0])
	_bar_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.04, 0.08, 0.78)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_bar_box.add_theme_stylebox_override("panel", sb)
	_bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_box.visible = false
	add_child(_bar_box)
	_bar = HFlowContainer.new()
	_bar.add_theme_constant_override("h_separation", 16)
	_bar.add_theme_constant_override("v_separation", 4)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_box.add_child(_bar)
	_note = WoodUI.label("", 26, Color(1, 0.95, 0.85), 6)
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.visible = false
	add_child(_note)


# ---------------------------------------------------------------- the actions

func load_binds() -> void:
	var cfg := ConfigFile.new()
	var saved := cfg.load(SETTINGS_PATH) == OK
	binds.clear()
	for a in ACTIONS:
		var list = cfg.get_value("pad", a[0]) if saved and cfg.has_section_key("pad", a[0]) else null
		binds[a[0]] = (list as Array).duplicate() if list is Array else (a[2] as Array).duplicate()
	sense = clampi(int(cfg.get_value("pad", "sense", DEFAULT_SENSE)) if saved else DEFAULT_SENSE, 0, DEAD_ZONES.size() - 1)
	_apply()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for a in binds:
		cfg.set_value("pad", a, binds[a])
	cfg.set_value("pad", "sense", sense)
	cfg.save(SETTINGS_PATH)


## The action gets this one button; another action that had it loses it.
func set_bind(id: String, b: String) -> void:
	for a in binds:
		binds[a] = (binds[a] as Array).filter(func(x): return x != b)
	binds[id] = [b]
	_save()
	_apply()


func reset_binds() -> void:
	for a in ACTIONS:
		binds[a[0]] = (a[2] as Array).duplicate()
	sense = DEFAULT_SENSE
	_save()
	_apply()


func set_sense(i: int) -> void:
	sense = clampi(i, 0, DEAD_ZONES.size() - 1)
	_save()
	_apply()


func dead_zone() -> float:
	return DEAD_ZONES[sense]


## The InputMap gets the pad_* actions with their events.
func _apply() -> void:
	for id in DIR_ACTIONS:
		var d: Array = DIR_ACTIONS[id]
		_set_action(id, ["b%d" % d[1], "a%d%s" % [d[2], "+" if d[3] > 0 else "-"]], dead_zone())
	for a in ACTIONS:
		_set_action(a[0], binds[a[0]], 0.5)
	_held.clear()
	_pressed.clear()
	changed.emit()


static func _set_action(id: String, list: Array, dz: float) -> void:
	if InputMap.has_action(id):
		InputMap.erase_action(id)
	InputMap.add_action(id, dz)
	for b in list:
		var e := event_of(b)
		if e != null:
			InputMap.action_add_event(id, e)


static func event_of(b: String) -> InputEvent:
	if b.begins_with("b"):
		var e := InputEventJoypadButton.new()
		e.button_index = int(b.substr(1)) as JoyButton
		e.device = -1
		return e
	if b.begins_with("a"):
		var e := InputEventJoypadMotion.new()
		e.axis = int(b.substr(1, b.length() - 2)) as JoyAxis
		e.axis_value = 1.0 if b.ends_with("+") else -1.0
		e.device = -1
		return e
	return null


## The binding an event makes (for the settings), "" if none.
func bind_of(e: InputEvent) -> String:
	if e is InputEventJoypadButton and e.pressed:
		return "b%d" % e.button_index
	if e is InputEventJoypadMotion and absf(e.axis_value) > 0.6:
		return "a%d%s" % [e.axis, "+" if e.axis_value > 0 else "-"]
	return ""


## The buttons of an action as the settings show them.
func binds_text(id: String) -> String:
	var list: Array = binds.get(id, [])
	return ", ".join(list.map(bind_text)) if not list.is_empty() else "-"


## A button by the name printed on this make of pad; PlayStation's face buttons by their shapes.
func bind_text(b: String) -> String:
	if kind == "ps" and b.begins_with("b"):
		match int(b.substr(1)):
			JOY_BUTTON_A: return "Крест"
			JOY_BUTTON_B: return "Круг"
			JOY_BUTTON_X: return "Квадрат"
			JOY_BUTTON_Y: return "Треугольник"
	if kind == "generic" and b.begins_with("b"):
		match int(b.substr(1)):
			JOY_BUTTON_A: return "Нижняя"
			JOY_BUTTON_B: return "Правая"
			JOY_BUTTON_X: return "Левая"
			JOY_BUTTON_Y: return "Верхняя"
	return Glyph.label_of(b, kind)


## The lines of the help window (F1, Select): [binding, what it does].
func help_rows() -> Array:
	var rows := [["dir", "выбор"]]
	for a in ACTIONS:
		rows.append([_b(a[0]), String(a[1]).to_lower()])
	rows.append(["a%d-" % JOY_AXIS_RIGHT_Y, "прокрутка"])
	return rows


## A picture of a button `h` high, for the help window.
func glyph(b: String, h: float) -> Control:
	var g := Glyph.new()
	g.pad = self
	g.bind = b
	g.custom_minimum_size = Vector2(h * (1.6 if Glyph.wide(b, kind) else 1.0), h)
	return g


static func action_name(id: String) -> String:
	for a in ACTIONS:
		if a[0] == id:
			return a[1]
	return id


# ---------------------------------------------------------------- the pad

func _on_joy_connection(dev: int, connected: bool) -> void:
	if connected:
		_set_device(dev)
		show_note("Геймпад подключён")
	elif dev == device:
		var pads := Input.get_connected_joypads()
		active = false
		if pads.is_empty():
			device = -1
			pad_name = ""
			kind = "generic"
		else:
			_set_device(pads[0])
		_held.clear()
		_pressed.clear()
		_dir = Vector2.ZERO
		show_note("Геймпад отключён")
	changed.emit()


func _set_device(dev: int) -> void:
	device = dev
	pad_name = Input.get_joy_name(dev)
	kind = kind_of(pad_name, Input.get_joy_info(dev))
	_bar_mode = ""


## The make of a pad by its name (SDL's gamecontrollerdb) and its vendor.
static func kind_of(joy_name: String, info := {}) -> String:
	var n := joy_name.to_lower()
	var vendor := int(info.get("vendor_id", 0))
	if vendor == 0x054c or ["playstation", "dualshock", "dualsense", "ps3", "ps4", "ps5", "sony"].any(func(s): return n.contains(s)):
		return "ps"
	if vendor == 0x057e or ["nintendo", "switch", "joy-con", "joycon", "pro controller"].any(func(s): return n.contains(s)):
		return "nintendo"
	if vendor == 0x045e or ["xbox", "xinput", "microsoft", "x-box"].any(func(s): return n.contains(s)):
		return "xbox"
	return "generic"


func connected() -> bool:
	return not Input.get_connected_joypads().is_empty()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		_pad_event(event)
		return
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0 \
			or event is InputEventMouseButton or event is InputEventScreenTouch \
			or event is InputEventKey and event.device != PAD_DEVICE:
		if active:
			active = false
			_bar_mode = ""
		if capture.is_valid() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			var cb := capture
			capture = Callable()
			cb.call("")
			get_viewport().set_input_as_handled()


func _pad_event(e: InputEvent) -> void:
	if e.device != device and (e is InputEventJoypadButton and e.pressed or e is InputEventJoypadMotion and absf(e.axis_value) > 0.5):
		_set_device(e.device)
	if capture.is_valid():
		var b := bind_of(e)
		if b != "":
			var cb := capture
			capture = Callable()
			cb.call(b)
			for a in ACTIONS:             # the button just taken does nothing until let go
				if InputMap.event_is_action(e, a[0]):
					_pressed[a[0]] = true
		return
	if e is InputEventJoypadMotion and e.axis == JOY_AXIS_RIGHT_Y:
		_scroll_y = e.axis_value if absf(e.axis_value) > dead_zone() else 0.0
		if _scroll_y != 0.0:
			_wake()
		return
	var src := ("b%d" % e.button_index) if e is InputEventJoypadButton else ("a%d" % e.axis)
	for id in DIR_ACTIONS:
		if InputMap.event_is_action(e, id):
			_hold(id, src, e.get_action_strength(id) if _strength_ok(e, id) else 0.0)
	for a in ACTIONS:
		var id: String = a[0]
		if not InputMap.event_is_action(e, id):
			continue
		var s := e.get_action_strength(id) if _strength_ok(e, id) else 0.0
		_hold(id, src, s)
		var now := _strength(id) >= 0.5
		var was: bool = _pressed.get(id, false)
		_pressed[id] = now
		if now and not was:
			_wake()
			_do(a[3])


## A motion of the other sign is the release of this direction.
static func _strength_ok(e: InputEvent, id: String) -> bool:
	if e is InputEventJoypadMotion:
		for ev in InputMap.action_get_events(id):
			if ev is InputEventJoypadMotion and ev.axis == e.axis:
				return signf(ev.axis_value) == signf(e.axis_value)
	return true


func _hold(id: String, src: String, s: float) -> void:
	if not _held.has(id):
		_held[id] = {}
	if s > 0.0:
		_held[id][src] = s
	else:
		_held[id].erase(src)


func _strength(id: String) -> float:
	var best := 0.0
	for v in _held.get(id, {}).values():
		best = maxf(best, v)
	return best


func _wake() -> void:
	if not active:
		active = true
		_bar_mode = ""


func _process(delta: float) -> void:
	# The direction held: the cross or the stick, the stronger axis.
	var v := Vector2.ZERO
	for id in DIR_ACTIONS:
		v += DIR_ACTIONS[id][0] * _strength(id)
	var dir := Vector2.ZERO
	if v.length() > 0.0:
		dir = Vector2(signf(v.x), 0) if absf(v.x) >= absf(v.y) else Vector2(0, signf(v.y))
	if dir != _dir:
		_dir = dir
		if dir != Vector2.ZERO:
			_wake()
			_arrow(dir, false)
			_repeat = REPEAT_FIRST
	elif dir != Vector2.ZERO:
		_repeat -= delta
		if _repeat <= 0.0:
			_repeat = REPEAT_NEXT
			_arrow(dir, true)
	if _scroll_y != 0.0:
		var kn = _kn()
		if kn != null and not _board_claims():
			kn._scroll(_scroll_y * 1400.0 * delta)
		elif _board() != null and _board().has_method("pad_scroll"):
			_board().pad_scroll(_scroll_y * 1400.0 * delta)
	_update_bar()
	if _note.visible:
		_note_time -= delta
		_note.modulate.a = clampf(_note_time, 0.0, 1.0)
		if _note_time <= 0.0:
			_note.visible = false


# ---------------------------------------------------------------- what the buttons do

func _kn():
	return get_node_or_null("/root/KeyNav")


func _main():
	for m in get_tree().root.get_children():
		if m.has_method("show_pause"):
			return m
	return null


func _board():
	var m = _main()
	if m == null:
		return null
	var b = m.get("board")
	return b if b != null and is_instance_valid(b) and b.is_inside_tree() and b.game != null else null


func _board_claims() -> bool:
	var b = _board()
	return b != null and b.kb_claims()


func _arrow(dir: Vector2, echo: bool) -> void:
	_send_key([ARROWS[dir], false, false, false], echo)


func _do(to: String) -> void:
	match to:
		"esc":
			_send_key([KEY_ESCAPE, false, false, false])
		"pause":
			var m = _main()
			var b = _board()
			if m != null and b != null and b.is_visible_in_tree() and b.game.phase != "over" \
					and (b.kb_claims() or m.get("_pause_root") != null and is_instance_valid(m.get("_pause_root"))):
				if b.has_method("pad_close_log"):
					b.pad_close_log()
				m.show_pause()
			else:
				_send_key([KEY_ESCAPE, false, false, false])
		"log":
			var b = _board()
			if b != null and b.is_visible_in_tree() and (b.kb_claims() or b.pad_log_open()):
				b.pad_toggle_log()
			elif _kn() != null:
				_kn().toggle_help()
		"prev", "next":
			_page(-1 if to == "prev" else 1)
		_:
			var kn = _kn()
			if kn == null:
				return
			var list: Array = kn.keys.get(to, [])
			if not list.is_empty():
				_send_key(list[0])


## A key press made of the pad, as the keyboard would send it.
func _send_key(k: Array, echo := false) -> void:
	for down in ([true] if echo else [true, false]):
		var e := InputEventKey.new()
		e.keycode = int(k[0]) as Key
		e.physical_keycode = int(k[0]) as Key
		e.ctrl_pressed = bool(k[1])
		e.shift_pressed = bool(k[2])
		e.alt_pressed = bool(k[3])
		e.pressed = down
		e.echo = echo
		e.device = PAD_DEVICE
		Input.parse_input_event(e)
	sent += 1


## The shoulders: a tab of the window on top, else a page of its list; on the table the cards
## of the hand one by one.
func _page(step: int) -> void:
	var b = _board()
	if b != null and b.kb_claims():
		b.pad_hand_step(step)
		return
	var kn = _kn()
	if kn == null:
		return
	var tabs := _visible_tabs(kn)
	if not tabs.is_empty():
		var cur := -1
		for i in tabs.size():
			if tabs[i] is BaseButton and (tabs[i] as BaseButton).button_pressed:
				cur = i
		var next: Control = tabs[posmod(cur + step, tabs.size())] if cur >= 0 else tabs[0]
		kn.pick(next)
		kn.activate(next)
		return
	kn._scroll(step * 600.0)


## Tabs of the window on top: toggle buttons of one group (WoodUI.tab), as KeyNav can reach them.
func _visible_tabs(kn) -> Array:
	var groups := {}
	for c in kn.targets():
		if c is BaseButton and (c as BaseButton).toggle_mode and (c as BaseButton).button_group != null:
			var g: ButtonGroup = (c as BaseButton).button_group
			if not groups.has(g):
				groups[g] = []
			groups[g].append(c)
	var best: Array = []
	for g in groups:
		if groups[g].size() > best.size():
			best = groups[g]
	return best if best.size() >= 2 else []


# ---------------------------------------------------------------- hints and notes

func show_note(text: String) -> void:
	_note.text = text
	_note.visible = true
	_note_time = 2.5
	_note.reset_size()
	var r := _screen()
	_note.position = Vector2(r.get_center().x - _note.size.x * 0.5, r.position.y + 16.0)


## The visible screen in this layer's units, free of the phone's cutout.
func _screen() -> Rect2:
	var vp := get_viewport()
	var r := vp.get_visible_rect()
	if Phone.active:
		var safe := Phone.safe_window_rect()
		var inv := vp.get_final_transform().affine_inverse()
		r = r.intersection(Rect2(inv * safe.position, inv.basis_xform(safe.size)))
	return r


## The lines of hints: [binding or "dir", text].
func hints(mode: String) -> Array:
	match mode:
		"table":
			return [["dir", "Выбор"], [_b("pad_accept"), "Нажать"], [_b("pad_back"), "Назад"],
				[_b("pad_draw"), "Взять карту"], [_b("pad_end"), "Завершить ход"], [_b("pad_card"), "Карта"],
				[_b("pad_log"), "Лог"], [_b("pad_pause"), "Пауза"]]
		"capture":
			return [["", "Нажми кнопку"]]
	return [["dir", "Выбор"], [_b("pad_accept"), "Нажать"], [_b("pad_back"), "Назад"],
		[_b("pad_prev") + "|" + _b("pad_next"), "Листать"], [_b("pad_card"), "Карта"]]


func _b(id: String) -> String:
	var list: Array = binds.get(id, [])
	return list[0] if not list.is_empty() else ""


func _update_bar() -> void:
	var show := active and device >= 0
	_bar_box.visible = show
	if not show:
		return
	var mode := "capture" if capture.is_valid() else ("table" if _board_claims() else "menu")
	if mode != _bar_mode:
		_bar_mode = mode
		for ch in _bar.get_children():
			ch.queue_free()
		var big := Phone.active
		var h := (24.0 if big else 30.0) if mode == "table" else (26.0 if big else 34.0)
		for row in hints(mode):
			if row[1] == "":
				continue
			var item := HBoxContainer.new()
			item.add_theme_constant_override("separation", 6)
			item.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for one in String(row[0]).split("|", false):
				var g := Glyph.new()
				g.pad = self
				g.bind = one
				g.custom_minimum_size = Vector2(h * (1.6 if Glyph.wide(one, kind) else 1.0), h)
				item.add_child(g)
			var l := WoodUI.label(row[1], (Phone.FONT_MIN if big else 18) if mode == "table" else (16 if big else 20),
				Color(1, 0.96, 0.88), 0)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			item.add_child(l)
			_bar.add_child(item)
		_bar_box.reset_size()
	# The menus: a line at the bottom. The table: a block at the top left, where the table has
	# only its decor (the hand is at the bottom).
	var r := _screen()
	var table := _bar_mode == "table"
	var max_w := r.size.x * (0.3 if table else 1.0) - 24.0
	var row_w := 0.0
	for ch in _bar.get_children():
		row_w += ch.get_combined_minimum_size().x + 16.0
	_bar.custom_minimum_size.x = minf(row_w, max_w)
	_bar_box.size = Vector2.ZERO
	_bar_box.reset_size()
	if table:
		_bar_box.position = r.position + Vector2(8.0, 6.0)
	else:
		_bar_box.position = Vector2(r.get_center().x - _bar_box.size.x * 0.5, r.end.y - _bar_box.size.y - 6.0)


## A button of the pad, drawn as its make shows it.
class Glyph extends Control:
	var pad
	var bind := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	static func wide(b: String, k: String) -> bool:
		var t := label_of(b, k)
		return t.length() >= 3

	## The short name of a button as printed on the pad (its face buttons are drawn instead).
	static func label_of(b: String, k: String) -> String:
		if b == "dir" or b == "":
			return ""
		if b.begins_with("a"):
			var axis := int(b.substr(1, b.length() - 2))
			match axis:
				JOY_AXIS_TRIGGER_LEFT: return {"xbox": "LT", "ps": "L2", "nintendo": "ZL"}.get(k, "L2")
				JOY_AXIS_TRIGGER_RIGHT: return {"xbox": "RT", "ps": "R2", "nintendo": "ZR"}.get(k, "R2")
				JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return "LS"
				_: return "RS"
		match int(b.substr(1)):
			JOY_BUTTON_LEFT_SHOULDER: return {"xbox": "LB", "ps": "L1", "nintendo": "L"}.get(k, "L1")
			JOY_BUTTON_RIGHT_SHOULDER: return {"xbox": "RB", "ps": "R1", "nintendo": "R"}.get(k, "R1")
			JOY_BUTTON_LEFT_STICK: return {"xbox": "LS", "nintendo": "LS"}.get(k, "L3")
			JOY_BUTTON_RIGHT_STICK: return {"xbox": "RS", "nintendo": "RS"}.get(k, "R3")
			JOY_BUTTON_START: return {"xbox": "Menu", "ps": "OPT", "nintendo": "+"}.get(k, "START")
			JOY_BUTTON_BACK: return {"xbox": "View", "ps": "SHARE", "nintendo": "-"}.get(k, "SELECT")
			JOY_BUTTON_GUIDE: return "Home"
			JOY_BUTTON_A: return {"nintendo": "B"}.get(k, "A")
			JOY_BUTTON_B: return {"nintendo": "A"}.get(k, "B")
			JOY_BUTTON_X: return {"nintendo": "Y"}.get(k, "X")
			JOY_BUTTON_Y: return {"nintendo": "X"}.get(k, "Y")
			JOY_BUTTON_DPAD_UP: return "↑"
			JOY_BUTTON_DPAD_DOWN: return "↓"
			JOY_BUTTON_DPAD_LEFT: return "←"
			JOY_BUTTON_DPAD_RIGHT: return "→"
		return "%d" % int(b.substr(1))

	func _draw() -> void:
		var k: String = pad.kind if pad != null else "generic"
		var r := Rect2(Vector2.ZERO, size)
		var c := r.get_center()
		var rad := minf(size.x, size.y) * 0.46
		var ink := Color(0.08, 0.06, 0.1)
		var white := Color(0.97, 0.95, 0.9)
		if bind == "dir":
			# The cross: a plus.
			var t := rad * 0.62
			draw_rect(Rect2(c - Vector2(t * 0.5, rad), Vector2(t, rad * 2)), white)
			draw_rect(Rect2(c - Vector2(rad, t * 0.5), Vector2(rad * 2, t)), white)
			draw_rect(Rect2(c - Vector2(t, t) * 0.25, Vector2(t, t) * 0.5), ink)
			return
		var face := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
		var btn := int(bind.substr(1)) if bind.begins_with("b") else -1
		if btn in face:
			if k == "ps":
				draw_circle(c, rad, Color(0.14, 0.13, 0.17))
				draw_arc(c, rad - 0.5, 0, TAU, 32, Color(white, 0.5), maxf(1.0, rad * 0.06), true)
				var s := rad * 0.5
				var w := maxf(2.0, rad * 0.16)
				match btn:
					JOY_BUTTON_A:
						var col := Color(0.55, 0.7, 1.0)
						draw_line(c - Vector2(s, s), c + Vector2(s, s), col, w, true)
						draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, w, true)
					JOY_BUTTON_B:
						draw_arc(c, s, 0, TAU, 32, Color(1.0, 0.45, 0.5), w, true)
					JOY_BUTTON_X:
						draw_rect(Rect2(c - Vector2(s, s) * 0.85, Vector2(s, s) * 1.7), Color(1.0, 0.6, 0.85), false, w)
					JOY_BUTTON_Y:
						var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, s * 0.75), c + Vector2(-s, s * 0.75), c + Vector2(0, -s)])
						draw_polyline(pts, Color(0.4, 0.95, 0.75), w, true)
				return
			if k == "generic":
				# Four dots, the one of this place filled.
				draw_circle(c, rad, Color(0.14, 0.13, 0.17))
				var off := {JOY_BUTTON_A: Vector2(0, 1), JOY_BUTTON_B: Vector2(1, 0), JOY_BUTTON_X: Vector2(-1, 0), JOY_BUTTON_Y: Vector2(0, -1)}
				for b2 in off:
					var p: Vector2 = c + off[b2] * rad * 0.52
					if b2 == btn:
						draw_circle(p, rad * 0.26, white)
					else:
						draw_arc(p, rad * 0.22, 0, TAU, 16, white, maxf(1.5, rad * 0.08), true)
				return
			var cols := {JOY_BUTTON_A: Color(0.36, 0.72, 0.3), JOY_BUTTON_B: Color(0.85, 0.3, 0.27),
				JOY_BUTTON_X: Color(0.27, 0.5, 0.9), JOY_BUTTON_Y: Color(0.92, 0.76, 0.2)}
			var fill: Color = cols[btn] if k == "xbox" else Color(0.14, 0.13, 0.17)
			draw_circle(c, rad, fill)
			draw_arc(c, rad - 0.5, 0, TAU, 32, white, maxf(1.0, rad * 0.08), true)
			_text(label_of(bind, k), c, rad * 1.25, white)
			return
		# Shoulders, triggers, Start, Select, sticks: a rounded plate with the name.
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.13, 0.17)
		sb.border_color = white
		sb.set_border_width_all(maxi(1, int(rad * 0.08)))
		sb.set_corner_radius_all(int(rad * 0.6))
		draw_style_box(sb, r.grow(-1))
		var t := label_of(bind, k)
		_text(t, c, rad * (1.0 if t.length() <= 2 else 0.78 if t.length() <= 4 else 0.62), white)

	func _text(t: String, c: Vector2, px: float, col: Color) -> void:
		var f: Font = WoodUI.BOLD
		var fs := maxi(8, int(px))
		var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - sz.x * 0.5, c.y + f.get_ascent(fs) * 0.5 - f.get_descent(fs) * 0.3), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
