extends SceneTree
## How long the window freezes when the profile opens (main.gd show_profile) and while the avatar
## pictures load behind it. It took 2.5 s when all the heroes' full pictures were loaded at once.
##   godot --path . -s res://tests/profile_timing.gd

const Account = preload("res://scripts/net/account.gd")
const ProfileScreen = preload("res://scripts/ui/profile_screen.gd")

var _last := 0
var _worst := 0.0


func _tick() -> void:
	var now := Time.get_ticks_usec()
	if _last > 0:
		_worst = maxf(_worst, (now - _last) / 1000.0)
	_last = now


func _initialize() -> void:
	await process_frame
	process_frame.connect(_tick)
	var a := Account.new()
	a.path = "user://profile_timing.cfg"
	a.nick = "Тест"
	a.token = "x"
	var t := Time.get_ticks_usec()
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	var s = ProfileScreen.new()
	s.setup(a, null)
	ProfileScreen.place(holder, s)
	print("OPEN  %7.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	_worst = 0.0
	_last = Time.get_ticks_usec()
	await create_timer(3.0).timeout
	var empty := 0
	for c in s.find_children("*", "GridContainer", true, false)[0].get_children():
		if c.get("texture") == null:
			empty += 1
	print("FRAME %7.1f ms worst after open, %d avatars without a picture" % [_worst, empty])
	quit()
