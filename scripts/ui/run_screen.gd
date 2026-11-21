extends Control
## The screen of «Бесконечный поезд» between fights: the train rolling on with the
## wagons passed (and who was in them) and the hero riding in the current one, the
## sliding doors to the next wagon, the items, the trophies, the rest and the end of the run.
## main.gd plays the fights (fight_requested) and ends the run (give_up_requested);
## everything else happens here, on the run (scripts/train/train_run.gd).

signal fight_requested
signal give_up_requested
signal new_run_requested
signal exit_requested
signal board_requested

const CardDB = preload("res://scripts/core/card_db.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const TouchInput = preload("res://scripts/ui/touch_input.gd")
const CardZoom = preload("res://scripts/ui/card_zoom.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const TrainRun = preload("res://scripts/train/train_run.gd")
const TrainItems = preload("res://scripts/train/train_items.gd")
const TrainEvents = preload("res://scripts/train/train_events.gd")
const TrainWagons = preload("res://scripts/train/train_wagons.gd")
static var REST_PICTURE: Texture2D = load("res://assets/bg/tree_fort.jpg")
static var SHOP_PICTURE: Texture2D = load("res://assets/bg/fireflies.jpg")
static var UPGRADE_PICTURE: Texture2D = load("res://assets/bg/giant_tree.jpg")
static var LAND_PICTURE: Texture2D = load("res://assets/bg/earth.jpg")
static var CARD_BACK: Texture2D = load("res://assets/cards/sharp/_back.res")
# The train and the doors of Adventure Time's «Dungeon Train» (art_src/train/make_svg.py).
static var WAGON: Texture2D = load("res://assets/run/wagon.png")
static var WAGON_BOSS: Texture2D = load("res://assets/run/wagon_boss.png")
static var DOOR_FRAME: Texture2D = load("res://assets/run/door_frame.png")
static var DOOR_LEAF: Texture2D = load("res://assets/run/door_leaf.png")
static var DOOR_ROOM: Texture2D = load("res://assets/run/door_room.png")
const INK := Color(0.11, 0.18, 0.1)
const GOLD := Color(1.0, 0.86, 0.35)
const LEVEL_COLOR := Color(0.55, 0.88, 1.0)
const CURSE_COLOR := Color(0.72, 0.42, 0.95)
const BAD_COLOR := Color(1.0, 0.5, 0.45)
const GOOD_COLOR := Color(0.55, 0.95, 0.55)
const KINDS := {
	"fight": {"name": "Бой", "color": Color(0.4, 0.75, 1.0)},
	"elite": {"name": "Элита", "color": Color(1.0, 0.58, 0.2)},
	"boss": {"name": "Босс", "color": Color(1.0, 0.34, 0.3)},
	"rest": {"name": "Отдых", "color": Color(0.45, 0.85, 0.5)},
	"treasure": {"name": "Сундук", "color": Color(1.0, 0.85, 0.3)},
	"double": {"name": "Сдвоенный", "color": Color(0.78, 0.55, 1.0)},
	"shop": {"name": "Лавка", "color": Color(0.95, 0.72, 0.3)},
	"event": {"name": "Событие", "color": Color(0.45, 0.88, 0.85)},
	"dark": {"name": "Тёмная дверь", "color": Color(0.6, 0.42, 0.9)},
}
const REWARDS := {"fight": "Трофей: карта", "elite": "Две карты и предмет", "double": "Две карты",
	"boss": "Предмет и +%d HP" % TrainRun.BOSS_HEAL}
const PICTURE_H := 294.0
# The train (drawn in _train, local coordinates; the spots are on the wagon picture).
const WAGON_SIZE := Vector2(160, 132)
const WAGON_GAP := 12.0
const WAGON_DOOR := Vector2(80, 89)
const PORTHOLES := [44.0, 80.0, 116.0]
const PORTHOLE_Y := 65.0
const WHEELS := [22.0, 46.0, 114.0, 138.0]
const WHEEL_Y := 124.0
const RAIL_Y := 131.0
const SLEEPER_GAP := 26.0
# Round crops of the pictures (UV rectangles): the art of a hero card, the tree fort, the card back.
const HERO_ART := Rect2(0.1, 0.13, 0.8, 0.58)
const REST_ART := Rect2(0.34, 0.17, 0.3125, 0.556)
const BACK_ART := Rect2(0.1, 0.214, 0.8, 0.571)
# Doors: the opening in the stone wall and the two leaves sliding apart in it.
const DOOR_SIZE := Vector2(320, 440)
const DOOR_HOLE := Rect2(22, 64, 276, 366)
const DOOR_OPEN := 0.9              # how far the leaves slide apart under the mouse
const DOOR_SHADE := 0.72            # the dark of the room while the door is shut

static var _seen := {}              # run seed -> [train, wagon] last shown: the train rolls on from there

var run                         # train_run.gd
var records := {}               # best (all runs), deck (this run's deck), level (this difficulty), open: the records and open levels, this run included
var prev := {}                  # the same before this run
var daily_status := ""          # the train of the day, over: what became of its result ("Отправка", "Место 3")
var _daily_label: Label = null
var _status: HBoxContainer
var _train: Control
var _body: Control
var _bottom: HBoxContainer
var _leave_row: HBoxContainer       # the way out of the run, small in the corner
var _items_button: Button
var _deck_button: Button
var _give_up: Button
var _popup: Control = null
var _zoom: CanvasLayer = null           # the card big over the screen (CardZoom)
var _hero_tex: Texture2D
var _time := 0.0
var _marker := 0.0                  # the wagon the hero rides in; between two while the train rolls on
var _speed := 1.0                   # of the wheels and the sleepers
var _rail_shift := 0.0
var _wheel_angle := 0.0
var _leaving := false               # a door was taken: no more clicks
var _art := {}                      # hero card id -> its picture: kept, the train draws them every frame


func setup(p_run, p_records: Dictionary, p_prev: Dictionary) -> void:
	run = p_run
	records = p_records
	prev = p_prev


func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.07, 0.04, 0.02, 0.5)
	dim.size = size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var title := WoodUI.label_fixed("БЕСКОНЕЧНЫЙ ПОЕЗД", 76, GOLD, 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(1920, 100)
	title.position = Vector2(0, 14)
	add_child(title)
	_status = HBoxContainer.new()
	_status.alignment = BoxContainer.ALIGNMENT_CENTER
	_status.add_theme_constant_override("separation", 24)
	_status.position = Vector2(0, 118)
	_status.size = Vector2(1920, 80)
	add_child(_status)
	_train = Control.new()
	_train.position = Vector2(0, 200)
	_train.size = Vector2(1920, 140)
	_train.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_train.draw.connect(_draw_train)
	add_child(_train)
	_body = Control.new()
	_body.position = Vector2(0, 344)
	_body.size = Vector2(1920, 620)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)

	# What the hero has, in the middle; the way out of the run, small in the corner.
	_bottom = HBoxContainer.new()
	_bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom.add_theme_constant_override("separation", 18)
	_bottom.position = Vector2(0, 986)
	_bottom.size = Vector2(1920, 60)
	if Phone.active:
		_bottom.position.y = 1080.0 - WoodUI.STAGE_TOUCH - 8.0     # a phone: the taller buttons stay on the screen
	add_child(_bottom)
	var hero := WoodUI.button_fixed("Герой", UI.ORANGE, 26, Vector2(220, 58))
	hero.pressed.connect(_open_stats)
	_bottom.add_child(hero)
	_items_button = WoodUI.button_fixed("Предметы", UI.GREEN, 26, Vector2(220, 58))
	_items_button.pressed.connect(_open_items)
	_bottom.add_child(_items_button)
	_deck_button = WoodUI.button_fixed("Колода", UI.BLUE, 26, Vector2(220, 58))
	_deck_button.pressed.connect(func(): _open_deck(""))
	_bottom.add_child(_deck_button)
	_leave_row = HBoxContainer.new()
	_leave_row.alignment = BoxContainer.ALIGNMENT_END
	_leave_row.add_theme_constant_override("separation", 12)
	_leave_row.position = Vector2(1300, 994)
	_leave_row.size = Vector2(590, 50)
	if Phone.active:
		_leave_row.position = Vector2(1490, 1080.0 - WoodUI.STAGE_TOUCH - 8.0)
		_leave_row.size = Vector2(420, WoodUI.STAGE_TOUCH)
	add_child(_leave_row)
	var menu := WoodUI.button_fixed("В меню", UI.PURPLE, 20, Vector2(150, 46))
	menu.pressed.connect(func(): exit_requested.emit())
	_leave_row.add_child(menu)
	_give_up = WoodUI.button_fixed("Бросить забег", UI.RED, 20, Vector2(200, 46))
	_give_up.pressed.connect(func():
		if _give_up.text == "Бросить забег":
			_give_up.text = "Точно бросить?"
			UI.sfx("error")
		else:
			give_up_requested.emit())
	_leave_row.add_child(_give_up)
	_hero_tex = _hero_art(run.hero_card)
	rebuild()


func _process(delta: float) -> void:
	_time += delta
	_rail_shift = fmod(_rail_shift + delta * 46.0 * _speed, SLEEPER_GAP)
	_wheel_angle += delta * 4.0 * _speed
	_train.queue_redraw()


## Builds the screen for the run's current step.
func rebuild() -> void:
	for ch in _body.get_children():
		ch.queue_free()
	_close_popup()
	_close_zoom()
	_fill_status()
	_roll_on()
	_train.queue_redraw()
	var over: bool = run.phase == "over"      # the end screen has the room of the train too
	_bottom.visible = not over
	_leave_row.visible = not over
	_status.visible = not over                # its numbers are on the end screen
	_items_button.text = "Предметы · %d" % run.items.size() if not run.items.is_empty() else "Предметы"
	_deck_button.text = "Колода · %d" % run.deck_size()
	_train.visible = not over
	_body.position.y = 200.0 if over else 344.0
	_body.size.y = 860.0 if over else 620.0
	_give_up.text = "Бросить забег"
	match run.phase:
		"doors":
			_show_doors()
		"fight":
			_show_fight()
		"level":
			_show_level()
		"item":
			_show_items()
		"reward":
			_show_reward()
		"rest":
			_show_rest()
		"shop":
			_show_shop()
		"event":
			_show_event()
		"over":
			_show_over()


# ---------------------------------------------------------------- status and train

func _fill_status() -> void:
	for ch in _status.get_children():
		ch.queue_free()
	var card := _card_pic(_hero_art(run.hero_card), Vector2(56, 77))
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.add_child(card)
	_status.add_child(_stat(CardDB.hero_card(run.hero_card)["name"], CardDB.hero_color(run.deck_id), 34))
	_status.add_child(_stat("♥ %d / %d" % [maxi(run.hp, 0), run.max_hp], Color(1.0, 0.45, 0.42) if run.hp <= 8 else Color.WHITE))
	_status.add_child(_stat("Ур. %d" % run.level, LEVEL_COLOR))
	_status.add_child(_stat("Монеты %d" % run.coins, GOLD))
	if not run.curses.is_empty():
		_status.add_child(_stat("Проклятия %d" % run.curses.size(), CURSE_COLOR))
	# the road so far, smaller: the deck is on its button below
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(14, 0)
	_status.add_child(gap)
	var dim := Color(UI.CREAM, 0.85)
	_status.add_child(_stat("Состав %d" % run.train, dim, 23))
	_status.add_child(_stat("Пройдено %d" % run.passed, dim, 23))
	if run.daily != "":
		_status.add_child(_stat("Поезд дня", GOLD, 23))
	else:
		_status.add_child(_stat("Рекорд %d" % maxi(int(records.get("best", 0)), run.passed), GOLD, 23))
		if run.difficulty > 0:
			var d := _stat("Сложность %d" % run.difficulty, BAD_COLOR, 23)
			d.mouse_filter = Control.MOUSE_FILTER_STOP
			d.tooltip_text = "\n".join(TrainRun.difficulty_lines(run.difficulty))
			d.gui_input.connect(func(e):
				if run.difficulty > 0 and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_open_difficulty())
			_status.add_child(d)


func _stat(text: String, color: Color, font_size := 30) -> Label:
	var l := WoodUI.label_fixed(text, font_size, color, 8 if font_size >= 30 else 6)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## The hero moves on to the run's wagon: the train rolls from the last one shown.
func _roll_on() -> void:
	var seen: Array = _seen.get(run.seed_value, [])
	var target := float(run.wagon)
	if run.phase != "over" and seen.size() == 2 and int(seen[0]) == run.train and int(seen[1]) < run.wagon:
		_marker = float(seen[1])
		_speed = 4.0
		var tw := create_tween()
		tw.tween_property(self, "_marker", target, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func(): _speed = 1.0)
	elif not (run.phase == "over" and seen.size() == 2):
		_marker = target
	_seen[run.seed_value] = [run.train, run.wagon]


func _wagon_x(i: int) -> float:
	var n: int = TrainRun.TRAIN_LEN
	var total := WAGON_SIZE.x * n + WAGON_GAP * (n - 1)
	return (1920.0 - total) * 0.5 + i * (WAGON_SIZE.x + WAGON_GAP)


func _wagon_mid(i: int) -> float:
	return _wagon_x(i) + WAGON_DOOR.x


func _bob(i: int) -> float:
	return sin(_time * 3.1 + i * 0.9) * 1.5


## The train of this run, the Dungeon Train: it runs in a ring, so it has no engine and
## more wagons fade in at both ends. A passed wagon shows on its door who was in it, the
## hero rides in the current one (its portholes are lit), the last one is the boss's.
func _draw_train() -> void:
	var n: int = TrainRun.TRAIN_LEN
	var x := -_rail_shift
	while x < 1920.0:
		_train.draw_rect(Rect2(x, RAIL_Y - 3, 15, 9), Color(0.33, 0.24, 0.18))
		_train.draw_rect(Rect2(x, RAIL_Y - 3, 15, 9), Color(0.13, 0.09, 0.07), false, 1.5)
		x += SLEEPER_GAP
	_train.draw_rect(Rect2(0, RAIL_Y - 2, 1920, 4), Color(0.72, 0.74, 0.8))
	_train.draw_line(Vector2(0, RAIL_Y + 2), Vector2(1920, RAIL_Y + 2), Color(0.16, 0.16, 0.2), 1.5)
	for i in range(-1, n + 1):
		_draw_wagon(i)
	if run.phase != "over":
		var a := floori(_marker)
		var b := mini(a + 1, n - 1)
		var mx := lerpf(_wagon_mid(a), _wagon_mid(b), _marker - a)
		var my := WAGON_DOOR.y + _bob(roundi(_marker))
		_medallion(Vector2(mx, my), 20.0, _hero_tex, HERO_ART, GOLD, 3.5)
		var ay := -14.0 + sin(_time * 4.0) * 3.0
		var arrow := PackedVector2Array([Vector2(mx - 11, ay), Vector2(mx + 11, ay), Vector2(mx, ay + 13)])
		_train.draw_colored_polygon(arrow, GOLD)
		arrow.append(arrow[0])
		_train.draw_polyline(arrow, Color(0.25, 0.15, 0.05), 2.0, true)


## Wagon i; -1 and TRAIN_LEN are the faded ones beyond the ends of the train.
func _draw_wagon(i: int) -> void:
	var n: int = TrainRun.TRAIN_LEN
	var ghost := i < 0 or i >= n
	var x := _wagon_x(i)
	var top := _bob(i)
	var tint := Color(1, 1, 1, 0.3) if ghost else Color.WHITE
	# the gangway to the wagon before and the coupling
	if i > -1:
		var gx := x - WAGON_GAP - 9.0
		var gangway := Rect2(gx, top + 60, WAGON_GAP + 18.0, 48)
		_train.draw_rect(gangway, Color(0.24, 0.33, 0.2, tint.a))
		for k in 3:
			var lx := gx + 5.0 + k * (WAGON_GAP + 8.0) / 2.0
			_train.draw_line(Vector2(lx, top + 62), Vector2(lx, top + 106), Color(INK, tint.a), 1.2)
		_train.draw_rect(gangway, Color(INK, tint.a), false, 1.6)
		_train.draw_rect(Rect2(gx, top + 111, WAGON_GAP + 18.0, 4), Color(0.2, 0.2, 0.22, tint.a))
	for wx: float in WHEELS:
		_wheel(Vector2(x + wx, WHEEL_Y + _bob(i) * 0.3), 6.5, tint.a)
	var boss: bool = i == n - 1
	_train.draw_texture_rect(WAGON_BOSS if boss else WAGON, Rect2(Vector2(x, top), WAGON_SIZE), false, tint)
	if ghost:
		return
	var door := Vector2(x, top) + WAGON_DOOR
	if i == run.wagon and run.phase != "over":
		for px: float in PORTHOLES:
			var c := Vector2(x + px, top + PORTHOLE_Y)
			_train.draw_circle(c, 7.0, Color(1.0, 0.85, 0.4, 0.22 + 0.06 * sin(_time * 5.0)))
			_train.draw_circle(c, 2.6, Color(1.0, 0.9, 0.55))
	elif i < run.wagon and i < run.history.size():
		_met_medallion(i, door, 17.0)
	if boss:
		_boss_plate(x, top, door)


## The boss's wagon: its name plate and, once the doors show it, who waits there.
func _boss_plate(x: float, top: float, door: Vector2) -> void:
	_train.draw_string(UI.UI_FONT, Vector2(x + 46, top + 45), "БОСС", HORIZONTAL_ALIGNMENT_CENTER, 68, 15,
		Color(1.0, 0.9, 0.7))
	if run.wagon != TrainRun.TRAIN_LEN - 1 or run.phase == "over":
		return
	var shown: Dictionary = run.current if not run.current.is_empty() else (run.doors[0] if not run.doors.is_empty() else {})
	var boss := String(shown.get("enemy", ""))
	if boss != "":
		_medallion(Vector2(x + 122, door.y - 4), 16.0, _hero_art(boss), HERO_ART, Color(1.0, 0.5, 0.45), 3.0)


func _wheel(c: Vector2, r: float, alpha := 1.0) -> void:
	_train.draw_circle(c, r, Color(0.42, 0.45, 0.41, alpha))
	for k in 2:
		var d := Vector2.from_angle(_wheel_angle + k * PI / 2.0) * (r - 1.5)
		_train.draw_line(c - d, c + d, Color(INK, alpha), 1.4, true)
	_train.draw_arc(c, r, 0.0, TAU, 20, Color(INK, alpha), 1.8, true)
	_train.draw_circle(c, 2.0, Color(0.75, 0.77, 0.72, alpha))


## Who was in passed wagon i: the enemy's hero card, the tree fort, the card back.
func _met_medallion(i: int, c: Vector2, r: float) -> void:
	var kind := String(run.history[i])
	var enemy := String(run.met[i]) if i < run.met.size() else ""
	var ring := Color(KINDS[kind]["color"]).lightened(0.3)
	if enemy != "":
		_medallion(c, r, _hero_art(enemy), HERO_ART, ring)
	elif kind == "rest":
		_medallion(c, r, REST_PICTURE, REST_ART, ring)
	else:
		_medallion(c, r, CARD_BACK, BACK_ART, ring)


## The picture of a hero card. A drawing only refers to a texture: one loaded just for
## it would be freed before the frame shows it (and come out white), so they are kept.
func _hero_art(id: String) -> Texture2D:
	if not _art.has(id):
		_art[id] = load(CardDB.hero_image(id))
	return _art[id]


## A round crop of a picture (uv: the part of it, in 0..1) with a ring.
func _medallion(c: Vector2, r: float, tex: Texture2D, uv: Rect2, ring: Color, width := 3.0, on: CanvasItem = null) -> void:
	var canvas: CanvasItem = on if on != null else _train
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for k in 28:
		var d := Vector2.from_angle(TAU * k / 28.0)
		pts.append(c + d * r)
		uvs.append(uv.get_center() + d * uv.size * 0.5)
	canvas.draw_colored_polygon(pts, Color.WHITE, uvs, tex)
	canvas.draw_arc(c, r, 0.0, TAU, 32, ring, width, true)


# ---------------------------------------------------------------- steps

func _centered(node: Control) -> void:
	var center := CenterContainer.new()
	center.size = _body.size
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(center)
	# What does not fit the body is scaled down, never pushed off the screen (a container
	# resets the scale of its children, so the node sits in a plain control). The wrapped
	# texts know their height only after the layout: the fit is made again when it changes.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(node)
	center.add_child(holder)
	var fit := func():
		var need := node.get_combined_minimum_size()
		var k := minf(1.0, minf((_body.size.x - 40.0) / maxf(need.x, 1.0), _body.size.y / maxf(need.y, 1.0)))
		node.size = need
		node.scale = Vector2.ONE * k
		holder.custom_minimum_size = need * k
	fit.call()
	node.minimum_size_changed.connect(fit)


func _show_doors() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 56)
	for i in run.doors.size():
		var idx: int = i
		row.add_child(_door(run.doors[i], func():
			run.enter(idx)
			if run.phase == "fight":
				fight_requested.emit()
			else:
				rebuild()))
	_centered(row)


## A fight that did not end (the game was closed or left): it starts over.
func _show_fight() -> void:
	_centered(_door(run.current, func(): fight_requested.emit()))


## The iron double door of a dungeon room in its stone wall. The plate over it says what
## kind of wagon is behind it and the lines under it who is there; through its windows
## the room shows dimly. Under the mouse the leaves slide apart and show the picture; a
## click opens them all the way and goes in.
func _door(door: Dictionary, on_enter: Callable) -> Control:
	var kind := String(door["kind"])
	var dark := bool(door.get("dark", false))    # a dark door shows neither the wagon nor its rule
	var shown := "dark" if dark else kind
	var col: Color = KINDS[shown]["color"]
	var tex: Texture2D = CARD_BACK
	match shown:
		"rest":
			tex = REST_PICTURE
		"shop":
			tex = SHOP_PICTURE
		"event":
			tex = _event_art(String(door["event"]))
		"treasure", "dark":
			tex = CARD_BACK
		_:
			tex = _hero_art(String(door["enemy"]))
	var tex2: Texture2D = _hero_art(String(door["second"]["enemy"])) if door.has("second") and not dark else null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var frame := Panel.new()
	frame.custom_minimum_size = DOOR_SIZE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER    # the lines under it may be wider
	frame.pivot_offset = DOOR_SIZE * 0.5
	frame.add_theme_stylebox_override("panel", UI.box(Color(0.56, 0.7, 0.73), 10, 0, Color.WHITE, 14))
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.add_child(frame)
	var inside := Control.new()
	inside.position = DOOR_HOLE.position
	inside.size = DOOR_HOLE.size
	inside.clip_contents = true
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(inside)
	# Behind the door: the room in the light of its kind and its picture.
	var room := _image(DOOR_ROOM, inside.size)
	room.modulate = col.darkened(0.3)
	inside.add_child(room)
	var pic_h := inside.size.y - 50.0
	if tex2 != null:        # a pair: the second enemy behind the first
		var small := Vector2(round(pic_h * 0.78 * 0.727), round(pic_h * 0.78))
		var back_pic := _card_pic(tex2, small)
		back_pic.position = Vector2(inside.size.x - small.x - 6.0, (inside.size.y - small.y) * 0.5 + 18.0)
		inside.add_child(back_pic)
		var front_pic := _card_pic(tex, small)
		front_pic.position = Vector2(6.0, (inside.size.y - small.y) * 0.5 - 14.0)
		inside.add_child(front_pic)
	else:
		var pic := _card_pic(tex, Vector2(round(pic_h * 0.727), pic_h), kind in ["rest", "shop"])
		pic.position = (inside.size - pic.size) * 0.5
		inside.add_child(pic)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.05, DOOR_SHADE)
	shade.size = inside.size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.add_child(shade)
	# The leaves meet in the middle, the handles are there.
	var half := inside.size.x * 0.5
	var left := _image(DOOR_LEAF, Vector2(half, inside.size.y))
	inside.add_child(left)
	var right := _image(DOOR_LEAF, Vector2(half, inside.size.y))
	right.flip_h = true
	right.position.x = half
	inside.add_child(right)
	frame.add_child(_image(DOOR_FRAME, DOOR_SIZE))
	var plate := PanelContainer.new()
	var plate_box := WoodUI.plate(col, 3, 1, 12)
	plate_box.content_margin_left = 18
	plate_box.content_margin_right = 18
	plate.add_theme_stylebox_override("panel", plate_box)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(WoodUI.label_fixed(KINDS[shown]["name"], 34, col, 9))
	frame.add_child(plate)
	plate.reset_size()
	plate.position = Vector2((DOOR_SIZE.x - plate.size.x) * 0.5, (DOOR_HOLE.position.y - plate.size.y) * 0.5 - 4.0)
	# Who is behind the door, always visible under it: who in full, the rest smaller.
	var door_lines := _door_lines(door)
	for i in door_lines.size():
		var line_data: Array = door_lines[i]
		var main_line: bool = door_lines.size() > 1 and (i == 0 or (i == 1 and door.has("second")))
		var l := WoodUI.label_fixed(line_data[0], 28 if main_line else 23, line_data[1], 7 if main_line else 6)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART    # a long line wraps under its door, it never widens the row
		l.custom_minimum_size = Vector2(DOOR_SIZE.x + 40.0, 0)
		box.add_child(l)
	# The wagon's rule: a sign on the door with its name and rule, read before the door is picked.
	var rule := String(door.get("wagon", ""))
	if rule != "" and not dark:
		var wg := TrainWagons.wagon(rule)
		var col_rule: Color = TrainWagons.level(rule)["color"]
		var sign := PanelContainer.new()
		var sign_box := WoodUI.plate(col_rule, 3, 2, 12)
		sign_box.content_margin_left = 10
		sign_box.content_margin_right = 10
		sign_box.content_margin_top = 6
		sign_box.content_margin_bottom = 8
		sign.add_theme_stylebox_override("panel", sign_box)
		sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 2)
		sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sign.add_child(sv)
		var name_l := WoodUI.label_fixed(wg["name"], 26, col_rule, 7)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(name_l)
		var text_l := WoodUI.label_fixed(wg["text"], 19, UI.CREAM, 5, UI.UI_FONT)
		text_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_l.custom_minimum_size = Vector2(DOOR_HOLE.size.x - 4, 0)
		sv.add_child(text_l)
		frame.add_child(sign)
		# The wrapped text knows its height only after the layout: the sign hangs from its bottom.
		var hang := func(): sign.position = Vector2((DOOR_SIZE.x - sign.size.x) * 0.5, DOOR_HOLE.end.y - sign.size.y - 10.0)
		sign.resized.connect(hang)
		sign.reset_size()
		hang.call()

	# One tween at a time: a quick pass of the mouse once left an older, longer one
	# finishing after the newer and the door stuck half open.
	var anim := {"tween": null}
	var slide := func(to: float, t: float, trans: Tween.TransitionType) -> Tween:
		if anim["tween"] != null:
			(anim["tween"] as Tween).kill()
		var tw := frame.create_tween().set_parallel()
		anim["tween"] = tw
		tw.tween_property(left, "position:x", -half * to, t).set_trans(trans).set_ease(Tween.EASE_OUT)
		tw.tween_property(right, "position:x", half + half * to, t).set_trans(trans).set_ease(Tween.EASE_OUT)
		tw.tween_property(shade, "color:a", 0.0 if to > 0.0 else DOOR_SHADE, t)
		tw.tween_property(frame, "scale", Vector2.ONE * (1.0 + 0.04 * minf(to, 1.0)), t)
		return tw
	frame.mouse_entered.connect(func():
		if not _leaving:
			UI.sfx("flip")
			slide.call(DOOR_OPEN, 0.35, Tween.TRANS_BACK))
	frame.mouse_exited.connect(func():
		if not _leaving:
			slide.call(0.0, 0.25, Tween.TRANS_SINE))
	frame.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _leaving:
			_leaving = true
			UI.sfx("select")
			var tw: Tween = slide.call(1.05, 0.25, Tween.TRANS_SINE)
			tw.tween_property(frame, "scale", Vector2.ONE * 1.1, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(room, "modulate", col.lightened(0.2), 0.35)
			tw.chain().tween_interval(0.15)
			tw.chain().tween_callback(func():
				_leaving = false
				on_enter.call()))
	return box


## A picture filling a rectangle, not taking the mouse.
func _image(tex: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE      # before the size: else the texture's size is the minimum
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A card picture with round smooth corners. The scanned cards have a rough edge with
## stepped corners: it is cut off. cover: a picture that is not a card fills it all.
func _card_pic(tex: Texture2D, sz: Vector2, cover := false) -> Control:
	var radius := roundi(sz.x * 0.055)
	var clip := Panel.new()
	clip.custom_minimum_size = sz
	clip.size = sz
	clip.add_theme_stylebox_override("panel", UI.box(Color.WHITE, radius))
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if cover:
		r.texture = tex
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		var trim := tex.get_size() * 0.02
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(trim, tex.get_size() - trim * 2.0)
		r.texture = at
		r.stretch_mode = TextureRect.STRETCH_SCALE
	r.material = CardView.SHARP
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.add_child(r)
	var rim := Panel.new()
	var rim_box := UI.box(Color.TRANSPARENT, radius, maxi(2, roundi(sz.x * 0.01)), Color(0.08, 0.06, 0.04, 0.8))
	rim_box.draw_center = false
	rim.add_theme_stylebox_override("panel", rim_box)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.add_child(rim)
	return clip


## The lines under a door: who is there, how strong, what it gives.
func _door_lines(door: Dictionary) -> Array:
	if bool(door.get("dark", false)):
		return [["?", Color.WHITE]]
	match String(door["kind"]):
		"rest":
			return [["+%d HP, карта или земля" % run.rest_amount(), UI.CREAM]]     # the plate names the kind
		"treasure":
			return [["Предмет на выбор", UI.CREAM]]
		"shop":
			return [["Карты и предметы за монеты", UI.CREAM]]
		"event":
			return [[TrainEvents.event(String(door["event"]))["name"], Color.WHITE], ["Выбор и цена", UI.CREAM]]
	var enemy := String(door["enemy"])
	var lv := AILevels.level(String(door["level"]))
	var reward: String = REWARDS[String(door["kind"])]
	var lines := [["%s · ♥ %d" % [CardDB.hero(enemy)["name"], int(door["hp"])], CardDB.hero_color(enemy)]]
	if door.has("second"):
		var sec: Dictionary = door["second"]
		lines.append(["%s · ♥ %d" % [CardDB.hero(String(sec["enemy"]))["name"], int(sec["hp"])], CardDB.hero_color(String(sec["enemy"]))])
	lines.append(["%s · %s" % [lv["name"], reward], UI.CREAM])
	var traits := TrainRun.enemy_stat_lines(door.get("stats", {}))
	if not traits.is_empty():
		lines.append([" · ".join(traits), UI.ORANGE])
	return lines


func _door_panel(door: Dictionary, button_text: String, on_press: Callable) -> PanelContainer:
	var kind := String(door["kind"])
	var info: Dictionary = KINDS[kind]
	var panel := PanelContainer.new()
	var sb := WoodUI.plate(info["color"], 4, 3, 22)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(390, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var t := WoodUI.label_fixed(info["name"], 46, info["color"], 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(340, PICTURE_H)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var lines := []
	match kind:
		"rest":
			pic.texture = REST_PICTURE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			lines = [["+%d HP" % run.rest_amount(), Color.WHITE], ["или минус карта", UI.CREAM]]
		"treasure":
			pic.texture = CARD_BACK
			lines = [["Предмет", Color.WHITE], ["на выбор", UI.CREAM]]
		_:
			var enemy := String(door["enemy"])
			pic.texture = load(CardDB.hero_image(enemy))
			var lv := AILevels.level(String(door["level"]))
			lines = [[CardDB.hero(enemy)["name"], CardDB.hero_color(enemy)], ["♥ %d · %s" % [int(door["hp"]), lv["name"]], lv["color"]],
				[REWARDS[kind], UI.CREAM]]
	for line in lines:
		var l := WoodUI.label_fixed(line[0], 28, line[1], 7)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var box := CenterContainer.new()
	v.add_child(box)
	var b := WoodUI.button_fixed(button_text, UI.GREEN, 30, Vector2(260, 62))
	b.pressed.connect(on_press)
	box.add_child(b)
	return panel


func _show_reward() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var head := "Трофей" if run.picks_left < 2 else "Трофей 1 из 2"
	var t := WoodUI.label_fixed(head + " · выбери карту в колоду", 36, GOLD, 9)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	v.add_child(row)
	for id: String in run.offers:
		row.add_child(_card_button(id, Vector2(290, 448), func():
			UI.sfx("place")
			run.take(id)
			rebuild()))
	var box := CenterContainer.new()
	v.add_child(box)
	var gift := "+3 HP" if run.hp < run.max_hp else "+1 опыт"
	var skip := WoodUI.button_fixed("Отказаться: " + gift, UI.PURPLE, 26, Vector2(320, 58))
	skip.pressed.connect(func():
		run.skip()
		rebuild())
	box.add_child(skip)
	_centered(v)


## An item to take: from a chest, an elite, a boss, now and then a common fight.
func _show_items() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	var head := "Сундук" if String(run.current.get("kind", "")) == "treasure" else "Добыча"
	var t := WoodUI.label_fixed(head + " · выбери предмет", 36, GOLD, 9)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	v.add_child(row)
	for id: String in run.item_offers:
		row.add_child(_item_card(id, Vector2(320, 440), func():
			UI.sfx("buff")
			run.take_item(id)
			rebuild()))
	var box := CenterContainer.new()
	v.add_child(box)
	var skip := WoodUI.button_fixed("Пропустить", UI.PURPLE, 26, Vector2(240, 58))
	skip.pressed.connect(func():
		run.skip_item()
		rebuild())
	box.add_child(skip)
	_centered(v)


## An item as a card: its rarity, name and what it does. With on_press it grows under
## the mouse and a click takes it.
## `in_bag`: the hero's own item on the items screen, copies counted; otherwise an offer
## that says how many the hero has already.
func _item_card(id: String, sz: Vector2, on_press := Callable(), curse := false, in_bag := false) -> Control:
	var it: Dictionary = TrainItems.curse(id) if curse else TrainItems.item(id)
	var col: Color = CURSE_COLOR if curse else TrainItems.rarity(id)["color"]
	var k := sz.x / 320.0
	var panel := PanelContainer.new()
	var sb := WoodUI.plate(col, maxi(2, roundi(5 * k)), 4, roundi(22 * k))
	sb.content_margin_left = 20 * k
	sb.content_margin_right = 20 * k
	sb.content_margin_top = 18 * k
	sb.content_margin_bottom = 20 * k
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = sz
	panel.pivot_offset = sz * 0.5
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", roundi(12 * k))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var head: String = "Проклятие" if curse else String(TrainItems.rarity(id)["name"])
	var have: int = 0 if curse else run.items.count(id)
	if in_bag and have > 1:
		head += " · ×%d" % have
	elif not in_bag and have > 0:
		head += " · есть" + (" ×%d" % have if have > 1 else "")
	var rarity := WoodUI.label_fixed(head, roundi(22 * k), col, 5)
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rarity)
	var name_l := WoodUI.label_fixed(it["name"], roundi(36 * k), GOLD, roundi(9 * k))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(sz.x - 40 * k, 0)
	v.add_child(name_l)
	var line := ColorRect.new()
	line.color = Color(col, 0.6)
	line.custom_minimum_size = Vector2(0, maxf(2.0, 3.0 * k))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	var text := WoodUI.label_fixed(it["text"], roundi(28 * k), UI.CREAM, roundi(6 * k))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(sz.x - 40 * k, 0)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(text)
	for l: Label in [rarity, name_l, text]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not on_press.is_valid():
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return panel
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_entered.connect(func():
		UI.sfx("hover")
		panel.create_tween().tween_property(panel, "scale", Vector2.ONE * 1.06, 0.12))
	panel.mouse_exited.connect(func(): panel.create_tween().tween_property(panel, "scale", Vector2.ONE, 0.12))
	panel.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_press.call())
	return panel


## A new level: one of the offered stats grows.
func _show_level() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	var head := "Новый уровень %d!" % (run.level - run.levels_due + 1)
	var t := WoodUI.label_fixed(head, 48, LEVEL_COLOR, 11)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	v.add_child(row)
	for key: String in run.perks:
		row.add_child(_perk_panel(key))
	_centered(v)


func _perk_panel(key: String) -> PanelContainer:
	var info: Dictionary = TrainRun.STATS[key]
	var panel := PanelContainer.new()
	var sb := WoodUI.plate(LEVEL_COLOR, 4, 5, 22)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(400, 330)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var name_l := WoodUI.label_fixed(info["name"], 40, GOLD, 10)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var now: int = run.stat(key)
	var next: int = mini(now + run.stat_step(key), run.stat_cap(key))
	var value := WoodUI.label_fixed("%s → %s" % [TrainRun.stat_text(key, now), TrainRun.stat_text(key, next)], 48, Color.WHITE, 10)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(value)
	var about := WoodUI.label_fixed(info["about"], 26, UI.CREAM, 6)
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(356, 76)
	about.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(about)
	var box := CenterContainer.new()
	v.add_child(box)
	var b := WoodUI.button_fixed("Взять", UI.GREEN, 30, Vector2(240, 62))
	b.pressed.connect(func():
		UI.sfx("buff")
		run.pick_perk(key)
		rebuild())
	box.add_child(b)
	return panel


func _show_rest() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	var heal_to: int = mini(run.hp + run.rest_amount(), run.max_hp)
	row.add_child(_choice_panel("Отдохнуть", REST_PICTURE, "♥ %d → %d" % [run.hp, heal_to], "Отдохнуть", true, func():
		UI.sfx("buff")
		run.rest_heal()
		rebuild()))
	row.add_child(_choice_panel("Выкинуть карту", CARD_BACK, "Колода %d → %d" % [run.deck_size(), run.deck_size() - 1],
		"Выбрать карту" if run.can_remove() else "Колода мала", run.can_remove(), func(): _open_deck("remove")))
	row.add_child(_choice_panel("Улучшить карту", UPGRADE_PICTURE, "+1/+1 или цена −1",
		"Выбрать карту" if run.has_upgrades() else "Нечего улучшать", run.has_upgrades(), func(): _open_deck("upgrade")))
	row.add_child(_choice_panel("Сменить землю", LAND_PICTURE, "Одну из четырёх", "Выбрать землю", true, func(): _open_lands()))
	_centered(row)


## The shop: cards and items on the shelf for coins, and the services (improve a card,
## throw one out, take a curse off), each of them once.
func _show_shop() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var t := WoodUI.label_fixed("Лавка" + (" · всё за полцены" if bool(run.shop.get("sale", false)) else ""), 40, GOLD, 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var shelf := HBoxContainer.new()
	shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	shelf.add_theme_constant_override("separation", 22)
	v.add_child(shelf)
	for id: String in run.shop["cards"]:
		var price: int = run.shop_price(TrainRun.card_price(id))
		var tile := _card_button(id, Vector2(206, 318), func():
			if _can_buy(price):
				UI.sfx("coin")
				run.buy_card(id)
				rebuild())
		shelf.add_child(_priced(tile, price))
	if not run.shop["items"].is_empty():
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(26, 0)
		shelf.add_child(gap)
	for id: String in run.shop["items"]:
		var price: int = run.shop_price(TrainRun.item_price(id))
		var tile := _item_card(id, Vector2(250, 318), func():
			if _can_buy(price):
				UI.sfx("coin")
				run.buy_item(id)
				rebuild())
		shelf.add_child(_priced(tile, price))
	# Under the shelf, as wide as it: the services, small and alike, on the left, the way out on the right.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	foot.custom_minimum_size = Vector2(0, 76)
	v.add_child(foot)
	var refresh := _service("Обновить · %d" % run.reroll_price(), UI.BLUE, run.can_pay(run.reroll_price()), func():
		UI.sfx("coin")
		run.shop_reroll()
		rebuild())
	refresh.tooltip_text = "Новые карты и предметы"
	foot.add_child(refresh)
	# a service bought once is gone from the row; one that is not for this hero is not shown
	if run.shop["upgrade"] and run.has_upgrades():
		var price: int = run.shop_price(TrainRun.PRICE_UPGRADE)
		foot.add_child(_service("Улучшить карту · %d" % price, UI.BLUE, run.can_pay(price), func(): _open_deck("upgrade")))
	if run.shop["remove"] and run.can_remove():
		var price: int = run.shop_price(TrainRun.PRICE_REMOVE)
		foot.add_child(_service("Выкинуть карту · %d" % price, UI.BLUE, run.can_pay(price), func(): _open_deck("remove")))
	if run.shop["uncurse"] and not run.curses.is_empty():
		var price: int = run.shop_price(TrainRun.PRICE_UNCURSE)
		foot.add_child(_service("Снять проклятие · %d" % price, CURSE_COLOR.darkened(0.2), run.can_pay(price), func(): _open_curses()))
	if run.can_sale():
		var sale := _service("Скидка за проклятие", CURSE_COLOR.darkened(0.2), true, func():
			UI.sfx("buff")
			run.shop_sale()
			rebuild())
		sale.tooltip_text = "Все цены лавки вдвое ниже, на героя ляжет случайное проклятие"
		foot.add_child(sale)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fill)
	var leave := WoodUI.button_fixed("Уйти", UI.PURPLE, 26, Vector2(220, 56))
	leave.pressed.connect(func():
		run.leave_shop()
		rebuild())
	foot.add_child(leave)
	_centered(v)


## A service of the shop: a small button under the shelf.
func _service(text: String, color: Color, enabled: bool, on_press: Callable) -> Button:
	var b := WoodUI.button_fixed(text, color, 20, Vector2(0, 50))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = not enabled
	b.pressed.connect(on_press)
	return b


static func coins_text(n: int) -> String:
	return TrainRun.coins_text(n)


func _can_buy(price: int) -> bool:
	if run.can_pay(price):
		return true
	UI.sfx("error")
	return false


## A shelf place: the goods with the price under them, dimmed when the coins are not enough.
func _priced(goods: Control, price: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(goods)
	var afford: bool = run.can_pay(price)
	goods.modulate = Color.WHITE if afford else Color(1, 1, 1, 0.45)
	var l := WoodUI.label_fixed(coins_text(price), 28, GOLD if afford else Color(1.0, 0.5, 0.45), 7)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


## The picture of an event's hero: its hero card, the card back when it has none.
func _event_art(id: String) -> Texture2D:
	var art := String(TrainEvents.event(id)["art"])
	return _hero_art(art) if art != "" else CARD_BACK


## An event: the hero with what they say, the offers with their prices, then what came of it.
func _show_event() -> void:
	var id := String(run.event["id"])
	var ev: Dictionary = TrainEvents.event(id)
	var stage := String(run.event["stage"])
	var col: Color = KINDS["event"]["color"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 44)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 10)
	who.add_child(_card_pic(_event_art(id), Vector2(300, 412)))
	var name_l := WoodUI.label_fixed(ev["name"], 34, col, 8)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_child(name_l)
	row.add_child(who)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 18)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	var said := WoodUI.label_fixed(String(ev["text"]) if stage == "options" else String(run.event["result"]), 32, UI.CREAM, 8)
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.custom_minimum_size = Vector2(1240, 0)
	right.add_child(said)
	match stage:
		"options":
			var offers := HBoxContainer.new()
			offers.add_theme_constant_override("separation", 24)
			right.add_child(offers)
			var options: Array = ev["options"]
			for i in options.size():
				var idx: int = i
				offers.add_child(_event_offer(options[i], run.event_block(i), func():
					UI.sfx("select")
					run.choose_event(idx)
					rebuild()))
			var box := CenterContainer.new()
			right.add_child(box)
			var leave := WoodUI.button_fixed("Уйти", UI.PURPLE, 26, Vector2(240, 58))
			leave.pressed.connect(func():
				run.leave_event()
				rebuild())
			box.add_child(leave)
		"pick":
			var pick := String(run.event["pick"])
			_got_lines(right, run.event["got"])
			var box := CenterContainer.new()
			right.add_child(box)
			var again := WoodUI.button_fixed({"remove": "Выбрать карту", "upgrade": "Выбрать карту", "curse": "Выбрать проклятие"}[pick],
				UI.GREEN, 30, Vector2(340, 64))
			again.pressed.connect(func(): _open_event_pick(pick))
			box.add_child(again)
			_open_event_pick.call_deferred(pick)
		_:
			_got_lines(right, run.event["got"])
			var box := CenterContainer.new()
			right.add_child(box)
			var go := WoodUI.button_fixed("Дальше", UI.GREEN, 30, Vector2(300, 64))
			go.pressed.connect(func():
				run.finish_event()
				rebuild())
			box.add_child(go)
	_centered(row)


## What an event gave and took, a line each.
func _got_lines(parent: Control, got: Array) -> void:
	for line: String in got:
		var bad := line.begins_with("−") or line.begins_with("Проклятие") or line.contains("−")
		var l := WoodUI.label_fixed(line, 32, BAD_COLOR if bad else GOOD_COLOR, 8)
		parent.add_child(l)


## The card (or the curse) the event wants chosen.
func _open_event_pick(pick: String) -> void:
	if run.phase != "event" or String(run.event["stage"]) != "pick":
		return
	if pick == "curse":
		_open_curses()
	else:
		_open_deck(pick)


## One offer of an event: its label, what it takes, what it gives. `block`: why it cannot be taken.
func _event_offer(opt: Dictionary, block: String, on_press: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := WoodUI.plate(KINDS["event"]["color"], 4, 6, 22)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(392, 300)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var t := WoodUI.label_fixed(opt["text"], 36, GOLD, 9)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var lines := []
	if opt.has("chance"):
		var ch: Dictionary = opt["chance"]
		lines.append(["%d%%: %s" % [int(ch["p"]), ", ".join(TrainEvents.lines(ch["win"], false))], GOOD_COLOR])
		lines.append(["%d%%: %s" % [100 - int(ch["p"]), ", ".join(TrainEvents.lines(ch["lose"], true))], BAD_COLOR])
	for line in TrainEvents.lines(opt.get("cost", {}), true):
		lines.append([line, BAD_COLOR])
	for line in TrainEvents.lines(opt.get("gain", {}), false):
		lines.append([line, GOOD_COLOR])
	for line in lines:
		var l := WoodUI.label_fixed(line[0], 28, line[1], 7)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	if block != "":
		var b := WoodUI.label_fixed(block, 26, BAD_COLOR, 6)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(b)
	var box := CenterContainer.new()
	v.add_child(box)
	var go := WoodUI.button_fixed("Выбрать", UI.GREEN, 28, Vector2(220, 58))
	go.disabled = block != ""
	go.pressed.connect(on_press)
	box.add_child(go)
	return panel


## The curses over the screen: in a shop one is bought off, in an event one is chosen.
func _open_curses() -> void:
	var v := _popup_page("Какое проклятие снять?")
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(1700, 800)
	v.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	center.add_child(row)
	for id: String in run.curses:
		row.add_child(_item_card(id, Vector2(300, 420), func():
			UI.sfx("buff")
			if run.phase == "shop":
				run.shop_uncurse(id)
			else:
				run.event_pick(id)
			rebuild(), true))
	var box := CenterContainer.new()
	v.add_child(box)
	var close := WoodUI.button_fixed("Назад", UI.PURPLE, 28, Vector2(240, 62))
	close.pressed.connect(_close_popup)
	box.add_child(close)


func _choice_panel(title: String, tex: Texture2D, line: String, button_text: String, enabled: bool, on_press: Callable) -> PanelContainer:
	var door := _door_panel({"kind": "rest"}, button_text, on_press)
	var v: VBoxContainer = door.get_child(0)
	(v.get_child(0) as Label).text = title
	var pic: TextureRect = v.get_child(1)
	pic.texture = tex
	if tex == CARD_BACK:
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	else:
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	(v.get_child(2) as Label).text = line
	(v.get_child(3) as Label).visible = false
	var b: Button = v.get_child(4).get_child(0)
	b.disabled = not enabled
	return door


## The line under the end of a train of the day: what became of its result.
func set_daily_status(text: String) -> void:
	daily_status = text
	if _daily_label != null and is_instance_valid(_daily_label):
		_daily_label.text = text


## A short line over the screen that fades by itself: "Открыта сложность 1".
func announce(text: String) -> void:
	var l := WoodUI.label_fixed(text, 30, GOLD, 9)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(1920, 40)
	l.position = Vector2(0, 938)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


## The penalties of the run's difficulty over the screen.
func _open_difficulty() -> void:
	var v := _popup_page("Сложность %d" % run.difficulty)
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(1700, 760)
	v.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)
	var lines := TrainRun.difficulty_lines(run.difficulty)
	for i in lines.size():
		col.add_child(WoodUI.label_fixed("%d   %s" % [i + 1, lines[i]], 34, UI.CREAM, 8))
	var box := CenterContainer.new()
	v.add_child(box)
	var close := WoodUI.button_fixed("Закрыть", UI.PURPLE, 28, Vector2(240, 62))
	close.pressed.connect(_close_popup)
	box.add_child(close)


func _show_over() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var t := WoodUI.label_fixed("ЗАБЕГ ОКОНЧЕН", 80, GOLD, 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 70)
	v.add_child(cols)
	cols.add_child(_over_road())
	cols.add_child(_over_facts())
	if run.daily != "":
		_daily_label = WoodUI.label_fixed(daily_status, 34, GOLD, 8)
		_daily_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(_daily_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	if run.daily != "":
		var board := WoodUI.button_fixed("Таблица дня", UI.BLUE, 30, Vector2(320, 74))
		board.pressed.connect(func(): board_requested.emit())
		row.add_child(board)
	var deck := WoodUI.button_fixed("Колода", UI.BLUE, 30, Vector2(260, 74))
	deck.pressed.connect(func(): _open_deck(""))
	row.add_child(deck)
	var again := WoodUI.button_fixed("Новый забег", UI.GREEN, 32, Vector2(320, 74))
	again.pressed.connect(func(): new_run_requested.emit())
	row.add_child(again)
	var menu := WoodUI.button_fixed("В меню", UI.PURPLE, 30, Vector2(260, 74))
	menu.pressed.connect(func(): exit_requested.emit())
	row.add_child(menu)
	_centered(v)


# ---------------------------------------------------------------- the chronicle

## The road of the run, a row of wagons for every train; a lost fight ends it with a crossed wagon.
func _over_road() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.add_child(WoodUI.label_fixed("Путь", 36, GOLD, 9))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1040, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	var road: Array = run.chronicle.duplicate()
	if not run.fell.is_empty():
		road.append(run.fell)
	if road.is_empty():
		rows.add_child(WoodUI.label_fixed("Ни одного вагона", 30, UI.CREAM, 7))
	var n: int = TrainRun.TRAIN_LEN
	for t in ceili(road.size() / float(n)):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		var name_l := WoodUI.label_fixed("Состав %d" % (t + 1), 22, UI.CREAM, 5)
		name_l.custom_minimum_size = Vector2(110, 0)
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(name_l)
		for i in range(t * n, mini((t + 1) * n, road.size())):
			line.add_child(_road_tile(road[i], i, i >= run.chronicle.size()))
		rows.add_child(line)
	return col


## One wagon of the road: who was in it as a round picture, its kind under it. `end`: the fight that was lost.
func _road_tile(e: Dictionary, index: int, end: bool) -> Control:
	var kind := String(e.get("kind", ""))
	var enemy := String(e.get("enemy", ""))
	var tile := Control.new()
	tile.custom_minimum_size = Vector2(92, 100)
	var known: bool = KINDS.has(kind)
	var color: Color = KINDS[kind]["color"] if known else Color(0.5, 0.5, 0.55)
	var caption := "Конец" if end else (String(KINDS[kind]["name"]) if known else "")
	var tip := "Вагон %d" % (index % TrainRun.TRAIN_LEN + 1)
	if known:
		tip += " · " + String(KINDS[kind]["name"])
	if enemy != "":
		tip += " · " + String(CardDB.hero(enemy)["name"])
	if String(e.get("second", "")) != "":
		tip += " и " + String(CardDB.hero(String(e["second"]))["name"])
	if String(e.get("wagon", "")) != "" and TrainWagons.has(String(e["wagon"])):
		tip += "\n" + String(TrainWagons.wagon(String(e["wagon"]))["name"])
	tile.tooltip_text = tip
	tile.draw.connect(func():
		var c := Vector2(46, 38)
		var ring := color.lightened(0.3)
		if not known:
			tile.draw_circle(c, 30.0, Color(0.16, 0.15, 0.2))
			tile.draw_arc(c, 30.0, 0.0, TAU, 32, ring, 3.0, true)
			return
		if enemy != "":
			_medallion(c, 30.0, _hero_art(enemy), HERO_ART, ring, 5.0 if kind == "boss" else 3.0, tile)
		elif kind == "rest":
			_medallion(c, 30.0, REST_PICTURE, REST_ART, ring, 3.0, tile)
		else:
			_medallion(c, 30.0, CARD_BACK, BACK_ART, ring, 3.0, tile)
		if end:
			tile.draw_circle(c, 30.0, Color(0.5, 0.0, 0.0, 0.3))
			tile.draw_line(c + Vector2(-17, -17), c + Vector2(17, 17), BAD_COLOR, 6.0, true)
			tile.draw_line(c + Vector2(-17, 17), c + Vector2(17, -17), BAD_COLOR, 6.0, true))
	var l := WoodUI.label_fixed(caption, 15, BAD_COLOR if end else color, 4)
	l.position = Vector2(0, 72)
	l.size = Vector2(92, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(l)
	return tile


## The numbers of the run, the records and what the hero carried.
func _over_facts() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(740, 0)
	col.add_child(WoodUI.label_fixed(CardDB.hero_card(run.hero_card)["name"], 36, CardDB.hero_color(run.deck_id), 9))
	col.add_child(WoodUI.label_fixed("Пройдено вагонов: %d" % run.passed, 38, Color.WHITE, 9))
	col.add_child(WoodUI.label_fixed("Побед в боях: %d" % run.wins, 32, UI.CREAM, 8))
	if run.daily != "":
		col.add_child(WoodUI.label_fixed("Поезд дня", 34, GOLD, 8))
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 2)
		col.add_child(grid)
		var rows := [["Рекорд", "best"], ["Колода %s" % CardDB.hero(run.deck_id)["name"], "deck"]]
		if run.difficulty > 0 or int(records.get("open", 0)) > 0:
			rows.append(["Сложность %d" % run.difficulty, "level"])
		var any_fresh := false
		for r: Array in rows:
			var fresh: bool = run.passed > int(prev.get(r[1], 0))
			any_fresh = any_fresh or fresh
			grid.add_child(WoodUI.label_fixed(r[0], 30, UI.CREAM, 7))
			var value := WoodUI.label_fixed(str(maxi(int(records.get(r[1], 0)), run.passed)), 30, GOLD if fresh else Color.WHITE, 7)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value.custom_minimum_size = Vector2(60, 0)
			grid.add_child(value)
		if any_fresh:      # once, the new numbers are in gold
			col.add_child(WoodUI.label_fixed("Новый рекорд!", 30, GOLD, 8))
		if run.unlocks() > int(prev.get("open", 0)):
			col.add_child(WoodUI.label_fixed("Открыта сложность %d" % run.unlocks(), 32, GOLD, 8))
	var improved := 0
	for id: String in run.upgraded:
		improved += int(run.upgraded[id])
	col.add_child(WoodUI.label_fixed("Колода %d" % run.deck_size() + (" · улучшено %d" % improved if improved > 0 else ""), 30, UI.CREAM, 7))
	if not run.items.is_empty():
		col.add_child(WoodUI.label_fixed("Предметы · %d" % run.items.size(), 28, GOLD, 7))
		col.add_child(_chips(run.items, false))
	if not run.curses.is_empty():
		col.add_child(WoodUI.label_fixed("Проклятия · %d" % run.curses.size(), 28, CURSE_COLOR, 7))
		col.add_child(_chips(run.curses, true))
	return col


## The names of items or curses, each in a frame of its rarity; the text is its tooltip.
func _chips(ids: Array, curse: bool) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	flow.custom_minimum_size = Vector2(740, 0)
	var shown := []
	for id: String in ids:
		if shown.has(id):
			continue
		shown.append(id)
		var it: Dictionary = TrainItems.curse(id) if curse else TrainItems.item(id)
		var color: Color = CURSE_COLOR if curse else TrainItems.rarity(id)["color"]
		var chip := PanelContainer.new()
		var sb := WoodUI.plate(color, 2, 7, 10)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		chip.add_theme_stylebox_override("panel", sb)
		chip.tooltip_text = String(it["text"])
		var n := ids.count(id)
		var l := WoodUI.label_fixed(String(it["name"]) + (" ×%d" % n if n > 1 else ""), 24, color.lightened(0.25), 5)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(l)
		flow.add_child(chip)
	return flow


# ---------------------------------------------------------------- cards

## A card picture that grows a little under the mouse and is clicked as a whole.
func _card_button(id: String, sz: Vector2, on_press: Callable) -> TextureRect:
	return _tile_button(CardView.texture_for(id), sz, on_press)


## A picture that grows a little under the mouse and is clicked as a whole. The right button
## (a held finger) shows it big: the click comes with the release, so a held finger takes nothing.
func _tile_button(tex: Texture2D, sz: Vector2, on_press: Callable) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.material = CardView.SHARP
	r.custom_minimum_size = sz
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.pivot_offset = sz * 0.5
	r.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	r.mouse_entered.connect(func():
		UI.sfx("hover")
		r.create_tween().tween_property(r, "scale", Vector2.ONE * 1.06, 0.12))
	r.mouse_exited.connect(func(): r.create_tween().tween_property(r, "scale", Vector2.ONE, 0.12))
	var down := [false]
	r.gui_input.connect(func(e):
		if CardZoom.asks(e):
			down[0] = false
			_open_zoom(r)
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				down[0] = true
			elif down[0] and Rect2(Vector2.ZERO, r.size).has_point(e.position) and not TouchInput.long_pressed:
				down[0] = false
				on_press.call())
	return r


## The tile's card big (an improved one with its mark). `side`: a question beside it.
func _open_zoom(tile: TextureRect, side: Control = null) -> void:
	_close_zoom()
	_zoom = CardZoom.open(self, tile.texture, side)
	if tile.get_meta("improved", false):
		var pic: Control = _zoom.find_child("Card", true, false)
		var mark := Control.new()
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.draw.connect(func(): CardView.draw_upgrade_mark(mark, CardView.FONT))
		pic.add_child(mark)
		pic.resized.connect(func():
			mark.position = pic.size * 0.5
			mark.scale = Vector2.ONE * (pic.size.x / CardView.SIZE.x))


func _close_zoom() -> void:
	if _zoom != null and is_instance_valid(_zoom):
		_zoom.queue_free()
	_zoom = null


## The hero over the screen: the card, the level and every stat.
func _open_stats() -> void:
	_close_popup()
	var root := Control.new()
	root.size = size
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_popup = root
	root.add_child(WoodUI.table())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 60)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	row.add_child(left)
	left.add_child(_card_pic(_hero_art(run.hero_card), Vector2(340, 467)))
	var name_l := WoodUI.label_fixed(CardDB.hero_card(run.hero_card)["name"], 38, CardDB.hero_color(run.deck_id), 9)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(name_l)
	var lv := WoodUI.label_fixed("Уровень %d" % run.level, 36, LEVEL_COLOR, 9)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(lv)
	left.add_child(_xp_bar(Vector2(340, 34)))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	var t := WoodUI.label_fixed("Характеристики", 46, GOLD, 12)
	right.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	var hp_line := WoodUI.label_fixed("Здоровье", 30, Color.WHITE, 7)
	grid.add_child(hp_line)
	grid.add_child(WoodUI.label_fixed("%d / %d" % [maxi(run.hp, 0), run.max_hp], 30, GOLD, 7))
	grid.add_child(WoodUI.label_fixed(TrainRun.STATS["max_hp"]["about"], 24, UI.CREAM, 5))
	for key: String in TrainRun.STATS:
		if key == "max_hp":
			continue
		var value: int = run.stat(key)
		var base := key in ["hand", "luck", "crit_dmg"]       # these mean something at 0 too
		var on := value > 0 or base
		var dim_c := Color(1, 1, 1, 0.45)
		var n := WoodUI.label_fixed(TrainRun.STATS[key]["name"], 30, Color.WHITE if on else dim_c, 7)
		grid.add_child(n)
		var max_tag := "  макс." if value >= run.stat_cap(key) else ""
		grid.add_child(WoodUI.label_fixed(TrainRun.stat_text(key, value) + max_tag, 30, GOLD if on else dim_c, 7))
		grid.add_child(WoodUI.label_fixed(TrainRun.STATS[key]["about"], 24, UI.CREAM if on else dim_c, 5))
	for key: String in TrainRun.FIGHT_STATS:       # only items give these: shown when there
		if run.stat(key) == 0:
			continue
		grid.add_child(WoodUI.label_fixed(TrainRun.FIGHT_STATS[key]["name"], 30, Color.WHITE, 7))
		grid.add_child(WoodUI.label_fixed(TrainRun.stat_text(key, run.stat(key)), 30, GOLD, 7))
		grid.add_child(WoodUI.label_fixed(TrainRun.FIGHT_STATS[key]["about"], 24, UI.CREAM, 5))
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(0, 90)
	right.add_child(box)
	var close := WoodUI.button_fixed("Закрыть", UI.PURPLE, 28, Vector2(240, 62))
	close.pressed.connect(_close_popup)
	box.add_child(close)
	var center := CenterContainer.new()
	center.size = size
	center.add_child(row)
	root.add_child(center)


## Experience toward the next level: a bar with the numbers on it.
func _xp_bar(sz: Vector2) -> Control:
	var bar := Panel.new()
	bar.custom_minimum_size = sz
	bar.add_theme_stylebox_override("panel", UI.box(Color(0.08, 0.07, 0.12), int(sz.y / 2), 3, LEVEL_COLOR.darkened(0.3)))
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", UI.box(LEVEL_COLOR.darkened(0.15), int(sz.y / 2)))
	var share := clampf(float(run.xp) / run.xp_needed(), 0.0, 1.0)
	fill.position = Vector2(3, 3)
	fill.size = Vector2(maxf((sz.x - 6) * share, sz.y - 6 if share > 0.0 else 0.0), sz.y - 6)
	fill.visible = share > 0.0
	bar.add_child(fill)
	var l := WoodUI.label_fixed("Опыт %d / %d" % [run.xp, run.xp_needed()], 22, Color.WHITE, 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(l)
	return bar


## A set the hero has items of: how many of its items are taken (of how many make it) and what
## the set gives. Gold when the set is complete.
func _set_line(set_id: String) -> PanelContainer:
	var st: Dictionary = TrainItems.SETS[set_id]
	var done: bool = run.set_done(set_id)
	var col: Color = GOLD if done else UI.CREAM
	var panel := PanelContainer.new()
	var sb := WoodUI.plate(GOLD if done else Color(0.45, 0.42, 0.38), 3, 8, 18)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(WoodUI.label_fixed("Набор %s %d/%d" % [st["name"], run.set_count(set_id), int(st["need"])], 32, col, 7))
	v.add_child(WoodUI.label_fixed(String(st["text"]), 26, UI.CREAM, 5))
	return panel


## The hero's items over the screen.
func _open_items() -> void:
	_close_popup()
	_popup = items_page(_close_popup)
	add_child(_popup)


## Tab opens the hero's items, and closes them.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		if _popup != null and is_instance_valid(_popup) and _popup.has_meta("items"):
			_close_popup()
		elif _zoom == null and (_popup == null or not is_instance_valid(_popup)):
			_open_items()
		get_viewport().set_input_as_handled()


## The page of the hero's items and curses (also over a fight of the run, main.gd).
func items_page(on_close: Callable) -> Control:
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_meta("items", true)
	root.add_child(WoodUI.table())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.position = Vector2(110, 30)
	v.size = Vector2(1700, 1020)
	root.add_child(v)
	var t := WoodUI.label_fixed("Предметы · %d" % run.items.size(), 46, GOLD, 12)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1700, 860)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	scroll.add_child(content)
	if run.items.is_empty() and run.curses.is_empty():
		var none := WoodUI.label_fixed("Пока пусто", 36, UI.CREAM, 8)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		none.custom_minimum_size = Vector2(1700, 300)
		content.add_child(none)
	for set_id: String in TrainItems.SETS:
		if run.set_count(set_id) > 0:
			content.add_child(_set_line(set_id))
	for curse in [false, true]:
		var ids: Array = run.curses if curse else run.items
		if ids.is_empty():
			continue
		if curse:
			content.add_child(WoodUI.label_fixed("Проклятия · %d" % ids.size(), 40, CURSE_COLOR, 10))
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 24)
		content.add_child(grid)
		var shown := []
		for id: String in ids:
			if not shown.has(id):
				shown.append(id)
				grid.add_child(_item_card(id, Vector2(260, 358), Callable(), curse, true))
	var box := CenterContainer.new()
	v.add_child(box)
	var close := WoodUI.button_fixed("Закрыть", UI.PURPLE, 28, Vector2(240, 62))
	close.pressed.connect(on_close)
	box.add_child(close)
	return root


## A dark screen over the run with a title; `_popup` is its root.
func _popup_page(title: String) -> VBoxContainer:
	_close_popup()
	var root := Control.new()
	root.size = size
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_popup = root
	root.add_child(WoodUI.table())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.position = Vector2(110, 30)
	v.size = Vector2(1700, 1020)
	root.add_child(v)
	var t := WoodUI.label_fixed(title, 46, GOLD, 12)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return v


## The run deck over the screen. mode "remove": a click throws a card out, "upgrade": a click
## improves a card (both a rest); "": only to look at. Improved copies have a tile of their own.
func _open_deck(mode: String) -> void:
	var title: String = {"remove": "Какую карту выкинуть?", "upgrade": "Какую карту улучшить?"}.get(mode, "Колода · %d" % run.deck_size())
	var v := _popup_page(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1700, 860)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 22)
	scroll.add_child(grid)
	for id: String in _sorted_deck():
		for improved in [false, true]:
			var copies: int = run.upgrade_count(id) if improved else run.plain_count(id)
			if copies <= 0:
				continue
			grid.add_child(_deck_tile(id, improved, copies, mode))
	var box := CenterContainer.new()
	v.add_child(box)
	var close := WoodUI.button_fixed("Закрыть" if mode == "" else "Назад", UI.PURPLE, 28, Vector2(240, 62))
	close.pressed.connect(_close_popup)
	box.add_child(close)


## A card of the deck with its copies under it. Cards the mode cannot use are dimmed.
func _deck_tile(id: String, improved: bool, copies: int, mode: String) -> Control:
	var tile := VBoxContainer.new()
	tile.add_theme_constant_override("separation", 2)
	var usable := mode == "remove" or (mode == "upgrade" and not improved and TrainRun.upgradable(id))
	var holder := []                # the tile, for the click that comes after it is made
	var button := _card_button(id, Vector2(220, 340), func():
		if mode == "remove":
			_confirm_remove(holder[0], id, improved)
		elif mode == "upgrade" and usable:
			UI.sfx("buff")
			match run.phase:
				"shop":
					run.shop_upgrade(id)
				"event":
					run.event_pick(id)
				_:
					run.upgrade_card(id)
			rebuild())
	holder.append(button)
	if mode == "" or not usable:
		button.set_meta("kn_zoom", true)     # Enter shows the card big (key_nav.gd)
	if mode != "" and not usable:
		button.modulate = Color(1, 1, 1, 0.35)
		button.mouse_default_cursor_shape = Control.CURSOR_ARROW
	if improved:
		button.set_meta("improved", true)
		var mark := Control.new()
		mark.position = Vector2(110, 170)
		mark.scale = Vector2.ONE * (220.0 / CardView.SIZE.x)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.draw.connect(func(): CardView.draw_upgrade_mark(mark, CardView.FONT))
		button.add_child(mark)
	tile.add_child(button)
	var label := ""
	if improved:
		label = TrainRun.upgrade_text(id)
	if copies > 1:
		label += (" " if label != "" else "") + "×%d" % copies
	var badge := WoodUI.label_fixed(label, 28, GOLD, 8)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(220, 36)
	tile.add_child(badge)
	return tile


## «Точно сбросить?» beside the card big, before it leaves the deck.
func _confirm_remove(tile: TextureRect, id: String, improved: bool) -> void:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 22)
	var q := WoodUI.label_fixed("Точно сбросить?", 34, UI.CREAM, 8)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(q)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	side.add_child(row)
	var yes := WoodUI.button_fixed("Да", UI.RED, 28, Vector2(130, 62))
	yes.pressed.connect(func():
		_close_zoom()
		UI.sfx("flip")
		match run.phase:
			"shop":
				run.shop_remove(id, improved)
			"event":
				run.event_pick(id, improved)
			_:
				run.remove_card(id, improved)
		rebuild())
	row.add_child(yes)
	var no := WoodUI.button_fixed("Нет", UI.PURPLE, 28, Vector2(130, 62))
	no.pressed.connect(_close_zoom)
	row.add_child(no)
	_open_zoom(tile, side)


## A rest changes a land: first the one of the four lands, then the type it becomes.
func _open_lands(lane := -1) -> void:
	var v := _popup_page("Какую землю сменить?" if lane < 0 else "Какой будет земля %d?" % (lane + 1))
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(1700, 800)
	v.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	center.add_child(row)
	var types: Array = []
	if lane < 0:
		types = run.lands.duplicate()
	else:
		types = CardDB.land_types().filter(func(t): return t != run.lands[lane])
	for i in types.size():
		var idx: int = i
		var type: String = types[i]
		var tile := VBoxContainer.new()
		tile.add_theme_constant_override("separation", 6)
		tile.add_child(_tile_button(load("res://assets/lands/%s_1.png" % type), Vector2(230, 355), func():
			UI.sfx("flip")
			if lane < 0:
				_open_lands(idx)
			else:
				run.change_land(lane, type)
				rebuild()))
		var name_l := WoodUI.label_fixed(CardDB.land_name(type), 28, UI.CREAM, 7)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(name_l)
		row.add_child(tile)
	var box := CenterContainer.new()
	v.add_child(box)
	var close := WoodUI.button_fixed("Назад", UI.PURPLE, 28, Vector2(240, 62))
	if lane < 0:
		close.pressed.connect(_close_popup)
	else:
		close.pressed.connect(func(): _open_lands())
	box.add_child(close)


func _close_popup() -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null


## Creatures first, then by cost and name.
func _sorted_deck() -> Array:
	var ids: Array = run.cards.keys()
	var order := {"creature": 0, "building": 1, "spell": 2}
	ids.sort_custom(func(a, b):
		var da := CardDB.get_def(a)
		var db := CardDB.get_def(b)
		var ka: int = order.get(da["kind"], 3)
		var kb: int = order.get(db["kind"], 3)
		if ka != kb:
			return ka < kb
		if int(da["cost"]) != int(db["cost"]):
			return int(da["cost"]) < int(db["cost"])
		return String(da["name"]) < String(db["name"]))
	return ids
