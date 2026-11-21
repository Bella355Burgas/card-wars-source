extends CanvasLayer
## Play without a mouse: the arrows move a frame over what can be pressed in the window on top
## (buttons, tiles, cards in a list), Enter or Space presses it, I opens it big (the right click),
## E presses the main button of the screen («В бой!», «Дальше»), Shift with an arrow goes to the
## edge, F1 shows the keys. The keys can be changed (ACTIONS, saved in the settings, main.gd
## «Управление»). The table has its own frame (board.gd, keyboard): while it takes the keys
## (kb_claims), this one waits. A move of the mouse hides the frame.

const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const SETTINGS_PATH := "user://settings.cfg"
const CELL := 120.0              # the grid that finds what covers a point (targets)

## id, name, default keys: [physical key, ctrl, shift, alt].
const ACTIONS := [
	["left", "Влево", [[KEY_LEFT]]],
	["right", "Вправо", [[KEY_RIGHT]]],
	["up", "Вверх", [[KEY_UP]]],
	["down", "Вниз", [[KEY_DOWN]]],
	["press", "Нажать", [[KEY_ENTER], [KEY_SPACE], [KEY_KP_ENTER]]],
	["main", "Дальше, конец хода", [[KEY_E]]],
	["draw", "Взять карту", [[KEY_D]]],
	["hero", "Способность героя", [[KEY_H]]],
	["undo", "Отменить ход", [[KEY_Z, true]]],
	["card", "Карта крупно", [[KEY_I]]],
	["remove", "Убрать карту", [[KEY_DELETE], [KEY_BACKSPACE], [KEY_ENTER, true], [KEY_SPACE, true]]],
	["lane1", "Зона 1", [[KEY_1], [KEY_KP_1]]],
	["lane2", "Зона 2", [[KEY_2], [KEY_KP_2]]],
	["lane3", "Зона 3", [[KEY_3], [KEY_KP_3]]],
	["lane4", "Зона 4", [[KEY_4], [KEY_KP_4]]],
	["items", "Предметы в поезде", [[KEY_TAB]]],
	["help", "Клавиши", [[KEY_F1]]],
]
const DIRS := {"left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}

var current: Control = null      # what the frame stands on
var keyboard := false            # the frame shows: the last input was a key
var scope: Control = null        # when visible, only what is inside it is offered
var claimers: Array = []         # objects whose kb_claims() takes the keys from this frame
var keys := {}                   # action id -> its keys [[key, ctrl, shift, alt], ...]
var capture := Callable()        # «Управление»: the next key goes here (null on Esc)
var _frame: Control              # draws the frame: a child of what it stands on, so a window over it covers it
var _last_at := Vector2.INF      # where the frame stood: when that goes, the nearest target takes it
var _shown_at := 0.0
var _help: PanelContainer
var _time := 0.0
var _look := 0.0                 # the next look whether the frame still stands on something


func _ready() -> void:
	layer = 126
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_keys()


# ---------------------------------------------------------------- the keys

func load_keys() -> void:
	keys.clear()
	var cfg := ConfigFile.new()
	var saved := cfg.load(SETTINGS_PATH) == OK
	for a in ACTIONS:
		var list = cfg.get_value("keys", a[0]) if saved and cfg.has_section_key("keys", a[0]) else null
		keys[a[0]] = list if list is Array else default_keys(a[0])


static func default_keys(id: String) -> Array:
	for a in ACTIONS:
		if a[0] == id:
			return a[2].map(func(k): return [int(k[0]), k.size() > 1 and k[1], k.size() > 2 and k[2], k.size() > 3 and k[3]])
	return []


## The action gets this one key; another action that had it loses it.
func set_key(id: String, k: Array) -> void:
	for a in keys:
		keys[a] = keys[a].filter(func(x): return x != k)
	keys[id] = [k]
	_save_keys()


func reset_keys() -> void:
	for a in ACTIONS:
		keys[a[0]] = default_keys(a[0])
	_save_keys()


func _save_keys() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for a in keys:
		cfg.set_value("keys", a, keys[a])
	cfg.save(SETTINGS_PATH)


static func key_of(e: InputEventKey) -> Array:
	var code := e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
	return [int(code), e.ctrl_pressed or e.meta_pressed, e.shift_pressed, e.alt_pressed]


## The key event is this action. The arrows take Shift too (to the edge).
func is_action(e: InputEvent, id: String) -> bool:
	if not (e is InputEventKey and e.pressed):
		return false
	var k := key_of(e)
	for b in keys.get(id, []):
		if int(b[0]) == k[0] and bool(b[1]) == k[1] and bool(b[3]) == k[3] \
				and (bool(b[2]) == k[2] or DIRS.has(id) and not b[2]):
			return true
	return false


## The direction of an arrow key (any action of DIRS), or ZERO.
func dir_of(e: InputEvent) -> Vector2:
	for id in DIRS:
		if is_action(e, id):
			return DIRS[id]
	return Vector2.ZERO


## The zone a key 1-4 names (0..3), or -1.
func lane_of(e: InputEvent) -> int:
	for i in 4:
		if is_action(e, "lane%d" % (i + 1)):
			return i
	return -1


static func key_text(k: Array) -> String:
	var t := OS.get_keycode_string(int(k[0]))
	match int(k[0]):
		KEY_ENTER: t = "Enter"
		KEY_KP_ENTER: t = "Enter цифр."
		KEY_SPACE: t = "Пробел"
		KEY_LEFT: t = "←"
		KEY_RIGHT: t = "→"
		KEY_UP: t = "↑"
		KEY_DOWN: t = "↓"
	if int(k[0]) >= KEY_KP_0 and int(k[0]) <= KEY_KP_9:
		t = "%d цифр." % (int(k[0]) - KEY_KP_0)
	if k[3]:
		t = "Alt+" + t
	if k[2]:
		t = "Shift+" + t
	if k[1]:
		t = "Ctrl+" + t
	return t


## The keys of an action; `short`: without the ones of the number pad (the F1 list).
func keys_text(id: String, short := false) -> String:
	var list: Array = keys.get(id, [])
	if short:
		var main_keys := list.filter(func(k): return not (int(k[0]) >= KEY_KP_MULTIPLY and int(k[0]) <= KEY_KP_9))
		if not main_keys.is_empty():
			list = main_keys
	return ", ".join(list.map(key_text)) if not list.is_empty() else "—"


# ---------------------------------------------------------------- input

func _process(delta: float) -> void:
	_time += delta
	var shown := keyboard and _live(current) and not _claimed()
	if shown:
		_last_at = rect_of(current).get_center()
		_shown_at = _time
	_show_frame(shown)
	if not keyboard or _claimed() or _time < _look:
		return
	# A list made again under the frame (its target is gone just now): the nearest target
	# takes it. A new screen or a window over the old one: its first target.
	_look = _time + 0.2
	if not _live(current) or not _reachable(current):
		var remade := current != null and not is_instance_valid(current) and _time - _shown_at < 0.5
		_set_current(null)
		var cands := targets()
		if not cands.is_empty():
			_set_current(_nearest(cands, _last_at) if remade else _first(cands))


## The frame is a child of the control under it (an internal one, no container lays it out):
## it is drawn with it, under any window or note that is over it.
func _show_frame(on: bool) -> void:
	if not on:
		if _frame != null and is_instance_valid(_frame):
			_frame.visible = false
		return
	if _frame == null or not is_instance_valid(_frame):
		_frame = Control.new()
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.draw.connect(_draw_frame)
	if _frame.get_parent() != current:
		if _frame.get_parent() != null:
			_frame.get_parent().remove_child(_frame)
		current.add_child(_frame, false, Node.INTERNAL_MODE_BACK)
	_frame.visible = true
	_frame.position = Vector2.ZERO
	_frame.size = current.size
	_frame.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0 \
			or event is InputEventMouseButton or event is InputEventScreenTouch:
		keyboard = false
		return
	if not (event is InputEventKey and event.pressed):
		return
	# The card big (card_zoom.gd): Esc or the key of the big card closes the newest one.
	if not capture.is_valid() and not event.echo and (event.keycode == KEY_ESCAPE or is_action(event, "card")):
		var zooms := get_tree().get_nodes_in_group("card_zoom").filter(
			func(z): return is_instance_valid(z) and not z.is_queued_for_deletion() and z.visible)
		if not zooms.is_empty():
			zooms.back().queue_free()
			get_viewport().set_input_as_handled()
			return
	if capture.is_valid():
		var k := event as InputEventKey
		if k.echo or k.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			get_viewport().set_input_as_handled()
			return
		var cb := capture
		capture = Callable()
		cb.call(null if k.keycode == KEY_ESCAPE else key_of(k))
		get_viewport().set_input_as_handled()
		return
	# Out of a text field by the arrows up and down.
	var f := get_viewport().gui_get_focus_owner()
	if (f is LineEdit or f is TextEdit) and (event.keycode == KEY_UP or event.keycode == KEY_DOWN) \
			and not (f is TextEdit and (f as TextEdit).get_line_count() > 1):
		f.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var k := event as InputEventKey
	if is_action(k, "help") and not k.echo:
		toggle_help()
		get_viewport().set_input_as_handled()
		return
	if _help != null and k.keycode == KEY_ESCAPE:
		toggle_help()
		get_viewport().set_input_as_handled()
		return
	if _claimed():
		return
	var dir := dir_of(k)
	if dir != Vector2.ZERO:
		if _slide(dir):
			get_viewport().set_input_as_handled()
		elif move(dir, k.shift_pressed):
			get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_PAGEUP or k.keycode == KEY_PAGEDOWN:
		if _scroll(-600.0 if k.keycode == KEY_PAGEUP else 600.0):
			get_viewport().set_input_as_handled()
		return
	if k.echo:
		return
	if is_action(k, "press"):
		if press():
			get_viewport().set_input_as_handled()
	elif is_action(k, "main"):
		if press_main():
			get_viewport().set_input_as_handled()
	elif is_action(k, "remove"):
		if keyboard and _live(current) and current.has_meta("kn_remove"):
			(current.get_meta("kn_remove") as Callable).call()
			get_viewport().set_input_as_handled()
	elif is_action(k, "card"):
		if _live(current) and keyboard:
			_click(current, MOUSE_BUTTON_RIGHT)
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- what can be pressed

## Controls in the order they are drawn: a later one is over an earlier one (layers first).
func _controls() -> Array:
	var by_layer := {}
	_walk(get_tree().root, 0, by_layer)
	var layers := by_layer.keys()
	layers.sort()
	var out := []
	for l in layers:
		out.append_array(by_layer[l])
	return out


func _walk(n: Node, layer: int, by_layer: Dictionary) -> void:
	for ch in n.get_children():
		if ch == self or ch is Window:
			continue
		var l := layer
		if ch is CanvasLayer:
			if not (ch as CanvasLayer).visible:
				continue
			l = (ch as CanvasLayer).layer
		elif ch is CanvasItem and not (ch as CanvasItem).visible:
			continue
		if ch is Control:
			if not by_layer.has(l):
				by_layer[l] = []
			by_layer[l].append(ch)
		_walk(ch, l, by_layer)


## The rectangle of a control in the coordinates of the screen's canvas (what this layer draws on).
static func rect_of(c: Control) -> Rect2:
	var xf := c.get_global_transform_with_canvas()
	return Rect2(xf.origin, c.size * xf.get_scale()).abs()


## The control a click at `point` (canvas coordinates) would go to, or null.
func top_at(point: Vector2, list: Array = []) -> Control:
	if list.is_empty():
		list = _controls()
	for i in range(list.size() - 1, -1, -1):
		var c: Control = list[i]
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and rect_of(c).has_point(point) and not _clipped_out(c, point):
			return c
	return null


func _clipped_out(c: Control, point: Vector2) -> bool:
	var p := c.get_parent()
	while p is Control:
		if (p as Control).clip_contents and not rect_of(p).has_point(point):
			return true
		p = p.get_parent()
	return false


func _is_target(c: Control, screen_area: float) -> bool:
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE or c.size.x < 6.0 or c.size.y < 6.0:
		return false
	if c is BaseButton:
		return not (c as BaseButton).disabled
	if c is LineEdit:
		return (c as LineEdit).editable
	if c is TextEdit:
		return (c as TextEdit).editable
	if c is Slider:
		return (c as Slider).editable
	if c.has_meta("kn_skip") or c.gui_input.get_connections().is_empty():
		return false
	var r := rect_of(c)
	return r.size.x * r.size.y < screen_area * 0.5


## The point a target is reached at: its middle, or the middle of the list it scrolls in.
func _probe(c: Control) -> Control:
	var p := c.get_parent()
	while p is Control:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return c


func _reachable(c: Control) -> bool:
	var probe := _probe(c)
	var r := rect_of(probe).intersection(get_viewport().get_visible_rect())
	if r.size.x < 4.0 or r.size.y < 4.0:
		return false
	var hit := top_at(r.get_center())
	return hit != null and (hit == probe or probe.is_ancestor_of(hit))


## Everything the frame may stand on now, in the order of the tree: what is under a window or
## behind another control is left out. What covers a point is looked for in a grid of cells,
## so a screen of hundreds of cards (the deck builder) answers quickly.
func targets() -> Array:
	var list := _controls()
	var screen := get_viewport().get_visible_rect()
	var area := screen.size.x * screen.size.y
	var cols := ceili(screen.size.x / CELL)
	var rows := ceili(screen.size.y / CELL)
	var cells := []
	cells.resize(cols * rows)
	for i in cells.size():
		cells[i] = PackedInt32Array()
	var rects := []
	rects.resize(list.size())
	for i in list.size():
		var c: Control = list[i]
		if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		var r := rect_of(c)
		rects[i] = r
		var a := ((r.position - screen.position) / CELL).floor()
		var b := ((r.end - screen.position) / CELL).floor()
		for y in range(maxi(int(a.y), 0), mini(int(b.y), rows - 1) + 1):
			for x in range(maxi(int(a.x), 0), mini(int(b.x), cols - 1) + 1):
				cells[y * cols + x].append(i)
	var in_scope := scope != null and is_instance_valid(scope) and scope.is_visible_in_tree()
	var out := []
	for c: Control in list:
		if not _is_target(c, area) or in_scope and not scope.is_ancestor_of(c):
			continue
		var probe := _probe(c)
		var r := rect_of(probe).intersection(screen)
		if r.size.x < 4.0 or r.size.y < 4.0:
			continue
		var point := r.get_center()
		var cell := (point - screen.position) / CELL
		var at: PackedInt32Array = cells[clampi(int(cell.y), 0, rows - 1) * cols + clampi(int(cell.x), 0, cols - 1)]
		var hit: Control = null
		for j in range(at.size() - 1, -1, -1):
			var h: Control = list[at[j]]
			if (rects[at[j]] as Rect2).has_point(point) and not _clipped_out(h, point):
				hit = h
				break
		if hit != null and (hit == probe or probe.is_ancestor_of(hit)):
			out.append(c)
	return out


## The first target of a screen: its main button if it has one, else the first in the tree.
func _first(cands: Array) -> Control:
	return cands[0]


func _live(c) -> bool:
	return c != null and is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree() \
		and not (c is BaseButton and c.disabled) and c.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _claimed() -> bool:
	for o in claimers:
		if is_instance_valid(o) and o.kb_claims():
			return true
	return false


func claim(o: Object) -> void:
	claimers = claimers.filter(func(x): return is_instance_valid(x) and x != o)
	claimers.append(o)


## Marks the main button of a screen: E presses it wherever the frame is.
static func primary(c: Control) -> void:
	c.set_meta("kn_primary", true)


# ---------------------------------------------------------------- moving and pressing

## Puts the frame on `c` (a window opened by the keys starts on its first button).
func pick(c: Control) -> void:
	keyboard = true
	_set_current(c)


func _set_current(c: Control) -> void:
	if c == current:
		return
	if _live(current):
		current.mouse_exited.emit()
	current = c
	if c == null:
		return
	var p := c.get_parent()
	while p is Control:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
		p = p.get_parent()
	c.mouse_entered.emit()


## The frame goes to the nearest target that way (`edge`: as far as it goes); true when there
## was something to go to.
func move(dir: Vector2, edge := false) -> bool:
	var cands := targets()
	if cands.is_empty():
		return false
	var was_shown := keyboard
	keyboard = true
	if not cands.has(current):
		_set_current(_nearest(cands, rect_of(current).get_center() if _live(current) else Vector2.INF))
		return true
	if not was_shown or dir == Vector2.ZERO:
		return true
	var moved := false
	for step in (60 if edge else 1):
		var next := _next(cands, current, dir)
		if next == null:
			break
		current.mouse_exited.emit()
		current = next
		moved = true
	if moved:
		var c := current
		current = null
		_set_current(c)
		UI.sfx("hover")
	elif dir.y != 0.0:
		_scroll(dir.y * 300.0)
	return true


func _next(cands: Array, from_c: Control, dir: Vector2) -> Control:
	var from := rect_of(from_c)
	var best: Control = null
	var best_score := INF
	for c: Control in cands:
		if c == from_c:
			continue
		var r := rect_of(c)
		var d := r.get_center() - from.get_center()
		var along := d.dot(dir)
		if along <= 4.0:
			continue
		# Side by side on the other axis counts as straight ahead.
		var across := absf(d.cross(dir))
		var overlap := (r.position.y < from.end.y and r.end.y > from.position.y) if dir.x != 0.0 \
			else (r.position.x < from.end.x and r.end.x > from.position.x)
		var score := along + (0.0 if overlap else across * 2.0 + 200.0)
		if score < best_score:
			best_score = score
			best = c
	return best


func _nearest(cands: Array, at: Vector2) -> Control:
	if at == Vector2.INF:
		return _first(cands)
	var best: Control = cands[0]
	for c: Control in cands:
		if rect_of(c).get_center().distance_to(at) < rect_of(best).get_center().distance_to(at):
			best = c
	return best


## A slider under the frame moves left and right.
func _slide(dir: Vector2) -> bool:
	if not (keyboard and _live(current) and current is Slider and dir.x != 0.0):
		return false
	var s := current as Slider
	s.value += (s.step if s.step > 0.0 else (s.max_value - s.min_value) / 20.0) * dir.x
	return true


## The list under the frame (or the biggest one on screen) scrolls by `dy`.
func _scroll(dy: float) -> bool:
	var sc: ScrollContainer = null
	if _live(current) and _probe(current) is ScrollContainer:
		sc = _probe(current)
	if sc == null:
		var list := _controls()
		for c in list:
			if c is ScrollContainer and c.get_v_scroll_bar().max_value > c.size.y:
				var hit := top_at(rect_of(c).get_center(), list)
				if hit != null and (hit == c or c.is_ancestor_of(hit)):
					sc = c
	if sc == null:
		return false
	sc.scroll_vertical += int(dy)
	return true


## Presses what the frame stands on; with no frame yet it shows on the first target.
func press() -> bool:
	var cands := targets()
	if cands.is_empty():
		return false
	if not keyboard or not cands.has(current):
		return move(Vector2.ZERO)
	if current.has_meta("kn_zoom"):
		_click(current, MOUSE_BUTTON_RIGHT)      # a card only to look at: shown big
	else:
		activate(current)
	return true


## The main button of the screen («В бой!», «Дальше», «Оставить»), wherever the frame is.
func press_main() -> bool:
	for c: Control in targets():
		if c.has_meta("kn_primary"):
			keyboard = true
			_set_current(c)
			activate(c)
			return true
	return false


func activate(c: Control) -> void:
	if c is OptionButton or c is MenuButton:
		c.show_popup()
	elif c is BaseButton:
		var b := c as BaseButton
		if b.toggle_mode:
			if not (b.button_pressed and b.button_group != null):
				b.button_pressed = not b.button_pressed
		b.pressed.emit()
	elif c is LineEdit or c is TextEdit:
		c.grab_focus()
	elif c is Slider:
		pass
	else:
		_click(c, MOUSE_BUTTON_LEFT)


## A click of the mouse button in the middle of `c`, as its gui_input gets it.
func _click(c: Control, button: MouseButton) -> void:
	for down in [true, false]:
		if not is_instance_valid(c):
			return
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = down
		e.position = c.size * 0.5
		e.global_position = rect_of(c).get_center()
		c.gui_input.emit(e)


# ---------------------------------------------------------------- drawing and the keys list

func _draw_frame() -> void:
	var k := 1.0 / maxf(_frame.get_global_transform_with_canvas().get_scale().x, 0.05)
	ring(_frame, Rect2(Vector2.ZERO, _frame.size).grow(6.0 * k), 0.5 + 0.5 * sin(_time * 6.0), k)


## The keyboard frame: a white line on a dark one, the same on the table and in the windows.
static func ring(on: CanvasItem, r: Rect2, pulse: float, k := 1.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(int(14 * k))
	sb.set_border_width_all(int(9 * k))
	sb.border_color = Color(0.05, 0.03, 0.08, 0.7)
	on.draw_style_box(sb, r.grow(2.0 * k))
	sb.set_border_width_all(int(5 * k))
	sb.border_color = Color(1.0, 0.86, 0.3).lerp(Color.WHITE, pulse)
	on.draw_style_box(sb, r)


## The keys, short: one line a key (the four zones in one line).
func help_rows() -> Array:
	var rows := [[" ".join(["left", "right", "up", "down"].map(func(id): return keys_text(id, true))), "выбор"],
		["Shift+стрелка", "к краю"]]
	for id in ["press", "main", "draw", "hero", "undo", "card", "remove"]:
		rows.append([keys_text(id, true), _name(id).to_lower()])
	rows.append(["%s … %s" % [keys_text("lane1", true), keys_text("lane4", true)], "зона"])
	rows.append([keys_text("items", true), _name("items").to_lower()])
	rows.append(["Esc", "назад, меню"])
	rows.append([keys_text("help", true), _name("help").to_lower()])
	return rows


static func _name(id: String) -> String:
	for a in ACTIONS:
		if a[0] == id:
			return a[1]
	return id


func toggle_help() -> void:
	if _help != null:
		_help.queue_free()
		_help = null
		return
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", WoodUI.window(26.0, 18.0))
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	_help.add_child(grid)
	# The pad in use: its buttons drawn (gamepad.gd).
	var pad = get_node_or_null("/root/Gamepad")
	if pad != null and pad.active:
		for row in pad.help_rows():
			if row[0] == "":
				continue
			var g: Control = pad.glyph(row[0], 34.0)
			g.size_flags_horizontal = Control.SIZE_SHRINK_END
			grid.add_child(g)
			grid.add_child(WoodUI.text(row[1], 24))
	else:
		for row in help_rows():
			grid.add_child(WoodUI.text(row[0], 24, WoodUI.INK, true))
			grid.add_child(WoodUI.text(row[1], 24))
	add_child(_help)
	_help.reset_size()
	var screen := get_viewport().get_visible_rect()
	_help.position = Vector2(screen.end.x - _help.size.x - 24.0, screen.position.y + 24.0)
