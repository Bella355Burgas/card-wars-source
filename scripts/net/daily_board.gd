extends RefCounted
## The client of the table of the «Поезд дня» on the room server (server/relay/daily_store.gd):
## one request per connection, the answer or a short reason why there is none. The game
## never waits on it: every call is a coroutine with a time limit, and a server that is
## away or does not know the table (an old one) only gives {"ok": false, "r": ...}.
##   var answer: Dictionary = await DailyBoard.submit(tree, url, result, token)
##   var answer: Dictionary = await DailyBoard.top(tree, url, date, token)
## The token is the one of the account (scripts/net/account.gd): a result is taken only from a
## player who is logged in, the nick of the table is the account's. An answer has "ok": true and
## the server's own fields (rank, total; rows, me), or "ok": false and "r": "offline" | "timeout" |
## "old" (the server has no table) | the server's reason ("auth" no account behind the token,
## "date", "dup", "bad", "full", "rate"). "dup" means the result is there already.
## request() is also what scripts/net/account.gd asks the server with (the "acc_" requests).

const TIMEOUT_MS := 6000
const PROOF_TIMEOUT_MS := 30000
const PART := 48 * 1024            # the journal goes in parts of this size (a message of the server is at most 64 KB)
const PROOF_MAX := 1536 * 1024     # the server takes no bigger journal


## A result of a train of the day (TrainRun.daily_result) to the table, with the run's packed journal
## (TrainRun.packed_journal): the result is in the table at once ("rank"), the server plays the runs
## at the top again (an old server answered "check": true and showed it after). The journal goes first in parts {"op": "daily_part", "i", "data"},
## the result says how many there were ("parts").
static func submit(tree: SceneTree, url: String, result: Dictionary, token: String, proof := PackedByteArray()) -> Dictionary:
	if proof.size() > PROOF_MAX:
		return {"ok": false, "r": "big"}
	var parts: Array = []
	for at in range(0, proof.size(), PART):
		parts.append({"op": "daily_part", "i": parts.size(), "data": proof.slice(at, at + PART)})
	return await request(tree, url, {"op": "daily_submit", "token": token, "date": result["date"],
		"score": int(result["score"]), "wins": int(result["wins"]), "hero": String(result["hero"]), "deck": String(result["deck"]),
		"parts": parts.size()}, PROOF_TIMEOUT_MS if not parts.is_empty() else TIMEOUT_MS, parts)


## The table of a day, with the place of the account of the token in it.
static func top(tree: SceneTree, url: String, date: String, token: String) -> Dictionary:
	return await request(tree, url, {"op": "daily_top", "date": date, "token": token})


## before: messages sent first (one at a time, as the link takes them), the answer is msg's.
static func request(tree: SceneTree, url: String, msg: Dictionary, timeout_ms := TIMEOUT_MS, before: Array = []) -> Dictionary:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 256 * 1024
	ws.outbound_buffer_size = 256 * 1024
	if ws.connect_to_url(url) != OK:
		return {"ok": false, "r": "offline"}
	var t0 := Time.get_ticks_msec()
	var sent := false
	while Time.get_ticks_msec() - t0 < timeout_ms:
		await tree.process_frame
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if not sent and ws.get_current_outbound_buffered_amount() < PART:
					if not before.is_empty():
						ws.put_packet(var_to_bytes(before.pop_front()))
					else:
						ws.put_packet(var_to_bytes(msg))
						sent = true
				while ws.get_available_packet_count() > 0:
					var data = bytes_to_var(ws.get_packet())
					if not data is Dictionary:
						continue
					var op := String(data.get("op", ""))
					if op == "error":      # an old server: it knows rooms only
						ws.close()
						return {"ok": false, "r": "old"}
					if op == "bug_report":
						ws.close()
						return {"ok": bool(data.get("ok", false)), "r": String(data.get("r", ""))}
					if op == "status":
						ws.close()
						return data
					if op.begins_with("daily_") or op.begins_with("acc_"):
						ws.close()
						if op.ends_with("_error"):
							return {"ok": false, "r": String(data.get("r", "bad"))}
						data["ok"] = true
						return data
			WebSocketPeer.STATE_CLOSED:
				return {"ok": false, "r": "offline"}
	ws.close()
	return {"ok": false, "r": "timeout"}
