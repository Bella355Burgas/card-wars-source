extends RefCounted
## The card back every face-down card is drawn with. The player picks it in the settings
## («Рубашка»): the classic one or a picture from res://card_backs/ (tools/make_sharp.gd makes
## their sharp copies in res://card_backs/sharp/, only the copies go into the game).

const CLASSIC := "res://assets/cards/sharp/_back.res"
const DIR := "res://card_backs/sharp"

static var path := CLASSIC
static var _tex: Texture2D = null


## Every back to pick from: the classic one first.
static func all() -> Array:
	var out := [CLASSIC]
	if DirAccess.dir_exists_absolute(DIR):
		var files := Array(DirAccess.get_files_at(DIR))
		files.sort()
		for f: String in files:
			# An exported game lists "x.res.remap" for a resource it converted.
			f = f.trim_suffix(".remap")
			if f.get_extension() == "res" and not out.has(DIR.path_join(f)):
				out.append(DIR.path_join(f))
	return out


static func texture() -> Texture2D:
	if _tex == null:
		if path != CLASSIC and ResourceLoader.exists(path):
			_tex = load(path)
		if _tex == null:
			path = CLASSIC
			_tex = load(CLASSIC)
	return _tex


static func pick(p: String) -> void:
	path = p
	_tex = null
