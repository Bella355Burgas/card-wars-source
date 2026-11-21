extends Node
## Phones and tablets (main.gd adds it): a finger held still is the right mouse button
## (look at a card, take a copy out of a deck) and the system's Back is Escape (the menu
## in a game, closing a window). Godot itself turns taps and drags into the left button.
## The game's code was written for the mouse: where a left click would follow the held
## finger's release, it asks long_pressed first.
## In lists (ScrollContainer) a finger that moves scrolls the list. Many tiles there act
## on the press, so a press in a list waits: it reaches the game, with its release, only
## when the finger lets go without having moved.

const Phone = preload("res://scripts/ui/phone.gd")
const LONG_SEC := 0.45
const SLOP := 16.0                # px a held finger may wander before it is a drag (at least)
const SLOP_PART := 0.03           # ... or this part of the screen's height (32 px on 1080, about 2 mm)

## The touch going on (or just over) has become a right click: its release is no click.
static var long_pressed := false
## The last pointer was a finger. A finger does not hover: the mouse position stays where
## it was lifted, and what was «under the mouse» there would stay raised (hovers()).
static var finger := false

var _down := false
var _at := Vector2.ZERO
var _held := 0.0
var _list: Control = null         # the list the finger went down on (its press waits): a
                                   # ScrollContainer or a window taller than the phone (FitCenter)
var _scrolling := false
var _eat_touch := false            # the touch itself is held back too: a Button takes touches as
                                   # well, and would be pressed twice with the click sent later


func _ready() -> void:
	get_tree().quit_on_go_back = false
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)


## How far (window pixels) a finger may wander and still tap.
static func slop_px() -> float:
	return maxf(SLOP, SLOP_PART * float(DisplayServer.window_get_size().y))


## Things may rise under the pointer: a mouse, not a finger (nor a phone at all).
static func hovers() -> bool:
	return not (finger or Phone.active)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		finger = true
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION 			and event.relative.length() > 0.0:
		finger = false
	# Godot sends the left button made of a touch before the touch itself.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device == InputEvent.DEVICE_ID_EMULATION:
		if event.pressed:
			_at = event.position
			long_pressed = false
			_scrolling = false
			_list = _list_at(_at)
			_eat_touch = _list != null
		if _list == null:
			return
		get_viewport().set_input_as_handled()
		if not event.pressed:
			if not _scrolling and not long_pressed:
				_click(event.position)
			_list = null
	elif event is InputEventScreenTouch and event.index == 0:
		if _eat_touch:
			get_viewport().set_input_as_handled()
			_eat_touch = event.pressed
		_down = event.pressed
		_held = 0.0
		_at = event.position
	elif event is InputEventScreenTouch and event.pressed:
		_down = false                 # a second finger: a pinch of the table, not a held finger
	elif event is InputEventScreenDrag and event.index == 0:
		if _to_window(event.position).distance_to(_to_window(_at)) > slop_px():
			_down = false
			_scrolling = _list != null and not long_pressed
		if _scrolling and is_instance_valid(_list):
			if _list is ScrollContainer:
				_list.scroll_vertical -= roundi(event.relative.y)
				_list.scroll_horizontal -= roundi(event.relative.x)
			else:
				# A window taller than the screen (FitCenter): events are in units, it scrolls in its own.
				_list.scroll_by(event.relative.y / maxf(_list.scale.y, 0.01))


## A tap that went down on a list: its press and release.
func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		mb.pressed = pressed
		mb.position = _to_window(at)
		mb.global_position = mb.position
		Input.parse_input_event(mb)


## Events here are in the stage's units; Input takes window pixels. They differ when the
## screen is not 1080 high (1440 phones, a lowered game resolution) or with «Масштаб».
func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at


## The innermost list under the point that has something to scroll, else null. Of lists that
## are not inside each other the later one in the tree is on top (a window over a window).
func _list_at(at: Vector2) -> Control:
	var best: Control = null
	for node: Node in get_tree().root.find_children("*", "ScrollContainer", true, false):
		var sc := node as ScrollContainer
		if not sc.is_visible_in_tree() or not sc.get_global_rect().has_point(at):
			continue
		if not (sc.get_v_scroll_bar().max_value > sc.size.y + 1 or sc.get_h_scroll_bar().max_value > sc.size.x + 1):
			continue
		if best == null or best.is_ancestor_of(sc) or not sc.is_ancestor_of(best):
			best = sc
	if best != null:
		return best
	# A window taller than a phone's screen: the newest one that is shown.
	for node: Node in get_tree().get_nodes_in_group("phone_scroll"):
		if node.is_visible_in_tree() and node.can_scroll():
			best = node
	return best


func _process(delta: float) -> void:
	if not _down:
		return
	_held += delta
	if _held >= LONG_SEC:
		_down = false
		long_pressed = true
		Input.vibrate_handheld(30)
		for pressed in [true, false]:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_RIGHT
			mb.pressed = pressed
			mb.position = _to_window(_at)
			mb.global_position = mb.position
			Input.parse_input_event(mb)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		for pressed in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_ESCAPE
			key.physical_keycode = KEY_ESCAPE
			key.pressed = pressed
			Input.parse_input_event(key)
