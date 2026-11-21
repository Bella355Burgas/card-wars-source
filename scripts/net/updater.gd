extends Node
## Game updates, the same on every system (tools/publish.ps1 publishes them).
## The game asks for a small signed manifest, update_<system>.json and update_<system>.sig:
## first on GitHub (the release "manifest" of the updates repo), and only when GitHub can't be
## reached on the home server. It names the newest build: the app (with its build) and the
## update of the game over that app: "full", the whole newer game, when there is one, and
## "patch", the files changed since the app's game or since the full one. Every file lists its
## addresses on GitHub, tried before the home server. The manifest must be signed with the
## publisher's key (update_key.gd) and every file is checked by its SHA-256, so nobody but the
## publisher can hand out an update, whoever serves the bytes.
##
## When our app is the manifest's, only the game is updated, however big the change: the files
## that differ from ours come into user://update (scripts/patch_loader.gd loads them), its
## state.json is rewritten and the game restarts. A new app is needed only for a new Godot, new
## project settings or a new UI font. On Windows and Linux, in a folder the game can write, it
## replaces itself (a running exe or binary can be renamed); on Android, macOS and iOS, and when
## that fails, the browser downloads it to be installed by hand. iOS doesn't let an app start
## itself again: there the player closes the game and opens it.
## Games before 0.3.0 read other manifests (manifest*.json), which name the newest app.
##
## The server is asked once per start of the game. Leftovers go at the next start.

const PatchLoader = preload("res://scripts/patch_loader.gd")
const UpdateKey = preload("res://scripts/net/update_key.gd")

signal update_available(info: Dictionary)      # {"build", "version", "size", "app"}

const GITHUB_URL := "https://github.com/kiberbus/card-wars-updates/releases/download/manifest"
const SERVER_URL := "https://home-server.tail8c9fef.ts.net/updates"
const SETTINGS_PATH := "user://settings.cfg"
const SYSTEMS := {"Windows": "windows", "Android": "android", "macOS": "macos", "Linux": "linux", "iOS": "ios"}
const STALL_SEC := 60.0

var build := 0                   # this game's build (set before adding the node)
var server := SERVER_URL         # the last resort, for the manifest and every file
var sources: Array[String] = [GITHUB_URL, SERVER_URL]
var auto_accept := false         # --update-yes: no question asked (tests)
var manifest := {}


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var own := str(cfg.get_value("update", "url", ""))
	var args := OS.get_cmdline_user_args()
	var at := args.find("--update-url")
	if at >= 0 and at + 1 < args.size():
		own = args[at + 1]
	auto_accept = args.has("--update-yes")
	if own != "":
		# A test server: only it.
		server = own.trim_suffix("/")
		sources = [server]
	if can_update():
		print("update: this is build %d, app %d" % [build, PatchLoader.app_build])
		_drop_leftovers()


## Only the exported game updates itself (in the editor the "exe" is Godot).
func can_update() -> bool:
	return SYSTEMS.has(OS.get_name()) and OS.has_feature("template")


## Files of earlier updates nothing uses now.
func _drop_leftovers() -> void:
	var state := PatchLoader.read_state()
	var keep := []
	if int(state.get("app", -1)) == PatchLoader.app_build:
		keep.append("state.json")
		for part in ["full", "patch"]:
			keep.append(str(state.get(part, {}).get("file", "")))
	if DirAccess.dir_exists_absolute(PatchLoader.DIR):
		for f in DirAccess.get_files_at(PatchLoader.DIR):
			if not f in keep:
				DirAccess.remove_absolute(PatchLoader.DIR.path_join(f))
	# The app replaced last time; the patches and packs of the versions before 0.3.0.
	var exe := OS.get_executable_path()
	var old := [exe + ".old", exe + ".new"]
	if OS.get_name() in ["Windows", "Linux"]:
		old.append_array([exe.get_basename() + ".patch.pck", exe.get_basename() + ".patch.pck.new"])
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("CardWars.b") and (f.ends_with(".patch.pck") or f.ends_with(".new")):
			old.append("user://" + f)
	for path in old:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Why the game could not replace its exe where it lies: "zip" when it runs straight out of an archive
## (Windows and archivers unpack such an exe into the temp folder), "locked" when the folder takes no
## files, such as Program Files; "" when it can. The game itself updates in user:// anyway.
func folder_problem() -> String:
	if not can_update() or OS.get_name() != "Windows":
		return ""
	var dir := OS.get_executable_path().get_base_dir()
	if dir.replace("\\", "/").to_lower().contains("/appdata/local/temp/"):
		return "zip"
	return "" if _writable(dir) else "locked"


func _writable(dir: String) -> bool:
	var probe := dir.path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


## Asks for the newest build; update_available when it is newer than ours.
func check() -> void:
	if not can_update():
		return
	var m := {}
	var file: String = "update_" + SYSTEMS[OS.get_name()]
	for source: String in sources:
		var body := await _fetch(source + "/%s.json" % file, source != GITHUB_URL)
		var sig := await _fetch(source + "/%s.sig" % file, source != GITHUB_URL)
		if body.is_empty() or sig.is_empty():
			continue
		m = _verified(body, sig.get_string_from_utf8())
		if m.is_empty():
			push_warning("update: the manifest at %s is not signed by the publisher" % source)
		else:
			break
	if m.is_empty() or int(m["build"]) <= build:
		return
	manifest = m
	var size := 0
	for f: Dictionary in _todo():
		size += int(f["size"])
	print("update: build %d is out (this is %d), %d bytes" % [int(m["build"]), build, size])
	update_available.emit({"build": int(m["build"]), "version": str(m.get("version", "")), "size": size,
		"app": needs_app()})


## The newer version needs a new app.
func needs_app() -> bool:
	return not manifest.is_empty() and int(manifest["app"]["build"]) != PatchLoader.app_build


## The new app's address, for the browser, when the game can't replace its app itself ("" when it can
## or no new app is needed).
func app_link() -> String:
	if not needs_app() or _replaces_app():
		return ""
	var app: Dictionary = manifest["app"]
	if str(app.get("link", "")) != "":
		return str(app["link"])
	var urls: Array = app.get("urls", [])
	return str(urls[0]) if not urls.is_empty() else server + "/" + str(app["name"]).uri_encode()


## Windows and Linux replace their app in place, when the folder takes files.
func _replaces_app() -> bool:
	return OS.get_name() in ["Windows", "Linux"] and _writable(OS.get_executable_path().get_base_dir())


## The manifest's files we don't have yet.
func _todo() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if needs_app():
		if _replaces_app():
			out.append(manifest["app"])
		return out
	var state := PatchLoader.read_state()
	var mine: bool = int(state.get("app", -1)) == PatchLoader.app_build
	for part in ["full", "patch"]:
		var f: Dictionary = manifest.get(part, {})
		if not f.is_empty() and not (mine and str(state.get(part, {}).get("sha256", "")) == str(f["sha256"])):
			out.append(f)
	return out


## Downloads what the newer version needs and checks it.
## on_progress(done_bytes, total_bytes). Returns "" when ready to restart, else what went wrong.
func download(on_progress: Callable) -> String:
	if needs_app():
		if not _replaces_app():
			return "нужна новая версия приложения"
		return await _fetch_file(manifest["app"], OS.get_executable_path() + ".new", 0, int(manifest["app"]["size"]), on_progress)
	DirAccess.make_dir_recursive_absolute(PatchLoader.DIR)
	var todo := _todo()
	var total := 0
	for f in todo:
		total += int(f["size"])
	var done := 0
	for f in todo:
		var dest := PatchLoader.DIR.path_join(_file_name(f))
		var err := await _fetch_file(f, dest + ".new", done, total, on_progress)
		if err != "":
			return err
		DirAccess.remove_absolute(dest)
		if DirAccess.rename_absolute(dest + ".new", dest) != OK:
			return "не удалось сохранить обновление"
		done += int(f["size"])
	# The game the next start loads: the manifest's full game and patch over our app.
	var state := {"app": PatchLoader.app_build}
	for part in ["full", "patch"]:
		var f: Dictionary = manifest.get(part, {})
		if not f.is_empty():
			state[part] = {"build": int(f["build"]), "file": _file_name(f), "sha256": str(f["sha256"])}
	var tmp := PatchLoader.STATE + ".new"
	var sf := FileAccess.open(tmp, FileAccess.WRITE)
	if sf == null:
		return "не удалось сохранить обновление"
	sf.store_string(JSON.stringify(state, "\t"))
	sf.close()
	DirAccess.remove_absolute(PatchLoader.STATE)
	if DirAccess.rename_absolute(tmp, PatchLoader.STATE) != OK:
		return "не удалось сохранить обновление"
	return ""


## The name a downloaded file gets in user://update: a new one for other bytes, so it never is the
## file the running game has open.
static func _file_name(f: Dictionary) -> String:
	return str(f["sha256"]).left(12) + "-" + str(f["name"])


## One file into dest, from its addresses, then the home server; checked by its SHA-256.
func _fetch_file(f: Dictionary, dest: String, done: int, total: int, on_progress: Callable) -> String:
	var err := "не удалось начать загрузку"
	for u: String in _sources(f):
		err = await _download(u, dest, done, total, on_progress)
		if err == "" and FileAccess.get_sha256(dest) != str(f["sha256"]):
			err = "файл скачался с ошибкой"
		if err == "":
			return ""
		print("update: %s: %s" % [u, err])
		DirAccess.remove_absolute(dest)
	return err


## Where to get a file: its listed addresses, then the home server.
func _sources(f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for u in f.get("urls", []):
		if _url_ok(str(u)):
			out.append(str(u))
	out.append(server + "/" + str(f["name"]).uri_encode())
	return out


## Addresses in the manifest: https, or the same scheme as the server we were pointed at.
func _url_ok(u: String) -> bool:
	return u.begins_with("https://") or u.begins_with(server.get_slice("://", 0) + "://")


## The game can start itself again after an update (not on iOS).
func can_restart() -> bool:
	return OS.get_name() != "iOS"


## Puts a downloaded app in place and starts the game again. Returns what went wrong ("" when quitting).
func restart() -> String:
	var exe := OS.get_executable_path()
	if needs_app():
		DirAccess.remove_absolute(exe + ".old")
		if DirAccess.rename_absolute(exe, exe + ".old") != OK:
			return "не удалось заменить приложение"
		if DirAccess.rename_absolute(exe + ".new", exe) != OK:
			DirAccess.rename_absolute(exe + ".old", exe)
			return "не удалось заменить приложение"
		if OS.get_name() == "Linux":
			FileAccess.set_unix_permissions(exe, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER |
				FileAccess.UNIX_EXECUTE_OWNER | FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_EXECUTE_GROUP |
				FileAccess.UNIX_READ_OTHER | FileAccess.UNIX_EXECUTE_OTHER)
	print("update: restarting into build %d" % int(manifest["build"]))
	var args := PackedStringArray()
	if OS.get_name() != "Android":
		# The test switches survive the restart.
		if DisplayServer.get_name() == "headless":
			args.append("--headless")
		if not OS.get_cmdline_user_args().is_empty():
			args.append("--")
			args.append_array(OS.get_cmdline_user_args())
	if needs_app():
		# Started by its name: the system now takes the renamed old app for this one's executable.
		if OS.create_process(exe, args) <= 0:
			return "не удалось запустить новую версию"
	else:
		OS.set_restart_on_exit(true, args)
	get_tree().quit()
	return ""


## The manifest when its signature is the publisher's, else {}.
func _verified(body: PackedByteArray, sig_text: String) -> Dictionary:
	if not _signed(body, sig_text):
		return {}
	var m = JSON.parse_string(body.get_string_from_utf8())
	if not (m is Dictionary) or not (m.get("build") is float) or not _entry_ok(m.get("app")):
		return {}
	for part in ["full", "patch"]:
		if m.has(part) and not _entry_ok(m[part]):
			return {}
	return m


func _signed(body: PackedByteArray, sig_text: String) -> bool:
	var key := CryptoKey.new()
	if key.load_from_string(UpdateKey.PUBLIC_KEY, true) != OK:
		return false
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	var sig := Marshalls.base64_to_raw(sig_text.strip_edges())
	return not sig.is_empty() and Crypto.new().verify(HashingContext.HASH_SHA256, ctx.finish(), sig, key)


static func _entry_ok(f) -> bool:
	return f is Dictionary and f.get("urls", []) is Array and f.get("size") is float and f.get("build") is float \
		and str(f.get("name", "")) != "" and str(f.get("name", "")).get_file() == str(f.get("name", "")) \
		and not str(f.get("name", "")).begins_with(".") and str(f.get("sha256", "")).length() == 64


## Body of a small file, empty when it can't be had.
func _fetch(u: String, bust_cache := true) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var out := PackedByteArray()
	if http.request(u + ("?t=%d" % Time.get_unix_time_from_system() if bust_cache else "")) == OK:
		var r: Array = await http.request_completed
		if r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200:
			out = r[3]
	http.queue_free()
	return out


func _download(u: String, dest: String, done: int, total: int, on_progress: Callable) -> String:
	var http := HTTPRequest.new()
	http.use_threads = true
	http.download_chunk_size = 262144
	http.download_file = dest
	add_child(http)
	var state := {"r": null}
	http.request_completed.connect(func(result, code, _h, _b): state["r"] = [result, code])
	if http.request(u) != OK:
		http.queue_free()
		return "не удалось начать загрузку"
	var last := -1
	var still := 0.0
	while state["r"] == null:
		await get_tree().create_timer(0.25, true, false, true).timeout
		var got := http.get_downloaded_bytes()
		on_progress.call(done + got, total)
		if got == last:
			still += 0.25
			if still > STALL_SEC:
				http.cancel_request()
				http.queue_free()
				return "сервер перестал отвечать"
		else:
			last = got
			still = 0.0
	http.queue_free()
	var r: Array = state["r"]
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return "ошибка загрузки (%d, %d)" % [r[0], r[1]]
	return ""
