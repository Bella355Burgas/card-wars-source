extends Control
## The table of the «Поезд дня» over the game: the best trains of today, the place of the
## player marked. The table comes from the room server (scripts/net/daily_board.gd); when it
## is away the screen says so in a line and the game goes on. main.gd opens it (show_daily_board),
## `before_load` is a coroutine it gives to send a result that was left unsent first. A guest sees
## the table too, with a button to log in (only an account has a place in it).

const UI = preload("res://scripts/ui/ui_kit.gd")
const WoodUI = preload("res://scripts/ui/wood_ui.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const DailyBoard = preload("res://scripts/net/daily_board.gd")
const Account = preload("res://scripts/net/account.gd")
const Avatar = preload("res://scripts/net/avatar.gd")
const AvatarView = preload("res://scripts/ui/avatar_view.gd")
const NickStyle = preload("res://scripts/ui/nick_style.gd")
const TrainRun = preload("res://scripts/train/train_run.gd")
const GOLD := Color(1.0, 0.86, 0.35)
const ROWS_SHOWN := 14
# Why there is no table, as a short line.
const REASONS := {"offline": "Нет связи с сервером", "timeout": "Сервер не отвечает", "old": "Сервер без таблицы",
	"date": "День уже закончился", "bad": "Сервер не принял"}

signal closed
signal login_requested

var url := ""
var date := ""
var account: Account
var before_load: Callable = Callable()       # a coroutine, runs before the table is asked for
var _list: VBoxContainer
var _status: Label
var _busy := false


func setup(p_url: String, p_date: String, p_account: Account, p_before := Callable()) -> void:
	url = p_url
	date = p_date
	account = p_account
	before_load = p_before


func _ready() -> void:
	custom_minimum_size = Vector2(1200, 1000)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	var title := WoodUI.label("Поезд дня · %s" % date_text(date), 56, GOLD, 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var hero: String = CardDB.hero(TrainRun.daily_deck(date))["name"]
	var sub := WoodUI.label("Герой дня: %s" % hero, 30, UI.CREAM, 7)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_status = WoodUI.label("Загрузка", 30, UI.CREAM, 7)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	head.custom_minimum_size = Vector2(1180, 0)
	for col in [["", 60, HORIZONTAL_ALIGNMENT_LEFT], ["", 64, HORIZONTAL_ALIGNMENT_LEFT], ["Ник", 480, HORIZONTAL_ALIGNMENT_LEFT],
			["Вагонов", 120, HORIZONTAL_ALIGNMENT_RIGHT], ["Герой", 300, HORIZONTAL_ALIGNMENT_RIGHT]]:
		var l := WoodUI.label(col[0], 24, Color(1, 1, 1, 0.55), 5)
		l.custom_minimum_size = Vector2(col[1], 0)
		l.horizontal_alignment = col[2]
		head.add_child(l)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_child(head)
	v.add_child(pad)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1200, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.custom_minimum_size = Vector2(1180, 0)
	scroll.add_child(_list)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	v.add_child(buttons)
	var again := WoodUI.button("Обновить", UI.GREEN, 28, Vector2(240, 62))
	again.pressed.connect(load_table)
	buttons.add_child(again)
	if not account.logged_in():
		var enter := WoodUI.button("Войти", UI.BLUE, 28, Vector2(240, 62))
		enter.pressed.connect(func(): login_requested.emit())
		buttons.add_child(enter)
	var close := WoodUI.button("Закрыть", UI.PURPLE, 28, Vector2(240, 62))
	close.pressed.connect(func(): closed.emit())
	buttons.add_child(close)
	load_table()


## "16.10.2026" from "2026-10-16".
static func date_text(d: String) -> String:
	var parts := d.split("-")
	return "%s.%s.%s" % [parts[2], parts[1], parts[0]] if parts.size() == 3 else d


## Asks for the table and shows it (or why there is none).
func load_table() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Загрузка"
	if before_load.is_valid():
		await before_load.call()
	var answer: Dictionary = await DailyBoard.top(get_tree(), url, date, account.token)
	_busy = false
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not answer["ok"]:
		for ch in _list.get_children():
			ch.queue_free()
		_status.text = REASONS.get(answer["r"], "Нет таблицы")
		return
	_show(answer)
	# The avatars that are not on this PC come after the table, which is drawn again with them.
	var before := _cached_count(answer["rows"])
	await Avatar.fetch(get_tree(), url, answer["rows"])
	if is_instance_valid(self) and is_inside_tree() and _cached_count(answer["rows"]) > before:
		_show(answer)


func _cached_count(rows: Array) -> int:
	var n := 0
	for r: Dictionary in rows:
		if Avatar.cached(String(r["nick"]), String(r.get("av", ""))) != null:
			n += 1
	return n


func _show(answer: Dictionary) -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var total := int(answer["total"])
	_status.text = "Играли: %d" % total if total > 0 else "Пока никто не доехал"
	var rows: Array = answer["rows"]
	for i in mini(rows.size(), ROWS_SHOWN * 2):
		_list.add_child(_row(i + 1, rows[i], account.logged_in() and String(rows[i]["nick"]).to_lower() == account.nick.to_lower()))
	var me := int(answer.get("me", 0))
	if me > rows.size():
		_status.text += " · твоё место %d" % me
	if not account.logged_in():
		_status.text += " · войди, чтобы попасть в таблицу"


## One line of the table: the place, the nick, the wagons passed, the hero.
func _row(place: int, row: Dictionary, mine: bool) -> Control:
	var panel := PanelContainer.new()
	var sb := WoodUI.inset(place, 18, 4)
	if mine:
		sb.fill = WoodUI.ORANGE.darkened(0.35)
		sb.line_width = 4.0
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	panel.add_child(h)
	var color := GOLD if place <= 3 or mine else Color.WHITE
	var no := WoodUI.label(str(place), 32, color, 7)
	no.custom_minimum_size = Vector2(60, 0)
	h.add_child(no)
	var nick := String(row["nick"])
	var face := AvatarView.make(nick, Avatar.cached(nick, String(row.get("av", ""))), 52, color)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(face)
	var name_l := WoodUI.label(nick, 32, color, 7)
	NickStyle.apply(name_l, bool(row.get("rb", false)), String(row.get("col", "")))
	var tag := NickStyle.tag(String(row.get("tag", "")), 20)
	if tag == null:
		name_l.custom_minimum_size = Vector2(480, 0)
		name_l.clip_text = true
		h.add_child(name_l)
	else:
		var who := HBoxContainer.new()
		who.add_theme_constant_override("separation", 14)
		who.custom_minimum_size = Vector2(480, 0)
		name_l.clip_text = true
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.add_child(name_l)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who.add_child(tag)
		h.add_child(who)
	var wagons := WoodUI.label("%d" % int(row["score"]), 32, color, 7)
	wagons.custom_minimum_size = Vector2(120, 0)
	wagons.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(wagons)
	var hero_id := String(row["hero"])
	var hero_name := String(CardDB.hero(hero_id)["name"]) if CardDB.has_hero(hero_id) else hero_id
	var hero_l := WoodUI.label(hero_name, 26, UI.CREAM, 6)
	hero_l.custom_minimum_size = Vector2(300, 0)
	hero_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(hero_l)
	return panel
