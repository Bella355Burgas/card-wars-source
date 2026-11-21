extends RefCounted
## How a nick of an account looks: a rainbow nick or a colour of its own, and a tag under or beside it.
## They come from the room server with the account (account.gd, the rows of the table of the day, the
## players online) and are set there by hand or by an admin of the game; the game only draws them.
##   NickStyle.apply(label, true)                  # the letters of the label shimmer
##   NickStyle.apply(label, false, "541687")       # the letters take that colour
##   var tag := NickStyle.tag("Первый бета тестер", 22)    # null when the text is empty

const WoodUI = preload("res://scripts/ui/wood_ui.gd")

## The fill of the letters is white, the outline and the shadow are dark: the brighter the pixel,
## the more of the rainbow it gets. The colour runs along the line (the position in the label),
## not per letter.
const SHADER_CODE := """
shader_type canvas_item;
varying vec2 pos;
void vertex() {
	pos = VERTEX;
}
vec3 hue(float h) {
	vec3 k = abs(fract(vec3(h) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return mix(vec3(1.0), clamp(k - 1.0, 0.0, 1.0), 0.8);
}
void fragment() {
	float bright = smoothstep(0.4, 0.8, dot(COLOR.rgb, vec3(0.3333)));
	vec3 rainbow = hue(pos.x * 0.008 - TIME * 0.4);
	COLOR.rgb = mix(COLOR.rgb, rainbow, bright);
}
"""

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
	return _material


## Makes the letters of a label shimmer (a label made by WoodUI.label or WoodUI.text), or gives them the
## colour `col` (six hex digits). Does nothing when `on` is false and there is no colour.
static func apply(label: Label, on: bool, col := "") -> void:
	if label == null:
		return
	if not on:
		if is_color(col):
			var c := Color.html(col)
			label.label_settings.font_color = c
			# A dark colour gets a light outline, so it shows on the dark wood too.
			if c.get_luminance() < 0.35:
				label.label_settings.outline_size = maxi(label.label_settings.outline_size, maxi(4, roundi(label.label_settings.font_size * 0.14)))
				label.label_settings.outline_color = Color(1, 0.95, 0.85, 0.9)
		return
	var s := label.label_settings
	s.font_color = Color.WHITE
	s.outline_size = maxi(s.outline_size, maxi(5, roundi(s.font_size * 0.16)))
	s.outline_color = WoodUI.INK
	label.material = material()


## The colour of a nick as the server keeps it ("541687").
static func is_color(col: String) -> bool:
	return col.length() == 6 and col.is_valid_hex_number()


## The colour for a line of rich text: `col` or `fallback`.
static func color_of(col: String, fallback: Color) -> Color:
	return Color.html(col) if is_color(col) else fallback


## A small plate with the tag of a player; null when there is no tag.
static func tag(text: String, size := 22) -> Control:
	if text == "":
		return null
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.12, 0.36, 0.92)
	sb.border_color = Color(1.0, 0.82, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(roundi(size * 0.5))
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	plate.add_theme_stylebox_override("panel", sb)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := WoodUI.label(text, size, Color(1.0, 0.9, 0.5), 0)
	plate.add_child(l)
	return plate
