extends PanelContainer
## The window «Сообщить об ошибке»: a field for the text, a replay to send with it, «Отправить», a short
## line about the result.
## The report goes to the room server (scripts/net/bug_report.gd) and from there to the developer.
##   BugReportDialog.open(self)                       # over everything, closes itself
##   BugReportDialog.open(self, version, mode, nick)  # what the report says about the game

const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const FitCenter = preload("res://scripts/ui/fit_center.gd")
const BugReport = preload("res://scripts/net/bug_report.gd")
const NetScript = preload("res://scripts/net/net.gd")
const Replay = preload("res://scripts/core/replay.gd")
const FileDialogs = preload("res://scripts/ui/file_dialogs.gd")
const LIST_MAX := 6              # the latest games offered under «Выбрать»

var version := ""
var mode := ""
var nick := ""
var _layer: CanvasLayer
var _text: TextEdit
var _status: Label
var _send: Button
var _busy := false
var _replay := ""                # the attached replay file, "" none
var _replay_label: Label
var _drop: Button
var _list: VBoxContainer


## Opens the window over `parent`; the optional lines go into the report.
static func open(parent: Node, p_version := "", p_mode := "", p_nick := "") -> void:
	BugReport.install()
	var layer := CanvasLayer.new()
	layer.layer = 100
	parent.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := FitCenter.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var dialog := new()
	dialog.version = p_version
	dialog.mode = p_mode
	dialog.nick = p_nick
	dialog._layer = layer
	center.add_child(dialog)


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
	var title := WoodUI.title_tag("Сообщить об ошибке", 36)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(title)
	_text = TextEdit.new()
	_text.placeholder_text = "Что пошло не так"
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.custom_minimum_size = Vector2(760, 260) * WoodUI.font_scale
	WoodUI.edit(_text, 28)
	_text.text_changed.connect(_on_text)
	v.add_child(_text)
	_replay_row(v)
	_status = WoodUI.label("", 28, UI.CREAM, 7)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(0, 40)
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	_send = WoodUI.button("Отправить", UI.ORANGE, 32, Vector2(250, 68))
	_send.disabled = true
	_send.pressed.connect(_submit)
	row.add_child(_send)
	var back := WoodUI.button("Закрыть", UI.PURPLE, 32, Vector2(250, 68))
	back.pressed.connect(func(): _layer.queue_free())
	row.add_child(back)
	_text.grab_focus.call_deferred()


## «Реплей: …» with «Выбрать» and «Убрать»; the last game is there from the start. «Выбрать» opens
## the latest games and «Открыть файл» under it.
func _replay_row(v: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	_replay_label = WoodUI.label("", 24, UI.CREAM, 6, UI.UI_FONT)
	_replay_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_replay_label.custom_minimum_size = Vector2(1, 0)
	row.add_child(_replay_label)
	var pick := WoodUI.button("Выбрать", UI.BLUE, 24, Vector2(170, 54))
	pick.pressed.connect(func(): _list.visible = not _list.visible)
	row.add_child(pick)
	_drop = WoodUI.button("Убрать", UI.RED, 24, Vector2(150, 54))
	_drop.pressed.connect(func(): _attach(""))
	row.add_child(_drop)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.visible = false
	v.add_child(_list)
	var files := replay_files()
	for path: String in files.slice(0, LIST_MAX):
		var b := WoodUI.button(replay_title(path), UI.PURPLE, 22, Vector2(0, 50))
		b.clip_text = true
		b.pressed.connect(func(): _attach(path))
		_list.add_child(b)
	var from_file := WoodUI.button("Открыть файл", UI.BLUE, 22, Vector2(260, 50))
	from_file.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	from_file.pressed.connect(func():
		FileDialogs.open_file(self, "Реплей", ["*.%s ; Реплей" % Replay.EXT], _attach))
	_list.add_child(from_file)
	_attach(files[0] if not files.is_empty() else "")


func _attach(path: String) -> void:
	_replay = path
	_list.visible = false
	_drop.visible = path != ""
	if path == "":
		_replay_label.text = "Реплей: нет"
	elif BugReport.pack_replay(path).is_empty():
		_replay = ""
		_drop.visible = false
		_replay_label.text = "Реплей слишком большой"
	else:
		_replay_label.text = "Реплей: " + replay_title(path)


## The game's own replays, newest first (of any rules: an old one is still worth sending).
static func replay_files() -> Array:
	var out := []
	for file in DirAccess.get_files_at(Replay.DIR):
		if file.get_extension() == Replay.EXT:
			out.append(Replay.DIR.path_join(file))
	out.sort()
	out.reverse()
	return out


## "Призмо против Волшебника · 04.11 15:20 · поражение", the file's name when it is not a replay.
static func replay_title(path: String) -> String:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not (d.get("names") is Array) or d["names"].size() < 2:
		return path.get_file().get_basename()
	var date := str(d.get("date", ""))
	if date.length() >= 16:
		date = "%s.%s %s" % [date.substr(8, 2), date.substr(5, 2), date.substr(11, 5)]
	return "%s · %s · %s" % [Replay.title(d), date, Replay.result(d)]


func _on_text() -> void:
	if _text.text.length() > BugReport.TEXT_MAX:
		var line := _text.get_caret_line()
		var col := _text.get_caret_column()
		_text.text = _text.text.substr(0, BugReport.TEXT_MAX)
		_text.set_caret_line(line)
		_text.set_caret_column(col)
	_status.text = ""
	_send.disabled = _busy or _text.text.strip_edges().length() < 2


func _submit() -> void:
	if _busy:
		return
	_busy = true
	_send.disabled = true
	_status.text = "Отправка"
	var net := get_node_or_null("/root/Net")
	var url: String = net.relay_url if net != null else NetScript.RELAY_URL
	var answer: Dictionary = await BugReport.send(get_tree(), url, _text.text, version, mode, nick, _replay)
	if not is_instance_valid(self):
		return
	_busy = false
	if answer["ok"]:
		_text.text = ""
		_status.text = "Отправлено"
	else:
		_status.text = "Не отправлено"
		_send.disabled = _text.text.strip_edges().length() < 2
