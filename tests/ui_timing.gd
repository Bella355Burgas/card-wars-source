extends SceneTree
## How long the window stays frozen after each click on the way into a game against
## the AI: the hero selection, then the start of the game and its first choices.
##   godot --path . -s res://tests/ui_timing.gd

const MainScene := preload("res://scenes/main.tscn")
const CardDB = preload("res://scripts/core/card_db.gd")

var main
var _last := 0
var _worst := 0.0
var _t_click := 0


func _initialize() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	process_frame.connect(_tick)
	_run()


func _tick() -> void:
	var now := Time.get_ticks_usec()
	if _last > 0:
		_worst = maxf(_worst, (now - _last) / 1000.0)
	_last = now


## The longest frame of the next `t` seconds after `what` (the click itself included).
func _measure(what: String, t := 1.5) -> void:
	_worst = (Time.get_ticks_usec() - _t_click) / 1000.0
	_last = Time.get_ticks_usec()
	await create_timer(t).timeout
	print("FRAME %-34s worst %7.1f ms" % [what, _worst])


func _press(text: String) -> bool:
	_t_click = Time.get_ticks_usec()
	for b in root.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return true
	return false


func _click(c: Control) -> void:
	_t_click = Time.get_ticks_usec()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	c.gui_input.emit(e)


## The visible grid of the hero selection: "HeroGrid" or "DeckGrid".
func _grid(name: String) -> GridContainer:
	for g: GridContainer in main.overlay.find_children(name, "GridContainer", true, false):
		if g.is_visible_in_tree():
			return g
	return null


func _run() -> void:
	await create_timer(3.0).timeout     # a person needs longer to get from the title to here
	var ids: Array = CardDB.hero_card_ids()
	_t_click = Time.get_ticks_usec()
	main.show_hero_select("ai")
	await _measure("open hero select")
	_click(_grid("HeroGrid").get_child(ids.find("marceline")))
	await _measure("hero card -> deck step")
	_click(_grid("DeckGrid").get_child(CardDB.hero_ids().find("ice_king")))
	await _measure("deck -> next seat")
	_click(_grid("HeroGrid").get_child(ids.find("prismo")))
	await _measure("AI hero card -> deck step")
	_click(_grid("DeckGrid").get_child(CardDB.hero_ids().find("lich")))
	await _measure("AI deck")
	_press("В бой!")
	await _measure("В бой! -> coin curtain", 2.5)
	for k in 6:
		var pressed := false
		for text in ["Дальше", "Готово", "Оставить", "В бой!", "Начать ход"]:
			if _press(text):
				await _measure("button " + text, 2.0)
				pressed = true
				break
		if not pressed:
			var seen := []
			for b in root.find_children("*", "Button", true, false):
				if b.is_visible_in_tree():
					seen.append(b.text)
			print("BUTTONS ", seen)
			break
	print("DONE")
	quit()
