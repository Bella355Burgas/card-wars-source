extends RefCounted
## The phone layout: on Android and iPhone (or in a test that asks for it) the whole interface
## is drawn twice as big (content scale SCALE): the screen is then about 1200x540 units, a
## button of TOUCH units is a finger wide (≈7–8 mm on a 6–7" phone). The table (board.gd) is a
## fixed 1920x1080 stage and has its own phone layout. docs/MOBILE_UI.md tells the rules.
## No class_name: preload it (a new global class would change the patch fingerprint).

const SCALE := 2.0            # content scale of a phone at «Масштаб» 100%
const ZOOMS := [0.85, 1.0, 1.15]   # «Масштаб» steps on a phone, times SCALE
const TOUCH := 58.0           # the least side of what a finger presses, in units (×SCALE px at 1080 high)
const FONT_MIN := 15          # the least font size of a text, in units
const TOUCH_PART := 0.1       # tests: the least side of a pressed thing, part of the screen height

static var active := OS.has_feature("mobile")
## Tests on a PC: a cutout and a gesture bar to keep out of, in window pixels
## (left, top, right, bottom). A real phone gives them by DisplayServer.get_display_safe_area.
static var fake_insets := Vector4.ZERO


## The window's rect free of the camera cutout and the gesture bar, in window pixels.
static func safe_window_rect() -> Rect2:
	var full := Rect2(Vector2.ZERO, Vector2(DisplayServer.window_get_size()))
	if OS.has_feature("mobile"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		safe.position -= Vector2(DisplayServer.window_get_position())
		if safe.has_area():
			return full.intersection(safe)
		return full
	if active and fake_insets != Vector4.ZERO:
		return Rect2(full.position + Vector2(fake_insets.x, fake_insets.y),
			full.size - Vector2(fake_insets.x + fake_insets.z, fake_insets.y + fake_insets.w))
	return full


## The content scale for a «Масштаб» step.
static func content_scale(zoom: float) -> float:
	return zoom * SCALE if active else zoom


## The least size in window pixels of a button a finger presses (tests).
static func touch_px() -> float:
	return TOUCH_PART * float(DisplayServer.window_get_size().y)
