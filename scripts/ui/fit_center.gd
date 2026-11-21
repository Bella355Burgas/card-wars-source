extends Container
## A CenterContainer that never lets its child out of the screen: when the child is bigger
## than the room (a big interface scale on a small screen), the box scales itself down around
## the middle of the room until the child fits. The room is the screen without a margin at its
## edges and, on a phone, without the camera cutout (safe_rect). The children keep their own
## scale for animations.

const Phone = preload("res://scripts/ui/phone.gd")
const MARGIN := 12.0


## The part of the screen nothing important should leave, in the coordinates of the item's
## canvas layer: the visible rect less `margin`, and on a phone also less the cutout.
static func safe_rect(item: CanvasItem, margin := MARGIN) -> Rect2:
	var vp := item.get_viewport()
	var room := vp.get_visible_rect()
	if Phone.active or OS.has_feature("mobile"):
		room = room.intersection(vp.get_final_transform().affine_inverse() * Phone.safe_window_rect())
	return room.grow(-margin)


## A phone (Phone.active): the child is only made smaller to fit the width; a window taller than
## the screen scrolls under the finger instead (TouchInput drags it, the wheel too): its buttons
## keep the size a finger needs.
var scroll_y := 0.0
var _overflow := 0.0


func _ready() -> void:
	add_to_group("phone_scroll")


## TouchInput: the window has more than the screen shows.
func can_scroll() -> bool:
	return _overflow > 0.5


func scroll_by(dy: float) -> void:
	var was := scroll_y
	scroll_y = clampf(scroll_y - dy, 0.0, _overflow)
	if scroll_y != was:
		queue_sort()


func _input(event: InputEvent) -> void:
	if not can_scroll() or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed and 			(event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		scroll_by(60.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -60.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var room := safe_rect(self)
		if get_parent_control() != null:
			room = get_parent_control().get_global_transform_with_canvas().affine_inverse() * room
		room.position -= position
		var need := Vector2.ZERO
		for child in _children():
			need = need.max(child.get_combined_minimum_size())
		var k := minf(1.0, minf(room.size.x / maxf(need.x, 1.0), room.size.y / maxf(need.y, 1.0)))
		if Phone.active:
			k = minf(1.0, room.size.x / maxf(need.x, 1.0))
		_overflow = maxf(0.0, need.y * k - room.size.y) / k
		scroll_y = clampf(scroll_y, 0.0, _overflow)
		pivot_offset = room.get_center()
		scale = Vector2.ONE * k
		for child in _children():
			var own := child.get_combined_minimum_size()
			child.position = (room.get_center() - own * 0.5).floor()
			if _overflow > 0.0:
				# Its top at the top of the room (after the scale around the room's middle).
				child.position.y = room.get_center().y - (room.size.y * 0.5) / k - scroll_y
			child.size = own


func _children() -> Array[Control]:
	var out: Array[Control] = []
	for child in get_children():
		if child is Control and child.visible and not child.top_level:
			out.append(child)
	return out


func _get_minimum_size() -> Vector2:
	return Vector2.ZERO
