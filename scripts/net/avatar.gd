extends RefCounted
## Avatars of the players: a picture of any size is cut to a square from the middle, made 128×128
## and packed to a lossy WebP of at most LIMIT bytes (the room server takes nothing else, see
## server/relay/account_store.gd). Pictures of other players that came from the server are kept in
## user://avatars/, a file per nick and version, so a table is drawn at once the second time.
##   var bytes := Avatar.from_file(path)        # empty when it is no picture or too big
##   var bytes := Avatar.from_hero("finn")      # the picture of a hero card
##   var tex: Texture2D = Avatar.cached("Ник", av)
##   await Avatar.fetch(tree, url, [{"nick", "av"}, ...])     # then cached() has them

const CardDB = preload("res://scripts/core/card_db.gd")
const DailyBoard = preload("res://scripts/net/daily_board.gd")
const SIDE := 128
const LIMIT := 32 * 1024
const MAX_FILE := 24 * 1024 * 1024         # a picture file bigger than this is not even read
const MAX_PIXELS := 40000000
const DIR := "user://avatars"
const BATCH := 8                           # nicks in one request (the server's limit)
## Where the picture of a hero card is, in the 500×688 card: the art without the frame and the text.
const HERO_ART := Rect2i(14, 92, 472, 422)

static var _memory := {}                   # "nick|av" -> Texture2D
static var _asked := {}                    # "nick|av" -> true: the server had nothing for it


## The bytes are a lossy WebP of at most LIMIT bytes and SIDE pixels, read from its header before
## anything is decoded (the server's check, account_store.gd webp_side): no picture that unpacks huge.
static func small_webp(b: PackedByteArray) -> bool:
	if b.size() < 30 or b.size() > LIMIT:
		return false
	if b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "WEBP" \
			or b.slice(12, 16).get_string_from_ascii() != "VP8 " or b[23] != 0x9d or b[24] != 0x01 or b[25] != 0x2a:
		return false
	var w := b.decode_u16(26) & 0x3fff
	var h := b.decode_u16(28) & 0x3fff
	return w > 0 and h > 0 and w <= SIDE and h <= SIDE


## A picture to the bytes of an avatar; empty when it cannot be made small enough.
static func encode(source: Image) -> PackedByteArray:
	if source == null or source.is_empty() or source.get_width() * source.get_height() > MAX_PIXELS:
		return PackedByteArray()
	var img := source.duplicate() as Image
	if img.is_compressed() and img.decompress() != OK:
		return PackedByteArray()
	img.convert(Image.FORMAT_RGBA8)
	var side := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.resize(SIDE, SIDE, Image.INTERPOLATE_LANCZOS)
	# Transparent places are painted over, the avatar has no alpha.
	var flat := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBA8)
	flat.fill(Color(0.16, 0.15, 0.22))
	flat.blend_rect(img, Rect2i(0, 0, SIDE, SIDE), Vector2i.ZERO)
	flat.convert(Image.FORMAT_RGB8)
	for quality in [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3]:
		var bytes := flat.save_webp_to_buffer(true, quality)
		if bytes.size() <= LIMIT:
			return bytes
	return PackedByteArray()


static func from_file(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_FILE:
		return PackedByteArray()
	var data := f.get_buffer(f.get_length())
	f.close()
	return encode(_decode(data, path.get_extension().to_lower()))


## The picture of a file by its bytes: by the extension, then by trying the other kinds.
static func _decode(data: PackedByteArray, ext: String) -> Image:
	var img := Image.new()
	var order := ["png", "jpg", "webp", "bmp", "tga"]
	var first: String = {"jpeg": "jpg"}.get(ext, ext)
	if first in order:
		order.erase(first)
		order.push_front(first)
	for kind in order:
		var err := OK
		match kind:
			"png": err = img.load_png_from_buffer(data)
			"jpg": err = img.load_jpg_from_buffer(data)
			"webp": err = img.load_webp_from_buffer(data)
			"bmp": err = img.load_bmp_from_buffer(data)
			"tga": err = img.load_tga_from_buffer(data)
		if err == OK and not img.is_empty():
			return img
	return null


## The ids of the hero cards that are offered as avatars.
static func hero_ids() -> Array:
	return CardDB.hero_card_ids()


## The art part of a hero card's picture; `small`: from its small copy (for the avatar choice,
## the full pictures of all the heroes took seconds).
static func hero_image(hero: String, small := false) -> Image:
	if not CardDB.has_hero_card(hero):
		return null
	var tex := load(CardDB.hero_thumb(hero) if small else CardDB.hero_image(hero)) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	var rect := HERO_ART
	if img.get_width() != 500 or img.get_height() != 688:      # another size: the same part of it
		var k := float(img.get_width()) / 500.0
		rect = Rect2i(Vector2i(Vector2(rect.position) * k), Vector2i(Vector2(rect.size) * k))
	return img.get_region(rect)


static func from_hero(hero: String) -> PackedByteArray:
	return encode(hero_image(hero))


# ---------------------------------------------------------------- pictures of other players

static func _key(nick: String, av: String) -> String:
	return "%s|%s" % [nick.to_lower(), av]


static func _file(nick: String, av: String) -> String:
	return "%s/%s_%s.webp" % [DIR, nick.to_lower().sha256_text().substr(0, 16), av]


## The texture of an avatar (the version `av` of this nick), null when it is not here yet.
static func cached(nick: String, av: String) -> Texture2D:
	if av == "":
		return null
	var key := _key(nick, av)
	if _memory.has(key):
		return _memory[key]
	var file := _file(nick, av)
	if FileAccess.file_exists(file):
		var img := Image.new()
		if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(file)) == OK:
			_memory[key] = ImageTexture.create_from_image(img)
			return _memory[key]
	return null


## Keeps the avatar bytes of a nick (older versions of it go); the texture, null if they are no picture.
static func store(nick: String, av: String, bytes: PackedByteArray) -> Texture2D:
	var img := Image.new()
	if av == "" or not small_webp(bytes) or img.load_webp_from_buffer(bytes) != OK:
		return null
	DirAccess.make_dir_recursive_absolute(DIR)
	var mine := _file(nick, av)
	var prefix := mine.get_file().get_slice("_", 0) + "_"
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with(prefix) and DIR + "/" + f != mine:
			DirAccess.remove_absolute(DIR + "/" + f)
	var out := FileAccess.open(mine, FileAccess.WRITE)
	if out != null:
		out.store_buffer(bytes)
		out.close()
	var tex := ImageTexture.create_from_image(img)
	_memory[_key(nick, av)] = tex
	return tex


## Asks the server for the avatars of {"nick", "av"} rows that are not here yet.
static func fetch(tree: SceneTree, url: String, rows: Array) -> void:
	var missing := []
	for r: Dictionary in rows:
		var nick := String(r.get("nick", ""))
		var av := String(r.get("av", ""))
		if av != "" and not _asked.has(_key(nick, av)) and cached(nick, av) == null and not missing.has(nick):
			missing.append(nick)
	for i in range(0, missing.size(), BATCH):
		var batch: Array = missing.slice(i, i + BATCH)
		var answer: Dictionary = await DailyBoard.request(tree, url, {"op": "acc_avatars", "nicks": batch})
		if not answer["ok"]:
			return
		for item in answer.get("items", []):
			if item is Dictionary and item.get("data") is PackedByteArray:
				store(String(item["nick"]), String(item["av"]), item["data"])
		for r: Dictionary in rows:
			if batch.has(String(r.get("nick", ""))):
				_asked[_key(String(r["nick"]), String(r["av"]))] = true     # no second try for what is not there
