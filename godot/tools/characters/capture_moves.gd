extends SceneTree
## Fotos de conferência do movimento do 01, de lado, em vários instantes:
## corrida sem arma e com fuzil a 5 m/s, pistola andando/parada/mirando e pulo
## sem arma e com fuzil. Gera <out>_t0.png ... <out>_t4.png (uma linha de casos
## por instante).
## godot --path godot --script res://tools/characters/capture_moves.gd -- --out=C:/pasta/mov
const Registry = preload("res://scripts/characters/character_registry.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const GRAVITY := 22.0
const JUMP := 8.5
const DT := 1.0 / 60.0

# [rótulo, arma ("" = sem), velocidade local, pulando, mirando]
const CASES := [
	["sem arma 5 m/s", "", Vector3(0, 0, -5.0), false, false],
	["fuzil 5 m/s", "rifle", Vector3(0, 0, -5.0), false, false],
	["pistola 5 m/s", "pistol", Vector3(0, 0, -5.0), false, false],
	["pistola parada", "pistol", Vector3.ZERO, false, false],
	["pistola mirando", "pistol", Vector3.ZERO, false, true],
	["pulo sem arma", "", Vector3(0, 0, -5.0), true, false],
	["pulo fuzil", "rifle", Vector3(0, 0, -5.0), true, false],
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://moves"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	root.size = Vector2i(2100, 520)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.58, 0.66, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.76)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 20, 0)
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 10)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.26, 0.25)
	floor_mesh.material_override = mat
	world.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	camera.position = Vector3(0, 1.1, 12)
	world.add_child(camera)
	camera.current = true
	var avatars := []
	for i in CASES.size():
		var spec: Array = CASES[i]
		var avatar := Registry.create_visual("01")
		world.add_child(avatar)
		avatar.position = Vector3((i - (CASES.size() - 1) * 0.5) * 1.6, 0, 0)
		avatar.rotation.y = -PI * 0.5 # de perfil, andando para a direita da foto
		await process_frame
		var weapon_id: String = spec[1]
		avatar.call("set_armed", not weapon_id.is_empty())
		if not weapon_id.is_empty():
			avatar.call("configure_weapon", weapon_id, 1.0)
			var weapon := Node3D.new()
			(avatar.get("weapon_mount") as Node3D).add_child(weapon)
			var model := WeaponProportions.create_model(weapon_id)
			if model:
				weapon.add_child(model)
				WeaponProportions.apply(weapon, weapon_id, model)
			avatar.call("bind_weapon", weapon)
			# Pistola: pronta só mirando (como o player.gd faz).
			avatar.call("set_weapon_ready", weapon_id != "pistol" or spec[4])
		avatars.append(avatar)
	camera.size = 1.6 * CASES.size() * 0.5
	# Aquece os ciclos (fora do pulo) e depois fotografa 5 instantes.
	var times := [0.0, 0.12, 0.24, 0.36, 0.5]
	var elapsed := 0.0
	var shot := 0
	var warm := 1.2
	while shot < times.size():
		for i in CASES.size():
			var spec: Array = CASES[i]
			var avatar: Node3D = avatars[i]
			var jumping: bool = spec[3] and elapsed >= warm
			var air_t := elapsed - warm
			var velocity: Vector3 = spec[2]
			if jumping:
				velocity.y = JUMP - GRAVITY * air_t
				avatar.position.y = maxf(0.0, JUMP * air_t - 0.5 * GRAVITY * air_t * air_t)
			var target: Vector3 = avatar.global_position + avatar.global_basis * Vector3(0, 1.3, -10)
			avatar.call("set_aim_target", target, not str(spec[1]).is_empty() and (spec[1] != "pistol" or spec[4]))
			var moving := 1.0 if velocity.length() > 0.1 else 0.0
			avatar.call("animate", DT, moving, false, false, spec[4], jumping and avatar.position.y > 0.0, false, Vector2(0, -1), velocity)
		await process_frame
		elapsed += DT
		if elapsed >= warm + times[shot]:
			await RenderingServer.frame_post_draw
			var path := "%s_t%d.png" % [out, shot]
			root.get_texture().get_image().save_png(path)
			print("MOVES ", path)
			shot += 1
	quit()
