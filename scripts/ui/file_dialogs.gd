extends RefCounted
## The system's own Save and Open windows for deck and replay files (Godot's own
## dialog on Linux and where the system has none). The folder used last is remembered.

const SETTINGS_PATH := "user://settings.cfg"


## Asks where to save a file named `file_name` (the extension `ext` is added)
## and calls on_done(path) once the player has chosen.
static func save_file(parent: Node, title: String, file_name: String, ext: String, kind: String, on_done: Callable) -> void:
	var d := _dialog(parent, title, FileDialog.FILE_MODE_SAVE_FILE, ["*.%s ; %s" % [ext, kind]])
	d.current_file = "%s.%s" % [file_name.validate_filename(), ext]
	d.file_selected.connect(func(path: String):
		if path.get_extension().to_lower() != ext:
			path += "." + ext
		on_done.call(path))
	d.popup_centered_ratio(0.6)


## Asks for a file to open; filters like "*.cwdeck ; Колода".
static func open_file(parent: Node, title: String, filters: Array, on_done: Callable) -> void:
	var d := _dialog(parent, title, FileDialog.FILE_MODE_OPEN_FILE, filters)
	d.file_selected.connect(func(path: String): on_done.call(path))
	d.popup_centered_ratio(0.6)


## Russian words for Godot's own dialog, which only knows English.
const WORDS := {
	"Path:": "Папка:", "Directories & Files:": "Папки и файлы:", "File:": "Файл:",
	"Open": "Открыть", "Save": "Сохранить", "Cancel": "Отмена", "Select Current Folder": "Выбрать папку",
	"All Files": "Все файлы", "All Recognized": "Все подходящие", "Create Folder": "Новая папка",
	"Go to parent folder.": "Наверх", "Refresh files.": "Обновить", "Name:": "Имя:",
	"Create a new folder?": "Создать папку?", "Could not create folder.": "Не удалось создать папку.",
	"File \"%s\" already exists.\nDo you want to overwrite it?": "Файл «%s» уже есть.\nЗаменить его?",
	"Overwrite": "Заменить", "Network": "Сеть",
}


static func _add_words() -> void:
	var locale := TranslationServer.get_locale()
	if TranslationServer.get_translation_object(locale) != null:
		return
	var t := Translation.new()
	t.locale = locale
	for k: String in WORDS:
		t.add_message(k, WORDS[k])
	TranslationServer.add_translation(t)


static func _dialog(parent: Node, title: String, mode: FileDialog.FileMode, filters: Array) -> FileDialog:
	var d := FileDialog.new()
	d.file_mode = mode
	d.mode_overrides_title = false
	d.title = title
	if OS.get_name() == "Linux":
		_add_words()
		for k in ["favorites_enabled", "recent_list_enabled", "layout_toggle_enabled", "file_sort_options_enabled"]:
			d.set(k, false)
	d.access = FileDialog.ACCESS_FILESYSTEM
	# Linux's window comes from the desktop portal, and where the desktop has no
	# working one (tiling window managers, missing portal packages) nothing opens.
	d.use_native_dialog = OS.get_name() != "Linux"
	# Android's picker filters by file type, and it knows no type for ours: it would hide them.
	if OS.get_name() != "Android":
		d.filters = PackedStringArray(filters)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var dir := str(cfg.get_value("files", "dir", ""))
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if not DirAccess.dir_exists_absolute(dir):
		dir = OS.get_environment("HOME")
	d.current_dir = dir
	d.file_selected.connect(func(path: String):
		var now := ConfigFile.new()
		now.load(SETTINGS_PATH)
		now.set_value("files", "dir", path.get_base_dir())
		now.save(SETTINGS_PATH)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	parent.add_child(d)
	return d
