extends RefCounted
## Small factory helpers for the chunky, outlined Balatro-ish UI.

const CardDB = preload("res://scripts/core/card_db.gd")
const DISPLAY_FONT := preload("res://assets/fonts/display_font.tres")
const UI_FONT := preload("res://assets/fonts/ui_font.tres")
const FALLBACK_FONT := preload("res://assets/fonts/DejaVuSans-Bold.ttf")

const RED := Color(0.89, 0.27, 0.22)
const BLUE := Color(0.18, 0.5, 0.88)
const GREEN := Color(0.27, 0.68, 0.33)
const ORANGE := Color(0.95, 0.58, 0.16)
const PURPLE := Color(0.5, 0.33, 0.75)
const DARK := Color(0.11, 0.1, 0.16)
const PANEL := Color(0.16, 0.15, 0.22, 0.92)
const CREAM := Color(1.0, 0.96, 0.86)
const FINN_COLOR := Color(0.25, 0.6, 0.95)
const JAKE_COLOR := Color(0.97, 0.68, 0.17)


## Some phones (Tecno Camon 30C) have a system font without Cyrillic and show boxes with
## codes instead of Russian letters: the game fonts take the missing letters from the
## bundled DejaVu Sans. Set here, not in the .tres, because Godot reads the UI font before
## an update patch is loaded. The project theme holds the same UI_FONT, so all text gets it.
static func add_font_fallback() -> void:
	for font: Font in [UI_FONT, DISPLAY_FONT]:
		font.fallbacks = [FALLBACK_FONT]


static func hero_color(hero: String) -> Color:
	return CardDB.hero_color(hero)


static func box(bg: Color, radius := 16, border := 0, border_color := Color.WHITE, shadow := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	if shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_offset = Vector2(0, shadow * 0.5)
	sb.anti_aliasing = true
	return sb


static func label(text: String, size := 28, color := Color.WHITE, outline := 8, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font if font != null else DISPLAY_FONT
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Color(0.05, 0.04, 0.08, 0.95)
	ls.shadow_size = 0 if outline == 0 else 2
	ls.shadow_color = Color(0, 0, 0, 0.5)
	ls.shadow_offset = Vector2(2, 3)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Buttons that go back: their press has the «back» sound.
const BACK_SOUND_TEXTS := ["Назад", "Закрыть", "Отмена", "Позже"]


static func button(text: String, color := RED, size := 30, min_size := Vector2(0, 64)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", DISPLAY_FONT)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.85))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("outline_size", 6)
	var normal := box(color, 14, 0, Color.WHITE, 0)
	normal.shadow_size = 1
	normal.shadow_color = color.darkened(0.55)
	normal.shadow_offset = Vector2(0, 7)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.15)
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.1)
	pressed.shadow_offset = Vector2(0, 2)
	pressed.expand_margin_top = -5
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.35, 0.33, 0.4)
	disabled.shadow_color = Color(0.18, 0.17, 0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(func(): if not b.disabled: sfx("click"))
	b.pressed.connect(func(): sfx("back" if BACK_SOUND_TEXTS.has(b.text) else "press"))
	return b


static func sfx(name: String, pitch_var := 0.08, volume_db := 0.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_node("Sfx"):
		tree.root.get_node("Sfx").play(name, pitch_var, volume_db)


static func float_text(parent: Node, pos: Vector2, text: String, color: Color, size := 56, rise := 90.0, duration := 0.95) -> void:
	var l := label(text, size, color, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(400, size * 1.4)
	l.pivot_offset = l.size * 0.5
	l.position = pos - l.size * 0.5
	l.z_index = 300
	parent.add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - rise, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.3).from(Vector2.ONE * 1.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "rotation", 0.0, 0.3).from(randf_range(-0.25, 0.25))
	tw.tween_property(l, "modulate:a", 0.0, duration * 0.35).set_delay(duration * 0.65)
	tw.chain().tween_callback(l.queue_free)


static func burst(parent: Node, pos: Vector2, color: Color, amount := 26, speed := 420.0, size := 9.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 290
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.75
	p.spread = 180.0
	p.direction = Vector2.UP
	p.gravity = Vector2(0, 900)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.angular_velocity_min = -360
	p.angular_velocity_max = 360
	var g := Gradient.new()
	g.set_color(0, color.lightened(0.4))
	g.set_color(1, Color(color, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
