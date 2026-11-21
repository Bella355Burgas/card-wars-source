extends SceneTree
## Plays a replay through the engine and writes what came out, for the room server (a game of
## a tournament room, see docs/tournament-rooms-api.md):
##   godot --headless --path <the game> -s res://tools/replay_check.gd -- <replay.json> <out.json>
## out.json: {"err": "" when the replay plays to its recorded end, "over", "winner", "seed",
## "first", "heroes", "by_over": it ended by a surrender, not by the rules}. The server runs it
## as a process of its own, so a broken replay can't stop the rooms.

const Replay = preload("res://scripts/core/replay.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := {"err": "no file"}
	if args.size() >= 2:
		var d := Replay.read(args[0])
		if d.is_empty():
			out = {"err": "not a replay of these rules"}
		elif d["heroes"].size() != 2:
			out = {"err": "not a game for two"}
		else:
			var r: Dictionary = await Replay.check(d)
			var g = r["game"]
			var steps: Array = d["steps"]
			out = {"err": r["err"], "over": g.phase == "over", "winner": g.winner, "seed": int(d.get("seed", 0)),
				"first": int(d.get("first", 0)), "heroes": d["heroes"],
				"by_over": not steps.is_empty() and steps[-1].get("t") == "over"}
		var f := FileAccess.open(args[1], FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(out))
			f.close()
	quit()
