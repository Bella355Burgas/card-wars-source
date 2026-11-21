extends Control
## A round avatar: the picture of the player in a ring, or, while there is none, a colour and the
## first letter of the nick. Used by the main menu, the profile and the table of the day.
##   var v := AvatarView.make("Ник", texture, 72)

const UI = preload("res://scripts/ui/ui_kit.gd")
const POINTS := 48

var nick := ""
var texture: Texture2D = null
var ring := Color(1, 1, 1, 0.85)
var ring_width := 4.0
var _hover := false

signal pressed       # clicked (only when the view takes the mouse: see make_button)


static func make(p_nick: String, p_texture: Texture2D, side: float, p_ring := Color(1, 1, 1, 0.85)) -> Control:
	var v := new()
	v.nick = p_nick
	v.texture = p_texture
	v.ring = p_ring
	v.ring_width = clampf(side / 18.0, 2.0, 6.0)
	v.custom_minimum_size = Vector2(side, side)
	v.size = Vector2(side, side)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


## An avatar that can be clicked: it lights up under the mouse.
static func make_button(p_nick: String, p_texture: Texture2D, side: float) -> Control:
	var v := make(p_nick, p_texture, side, Color(1, 1, 1, 0.35))
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	v.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	v.mouse_entered.connect(func():
		v._hover = true
		v.queue_redraw())
	v.mouse_exited.connect(func():
		v._hover = false
		v.queue_redraw())
	return v


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()


func set_texture(tex: Texture2D) -> void:
	texture = tex
	queue_redraw()


## A colour of its own for every nick.
static func nick_color(text: String) -> Color:
	var h := float(text.to_lower().hash() % 360) / 360.0
	return Color.from_hsv(h, 0.55, 0.62)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in POINTS:
		var a := TAU * float(i) / float(POINTS)
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * (r - ring_width * 0.5))
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	if texture != null:
		draw_colored_polygon(pts, Color.WHITE, uvs, texture)
	else:
		draw_colored_polygon(pts, nick_color(nick))
		var letter := nick.left(1).to_upper() if nick != "" else "?"
		var fs := int(r * 1.1)
		var font := UI.DISPLAY_FONT
		var ts := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, Vector2(c.x - ts.x * 0.5, c.y + font.get_ascent(fs) * 0.5 - font.get_descent(fs) * 0.1 + 2), letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	var ring_pts := pts.duplicate()
	ring_pts.append(pts[0])
	draw_polyline(ring_pts, Color(1.0, 0.86, 0.35) if _hover else ring, ring_width, true)
