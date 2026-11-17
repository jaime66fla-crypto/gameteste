extends Node3D
## Cena de demonstração: o personagem corta uma árvore com o machado em loop.
## Abra scenes/survival/chop_preview.tscn no editor e aperte F6.
## Teclas: 1 machado, 2 machado improvisado, 3 pé de cabra na pedra, 4 parar;
## setas giram a câmera.
## Fotos: godot --path godot res://scenes/survival/chop_preview.tscn -- --capture=<pasta>
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")

var avatar: Node3D
var camera: Camera3D
var _orbit := 0.9
var _tree: Node3D
var _rock: Node3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color("#3d6f95")
	mat.sky_horizon_color = Color("#b8c7cc")
	sky.sky_material = mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	ground.material_override = SurfaceMaterials.make("grass", Color("#5d7a4e"))
	add_child(ground)
	_tree = _make_tree()
	_tree.position = Vector3(0, 0, -1.15)
	add_child(_tree)
	_rock = _make_rock()
	_rock.position = Vector3(0, 0, -0.95)
	_rock.visible = false
	add_child(_rock)
	avatar = load("res://scenes/characters/avatar.tscn").instantiate()
	avatar.rotation.y = 0.0 # olha para -Z (a árvore)
	add_child(avatar)
	camera = Camera3D.new()
	camera.fov = 50
	add_child(camera)
	camera.current = true
	await get_tree().process_frame
	avatar.call("set_armed", false)
	avatar.call("set_action", "chop", "axe")
	var capture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.substr(10)
	if not capture.is_empty():
		_capture(capture)

func _make_tree() -> Node3D:
	var node := Node3D.new()
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.17
	cyl.bottom_radius = 0.24
	cyl.height = 3.4
	trunk.mesh = cyl
	trunk.position.y = 1.7
	trunk.material_override = SurfaceMaterials.make("bark", Color("#5e4733"))
	node.add_child(trunk)
	var crown := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.8
	cone.height = 4.0
	crown.mesh = cone
	crown.position.y = 4.6
	crown.material_override = SurfaceMaterials.make("leaf", Color("#3f6a3c"))
	node.add_child(crown)
	# Marca do corte no tronco, na altura do golpe.
	var notch := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.12, 0.08)
	notch.mesh = box
	notch.position = Vector3(0, 1.0, 0.2)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#c9a46c")
	notch.material_override = m
	node.add_child(notch)
	return node

func _make_rock() -> Node3D:
	var node := Node3D.new()
	var rock := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 0.8
	rock.mesh = sphere
	rock.position.y = 0.3
	rock.material_override = SurfaceMaterials.make("concrete", Color("#7d7f7a"))
	node.add_child(rock)
	return node

func _process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_LEFT):
		_orbit -= delta * 1.5
	if Input.is_physical_key_pressed(KEY_RIGHT):
		_orbit += delta * 1.5
	camera.position = Vector3(sin(_orbit) * 4.2, 1.6, cos(_orbit) * 4.2) + Vector3(0, 0, -0.4)
	camera.look_at(Vector3(0, 1.1, -0.4))
	if avatar != null and avatar.has_method("animate"):
		avatar.call("animate", delta, 0.0, false, false, false, false, false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_1: _show("chop", "axe", true)
			KEY_2: _show("chop", "improvised_axe", true)
			KEY_3: _show("pry", "crowbar", false)
			KEY_4: _show("", "", true)

func _show(act: String, tool: String, tree: bool) -> void:
	_tree.visible = tree
	_rock.visible = not tree
	avatar.call("set_action", act, tool)

## Quatro fotos de fases do golpe (levantando, no alto, impacto, voltando) e o pé de cabra.
func _capture(folder: String) -> void:
	get_window().size = Vector2i(900, 900)
	var shots := [[0.25, "chop_1_levantando"], [0.5, "chop_2_no_alto"], [0.68, "chop_3_impacto"], [0.85, "chop_4_voltando"]]
	for shot in shots:
		avatar.set("_work_time", float(shot[0]) * float(avatar.get("WORK_CYCLE")) - 1.0 / 60.0)
		for i in 3:
			await get_tree().process_frame
		avatar.set("_work_time", float(shot[0]) * float(avatar.get("WORK_CYCLE")) - 1.0 / 60.0)
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(folder.path_join(str(shot[1]) + ".png"))
	_show("pry", "crowbar", false)
	avatar.set("_work_time", 0.68 * float(avatar.get("WORK_CYCLE")))
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(folder.path_join("pry_impacto.png"))
	print("fotos salvas em " + folder)
	get_tree().quit(0)
