extends SceneTree
## The profile window does not log out by accident:
##   godot --headless --path . -s res://tests/profile_test.gd
## Players lost their account right after picking an avatar: the avatars hid, the window shrank
## to the middle and «Выйти» came under the finger, so the next tap logged them out. Checks that
## no avatar tile has «Выйти» (or any button that moved) under it after the avatars hide, and
## that one press of «Выйти» only asks again.

const ProfileScreen = preload("res://scripts/ui/profile_screen.gd")
const Account = preload("res://scripts/net/account.gd")

var failures := 0


func _initialize() -> void:
	_run()


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", what)


func _frames(n := 3) -> void:
	for i in n:
		await process_frame


func _button(screen: Node, text: String) -> Button:
	for b in screen.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func _run() -> void:
	var account := Account.new()
	account.path = "user://profile_test_account.cfg"
	account.nick = "Тест"
	account.token = "0".repeat(64)
	# As main.gd show_profile puts it.
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)
	var screen = ProfileScreen.new()
	screen.setup(account)
	ProfileScreen.place(root, screen)
	var out_count := [0]
	screen.logged_out.connect(func(): out_count[0] += 1)
	await _frames()

	var change := _button(screen, "Сменить аватарку")
	var out := _button(screen, "Выйти")
	_expect(change != null and out != null, "the profile has its buttons")
	var rects_closed := {}
	for b in screen.find_children("*", "Button", true, false):
		if b.is_visible_in_tree():
			rects_closed[b] = b.get_global_rect()
	change.pressed.emit()
	await _frames()
	var cells: Array = screen._chooser.find_children("*", "", true, false).filter(
		func(n): return n is Control and n.mouse_filter == Control.MOUSE_FILTER_STOP and n.is_visible_in_tree())
	_expect(cells.size() > 10, "the avatars show (%d)" % cells.size())
	var points := []
	for c: Control in cells:
		var r := c.get_global_rect()
		for fx in [0.1, 0.5, 0.9]:
			for fy in [0.1, 0.5, 0.9]:
				points.append(r.position + r.size * Vector2(fx, fy))
	for b in rects_closed:
		_expect(b.get_global_rect() == rects_closed[b], "«%s» stays where it was when the avatars show" % b.text)
	_expect(screen.get_global_rect().end.y <= 1080, "the window fits the screen with the avatars open (%d)" % screen.get_global_rect().end.y)
	# An avatar was taken: the window hides the avatars (profile_screen.gd _apply).
	screen._chooser.visible = false
	await _frames()
	for b in rects_closed:
		_expect(b.get_global_rect() == rects_closed[b], "«%s» stays where it was when the avatars hide" % b.text)
	var under := 0
	for p: Vector2 in points:
		if out.get_global_rect().has_point(p):
			under += 1
	_expect(under == 0, "«Выйти» is not where the avatars were (%d points under it)" % under)

	var out_rect := out.get_global_rect()
	out.pressed.emit()
	await _frames()
	_expect(out_count[0] == 0, "one press of «Выйти» does not log out")
	_expect(out.text == "Точно выйти?", "it asks again")
	_expect(out.get_global_rect() == out_rect, "the question does not move the button")
	out.pressed.emit()
	await _frames()
	_expect(out_count[0] == 0, "the same tap twice is no yes")
	await create_timer(ProfileScreen.CONFIRM_SEC + 0.3).timeout
	_expect(out.text == "Выйти" and out_count[0] == 0, "the question goes away by itself")
	out.pressed.emit()
	await create_timer(ProfileScreen.ARM_SEC + 0.2).timeout
	out.pressed.emit()
	await _frames()
	_expect(out_count[0] == 1, "a press and a yes log out (%d)" % out_count[0])

	print("profile_test: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
