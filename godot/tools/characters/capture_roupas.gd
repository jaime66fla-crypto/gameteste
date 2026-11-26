extends SceneTree
## QA visual das roupas pagas do 01: prévia da loja (linha de cima) e o 01
## vestido de frente e de costas (linhas de baixo). Folha em res://.godot/roupas.png.
## godot --path godot --script res://tools/characters/capture_roupas.gd
const StorePreview = preload("res://scripts/loja/store_preview.gd")
const Avatar01 = preload("res://scripts/characters/avatar_01.gd")
const ITEMS := ["bone_vinho", "camiseta_oliva", "calca_cinza"]
const SIZE := 420
const SHOTS := [[Vector3(0.0, 1.45, 1.25), Vector3(0, 1.4, 0)], [Vector3(0.0, 1.45, -1.25), Vector3(0, 1.4, 0)], [Vector3(0.9, 0.8, 1.2), Vector3(0, 0.75, 0)]]

func _initialize() -> void:
	call_deferred("_run")

func _view(pos: Vector2, from: Vector3, to: Vector3, outfit: PackedStringArray, fov: float) -> SubViewport:
	var holder := SubViewportContainer.new()
	holder.position = pos
	holder.size = Vector2(SIZE, SIZE)
	holder.stretch = true
	root.add_child(holder)
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
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
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var avatar = Avatar01.new()
	avatar.roupas = outfit
	vp.add_child(avatar)
	avatar.rotation_degrees.y = 180
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.fov = fov
	cam.look_at_from_position(from, to)
	cam.current = true
	return vp

func _run() -> void:
	root.size = Vector2i(SIZE * 3, SIZE * 3)
	var views := []
	for i in ITEMS.size():
		var p = StorePreview.new(ITEMS[i], Vector2(SIZE, SIZE))
		p.position = Vector2(i * SIZE, 0)
		p.size = Vector2(SIZE, SIZE)
		root.add_child(p)
		views.append(p.viewport)
	var outfit := PackedStringArray(["bone_vinho", "camiseta_oliva", "calca_cinza"])
	for row in 2:
		for i in 3:
			var shot: Array = SHOTS[i]
			var from: Vector3 = shot[0]
			if row == 1:
				from = Vector3(-from.x, from.y, -from.z)
			views.append(_view(Vector2(i * SIZE, (row + 1) * SIZE), from, shot[1], outfit, 34.0 if i < 2 else 40.0))
	for f in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var sheet := Image.create(SIZE * 3, SIZE * 3, false, Image.FORMAT_RGB8)
	for k in views.size():
		var img: Image = (views[k] as SubViewport).get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, SIZE, SIZE), Vector2i((k % 3) * SIZE, (k / 3) * SIZE))
	print("ROUPAS SHEET=", sheet.save_png("res://.godot/roupas.png"))
	quit()
