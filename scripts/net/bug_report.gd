extends RefCounted
## A report of an error to the room server, which passes it on to Telegram (server/relay/relay_server.gd,
## op "bug_report"). The window for it is scripts/ui/bug_report_dialog.gd.
##   BugReport.install()        # once at the start: keeps the last lines of what the game prints
##   var answer: Dictionary = await BugReport.send(tree, url, text, version, mode, nick, replay_path)
## An answer has "ok": true, or "ok": false and "r": "offline" | "timeout" | "old" (a server without
## reports) | the server's reason ("rate" too many, "bad" no text, "off" the server has no bot, "fail").
## The log of the report is the lines kept by install(); without it the file user://logs/godot.log (it
## exists when file logging is on in the project settings), else nothing.

const DailyBoard = preload("res://scripts/net/daily_board.gd")
const LOG_FILE := "user://logs/godot.log"
const TEXT_MAX := 2000
const LOG_LINES := 60
const LOG_CHARS := 8000
const KEEP_LINES := 200
const TIMEOUT_MS := 15000
const REPLAY_MAX := 40 * 1024       # packed, as the server takes it (relay_server.gd BUG_REPLAY_MAX)

static var _logger: Logger
static var _lines := PackedStringArray()
static var _mutex := Mutex.new()


class GameLog extends Logger:
	var sink: Callable

	func _log_message(message: String, error: bool) -> void:
		sink.call(("ERROR " if error else "") + message)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			_error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		sink.call("ERROR %s (%s:%d) %s" % [rationale if rationale != "" else code, file.get_file(), line, function])


## Starts keeping the last lines of the output of the game (prints and errors); repeated calls change nothing.
static func install() -> void:
	if _logger == null:
		var logger := GameLog.new()
		logger.sink = _keep
		_logger = logger
		OS.add_logger(_logger)


static func _keep(text: String) -> void:
	_mutex.lock()
	for line in text.split("\n", false):
		_lines.append(line.substr(0, 400))
	if _lines.size() > KEEP_LINES:
		_lines = _lines.slice(_lines.size() - KEEP_LINES)
	_mutex.unlock()


## The last lines of the log as one text (at most LOG_LINES lines and LOG_CHARS characters), "" when there is none.
static func recent_log() -> String:
	var lines := PackedStringArray()
	_mutex.lock()
	lines = _lines.duplicate()
	_mutex.unlock()
	if lines.is_empty() and FileAccess.file_exists(LOG_FILE):
		lines = FileAccess.get_file_as_string(LOG_FILE).split("\n", false)
	if lines.size() > LOG_LINES:
		lines = lines.slice(lines.size() - LOG_LINES)
	var text := "\n".join(lines)
	if text.length() > LOG_CHARS:
		text = text.substr(text.length() - LOG_CHARS)
	return text


## `replay_path`: a *.cwreplay file to send with it ("" none); it goes packed and only when it is small enough.
static func send(tree: SceneTree, url: String, text: String, version: String, mode: String, nick: String,
		replay_path := "") -> Dictionary:
	var msg := {"op": "bug_report", "text": text.substr(0, TEXT_MAX), "version": version, "mode": mode,
		"log": recent_log(), "nick": nick}
	var packed := pack_replay(replay_path)
	if not packed.is_empty():
		msg["replay"] = packed
		msg["replay_name"] = replay_path.get_file().get_basename()
	var answer: Dictionary = await DailyBoard.request(tree, url, msg, TIMEOUT_MS)
	return answer


## A replay file packed for a report, empty when there is none or it is too big.
static func pack_replay(path: String) -> PackedByteArray:
	if path == "" or not FileAccess.file_exists(path):
		return PackedByteArray()
	var packed := FileAccess.get_file_as_bytes(path).compress(FileAccess.COMPRESSION_GZIP)
	return packed if packed.size() <= REPLAY_MAX else PackedByteArray()
