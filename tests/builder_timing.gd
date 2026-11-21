extends SceneTree
## How long the window freezes when the deck builder opens the way the game opens it
## (hero_select.show_deck_builder), and during a scroll through the pool. Video memory is printed
## too: the small copies of the pool and the full pictures of the preview are counted apart.
##   godot --path . -s res://tests/builder_timing.gd

const MainScene := preload("res://scenes/main.tscn")
const BuilderScript := preload("res://scripts/ui/deck_builder.gd")

var main


func _initialize() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	_run()


func _mem(what: String) -> void:
	print("MEM %-16s texture %6.1f MB  video %6.1f MB" % [what,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0


func _run() -> void:
	await create_timer(3.0).timeout
	_mem("title")
	var t0 := Time.get_ticks_usec()
	var holder = main._overlay_root(Color(0.03, 0.02, 0.07, 0.95))
	var b = BuilderScript.new()
	b.setup("", false)
	holder.add_child(b)
	print("BUILD %.1f ms" % _ms(t0))
	t0 = Time.get_ticks_usec()
	main._fill_screen(holder, b)
	print("FILL %.1f ms" % _ms(t0))
	var worst := 0.0
	for i in 6:
		t0 = Time.get_ticks_usec()
		await process_frame
		worst = maxf(worst, _ms(t0))
		print("FRAME %d %.1f ms" % [i, _ms(t0)])
	print("OPEN worst frame %.1f ms" % worst)
	await create_timer(1.0).timeout
	_mem("builder open")
	print("TILES %d, small %d, full %d, loading %d" % [b._tiles.size(), b._thumbs.size(), b._big.size(), b._loading.size()])

	# A scroll through the pool, one frame at a time.
	var scroll: ScrollContainer = b._pool_scroll
	worst = 0.0
	for i in 30:
		scroll.scroll_vertical += 220
		t0 = Time.get_ticks_usec()
		await process_frame
		worst = maxf(worst, _ms(t0))
	print("SCROLL 30 frames worst %.1f ms" % worst)
	await create_timer(1.0).timeout
	_mem("after scroll")
	print("TILES %d, small %d, full %d, loading %d" % [b._tiles.size(), b._thumbs.size(), b._big.size(), b._loading.size()])
	if OS.has_environment("SHOT"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("SHOT"))
	print("DONE")
	quit()
