extends SceneTree
## Small copies of the pictures that menus show small: they load many times faster than
## the full scans (945x1260), which made the hero selection stop for over a second.
##   - every hero card -> assets/heroes/thumbs/ (the hero grid, the seats, the lobbies)
##   - every card -> assets/cards/thumbs/ (the deck tiles: own decks show any three cards)
## 320 px wide: three times a hero tile and over three times a deck tile's card, sharp on 4K too.
## Kept like tools/make_sharp.gd's pictures: every mip level shrunk by Lanczos, so they stay
## sharp drawn small too (Godot's own levels are a box filter).
## Run it after adding hero cards, decks or pictures, then import:
##   godot --headless --path . -s res://tools/make_thumbs.gd
##   godot --headless --path . --import

const CardDB = preload("res://scripts/core/card_db.gd")
const MakeSharp = preload("res://tools/make_sharp.gd")

const WIDTH := 320
const QUALITY := 0.92


func _initialize() -> void:
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	var pics := {}       # source -> thumbnail
	for id: String in CardDB.hero_card_ids():
		var src := String(CardDB.hero_card(id)["image"])
		pics[src] = CardDB.thumb_path(src)
	for id: String in CardDB.card_ids():
		if FileAccess.file_exists(CardDB.scan_path(id)):
			pics[CardDB.scan_path(id)] = CardDB.card_thumb_path(id)
	var made := 0
	for src: String in pics:
		if _make(src, pics[src]):
			made += 1
	print("%d of %d thumbnails made" % [made, pics.size()])
	quit()


## False when the thumbnail is newer than its picture already.
func _make(src: String, dst: String) -> bool:
	var src_abs := ProjectSettings.globalize_path(src)
	var dst_abs := ProjectSettings.globalize_path(dst)
	if FileAccess.file_exists(dst_abs) and FileAccess.get_modified_time(dst_abs) >= FileAccess.get_modified_time(src_abs):
		return false
	var img := Image.load_from_file(src_abs)
	if img == null or img.is_empty():
		push_error("cannot read " + src)
		return false
	img.convert(Image.FORMAT_RGBA8)
	img.fix_alpha_edges()
	img.resize(WIDTH, roundi(img.get_height() * float(WIDTH) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	var tex := PortableCompressedTexture2D.new()
	tex.keep_compressed_buffer = true
	tex.create_from_image(MakeSharp.lanczos_mipmaps(img), PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, false, QUALITY)
	DirAccess.make_dir_recursive_absolute(dst_abs.get_base_dir())
	if ResourceSaver.save(tex, dst) != OK:
		push_error("cannot write " + dst)
		return false
	return true
