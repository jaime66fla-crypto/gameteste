extends SceneTree
## Renders icon.svg into icon.png (256 px) and icon.ico (16-256 px, PNG entries)
## for the window icon and the Windows .exe.
## godot --headless --path godot --script res://tools/build_icon.gd
const SIZES := [16, 24, 32, 48, 64, 128, 256]

func _initialize() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	if svg.is_empty():
		printerr("icon.svg missing")
		quit(1)
		return
	var pngs: Array[PackedByteArray] = []
	for size in SIZES:
		var image := Image.new()
		image.load_svg_from_string(svg, float(size) / 512.0)
		if image.get_width() != size:
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		pngs.append(image.save_png_to_buffer())
		if size == 256:
			image.save_png(ProjectSettings.globalize_path("res://icon.png"))
	# ICO container: header, one directory entry per size, then the PNG blobs.
	var ico := PackedByteArray()
	ico.resize(6 + 16 * SIZES.size())
	ico.encode_u16(0, 0)
	ico.encode_u16(2, 1)
	ico.encode_u16(4, SIZES.size())
	var offset := ico.size()
	for i in SIZES.size():
		var entry := 6 + 16 * i
		var size: int = SIZES[i]
		ico[entry] = size % 256 # 256 is stored as 0
		ico[entry + 1] = size % 256
		ico[entry + 2] = 0
		ico[entry + 3] = 0
		ico.encode_u16(entry + 4, 1)
		ico.encode_u16(entry + 6, 32)
		ico.encode_u32(entry + 8, pngs[i].size())
		ico.encode_u32(entry + 12, offset)
		offset += pngs[i].size()
	for png in pngs:
		ico.append_array(png)
	var file := FileAccess.open("res://icon.ico", FileAccess.WRITE)
	file.store_buffer(ico)
	file.close()
	print("icon.png and icon.ico written (", ico.size(), " bytes)")
	quit(0)
