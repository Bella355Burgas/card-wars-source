extends SceneTree
## The pictures the game draws cards with. Godot's own mip levels are a 2x2 box filter, and a
## card is drawn 4-9 times smaller than its scan, so cards looked soapy. Here every level is
## shrunk from the full scan by Lanczos and kept in a lossy PortableCompressedTexture2D: the
## same memory, file size and loading time as an imported picture, much sharper when small.
##   - every card scan and the back (assets/cards/) -> assets/cards/sharp/<name>.res
##   - every hero card (assets/heroes/) -> assets/heroes/sharp/<name>.res
##   - every card back to pick from (card_backs/) -> card_backs/sharp/<name>.res
## Командные карты are turned upright here, so the game does not turn them while it plays.
## The scans themselves are set to "skip" on import: only the copies go into the game.
## Run it after adding or changing pictures (it skips copies newer than their scan):
##   godot --headless --path . -s res://tools/make_sharp.gd
##   godot --headless --path . --import

const CardDB = preload("res://scripts/core/card_db.gd")

const QUALITY := 0.85
const SKIP_IMPORT := "[remap]\n\nimporter=\"skip\"\n"


func _initialize() -> void:
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	var pics := []
	for dir: String in ["res://assets/cards", "res://assets/heroes", "res://card_backs"]:
		for f: String in DirAccess.get_files_at(dir):
			if f.get_extension().to_lower() in ["webp", "png", "jpg", "jpeg"]:
				pics.append(dir.path_join(f))
	var made := 0
	var t0 := Time.get_ticks_msec()
	for src: String in pics:
		if _make(src, CardDB.sharp_path(src)):
			made += 1
		_skip_import(src)
	print("%d of %d pictures made in %.1f s" % [made, pics.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	quit()


## False when the copy is newer than its scan already.
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
	var id := src.get_file().get_basename()
	if src.begins_with("res://assets/cards/") and CardDB.has_def(id) and CardDB.get_def(id)["kind"] == "teamwork" \
			and img.get_width() < img.get_height():
		img.rotate_90(COUNTERCLOCKWISE)
	img.fix_alpha_edges()
	var tex := PortableCompressedTexture2D.new()
	tex.keep_compressed_buffer = true
	tex.create_from_image(lanczos_mipmaps(img), PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, false, QUALITY)
	DirAccess.make_dir_recursive_absolute(dst_abs.get_base_dir())
	if ResourceSaver.save(tex, dst) != OK:
		push_error("cannot write " + dst)
		return false
	return true


## The picture with mip levels, each shrunk from the full picture by Lanczos.
static func lanczos_mipmaps(img: Image) -> Image:
	var data := img.get_data()
	var w := img.get_width()
	var h := img.get_height()
	while w > 1 or h > 1:
		w = maxi(1, w >> 1)
		h = maxi(1, h >> 1)
		var level: Image = img.duplicate()
		level.resize(w, h, Image.INTERPOLATE_LANCZOS)
		data.append_array(level.get_data())
	return Image.create_from_data(img.get_width(), img.get_height(), true, Image.FORMAT_RGBA8, data)


## The scan is only the source of the copy: it stays out of the game.
func _skip_import(src: String) -> void:
	var path := ProjectSettings.globalize_path(src) + ".import"
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains("importer=\"skip\""):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(SKIP_IMPORT)
