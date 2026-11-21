extends SceneTree
## Saved replays must still play back to the very same game after engine changes:
##   godot --headless --path . -s res://tests/replay_files_test.gd -- <dir with *.cwreplay>
## Prints one line per file and the number that no longer match.

const Replay = preload("res://scripts/core/replay.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else Replay.DIR
	var files := []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == Replay.EXT:
			files.append(dir.path_join(f))
	files.sort()
	var bad := 0
	var checked := 0
	for path: String in files:
		var d := Replay.read(path)
		if d.is_empty():
			print("skip ", path.get_file())
			continue
		checked += 1
		var err: String = await Replay.verify(d)
		if err != "":
			bad += 1
		print("%s %s %s" % ["ok  " if err == "" else "FAIL", path.get_file(), err])
	print("replay files: %d checked, %d differ" % [checked, bad])
	quit(1 if bad > 0 else 0)
