extends RefCounted
## The open source copy of the game has no pictures, music or sounds: they are not ours to give
## away. Run from the editor, it takes them from an installed game instead: the game's own pack
## (CardWars.pck) and the updates it downloaded (user://update, the same folder for the editor
## and the game). Files of the project stay as they are: the packs only add what is missing.
## Where the game is: the file game_path.txt in the project's folder (the path to CardWars.pck
## or to its folder), else the place the installer puts it.
## Sfx calls it first thing, before anything loads a picture. In an exported game and in a
## project that has its pictures it does nothing.

const PatchLoader = preload("res://scripts/patch_loader.gd")
const PROBE := "res://assets/cards/sharp/_back.res"
const HINT := "res://game_path.txt"

static var loaded := false


static func load_packs() -> void:
	if loaded or OS.has_feature("template") or ResourceLoader.exists(PROBE):
		return
	loaded = true
	var packs := []
	# The newest first: a pack loaded later does not replace what is already there.
	var state := PatchLoader.read_state()
	for part: String in ["patch", "full"]:
		var f: Dictionary = state.get(part, {})
		if not f.is_empty():
			packs.append(PatchLoader.DIR.path_join(str(f.get("file", ""))))
	var app := installed_pck()
	if app != "":
		packs.append(app)
	var used := 0
	for p: String in packs:
		if FileAccess.file_exists(p) and ProjectSettings.load_resource_pack(p, false):
			used += 1
	if not ResourceLoader.exists(PROBE):
		push_warning("No pictures or sounds: install the game, or write the path to CardWars.pck in game_path.txt (README).")
	else:
		print("Pictures and sounds from the installed game (%d packs)" % used)


## The installed game's CardWars.pck, "" when it is not found.
static func installed_pck() -> String:
	var tries := []
	if FileAccess.file_exists(HINT):
		var hint := FileAccess.get_file_as_string(HINT).strip_edges()
		if hint != "":
			tries.append(hint)
			tries.append(hint.path_join("CardWars.pck"))
	match OS.get_name():
		"Windows":
			tries.append(OS.get_environment("LOCALAPPDATA").path_join("Programs/CardWars/CardWars.pck"))
		"macOS":
			tries.append("/Applications/CardWars.app/Contents/Resources/CardWars.pck")
			tries.append(OS.get_environment("HOME").path_join("Applications/CardWars.app/Contents/Resources/CardWars.pck"))
	for t: String in tries:
		if t.get_extension() == "pck" and FileAccess.file_exists(t):
			return t
	return ""
