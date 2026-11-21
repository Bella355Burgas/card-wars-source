extends Node
## The first autoload: puts the newer game over the app's own before anything else is loaded.
## On every system the game has the same two parts:
## - the app (CardWars.exe, the APK, CardWars.app, the Linux binary), installed once, with the
##   game of the build it was made from inside; data/app_build.json in it names that build;
## - updates of the game in user://update (scripts/net/updater.gd downloads them): "full", the
##   whole game of a newer build, when a patch would be too big, and "patch", the files changed
##   since the app's game or since the full one. Both go over the app's game, so even a big
##   update needs no new app.
## user://update/state.json names the files and the app they were made for: a new app leaves
## the old ones alone (the updater deletes them). Godot reads the global class list again from
## each pack it loads; what it reads before this runs comes only with a new app: the project
## settings, the UI font and this script (tools/fingerprint.ps1).

const APP_BUILD_PATH := "res://data/app_build.json"
const DIR := "user://update"
const STATE := "user://update/state.json"

## The build of the installed app (0 in the editor).
static var app_build := 0


func _init() -> void:
	if not OS.has_feature("template"):
		return
	var info = JSON.parse_string(FileAccess.get_file_as_string(APP_BUILD_PATH))
	app_build = int(info.get("build", 0)) if info is Dictionary else 0
	var state := read_state()
	if int(state.get("app", -1)) != app_build:
		return
	for part: String in ["full", "patch"]:
		var f: Dictionary = state.get(part, {})
		if f.is_empty():
			continue
		var path := DIR.path_join(str(f.get("file", "")))
		# A patch without the full game it was made over would mix two versions.
		if not FileAccess.file_exists(path) or not ProjectSettings.load_resource_pack(path):
			push_error("cannot load the update " + path)
			return


## What is in user://update: {"app": build, "full": {"build", "file", "sha256"}, "patch": {...}}, {} when nothing.
static func read_state() -> Dictionary:
	var s = JSON.parse_string(FileAccess.get_file_as_string(STATE)) if FileAccess.file_exists(STATE) else null
	return s if s is Dictionary else {}
