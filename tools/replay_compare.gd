extends SceneTree
## Compares the AI's commands in a replay with the search's choice in the same position:
##   godot --headless --path . -s res://tools/replay_compare.gd -- <file.cwreplay> [level]
## The recorded game goes on as it was; at every AI command the level's agent (impossible
## by default) is asked what it would play instead. Prints the positions where the search
## disagrees with the recording, with the board, and a count at the end.

const Replay = preload("res://scripts/core/replay.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var d := Replay.read(args[0])
	if d.is_empty():
		printerr("not a replay: " + args[0])
		quit(2)
		return
	var level := args[1] if args.size() > 1 else "impossible"
	var g = Replay.new_game(d)
	var player := Replay.Player.new(d["steps"])
	g.chooser = player
	var seats := [0, 1] if String(d.get("mode", "")) == "aivsai" else [1 - int(d.get("seat", 0))]
	var agents := [null, null]
	for p in seats:
		agents[p] = AILevels.agent(level, d["heroes"][p])
	var steps: Array = d["steps"]
	var total := 0
	var differ := 0
	var t0 := Time.get_ticks_msec()
	while player.pos < steps.size():
		var st: Dictionary = steps[player.pos]
		player.pos += 1
		if st.get("t") == "cmd" and st.get("c") is Dictionary and st["c"].has("cmd"):
			var p := int(st.get("p", 0))
			if seats.has(p):
				var agent = agents[p]
				var recorded: Dictionary = st["c"]
				var searched: Dictionary = await agent.pick_command_async(g, p)
				total += 1
				if searched != recorded:
					differ += 1
					print("turn %d, %s: recorded %s; search %s" % [g.turn_number, g.players[p].name,
						_describe(g, recorded), _describe(g, searched)])
					print("    " + _board(g))
		await Replay.apply(g, st)
	print("AI commands compared=%d  different=%d  (%.1f s)" % [total, differ,
		(Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


func _describe(g, c: Dictionary) -> String:
	match String(c["cmd"]):
		"play":
			var card = g.card(int(c["uid"]))
			return "играет «%s» в зону %d" % [card.card_name(), int(c["lane"]) + 1] if card != null else "играет карту"
		"floop", "activate":
			var s = g.slot(g.turn_player, String(c.get("kind", "creature")), int(c["lane"]))
			var name: String = s.card_name() if s != null else "?"
			return "%s «%s» (зона %d)" % [c["cmd"], name, int(c["lane"]) + 1]
		"attack":
			return "атакует из зоны %d" % (int(c["lane"]) + 1)
		"thaw":
			return "растапливает зону %d" % (int(c["lane"]) + 1)
	return String(c["cmd"])


## Both sides' creatures per lane, ATK/DEF: the side to move first.
func _board(g) -> String:
	var parts := []
	for p in [g.turn_player, 1 - g.turn_player]:
		var row := []
		for lane in 4:
			var c = g.players[p].creatures[lane]
			row.append("%s %d/%d" % [c.card_name(), g.atk_of(p, lane), g.hp_of(p, lane)] if c != null else "-")
		parts.append("%s: %s (hp %d)" % [g.players[p].name, " | ".join(row), g.players[p].hp])
	return "; ".join(parts)
