extends RefCounted
## Tournament awards of a profile as pictures on a wooden shelf: the gold cup with the hero who
## won in it, the silver and the bronze medal (assets/awards, docs/AWARDS.md). An award is one
## string of the profile's "aw" (relay social_store, set on the admin port), so the relay needs
## no change and an old game shows it as a plain plate:
##   «Кубок 07.11.2026 Ферн», «Серебро 07.11.2026», «Бронза 07.11.2026»
## Any other string stays a plate (NickStyle.tag). A tap on an award shows it big with what it is for.

const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const CardZoom = preload("res://scripts/ui/card_zoom.gd")
const TouchInput = preload("res://scripts/ui/touch_input.gd")
const CardDB = preload("res://scripts/core/card_db.gd")

const DIR := "res://assets/awards/"
const KINDS := {"Кубок": 1, "Серебро": 2, "Бронза": 3}
const CUP_H := 170.0                 # the cup on the shelf, units; the medals a bit lower
const MEDAL_H := 140.0
const PLATE := Rect2(0.337, 0.821, 0.324, 0.116)   # the brass plate of the cup, parts of its picture
const INK := Color(0.29, 0.19, 0.06)
const EDGE := Color(1.0, 0.94, 0.7, 0.8)


## {"place": 1..3, "date": "07.11.2026", "hero": "fern" or ""}, or {} for an award that is no picture.
static func parse(a: String) -> Dictionary:
	var re := RegEx.create_from_string("^(Кубок|Серебро|Бронза) (\\d{2}\\.\\d{2}\\.\\d{4})(?: (.+))?$")
	var m := re.search(a.strip_edges())
	if m == null:
		return {}
	return {"place": KINDS[m.get_string(1)], "date": m.get_string(2), "hero": _hero_id(m.get_string(3))}


## The id of a hero by its name in the game («Ферн» -> "fern"), "" when there is none.
static func _hero_id(name: String) -> String:
	if name == "":
		return ""
	var low := name.to_lower()
	for id in CardDB.hero_ids():
		if String(CardDB.hero(id).get("name", "")).to_lower() == low:
			return id
	return ""


## The picture of an award: the cup of its hero (cup_<hero>.png; the first cup was drawn with Ферн,
## a cup of another hero needs its own picture), the medals.
static func texture(aw: Dictionary) -> Texture2D:
	match int(aw.get("place", 0)):
		1:
			var own := DIR + "cup_%s.png" % aw.get("hero", "")
			return load(own if ResourceLoader.exists(own) else DIR + "cup_fern.png")
		2:
			return load(DIR + "medal_silver.png")
		3:
			return load(DIR + "medal_bronze.png")
	return null


## The shelf with the awards of `list` that are pictures, or null when there are none.
static func make(list: Array) -> Control:
	var items := []
	for a in list:
		var aw := parse(String(a))
		if not aw.is_empty():
			items.append(aw)
	if items.is_empty():
		return null
	items.sort_custom(func(x, y): return x["place"] < y["place"] if x["place"] != y["place"] else x["date"] > y["date"])
	var v := VBoxContainer.new()
	v.name = "AwardsShelf"
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# The awards stand on the plank, each one's date under the plank, in the same columns.
	var row := HBoxContainer.new()
	var dates := HBoxContainer.new()
	for box in [row, dates]:
		box.add_theme_constant_override("separation", 22)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
	for aw in items:
		var pic := _pic(aw)
		var date := WoodUI.label(String(aw["date"]), 18, UI.CREAM, 5, UI.UI_FONT)
		date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		date.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := maxf(pic.custom_minimum_size.x, date.get_combined_minimum_size().x)
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_END
		cell.custom_minimum_size.x = w
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(pic)
		row.add_child(cell)
		date.custom_minimum_size.x = w
		dates.add_child(date)
	v.add_child(row)
	var plank := Panel.new()
	plank.custom_minimum_size = Vector2(0, 24)
	plank.add_theme_stylebox_override("panel", WoodUI.plate(WoodUI.SEAM, 3, 31, 6))
	plank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(plank)
	v.add_child(dates)
	return v


## One award to stand on the shelf; a tap shows it big.
static func _pic(aw: Dictionary) -> TextureRect:
	var tex := texture(aw)
	var h := CUP_H if aw["place"] == 1 else MEDAL_H
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pic.custom_minimum_size = Vector2(roundf(h * tex.get_width() / tex.get_height()), h)
	pic.tooltip_text = title(aw)
	pic.mouse_filter = Control.MOUSE_FILTER_STOP
	pic.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pic.set_meta("award", aw)
	pic.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT 				and not TouchInput.long_pressed:
			show_big(pic, aw))
	return pic


## «1 место», «2 место», «3 место».
static func title(aw: Dictionary) -> String:
	return "%d место · Турнир %s" % [aw["place"], aw["date"]]


## The award big over the screen (CardZoom's window), the cup with its plate engraved,
## beside it what it is for.
static func show_big(host: Node, aw: Dictionary) -> CanvasLayer:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.custom_minimum_size.x = 260
	side.add_child(WoodUI.label("%d место" % aw["place"], 40, Color(1.0, 0.82, 0.3), 8))
	side.add_child(WoodUI.label("Турнир", 24, UI.CREAM, 5, UI.UI_FONT))
	side.add_child(WoodUI.label(String(aw["date"]), 24, UI.CREAM, 5, UI.UI_FONT))
	var layer := CardZoom.open(host.get_tree().root, texture(aw), side)
	var pic := layer.find_child("Card", true, false) as TextureRect
	if pic != null:
		pic.material = null
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if aw["place"] == 1:
			_engrave(pic, aw)
	return layer


## The cup's brass plate: «ПОБЕДИТЕЛЬ» and the day, cut in (a dark letter, a light edge under it).
static func _engrave(pic: TextureRect, aw: Dictionary) -> void:
	var h := pic.custom_minimum_size.y * PLATE.size.y
	var plate := VBoxContainer.new()
	plate.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_theme_constant_override("separation", 0)
	plate.anchor_left = PLATE.position.x
	plate.anchor_top = PLATE.position.y
	plate.anchor_right = PLATE.end.x
	plate.anchor_bottom = PLATE.end.y
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.add_child(plate)
	for pair in [["ПОБЕДИТЕЛЬ", 0.29], ["Турнир " + String(aw["date"]), 0.2]]:
		var l := Label.new()
		l.text = pair[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", UI.DISPLAY_FONT)
		l.add_theme_font_size_override("font_size", maxi(8, roundi(h * pair[1])))
		l.add_theme_color_override("font_color", INK)
		l.add_theme_color_override("font_shadow_color", EDGE)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", maxi(1, roundi(h * 0.03)))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(l)
