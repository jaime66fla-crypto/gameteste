extends SceneTree
## QA visual das skins de arma: a prévia da loja (store_preview.gd) de cada
## skin (colunas) em momentos diferentes do brilho animado (linhas), numa folha
## res://.godot/weapon-skins.png.
## godot --path godot --script res://tools/weapons/capture_skins.gd
const StorePreview = preload("res://scripts/loja/store_preview.gd")
const SKINS := ["pistol_oliva", "smg_azul_aco", "shotgun_ferrugem", "rifle_deserto", "sniper_floresta"]
const SIZE := 300
const ROWS := 3
const GAP_FRAMES := 45 # ~0,75 s entre as linhas

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(SIZE * SKINS.size(), SIZE * ROWS)
	var sheet := Image.create(SIZE * SKINS.size(), SIZE * ROWS, false, Image.FORMAT_RGB8)
	var previews: Array = []
	for i in SKINS.size():
		var p = StorePreview.new(SKINS[i], Vector2(SIZE, SIZE))
		p.position = Vector2(i * SIZE, 0)
		p.size = Vector2(SIZE, SIZE)
		root.add_child(p)
		previews.append(p)
	for row in ROWS:
		for f in GAP_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		for i in previews.size():
			var vp: SubViewport = previews[i].viewport
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(0, 0, SIZE, SIZE), Vector2i(i * SIZE, row * SIZE))
	print("SKIN SHEET=", sheet.save_png("res://.godot/weapon-skins.png"))
	quit()
