extends SceneTree
## Headless RL Bridge TCP Server for Godot Card Wars.
## Driven by SceneTree._process for non-blocking engine event loop.

const Game = preload("res://scripts/core/game.gd")
const RandomAgent = preload("res://scripts/core/random_agent.gd")
const AIEncoder = preload("res://scripts/ai/ai_encoder.gd")

var server: TCPServer
var peer: StreamPeerTCP
var game: Game
var agent: RandomAgent

var tracked_hp := [25, 25]
var tracked_creatures := [0, 0]
var agent_player := 0

var _in_buf := ""
var _busy := false


func _initialize() -> void:
	AIEncoder.init()
	var args := OS.get_cmdline_user_args()
	var port := 9999
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	
	server = TCPServer.new()
	var err := server.listen(port, "127.0.0.1")
	if err != OK:
		printerr("Failed to listen on port %d: %d" % [port, err])
		quit(1)
		return
	print("RL Bridge listening on 127.0.0.1:%d" % port)


func _process(_delta: float) -> bool:
	if _busy:
		return false
	
	if server == null:
		return false
	
	if peer == null or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if server.is_connection_available():
			peer = server.take_connection()
			peer.set_no_delay(true)
			_in_buf = ""
			print("Python client connected!")
		return false
	
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer = null
		return false
	
	var avail := peer.get_available_bytes()
	if avail > 0:
		var data := peer.get_data(avail)
		if data[0] == OK:
			_in_buf += (data[1] as PackedByteArray).get_string_from_utf8()
	
	var nl_pos := _in_buf.find("\n")
	if nl_pos != -1:
		var line := _in_buf.substr(0, nl_pos).strip_edges()
		_in_buf = _in_buf.substr(nl_pos + 1)
		if line != "":
			var json_obj = JSON.parse_string(line)
			if json_obj is Dictionary:
				_busy = true
				_process_command(json_obj)
	
	return false


func _process_command(msg: Dictionary) -> void:
	var resp := await _handle_cmd(msg)
	if peer != null and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var out_str := JSON.stringify(resp) + "\n"
		var out_bytes := out_str.to_utf8_buffer()
		peer.put_data(out_bytes)
	_busy = false


func _handle_cmd(msg: Dictionary) -> Dictionary:
	var cmd: String = msg.get("cmd", "")
	match cmd:
		"reset":
			return await _cmd_reset(msg)
		"step":
			return await _cmd_step(msg)
		"close":
			print("Closing RL Bridge.")
			quit(0)
			return {}
	return {"error": "unknown_cmd"}


func _cmd_reset(msg: Dictionary) -> Dictionary:
	var seed_val: int = int(msg.get("seed", randi() % 1000000))
	agent_player = int(msg.get("agent_player", 0))
	
	game = Game.new()
	game.fast_mode = true
	agent = RandomAgent.new(seed_val * 7919)
	game.chooser = agent
	
	var heroes := ["finn", "jake"]
	if msg.get("swap_heroes", false):
		heroes = ["jake", "finn"]
	
	game.setup(heroes, seed_val % 2, seed_val)
	for p in 2:
		if agent.rng.randf() < 0.2:
			await game.cmd_mulligan(p)
	await game.start_game()
	
	var bot_type: String = msg.get("bot", "random")
	if bot_type != "none" and game.turn_player != agent_player and game.phase != "over":
		await _run_bot_turns(bot_type)
	
	_update_tracking()
	
	var p: int = game.turn_player if bot_type == "none" else agent_player
	var obs := AIEncoder.encode_state(game, p)
	var mask := AIEncoder.get_action_mask(game, p)
	
	return {
		"obs": Array(obs),
		"action_mask": mask,
		"turn_player": game.turn_player,
		"done": game.phase == "over",
		"reward": 0.0,
		"winner": game.winner,
		"info": {
			"turn": game.turn_number,
			"hp0": game.players[0].hp,
			"hp1": game.players[1].hp,
			"agent_player": agent_player
		}
	}


func _cmd_step(msg: Dictionary) -> Dictionary:
	var action: int = int(msg.get("action", 58))
	var bot_type: String = msg.get("bot", "random")
	var acting_player: int = game.turn_player if bot_type == "none" else agent_player
	
	var initial_acting_player: int = acting_player
	var initial_self_hp: int = game.players[acting_player].hp
	var initial_opp_hp: int = game.players[game.opp(acting_player)].hp
	var initial_opp_creatures: int = game.creature_count(game.opp(acting_player))
	
	var g_cmd: Dictionary = AIEncoder.action_to_command(game, acting_player, action)
	await game.run_command(acting_player, g_cmd)
	
	if bot_type != "none" and game.phase != "over" and game.turn_player != agent_player:
		await _run_bot_turns(bot_type)
	
	if game.turn_number > 60 and game.phase != "over":
		game.phase = "over"
		if game.players[0].hp > game.players[1].hp:
			game.winner = 0
		elif game.players[1].hp > game.players[0].hp:
			game.winner = 1
		else:
			game.winner = -1
	
	var current_self_hp: int = game.players[initial_acting_player].hp
	var current_opp_hp: int = game.players[game.opp(initial_acting_player)].hp
	var current_opp_creatures: int = game.creature_count(game.opp(initial_acting_player))
	
	var delta_opp_hp: int = initial_opp_hp - current_opp_hp
	var delta_self_hp: int = initial_self_hp - current_self_hp
	var killed_creatures: int = initial_opp_creatures - current_opp_creatures
	
	var reward := 0.0
	if delta_opp_hp > 0:
		reward += float(delta_opp_hp) * 0.01
	if delta_self_hp > 0:
		reward -= float(delta_self_hp) * 0.01
	if killed_creatures > 0:
		reward += float(killed_creatures) * 0.005
	
	if game.phase == "over":
		if game.winner == initial_acting_player:
			reward += 1.0
		elif game.winner == game.opp(initial_acting_player):
			reward -= 1.0
	
	_update_tracking()
	
	var next_obs_player: int = game.turn_player if bot_type == "none" else agent_player
	var obs := AIEncoder.encode_state(game, next_obs_player)
	var mask := AIEncoder.get_action_mask(game, next_obs_player)
	
	return {
		"obs": Array(obs),
		"action_mask": mask,
		"turn_player": game.turn_player,
		"done": game.phase == "over",
		"reward": reward,
		"winner": game.winner,
		"info": {
			"turn": game.turn_number,
			"hp0": game.players[0].hp,
			"hp1": game.players[1].hp,
			"delta_opp_hp": delta_opp_hp,
			"delta_self_hp": delta_self_hp,
			"agent_player": agent_player
		}
	}


func _run_bot_turns(bot_type: String) -> void:
	var opp_player := game.opp(agent_player)
	var max_bot_steps := 50
	var steps := 0
	while game.phase != "over" and game.turn_player == opp_player and steps < max_bot_steps:
		var cmds := game.legal_commands(opp_player)
		if cmds.is_empty():
			break
		var picked: Dictionary
		if bot_type == "heuristic":
			picked = _pick_heuristic(cmds, opp_player)
		else:
			picked = agent.pick_command(cmds)
		await game.run_command(opp_player, picked)
		steps += 1


func _pick_heuristic(cmds: Array, _p: int) -> Dictionary:
	var attacks := cmds.filter(func(c): return c["cmd"] == "attack")
	if not attacks.is_empty():
		return attacks[0]
	var plays := cmds.filter(func(c): return c["cmd"] == "play")
	if not plays.is_empty():
		return plays[0]
	var floops := cmds.filter(func(c): return c["cmd"] == "floop" or c["cmd"] == "activate")
	if not floops.is_empty():
		return floops[0]
	var begin_atk := cmds.filter(func(c): return c["cmd"] == "begin_attack")
	if not begin_atk.is_empty():
		return begin_atk[0]
	return cmds[cmds.size() - 1]


func _update_tracking() -> void:
	for i in 2:
		tracked_hp[i] = game.players[i].hp
		tracked_creatures[i] = game.creature_count(i)
