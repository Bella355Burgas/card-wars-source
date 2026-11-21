extends PanelContainer
## The window to log in or to make an account on the room server: two tabs, «Вход» and
## «Регистрация», a nick, a password (hidden) and, for a registration, the password again.
## The answer of the server is a short line under the fields. main.gd opens it (show_login) and
## closes it on `done` (logged in, the account is in `account`) or `closed`.

const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const Account = preload("res://scripts/net/account.gd")

signal done
signal closed

var account: Account
var _register := false
var _nick: LineEdit
var _pass: LineEdit
var _again: LineEdit
var _error: Label
var _go: Button
var _tab_in: Button
var _tab_new: Button
var _busy := false


func setup(p_account: Account, as_register := false) -> void:
	account = p_account
	_register = as_register


func _ready() -> void:
	var sb := WoodUI.window()
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	add_child(v)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 14)
	v.add_child(tabs)
	_tab_in = WoodUI.tab("Вход", 30, Vector2(250, 64))
	_tab_in.pressed.connect(func(): _set_mode(false))
	tabs.add_child(_tab_in)
	_tab_new = WoodUI.tab("Регистрация", 30, Vector2(250, 64))
	_tab_new.pressed.connect(func(): _set_mode(true))
	tabs.add_child(_tab_new)
	_nick = _edit("Ник", false)
	v.add_child(_nick)
	_pass = _edit("Пароль", true)
	v.add_child(_pass)
	_again = _edit("Пароль ещё раз", true)
	v.add_child(_again)
	_error = WoodUI.label("", 28, Color(1.0, 0.45, 0.4), 7)
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.custom_minimum_size = Vector2(0, 40)
	v.add_child(_error)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	_go = WoodUI.button("Войти", UI.ORANGE, 32, Vector2(250, 68))
	_go.pressed.connect(_submit)
	row.add_child(_go)
	var back := WoodUI.button("Назад", UI.PURPLE, 32, Vector2(250, 68))
	back.pressed.connect(func(): closed.emit())
	row.add_child(back)
	_nick.text_submitted.connect(func(_t): _pass.grab_focus())
	_pass.text_submitted.connect(func(_t): _again.grab_focus() if _register else _submit())
	_again.text_submitted.connect(func(_t): _submit())
	_set_mode(_register)
	_nick.grab_focus.call_deferred()


func _edit(placeholder: String, secret: bool) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.max_length = Account.PASS_MAX if secret else Account.NICK_MAX
	edit.custom_minimum_size = Vector2(520, 62) * WoodUI.font_scale
	WoodUI.edit(edit, 30)
	edit.text_changed.connect(func(_t): _error.text = "")
	return edit


func _set_mode(register: bool) -> void:
	_register = register
	_again.visible = register
	_go.text = "Создать" if register else "Войти"
	_error.text = ""
	WoodUI.set_tab(_tab_in, not register)
	WoodUI.set_tab(_tab_new, register)


func _submit() -> void:
	if _busy:
		return
	var nick := _nick.text.strip_edges()
	var why := ""
	if _register:
		why = Account.nick_error(nick)
		if why == "":
			why = Account.pass_error(_pass.text)
		if why == "" and _pass.text != _again.text:
			_error.text = "Пароли не совпадают"
			return
	elif nick == "" or _pass.text == "":
		_error.text = "Введи ник и пароль"
		return
	if why != "":
		_error.text = Account.reason(why)
		return
	_busy = true
	_go.disabled = true
	_error.text = "Подождите"
	var answer: Dictionary
	if _register:
		answer = await account.register(get_tree(), nick, _pass.text)
	else:
		answer = await account.login(get_tree(), nick, _pass.text)
	if not is_instance_valid(self):
		return
	_busy = false
	_go.disabled = false
	if answer["ok"]:
		_pass.text = ""
		_again.text = ""
		done.emit()
	else:
		_error.text = Account.reason(String(answer["r"]))
