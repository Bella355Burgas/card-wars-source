extends Node
## Two-player link, in one of two modes:
##   room  ("relay"): both players connect to the room server (server/relay/relay_server.gd,
##         reached over the internet through an HTTPS tunnel). One creates a room and
##         tells the other its code; no VPN, IP address or open port is needed.
##   lan:  one player hosts, the other joins by IP, over LAN or a virtual LAN such
##         as Radmin VPN (ENet).
## Every game message is numbered and kept by both sides (the journal). If the
## link breaks, the match is kept: once the link is back, each side resends what
## the other one has not got yet, so the game carries on from the same place.
## With a direct link only the guest can come back (the host is the server); with
## a room either player reconnects to the room server. Autoloaded as `Net`.
##
## 2 на 2 and на троих (a room with four or three seats, room mode only): every guest has a link like the one
## above with the host, and the host passes each guest's game messages on to the others.
## So the host's messages are one numbered stream that every guest gets in full, the
## guests' own ones included (with "s", the seat that sent it: a guest skips its own).
##
## A tournament room (docs/tournament-rooms-api.md) is joined like any room, by a code of the
## player's own; the room server tells the seat (seat 0 is the host) and `tour`, what the games
## of the match are played with. At the end of each game both sides send their replay.
## Spectators (room mode, a room for two): the host also sends the room server its game
## for the watchers, the head and the journal as it grows (spec_follow, relay_server.gd
## «Spectators»); a watcher (mode "watch") gets them by the room's watch code. The guest
## is never told of either.

signal connected                        # a new match: handshake done
signal resumed                          # the link came back inside the running match
signal disconnected(reason: String)     # the link is gone (see the reasons below)
signal message(data: Dictionary)
signal room_ready(code: String)         # room mode: we sit in the room with this code
signal seat_joined(seat: int, resumed: bool)    # 2 на 2 host: a guest's link is up
signal seat_left(seat: int, on_purpose: bool)   # 2 на 2 host: a guest's link dropped / the guest left
signal tour_changed(what: String)       # tournament room: "state" (a game was decided), "settings" (the organizer changed them)
signal watch_ready                      # watcher: the room server took the watch code
signal spec_head(g: int, head: Dictionary)      # watcher: the host's new game (a replay without steps)
signal spec_steps(g: int, at: int, steps: Array)    # watcher: steps of its journal from place `at` (none: cut there)

const DEFAULT_PORT := 24565
## Bump when the message format or the rules change, so mismatched builds refuse to play.
const PROTOCOL := 33
## The room server. Can be changed in user://settings.cfg ([net] relay_url) or with
## the command line argument --relay <url> (tests).
const RELAY_URL := "wss://89-126-198-150.sslip.io"
## ENet gives up on a silent peer only after this long (ms). Its defaults (5-30 s)
## are too short for a Radmin VPN hiccup.
const TIMEOUT_MIN := 12000
const TIMEOUT_MAX := 60000
## Two slots: while the guest's dead connection still holds one, the guest can rejoin.
const MAX_CLIENTS := 2
## Room mode: a ping every PING_MS keeps the connection (and the tunnel) alive; a
## connection silent for SILENCE_MS is taken as lost; connecting gives up after CONNECT_MS.
const PING_MS := 4000
const SILENCE_MS := 20000
const CONNECT_MS := 12000
const ROOM_PEER := 2                    # the other seat in room mode, as an ENet-like peer id
## Host: the journal goes to the watchers at most this often, this many steps in a message.
const SPEC_MS := 250
const SPEC_CHUNK := 60

## disconnected reasons: "peer_left" / "server_left" (link lost, match kept; a watcher may rejoin),
## "failed" (a connect attempt failed, match kept), "left" (the other player quit on purpose),
## "version", "busy", "no_match", "full" and "invite" (refused), "no_room" (no room with this code),
## "desync" (the copies no longer agree), "closed" (the organizer closed the tournament room, see tour_closed; watcher: the room is gone).

var mode := ""                  # "relay", "lan", "watch" or "" (no link)
var is_host := false
var active := false             # link is up and the handshake is done
var match_id := 0               # 0 = no match; a guest rejoins only the match with this id
var room_code := ""             # room mode: the room we sit in
var relay_url := RELAY_URL
var _peer: ENetMultiplayerPeer = null
var _remote_id := 0             # peer id of the other player (0 = nobody)
var _connecting := false        # guest: handshake in progress
var _addr := ["", DEFAULT_PORT] # guest: where to rejoin
var _out_log: Array = []        # every game message this side sent in the match, numbered from 1
var _in_count := 0              # game messages received from the other side so far
# Room mode
var _ws: WebSocketPeer = null
var _ws_open := false
var _ws_first: Dictionary = {}  # what to say once the socket is open (create / join / resume)
var _ws_started := 0
var _last_heard := 0
var _last_ping := 0
var _token := ""                # proves our seat when we come back
var _closing: Array = []        # [socket, close at msec]: goodbyes still going out
# 2 на 2
var team := false               # the room has more than two seats (2 на 2, на троих)
var room_seats := 2             # how many: 2, 3 or 4
var seat_no := 0                # our seat in the room (0 = the host)
var _guests := {}               # host: seat -> {"active": bool, "in": game messages got from that guest}
var accept_new := true          # host: a new guest may come in (false while a game is on the table)
# Tournament room
var tour := {}                  # what the room server says of the match (relay_server.gd, _tour_info); {} = not a tournament
var tour_closed := ""           # why the organizer closed the room
var _tour_result := {}          # our replay of the last game, until the server has it
# Spectators
var watch_code := ""            # the room's watch code (host: from the room server; watcher: the one typed)
var _spec_on := false           # host: the room server takes the game for watchers
var _spec_game = null           # host: the game the watchers get
var _spec_head := {}
var _spec_g := 0                # its id
var _spec_head_sent := false
var _spec_sent: Array = []      # the steps of its journal the room server has (the same objects)
var _spec_next := 0             # msec of the next look at the journal


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # the room link is polled even while the game is paused
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		relay_url = String(cfg.get_value("net", "relay_url", RELAY_URL))
	var args := OS.get_cmdline_user_args()
	var i := args.find("--relay")
	if i >= 0 and i + 1 < args.size():
		relay_url = args[i + 1]


# ---------------------------------------------------------------- starting a link

## Room mode: opens a new room; room_ready(code) tells its code for the other player.
## seats: 4 a 2 на 2 room, 3 a room на троих; their match starts at once (the guests come in one by one).
## quick: the ticket of a quick game (relay_server.gd «Ranked games»): the server calls its players in.
func host_room(seats := 2, quick := "") -> Error:
	close()
	tour_closed = ""
	mode = "relay"
	is_host = true
	_remote_id = ROOM_PEER
	team = seats > 2
	room_seats = seats
	seat_no = 0
	if team:
		match_id = randi_range(1, 0x7fffffff)
		active = true
	var first := {"op": "create", "v": PROTOCOL, "seats": seats}
	if quick != "":
		first["q"] = quick
	return _ws_connect(first)


## Room mode: sits down in the room with this code. pass: of an invite (a room by invites only takes no other).
func join_room(code: String, pass_key := "") -> Error:
	close()
	tour_closed = ""
	mode = "relay"
	is_host = false
	_remote_id = 1
	room_code = code.strip_edges().to_upper()
	var first := {"op": "join", "code": room_code, "v": PROTOCOL}
	if pass_key != "":
		first["pass"] = pass_key
	return _ws_connect(first)


## Room mode: the token of our seat (it proves to the relay that the room is ours).
func seat_token() -> String:
	return _token


## Watches the match of the room with this watch code (from its host, or a tournament's).
## watch_ready, then spec_head and spec_steps bring the game.
func watch(code: String) -> Error:
	close()
	mode = "watch"
	watch_code = code.strip_edges().to_upper()
	return _ws_connect({"op": "watch", "code": watch_code, "v": PROTOCOL})


## Host: the watchers of the room get this game (head: Replay.from_game without its steps)
## and every step of its journal, till the next game. Only when the room server can take them.
func spec_follow(g, head: Dictionary) -> void:
	if mode != "relay" or not is_host or team or not _spec_on:
		return
	_spec_game = g
	_spec_head = head
	_spec_g = randi_range(1, 0x7fffffff)
	_spec_head_sent = false
	_spec_sent = []
	_spec_next = 0


## LAN mode: opens a new match and waits for the guest.
func host(port := DEFAULT_PORT, bind_ip := "*") -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip(bind_ip)
	var err := _peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	mode = "lan"
	is_host = true
	match_id = randi_range(1, 0x7fffffff)
	return OK


## LAN mode: starts a new match with the host at ip.
func join(ip: String, port := DEFAULT_PORT) -> Error:
	close()
	mode = "lan"
	_addr = [ip, port]
	return _connect()


## True when this side should reconnect: its own link is down while a match (or,
## in room mode, a room) is waiting for it.
func can_rejoin() -> bool:
	if mode == "relay":
		return room_code != "" and _ws == null
	if mode == "watch":
		return watch_code != "" and _ws == null
	return mode == "lan" and not is_host and match_id != 0 and not active


## Our own connection is up (room mode: to the room server; LAN: the match handshake is done).
func link_up() -> bool:
	return _ws_open if mode == "relay" or mode == "watch" else active


## Connects again to carry on with the running match (or the room).
func rejoin() -> Error:
	if mode == "watch":
		if _ws != null:
			return ERR_BUSY
		return _ws_connect({"op": "watch", "code": watch_code, "v": PROTOCOL})
	if mode == "relay":
		if room_code == "" or _token == "":
			return ERR_UNCONFIGURED
		if _ws != null:
			return ERR_BUSY
		return _ws_connect({"op": "resume", "code": room_code, "token": _token, "v": PROTOCOL})
	if is_host or match_id == 0:
		return ERR_UNCONFIGURED
	return _connect()


func _connect() -> Error:
	if _connecting:
		return ERR_BUSY
	_drop_link()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_addr[0], _addr[1])
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = _peer
	is_host = false
	_remote_id = 1
	_connecting = true
	return OK


# ---------------------------------------------------------------- sending and leaving

## Sends a game message. It is kept in the journal even while the link is down,
## and goes out (again, if needed) as soon as the link is back. 2 на 2 it carries
## our seat; the host's goes to every guest whose link is up.
func send(data: Dictionary) -> void:
	if match_id == 0:
		return
	var msg := data.duplicate()
	msg["k"] = _out_log.size() + 1
	if team:
		msg["s"] = int(msg.get("s", seat_no))
	_out_log.append(msg)
	if team and is_host:
		for g: int in _guests:
			if _guests[g]["active"]:
				_post_to(g, msg)
	elif active:
		_post(msg)


## 2 на 2: the seats of the guests whose links are up (the host's view).
func guest_seats() -> Array:
	var out := []
	for g: int in _guests:
		if _guests[g]["active"]:
			out.append(g)
	out.sort()
	return out


## Ends the match on purpose. The other player is told, so they do not wait for a rejoin.
func leave() -> void:
	if not active:
		close()
		return
	_post({"t": "leave"})
	if mode == "relay":
		close()         # says "close" to the room server after the goodbye
		return
	var old := _peer
	_peer = null
	_reset_match()
	mode = ""
	_close_later(old)


## Leaves at once, without telling the other player (in room mode the room
## server is told, so the room or the seat is freed).
func close() -> void:
	if _ws != null and _ws_open:
		_ws_put({"op": "close"})
	_drop_link()
	_reset_match()
	mode = ""
	room_code = ""
	_token = ""
	watch_code = ""
	_spec_on = false
	_spec_game = null
	tour = {}
	_tour_result = {}


## Tournament room: our replay of a finished game goes to the room server (again after a
## lost link, until it says it has it).
func send_tour_result(game: int, winner: int, replay: Dictionary) -> void:
	if ranked():
		# A ranked game: the server takes what both games say, no replay.
		_tour_result = {"op": "t_result", "game": game, "winner": winner}
		_ws_put(_tour_result)
		return
	var text := JSON.stringify(replay).to_utf8_buffer()
	_tour_result = {"op": "t_result", "game": game, "winner": winner, "size": text.size(),
		"replay": text.compress(FileAccess.COMPRESSION_GZIP)}
	_ws_put(_tour_result)


## A ranked match (a room the server made, «Ranked games» of relay_server.gd): tour has "rank".
func ranked() -> bool:
	return tour.get("rank") is Dictionary


## Ranked match: our bans (up to two decks) while its phase is "ban".
func rank_ban(decks: Array) -> void:
	_ws_put({"op": "r_ban", "decks": decks})


## Ranked match: our deck while its phase is "pick".
func rank_pick(deck: String) -> void:
	_ws_put({"op": "r_pick", "deck": deck})


## Drops the connection but keeps the match, so it can be resumed.
func _drop_link() -> void:
	active = false
	_connecting = false
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	if _ws != null:
		# Queued messages (a goodbye) still go out before the socket closes.
		_closing.append([_ws, Time.get_ticks_msec() + 500])
		_ws = null
	_ws_open = false


func _reset_match() -> void:
	active = false
	if mode != "relay":
		_remote_id = 0
	match_id = 0
	_out_log.clear()
	_in_count = 0
	_guests.clear()
	team = false
	room_seats = 2
	seat_no = 0
	accept_new = true


## Closes a peer a moment later, so the goodbye packet still goes out.
func _close_later(old: ENetMultiplayerPeer) -> void:
	await get_tree().create_timer(0.3).timeout
	if old != null:
		old.close()
		if multiplayer.multiplayer_peer == old:
			multiplayer.multiplayer_peer = null


## 2 на 2 host: a message to one guest only.
func _post_to(seat: int, msg: Dictionary) -> void:
	_ws_put({"op": "msg", "d": msg, "to": seat})


## A message to the other player, over whichever link is up.
func _post(msg: Dictionary) -> void:
	if mode == "relay":
		_ws_put({"op": "msg", "d": msg})
	elif _peer != null and _remote_id != 0:
		_recv.rpc_id(_remote_id, msg)


## IPv4 addresses of this machine, Radmin VPN (26.x.x.x) first.
func local_ipv4() -> Array:
	var out := []
	for a: String in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	out.sort_custom(func(a, b): return a.begins_with("26.") and not b.begins_with("26."))
	return out


## "26.1.2.3" or "26.1.2.3:24565" -> [ip, port]
static func parse_address(text: String) -> Array:
	var t := text.strip_edges()
	var port := DEFAULT_PORT
	if t.count(":") == 1:
		var parts := t.split(":")
		t = parts[0]
		if parts[1].is_valid_int():
			port = int(parts[1])
	return [t, port]


# ---------------------------------------------------------------- the match handshake (both modes)

@rpc("any_peer", "call_remote", "reliable")
func _recv(data: Dictionary) -> void:
	_handle(multiplayer.get_remote_sender_id(), data)


func _handle(sender: int, data: Dictionary) -> void:
	if team and is_host:
		_host_handle(sender, data)
		return
	match data.get("t", ""):
		"hello":
			if is_host:
				_on_hello(sender, data)
		"welcome":
			if not is_host and _connecting:
				_on_welcome(data)
		"refuse":
			if not is_host and _connecting:
				close()
				disconnected.emit(String(data.get("r", "failed")))
		"leave":
			if sender == _remote_id:
				_on_left()
		_:
			_on_game_message(sender, data)


## The guest greets the host: a new match, or the one it was in (match id and what it got).
func _say_hello() -> void:
	_connecting = true
	_post({"t": "hello", "v": PROTOCOL, "m": match_id, "in": _in_count})


## Host: a guest connects. A rejoin needs the match id; a new guest starts a new match.
func _on_hello(sender: int, data: Dictionary) -> void:
	if mode == "lan" and _peer == null:
		return      # we are leaving: the server is already closing
	if int(data.get("v", -1)) != PROTOCOL:
		_refuse(sender, "version")
		return
	var m := int(data.get("m", 0))
	var resuming := m != 0
	if resuming:
		if m != match_id:
			_refuse(sender, "no_match")
			return
	elif active:
		_refuse(sender, "busy")
		return
	else:
		match_id = randi_range(1, 0x7fffffff)
		_out_log.clear()
		_in_count = 0
	if mode == "lan":
		if _remote_id != 0 and _remote_id != sender:
			# The old connection may still be there, not yet timed out: it is replaced.
			_peer.disconnect_peer(_remote_id, true)
		_remote_id = sender
		_peer.get_peer(sender).set_timeout(32, TIMEOUT_MIN, TIMEOUT_MAX)
	active = true
	_post({"t": "welcome", "v": PROTOCOL, "m": match_id, "in": _in_count})
	var guest_in := int(data.get("in", 0))
	for msg in _out_log:
		if int(msg["k"]) > guest_in:
			_post(msg)
	if resuming:
		resumed.emit()
	else:
		connected.emit()


## Guest: the host accepted us. Then both sides resend what the other one missed.
func _on_welcome(data: Dictionary) -> void:
	if int(data.get("v", -1)) != PROTOCOL:
		close()
		disconnected.emit("version")
		return
	var m := int(data.get("m", 0))
	var resuming := match_id != 0
	if resuming and m != match_id:
		close()
		disconnected.emit("no_match")
		return
	if not resuming:
		match_id = m
	_connecting = false
	active = true
	var host_in := int(data.get("in", 0))
	for msg in _out_log:
		if int(msg["k"]) > host_in:
			_post(msg)
	if resuming:
		resumed.emit()
	else:
		connected.emit()


func _on_game_message(sender: int, data: Dictionary) -> void:
	if not active or sender != _remote_id:
		return
	if team:
		# The host's stream: every message counts, our own ones (passed back) are not played again.
		var k2 := int(data.get("k", 0))
		if k2 <= _in_count:
			return
		if k2 != _in_count + 1:
			close()
			disconnected.emit("desync")
			return
		_in_count += 1
		if int(data.get("s", 0)) != seat_no:
			message.emit(data)
		return
	var k := int(data.get("k", 0))
	if k <= _in_count:
		return      # a copy of something already received
	if k != _in_count + 1:
		# The link is ordered, so this cannot happen; if it does, the copies no longer match.
		close()
		disconnected.emit("desync")
		return
	_in_count += 1
	message.emit(data)


func _on_left() -> void:
	if is_host:
		_reset_match()      # the room (or the server) stays open for the next guest
	else:
		close()
	disconnected.emit("left")


func _refuse(peer_id: int, reason: String) -> void:
	_post({"t": "refuse", "r": reason})
	if mode != "lan":
		return      # the refused guest leaves the room by itself
	await get_tree().create_timer(0.3).timeout
	if _peer != null:
		_peer.disconnect_peer(peer_id)


# ---------------------------------------------------------------- 2 на 2 host

## A message of guest `g`: its hello, or a game message that the host plays and passes on.
func _host_handle(g: int, data: Dictionary) -> void:
	match data.get("t", ""):
		"hello":
			_host_hello(g, data)
		"welcome", "refuse", "leave":
			pass
		_:
			var link: Dictionary = _guests.get(g, {})
			if link.is_empty() or not link["active"]:
				return
			var k := int(data.get("k", 0))
			if k <= int(link["in"]):
				return
			if k != int(link["in"]) + 1:
				_post_to(g, {"t": "refuse", "r": "desync"})
				return
			link["in"] = k
			var fwd := data.duplicate()
			fwd.erase("k")
			fwd["s"] = g
			send(fwd)           # every guest gets it, with its place in the host's stream
			fwd["k"] = _out_log.size()
			message.emit(fwd)


## A guest says hello: a new guest of the room, or one coming back to the match.
## It gets the stream from where it stopped, and resends what we missed.
func _host_hello(g: int, data: Dictionary) -> void:
	if int(data.get("v", -1)) != PROTOCOL:
		_post_to(g, {"t": "refuse", "r": "version"})
		return
	var m := int(data.get("m", 0))
	if m != 0 and m != match_id:
		_post_to(g, {"t": "refuse", "r": "no_match"})
		return
	var resuming: bool = m != 0 and _guests.has(g)
	if not resuming and not accept_new:
		_post_to(g, {"t": "refuse", "r": "busy"})
		return
	if not resuming:
		_guests[g] = {"active": true, "in": 0}
	_guests[g]["active"] = true
	_post_to(g, {"t": "welcome", "v": PROTOCOL, "m": match_id, "in": int(_guests[g]["in"])})
	var got := int(data.get("in", 0))
	for msg in _out_log:
		if int(msg["k"]) > got:
			_post_to(g, msg)
	seat_joined.emit(g, resuming)


# ---------------------------------------------------------------- LAN (ENet) events

func _on_connected_to_server() -> void:
	if _peer == null:
		return
	_peer.get_peer(1).set_timeout(32, TIMEOUT_MIN, TIMEOUT_MAX)
	_say_hello()


func _on_connection_failed() -> void:
	_drop_link()
	disconnected.emit("failed")


func _on_server_disconnected() -> void:
	if is_host or _peer == null:
		return      # already dropped on purpose (a refusal or our own close)
	_drop_link()
	disconnected.emit("server_left")


func _on_peer_disconnected(id: int) -> void:
	if mode != "lan" or not is_host or id != _remote_id:
		return
	_remote_id = 0
	if active:
		active = false
		disconnected.emit("peer_left")


# ---------------------------------------------------------------- room mode (WebSocket)

func _ws_connect(first: Dictionary) -> Error:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 256 * 1024
	ws.outbound_buffer_size = 256 * 1024
	var err := ws.connect_to_url(relay_url)
	if err != OK:
		return err
	_ws = ws
	_ws_open = false
	_ws_first = first
	_ws_started = Time.get_ticks_msec()
	return OK


func _ws_put(data: Dictionary) -> void:
	if _ws != null and _ws_open:
		_ws.put_packet(var_to_bytes(data))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for item: Array in _closing.duplicate():
		var old: WebSocketPeer = item[0]
		old.poll()
		if now >= int(item[1]):
			old.close()
			_closing.erase(item)
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if now - _ws_started > CONNECT_MS:
				_ws_down(false)
		WebSocketPeer.STATE_OPEN:
			if not _ws_open:
				_ws_open = true
				_last_heard = now
				_last_ping = now
				_ws_put(_ws_first)
			while _ws != null and _ws.get_available_packet_count() > 0:
				var data = bytes_to_var(_ws.get_packet())
				_last_heard = now
				if data is Dictionary:
					_on_relay(data)
			if _ws == null:
				return
			if _spec_game != null and now >= _spec_next:
				_spec_flush(now)
			if now - _last_ping > PING_MS:
				_last_ping = now
				_ws_put({"op": "ping"})
			if now - _last_heard > SILENCE_MS:
				_ws_down(true)
		WebSocketPeer.STATE_CLOSED:
			_ws_down(_ws_open)
		_:
			pass


## The socket is gone: "server_left" if it had been open (the room keeps our
## seat, we can come back), "failed" if it never opened.
func _ws_down(was_open: bool) -> void:
	_drop_link()
	if mode == "watch":
		disconnected.emit("server_left" if was_open else "failed")    # watch() again or rejoin()
		return
	if room_code == "" or _token == "":
		# We never got a seat: there is nothing to come back to.
		var reason := "failed"
		close()
		disconnected.emit(reason)
		return
	disconnected.emit("server_left" if was_open else "failed")


func _on_relay(d: Dictionary) -> void:
	if mode == "watch":
		_on_watch_relay(d)
		return
	match String(d.get("op", "")):
		"created", "joined":
			room_code = String(d["code"])
			_token = String(d["token"])
			# The host of a room that has watchers: "watch" (its code, shown in the lobby) or "spec" (a
			# tournament room: the players never see its watch code).
			watch_code = String(d.get("watch", ""))
			_spec_on = watch_code != "" or d.get("spec") == true
			if int(d.get("seats", 2)) > 2:
				team = true
				room_seats = int(d["seats"])
				seat_no = int(d.get("seat", 0))
			if d.get("tour") is Dictionary:
				# A tournament code: the server says which seat is ours, seat 0 hosts the games.
				tour = d["tour"]
				is_host = int(d.get("seat", 1)) == 0
				_remote_id = ROOM_PEER if is_host else 1
			room_ready.emit(room_code)
		"resumed":
			if d.get("tour") is Dictionary:
				var was: Dictionary = tour
				tour = d["tour"]
				if not _tour_result.is_empty():
					_ws_put(_tour_result)
				if was.get("turn_time") != tour.get("turn_time") or was.get("undo") != tour.get("undo"):
					tour_changed.emit("settings")
				if was.get("seed") != tour.get("seed") or was.get("over") != tour.get("over") or ranked():
					tour_changed.emit("state")
			if _spec_game != null and _spec_head_sent:
				# The room server answers "spec_need" if steps got lost with the link.
				_ws_put({"op": "spec", "g": _spec_g, "at": _spec_sent.size(), "steps": []})
			if team and is_host:
				# Back in our room: each guest says hello again when the server pairs us.
				active = true
				for g: int in _guests:
					_guests[g]["active"] = false
				resumed.emit()
				return
			if not bool(d.get("peer", false)) and match_id != 0:
				# We are back, the other player is not (yet).
				disconnected.emit("peer_left")
		"paired":
			if not is_host:
				_say_hello()
		"msg":
			if d.get("d") is Dictionary:
				_handle(int(d.get("from", _remote_id)) if team and is_host else _remote_id, d["d"])
		"peer_left":
			if team and is_host:
				var g := int(d.get("seat", -1))
				if _guests.has(g):
					_guests[g]["active"] = false
				seat_left.emit(g, false)
				return
			_connecting = false
			if active:
				active = false
				disconnected.emit("peer_left")
		"peer_quit":
			if team and is_host:
				var g2 := int(d.get("seat", -1))
				_guests.erase(g2)
				seat_left.emit(g2, true)
				return
			if match_id != 0 or active:
				_on_left()
		"spec_need":
			if _spec_game != null and d.get("at") is int:
				if d.get("g") != _spec_g:
					_spec_head_sent = false
				else:
					_spec_sent.resize(clampi(d["at"], 0, _spec_sent.size()))
				_spec_next = 0
		"room_closed":
			var had_match := match_id != 0
			var was_tour := not tour.is_empty() and not ranked()    # a ranked room the server closes after its match
			close()
			disconnected.emit("closed" if was_tour else ("no_match" if had_match else "no_room"))
		"t_state":
			if d.get("tour") is Dictionary:
				tour = d["tour"]
				tour_changed.emit("state")
		"t_settings":
			if not tour.is_empty() and d.get("turn_time") is int and d.get("undo") is bool:
				tour["turn_time"] = d["turn_time"]
				tour["undo"] = d["undo"]
				tour_changed.emit("settings")
		"t_closed":
			tour_closed = String(d.get("reason", ""))
		"t_result":
			if int(d.get("game", -1)) == int(_tour_result.get("game", -2)):
				_tour_result = {}
		"r_error":
			if ranked():
				tour_changed.emit("state")      # a ban or a pick the server did not take: the window shows the state again
		"error":
			var r := String(d.get("r", "failed"))
			var had_match := match_id != 0
			close()
			disconnected.emit("no_match" if r == "no_room" and had_match else r)
		_:
			pass


# ---------------------------------------------------------------- spectators

## Host: what the room server has not got of the game yet. Steps are compared by identity,
## so an undo (the journal cut and grown again) is seen: the server is told where to cut.
func _spec_flush(now: int) -> void:
	_spec_next = now + SPEC_MS
	if not _spec_head_sent:
		_ws_put({"op": "spec_head", "g": _spec_g, "head": _spec_head})
		_spec_head_sent = true
		_spec_sent = []
	var j = _spec_game.journal
	if j == null:
		return
	var n := mini(_spec_sent.size(), j.size())
	var same := 0
	while same < n and is_same(_spec_sent[same], j[same]):
		same += 1
	if same == _spec_sent.size() and same == j.size():
		return
	var part: Array = j.slice(same, same + SPEC_CHUNK)
	_ws_put({"op": "spec", "g": _spec_g, "at": same, "steps": part})
	_spec_sent.resize(same)
	_spec_sent.append_array(part)
	if _spec_sent.size() < j.size():
		_spec_next = now        # more to send: the next frame


## Watcher: what the room server says.
func _on_watch_relay(d: Dictionary) -> void:
	match String(d.get("op", "")):
		"watching":
			watch_ready.emit()
		"spec_head":
			if d.get("g") is int and d.get("head") is Dictionary:
				spec_head.emit(d["g"], d["head"])
		"spec":
			if d.get("g") is int and d.get("at") is int and d.get("steps") is Array:
				spec_steps.emit(d["g"], d["at"], d["steps"])
		"room_closed":
			close()
			disconnected.emit("closed")
		"error":
			var r := String(d.get("r", "failed"))
			close()
			disconnected.emit(r)
