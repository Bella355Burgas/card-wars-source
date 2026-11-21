extends Node
## Music and voices: the menu track on the title, the rival hero's theme in a fight against
## the AI, the mixes going from track to track, the heroes' lines, quiet after the end, then the menu track softly; every track
## and line of sound_index.gd loads.
##   godot --path . res://tests/music_test.tscn
## Prints FAIL lines for what is wrong and "music OK" when all is right.

const MainScene := preload("res://scenes/main.tscn")
const SoundIndex = preload("res://scripts/ui/sound_index.gd")

var main
var failed := false


func _ready() -> void:
	main = MainScene.instantiate()
	add_child(main)
	_run()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _check(ok: bool, what: String) -> void:
	if not ok:
		failed = true
		print("FAIL ", what)


func _button(text: String) -> Button:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree():
			return b
	return null


func _run() -> void:
	var sfx = get_node("/root/Sfx")
	var voices_were: bool = sfx.voices_on
	sfx.voices_on = true
	for id: String in SoundIndex.TRACKS:
		_check(load("res://assets/music/%s.ogg" % id) is AudioStream, "track %s does not load" % id)
	var n := 0
	for hero: String in SoundIndex.LINES:
		for event: String in SoundIndex.LINES[hero]:
			for line: Array in SoundIndex.LINES[hero][event]:
				n += 1
				_check(load("res://assets/sfx/voices/%s.ogg" % line[0]) is AudioStream, "line %s does not load" % line[0])
	print("tracks %d, lines %d" % [SoundIndex.TRACKS.size(), n])
	await _wait(1.0)
	_check(sfx.mix_name() == "menu" and sfx.music_id() != "", "no menu mix on the title ('%s')" % sfx.mix_name())
	# The mix goes on to other tracks, never one twice running.
	var heard := [sfx.music_id()]
	for i in 4:
		sfx._switch_at = 0.01
		await _wait(0.3)
		_check(sfx.music_id() != heard[-1], "the mix played %s twice running" % heard[-1])
		heard.append(sfx.music_id())
	print("menu mix: ", heard)
	_check(sfx.mix_name() == "menu", "the menu mix is gone ('%s')" % sfx.mix_name())
	# The heroes' lines: AI against AI plays by itself.
	main.start_ai_vs_ai_game(["bmo", "marceline"])
	await _wait(1.0)
	_check(sfx.music_id() == "marceline", "AI against AI (BMO, Marceline) plays '%s'" % sfx.music_id())
	var spoke := false
	for i in 400:
		await _wait(0.1)
		var more := _button("Начать")
		if more != null and i % 5 == 0:
			more.pressed.emit()
		if sfx.voice_playing():
			spoke = true
			print("first line after %.1f s, turn %d" % [i * 0.1, main.game.turn_number])
			break
	_check(spoke, "nobody spoke in the first 40 s of the fight (turn %d)" % main.game.turn_number)
	main.board.play({"type": "game_over", "winner": 0})
	await _wait(1.6)
	_check(sfx.music_id() == "", "music '%s' goes on after the end of the game" % sfx.music_id())
	await _wait(3.5)
	_check(sfx.mix_name() == "menu", "no menu music comes back under the results ('%s')" % sfx.mix_name())
	var to_menu := _button("Главное меню")
	_check(to_menu != null, "no «Главное меню» on the results")
	if to_menu != null:
		to_menu.pressed.emit()
	else:
		main._end_game()
		main.show_title()
	await _wait(2.5)
	_check(sfx.mix_name() == "menu" and sfx.music_playing(), "no menu music back on the title (%s)" % sfx.mix_name())
	# Against the AI: the theme of the AI's hero (the game waits at its first screen here).
	main.start_ai_game(["finn", "jake"])
	await _wait(1.0)
	_check(sfx.music_id() == "jake", "a fight against Jake plays '%s'" % sfx.music_id())
	await _wait(4.0)
	_check(sfx.music_playing() and sfx.mix_name() == "fight:jake", "no fight music after 5 s (%s)" % sfx.mix_name())
	sfx.voices_on = voices_were
	print("music OK" if not failed else "music FAILED")
	get_tree().quit()
