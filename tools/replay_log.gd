extends SceneTree
## Prints the game log of a replay with HP, hand sizes and the creatures on the
## lanes (ATK/HP left) after every turn, to see what the AI did in a player's game:
##   godot --headless --path . -s res://tools/replay_log.gd -- <file.cwreplay>
## The game keeps replays in %APPDATA%\Godot\app_userdata\<project name>\replays.

const Replay = preload("res://scripts/core/replay.gd")


func _initialize() -> void:
	var d := Replay.read(OS.get_cmdline_user_args()[0])
	var g = Replay.new_game(d)
	var player := Replay.Player.new(d["steps"])
	g.chooser = player
	var steps: Array = d["steps"]
	var shown := 0
	while player.pos < steps.size():
		var st: Dictionary = steps[player.pos]
		player.pos += 1
		await Replay.apply(g, st)
		if st.get("t") == "turn" or st.get("t") == "end" or player.pos >= steps.size():
			for line in g.log_lines.slice(shown):
				print("    ", line)
			shown = g.log_lines.size()
			var lanes := []
			for p in 2:
				var row := []
				for lane in 4:
					var c = g.slot(p, "creature", lane)
					row.append("%s %d/%d" % [c.def()["name"], g.atk_of(p, lane), g.def_of(p, lane) - c.damage] if c != null else "-")
				lanes.append(" | ".join(row))
			print("== turn %d, HP %d : %d (hands %d : %d)" % [g.turn_number, g.players[0].hp, g.players[1].hp,
				g.players[0].hand.size(), g.players[1].hand.size()])
			print("   P0: ", lanes[0])
			print("   P1: ", lanes[1])
	quit()
