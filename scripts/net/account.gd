extends RefCounted
## The account of the player on the room server (server/relay/account_store.gd): a nick, a
## password, an avatar. Without an account everything but the table of the «Бесконечный поезд»
## works as before; the results of the train of the day go to the table only from an account.
## After a registration or a login the server gives a token; it is kept in user://account.cfg
## (not in settings.cfg) and logs the player in at the next start, so the password is typed once.
## The game never waits on the server: every call is a coroutine with a time limit, a server that
## is away leaves the player logged in with the token kept (only a server that says the token is
## no good takes it away).
##   var account := Account.new(); account.setup(url)      # loads the saved login
##   await account.verify(tree)                            # asks if the token still holds
##   var answer: Dictionary = await account.login(tree, nick, password)    # "ok", "r"
## "r" of a failed answer: "offline" | "timeout" | "old" (a server without accounts) | the server's
## ("nick_len", "nick_chars", "pass_len", "nick_taken", "wrong", "locked", "rate", "full", "token", "big", "bad").

const DailyBoard = preload("res://scripts/net/daily_board.gd")
const Avatar = preload("res://scripts/net/avatar.gd")
const PATH := "user://account.cfg"
const TIMEOUT_MS := 15000          # a password takes the server a moment to hash
const NICK_MIN := 3
const NICK_MAX := 16
const PASS_MIN := 6
const PASS_MAX := 64
## Why a request failed, as a short line for the player.
const REASONS := {"offline": "Нет связи", "timeout": "Нет связи", "old": "Сервер без аккаунтов",
	"nick_len": "Ник от 3 до 16 знаков", "nick_chars": "В нике буквы, цифры, _ и -", "pass_len": "Пароль от 6 знаков",
	"nick_taken": "Ник занят", "wrong": "Неверный ник или пароль", "locked": "Слишком много попыток",
	"rate": "Подождите и повторите", "full": "Сервер полон", "token": "Нужно войти снова",
	"big": "Картинка слишком большая", "bad": "Сервер не принял"}

signal changed

var url := ""
var path := PATH        # where the login is kept (tests use another file)
var nick := ""          # "" = a guest
var token := ""
var av := ""            # the mark of the avatar on the server, "" = none
var tag := ""           # the tag under the nick, set on the server by hand ("" = none)
var rainbow := false    # the nick shimmers, set on the server by hand
var color := ""         # the colour of the nick ("541687", "" = the usual one), set on the server


## A nick of the right length and letters: "" when it is good, else the reason ("nick_len", "nick_chars").
static func nick_error(text: String) -> String:
	if text.length() < NICK_MIN or text.length() > NICK_MAX:
		return "nick_len"
	for i in text.length():
		var c := text.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or c == 45
				or (c >= 0x410 and c <= 0x44F) or c == 0x401 or c == 0x451):
			return "nick_chars"
	return ""


static func pass_error(text: String) -> String:
	return "" if text.length() >= PASS_MIN and text.length() <= PASS_MAX else "pass_len"


static func reason(r: String) -> String:
	return REASONS.get(r, "Не получилось")


func setup(p_url: String) -> void:
	url = p_url
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		token = str(cfg.get_value("account", "token", ""))
		nick = str(cfg.get_value("account", "nick", ""))
		av = str(cfg.get_value("account", "av", ""))
		tag = str(cfg.get_value("account", "tag", ""))
		rainbow = bool(cfg.get_value("account", "rb", false))
		color = str(cfg.get_value("account", "col", ""))
	if token == "" or nick == "":
		_forget()


func logged_in() -> bool:
	return token != ""


## The picture of the avatar, null when there is none (or it is not on this PC yet).
func texture() -> Texture2D:
	return Avatar.cached(nick, av)


## Asks the server if the token holds, takes the nick and the avatar from it. A server that
## cannot be reached changes nothing.
func verify(tree: SceneTree) -> void:
	if token == "":
		return
	var answer: Dictionary = await DailyBoard.request(tree, url, {"op": "acc_token", "token": token}, TIMEOUT_MS)
	if answer["ok"]:
		_take(answer, token)
		await _pull_avatar(tree)
	elif answer["r"] == "token":
		_forget()
		_save()
		changed.emit()


func register(tree: SceneTree, p_nick: String, password: String) -> Dictionary:
	return await _enter(tree, {"op": "acc_register", "nick": p_nick, "pass": password})


func login(tree: SceneTree, p_nick: String, password: String) -> Dictionary:
	return await _enter(tree, {"op": "acc_login", "nick": p_nick, "pass": password})


func _enter(tree: SceneTree, msg: Dictionary) -> Dictionary:
	var answer: Dictionary = await DailyBoard.request(tree, url, msg, TIMEOUT_MS)
	if answer["ok"]:
		_take(answer, String(answer.get("token", "")))
		await _pull_avatar(tree)
	return answer


## Logs out: the token is revoked on the server (when it can be reached) and forgotten here.
func logout(tree: SceneTree) -> void:
	var old := token
	_forget()
	_save()
	changed.emit()
	if old != "":
		await DailyBoard.request(tree, url, {"op": "acc_logout", "token": old}, 5000)


## A new avatar (the bytes of Avatar.encode); the answer of the server.
func set_avatar(tree: SceneTree, bytes: PackedByteArray) -> Dictionary:
	var answer: Dictionary = await DailyBoard.request(tree, url, {"op": "acc_avatar_set", "token": token, "data": bytes}, TIMEOUT_MS)
	if answer["ok"]:
		av = String(answer["av"])
		Avatar.store(nick, av, bytes)
		_save()
		changed.emit()
	elif answer["r"] == "token":
		_forget()
		_save()
		changed.emit()
	return answer


func _take(answer: Dictionary, new_token: String) -> void:
	nick = String(answer["nick"])
	av = String(answer.get("av", ""))
	tag = String(answer.get("tag", ""))
	rainbow = bool(answer.get("rb", false))
	color = String(answer.get("col", ""))
	token = new_token
	_save()
	changed.emit()


## An admin changed how our nick looks (relay «s_style»): it shows at once.
func restyle(d: Dictionary) -> void:
	tag = String(d.get("tag", ""))
	rainbow = d.get("rb") == true
	color = String(d.get("col", ""))
	_save()
	changed.emit()


## The avatar of the account is fetched when this PC does not have it (a new device).
func _pull_avatar(tree: SceneTree) -> void:
	if av != "" and Avatar.cached(nick, av) == null:
		await Avatar.fetch(tree, url, [{"nick": nick, "av": av}])
		changed.emit()


func _forget() -> void:
	token = ""
	nick = ""
	av = ""
	tag = ""
	rainbow = false
	color = ""


func _save() -> void:
	var cfg := ConfigFile.new()
	if token != "":
		cfg.set_value("account", "token", token)
		cfg.set_value("account", "nick", nick)
		cfg.set_value("account", "av", av)
		cfg.set_value("account", "tag", tag)
		cfg.set_value("account", "rb", rainbow)
		cfg.set_value("account", "col", color)
	cfg.save(path)
