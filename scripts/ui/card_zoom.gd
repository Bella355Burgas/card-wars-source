extends RefCounted
## The card big in a felt window over a dimmed screen, as the deck builder shows it: for the
## right button or a held finger on a card in a list (a discard pile, a choice, the train's
## deck). `side` (optional) stands at the right of the card: a question with its buttons.
## A tap beside the window closes it. The card is as big as the screen lets it be, at any
## «Масштаб»; FitCenter keeps the window inside the screen whatever is beside the card. The
## window lies on a layer of its own over the whole screen, so the dim reaches every edge.

const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const TouchInput = preload("res://scripts/ui/touch_input.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

const GAP := 26.0
const LAYER := 20                  # over the table, its windows and the run screen


## Opens the window over `host` and returns it; free it to close it.
static func open(host: Node, tex: Texture2D, side: Control = null) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "CardZoom"
	layer.layer = LAYER
	layer.add_to_group("card_zoom")        # Esc or B closes it (key_nav.gd)
	host.add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.07, 0.04, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		# a held finger's own release is no tap; a real mouse never holds
		if e is InputEventMouseButton and e.pressed \
				and not (TouchInput.long_pressed and e.device == InputEvent.DEVICE_ID_EMULATION):
			layer.queue_free())
	root.add_child(dim)
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var win := PanelContainer.new()
	var sb := WoodUI.window(30, 24)
	win.add_theme_stylebox_override("panel", sb)
	center.add_child(win)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(GAP))
	win.add_child(h)
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.material = CardView.SHARP
	pic.name = "Card"
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.texture = tex
	h.add_child(pic)
	var side_w := 0.0
	if side != null:
		side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(side)
		side_w = side.get_combined_minimum_size().x + GAP
	var room: Rect2 = root.get_global_transform_with_canvas().affine_inverse() * FitCenter.safe_rect(root)
	var frame := Vector2(sb.content_margin_left + sb.content_margin_right, sb.content_margin_top + sb.content_margin_bottom)
	var avail := room.size - frame - Vector2(side_w + 16.0, 16.0)
	var aspect := 0.714
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / tex.get_height()
	var ph := minf(avail.y, avail.x / aspect)
	if aspect > 1.0:
		ph = minf(ph, room.size.x * 0.62 / aspect)    # a teamwork card on its side
	pic.custom_minimum_size = Vector2(ph * aspect, ph).floor()
	UI.sfx("deal")
	return layer


## True for the click that asks for the big card: the right button, or a held finger.
static func asks(e: InputEvent) -> bool:
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT
