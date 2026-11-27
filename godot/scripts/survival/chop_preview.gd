extends Node3D
## Cena de demonstração: o personagem corta uma árvore com o machado em loop.
## Abra scenes/survival/chop_preview.tscn no editor e aperte F6.
## Teclas: 1/2 machado cortando a árvore, 3 picareta na pedra, 4 pé de cabra,
## ataques (Q): 5 machado, 6 picareta, 7 faca, 8 facão, 9 lança; 0 parar;
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
	avatar = load("res://scenes/characters/01.tscn").instantiate()
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

var _attack := ["", ""] # golpe de ataque repetindo (Q no jogo): [ferramenta, alvo]
var _attack_clock := 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_1: _show("chop", "stone_axe", "tree")
			KEY_2: _show("chop", "iron_axe", "tree")
			KEY_3: _show("pry", "stone_pick", "rock")
			KEY_4: _show("pry", "crowbar", "rock")
			KEY_5: _show("swing", "iron_axe", "")
			KEY_6: _show("swing", "iron_pick", "")
			KEY_7: _show("swing", "stone_knife", "")
			KEY_8: _show("swing", "machete", "")
			KEY_9: _show("swing", "wood_spear", "")
			KEY_0: _show("", "", "tree")

func _show(act: String, tool: String, target: String) -> void:
	_tree.visible = target == "tree"
	_rock.visible = target == "rock"
	avatar.call("set_action", "", "")
	avatar.call("set_action", act, tool)
	_attack = [tool, target] if act == "swing" else ["", ""]
	_attack_clock = 0.0

func _physics_process(delta: float) -> void:
	# Ataques são um golpe só: repete a cada 0,9 s para dar para ver.
	if _attack[0] == "":
		return
	_attack_clock += delta
	if _attack_clock > 0.9:
		_show("swing", _attack[0], _attack[1])

func _shot(folder: String, label: String, time: float) -> void:
	for i in 3:
		avatar.set("_work_time", time - 1.0 / 60.0)
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))

## Fotos das fases de cada golpe (corte lateral, picareta, ataques de cada arma).
func _capture(folder: String) -> void:
	get_window().size = Vector2i(700, 700)
	var cycle := float(avatar.get("WORK_CYCLE"))
	var swing := float(avatar.get("SWING_CYCLE"))
	var loops := [["chop", "stone_axe", "tree"], ["mine", "stone_pick", "rock"]]
	for spec in loops:
		_show("chop" if spec[0] == "chop" else "pry", spec[1], spec[2])
		_attack = ["", ""]
		for view in [[0.9, ""], [2.3, "_frente"]]:
			_orbit = float(view[0])
			for phase in [[0.3, "1_preparando"], [0.5, "2_no_alto"], [0.6, "3_descendo"], [0.66, "4_impacto"]]:
				await _shot(folder, "%s%s_%s" % [spec[0], view[1], phase[1]], float(phase[0]) * cycle)
	_orbit = 2.4
	for tool in ["iron_axe", "iron_pick", "stone_knife", "machete", "wood_spear"]:
		_show("swing", tool, "")
		_attack = ["", ""]
		for phase in [[0.3, "1_prepara"], [0.5, "2_golpe"], [0.6, "3_fim"]]:
			await _shot(folder, "atk_%s_%s" % [tool, phase[1]], float(phase[0]) * swing)
	print("fotos salvas em " + folder)
	get_tree().quit(0)
