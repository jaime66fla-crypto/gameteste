extends SceneTree
## QA visual dos tênis do 01: prévia da loja de cada modelo (linha de cima) e o
## 01 calçado, pés de perto (linha de baixo). Folha em res://.godot/tenis.png.
## godot --path godot --script res://tools/characters/capture_tenis.gd
const StorePreview = preload("res://scripts/loja/store_preview.gd")
const Avatar01 = preload("res://scripts/characters/avatar_01.gd")
const ITEMS := ["tenis_asfalto", "tenis_brasa", "tenis_noturno"]
const SIZE := 420

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(SIZE * 3, SIZE * 2)
	var previews := []
	for i in ITEMS.size():
		var p = StorePreview.new(ITEMS[i], Vector2(SIZE, SIZE))
		p.position = Vector2(i * SIZE, 0)
		p.size = Vector2(SIZE, SIZE)
		root.add_child(p)
		previews.append(p)
	var feet := []
	for i in ITEMS.size():
		var holder := SubViewportContainer.new()
		holder.position = Vector2(i * SIZE, SIZE)
		holder.size = Vector2(SIZE, SIZE)
		holder.stretch = true
		root.add_child(holder)
		var vp := SubViewport.new()
		vp.size = Vector2i(SIZE, SIZE)
		vp.own_world_3d = true
		holder.add_child(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("#1a2a30")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color("#9fb0b8")
		env.environment.ambient_light_energy = 0.5
		vp.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, 30, 0)
		vp.add_child(sun)
		var avatar = Avatar01.new()
		avatar.roupas = PackedStringArray(["bone", "camiseta", "calca", ITEMS[i]])
		vp.add_child(avatar)
		avatar.rotation_degrees.y = 200 + i * 35
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.fov = 30
		cam.look_at_from_position(Vector3(0.0, 0.45, 1.2), Vector3(0, 0.08, 0))
		cam.current = true
		feet.append(vp)
	for f in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var sheet := Image.create(SIZE * 3, SIZE * 2, false, Image.FORMAT_RGB8)
	for i in ITEMS.size():
		for row in 2:
			var vp: SubViewport = previews[i].viewport if row == 0 else feet[i]
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(0, 0, SIZE, SIZE), Vector2i(i * SIZE, row * SIZE))
	print("TENIS SHEET=", sheet.save_png("res://.godot/tenis.png"))
	quit()
