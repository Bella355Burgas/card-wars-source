extends SceneTree
## Russian text stays readable when the phone's system font has no Cyrillic letters
## (Tecno Camon 30C showed squares with codes): both game fonts carry DejaVu Sans as a fallback
## (UiKit.add_font_fallback), and the theme of all controls holds that same UI font.
## Wingdings stands in for such a system font.
##   godot --headless --path . -s res://tests/font_fallback_test.gd

const UI = preload("res://scripts/ui/ui_kit.gd")
const TEXT := "Карточные войны 2 на 2"


func _init() -> void:
	var fails := 0
	var bare := _font_without_cyrillic([])
	if _missing(bare) == 0:
		push_error("the stand-in font already has Cyrillic, the test proves nothing")
		fails += 1
	UI.add_font_fallback()
	if ThemeDB.get_default_theme().default_font != UI.UI_FONT:
		push_error("the controls' theme does not hold UI_FONT, it misses the fallback")
		fails += 1
	for game_font: Font in [UI.UI_FONT, UI.DISPLAY_FONT]:
		var missing := _missing(_font_without_cyrillic(game_font.fallbacks))
		print("%s: %d missing glyphs" % [game_font.resource_path, missing])
		if missing > 0:
			fails += 1
	print("FAIL" if fails else "OK")
	quit(1 if fails else 0)


func _font_without_cyrillic(fallbacks: Array[Font]) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Wingdings"])
	f.allow_system_fallback = false
	f.fallbacks = fallbacks
	return f


func _missing(font: Font) -> int:
	var line := TextLine.new()
	line.add_string(TEXT, font, 32)
	var ts := TextServerManager.get_primary_interface()
	var n := 0
	for g in ts.shaped_text_get_glyphs(line.get_rid()):
		# A glyph no font has comes without a font and is drawn as a box with its code.
		if not g["font_rid"].is_valid() and not (g["flags"] & TextServer.GRAPHEME_IS_SPACE):
			n += 1
	return n
