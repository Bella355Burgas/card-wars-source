extends SceneTree
## Plays the journal of a train of the day again, for the room server (its table, see
## scripts/train/run_check.gd):
##   godot --headless --path <the game> -s res://tools/run_check.gd -- <journal.gz> <out.json> [<date>]
## (no date: an ordinary run, a record of the train)
## out.json: {"err": "" when the run is right, "score", "wins", "hero", "deck", "restarts", "ms"}. The
## server runs it as a process of its own, one at a time.

const RunCheck = preload("res://scripts/train/run_check.gd")
const JOURNAL_MAX := 32 * 1024 * 1024     # unpacked


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := {"err": "no file"}
	var t0 := Time.get_ticks_msec()
	if args.size() >= 2:
		var packed := FileAccess.get_file_as_bytes(args[0])
		var text := packed.decompress_dynamic(JOURNAL_MAX, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
		out = await RunCheck.check(RunCheck.parse(text), args[2] if args.size() >= 3 else "") if text != "" else {"err": "not a packed journal"}
		out["ms"] = Time.get_ticks_msec() - t0
		out["mb"] = int(OS.get_static_memory_peak_usage() / 1048576)
		var f := FileAccess.open(args[1], FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(out))
			f.close()
	quit()
