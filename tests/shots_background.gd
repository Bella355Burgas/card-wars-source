extends Node
## Настройки → Фон: a picture is pinned and stays, «По очереди» brings the slideshow back:
##   godot --path . res://tests/shots_background.tscn -- <output_dir>
## The player's own [ui] background setting is put back at the end.

const MainScene := preload("res://scenes/main.tscn")

var out_dir := "user://shots_background"
var main
var n := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MainScene.instantiate()
	add_child(main)
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out_dir, n, name])


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _button(text: String) -> Button:
	for b in main.overlay.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree():
			return b
	return null


func _run() -> void:
	var saved = main._load_setting("ui", "background", "")
	await _wait(0.8)
	main.show_settings()
	await _wait(0.5)
	await _shot("settings")
	_button("Фон:").pressed.emit()
	await _wait(0.6)
	await _shot("picker")
	var buttons: Array = main.overlay.find_children("*", "TextureButton", true, false)
	print("pictures offered: ", buttons.size())
	buttons[4].pressed.emit()
	await _wait(1.0)
	var pinned: String = main.backdrop.pinned
	print("pinned: %s, saved: %s, button: %s" % [pinned, main._load_setting("ui", "background", ""), _button("Фон:").text])
	var tex = main.backdrop.current_texture()
	Engine.time_scale = 10.0
	await _wait(30.0 * 10.0 / 10.0)
	Engine.time_scale = 1.0
	print("still the same picture after 30 s: ", main.backdrop.current_texture() == tex)
	await _shot("pinned")
	_button("Фон:").pressed.emit()
	await _wait(0.5)
	_button("По очереди").pressed.emit()
	await _wait(0.5)
	tex = main.backdrop.current_texture()
	Engine.time_scale = 10.0
	await _wait(20.0)
	Engine.time_scale = 1.0
	print("auto again: pinned '%s', picture changed: %s" % [main.backdrop.pinned, main.backdrop.current_texture() != tex])
	main._save_setting("ui", "background", saved)
	get_tree().quit()
