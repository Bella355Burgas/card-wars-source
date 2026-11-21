extends SceneTree
## Rasterizes every SVG of a folder to PNG with Godot's own SVG renderer:
##   godot --headless --path . -s res://tools/svg_to_png.gd -- <svg_dir> <png_dir> [scale]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <svg_dir> <png_dir> [scale]")
		quit(1)
		return
	var src := ProjectSettings.globalize_path("res://" + args[0]) if not args[0].is_absolute_path() else args[0]
	var dst := ProjectSettings.globalize_path("res://" + args[1]) if not args[1].is_absolute_path() else args[1]
	var scale := float(args[2]) if args.size() > 2 else 1.0
	DirAccess.make_dir_recursive_absolute(dst)
	for file in DirAccess.get_files_at(src):
		if file.get_extension() != "svg":
			continue
		var img := Image.new()
		var err := img.load_svg_from_string(FileAccess.get_file_as_string(src.path_join(file)), scale)
		if err != OK:
			printerr("failed ", file)
			continue
		img.save_png(dst.path_join(file.get_basename() + ".png"))
		print(file, " -> ", img.get_size())
	quit()
