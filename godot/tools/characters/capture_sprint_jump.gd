extends SceneTree
## Fotos do sprint e do pulo sem arma DENTRO do jogo (player.gd de verdade,
## fÃ­sica, Shift e EspaÃ§o): cada instante sai pela cÃ¢mera do jogo e de lado.
## Gera <out>_NN_<nome>_jogo.png e <out>_NN_<nome>_lado.png.
## godot --path godot --script res://tools/characters/capture_sprint_jump.gd -- --out=C:/pasta/sj
const Registry = preload("res://scripts/characters/character_registry.gd")
const SELECTION := "user://capture_sprint_jump_selection.cfg"

var out := "user://sj"
var shot := 0
var side_camera: Camera3D
var game_camera: Camera3D
var player: CharacterBody3D

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _snap(label: String) -> void:
	game_camera = root.get_camera_3d()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%02d_%s_jogo.png" % [out, shot, label])
	# De lado, Ã  direita do corpo, na altura do quadril.
	var body := player.global_transform
	var right := Vector3(cos(float(player.get("yaw"))), 0, -sin(float(player.get("yaw"))))
	side_camera.global_position = body.origin + right * 4.5 + Vector3.UP * 1.0
	side_camera.look_at(body.origin + Vector3.UP * 0.9, Vector3.UP)
	side_camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s_%02d_%s_lado.png" % [out, shot, label])
	if game_camera != null:
		game_camera.current = true
	print("FOTO %02d %s y=%.2f vel=%.2f" % [shot, label, player.global_position.y, Vector2(player.velocity.x, player.velocity.z).length()])
	shot += 1

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	Registry.storage_path = SELECTION
	Registry.select_character("atacante")
	root.size = Vector2i(960, 540)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Jaime") as CharacterBody3D
	# ChÃ£o plano e largo, longe do mapa, para correr reto.
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(400, 30, 400)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collider.shape = shape
	floor_body.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	floor_body.add_child(mesh)
	scene.add_child(floor_body)
	side_camera = Camera3D.new()
	side_camera.fov = 40.0
	scene.add_child(side_camera)
	player.global_position = Vector3(400, 30.6, 460)
	player.set("yaw", 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _frames(40)
	if not bool(player.get("weapon_holstered")):
		player.call("_toggle_weapon_holster")
	await _frames(20)
	await _snap("parado")
	# Correndo normal (5 m/s) e depois Shift (8 m/s).
	Input.action_press("move_forward")
	await _frames(50)
	await _snap("corrida")
	Input.action_press("sprint")
	for i in 3:
		await _frames(9 if i > 0 else 50)
		await _snap("sprint")
	# Pulo no sprint em cÃ¢mera lenta (1/4): a cada ~0,09 s de jogo, do pulo atÃ©
	# depois do pouso.
	Engine.time_scale = 0.25
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	for i in 11:
		await _snap("pulo_sprint")
		await _frames(5)
	Engine.time_scale = 1.0
	# Parar do sprint.
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _frames(10)
	await _snap("freio")
	# Pulo parado.
	await _frames(60)
	Engine.time_scale = 0.25
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	for i in 11:
		await _snap("pulo_parado")
		await _frames(5)
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SELECTION))
	quit(0)
