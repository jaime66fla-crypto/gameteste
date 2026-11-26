extends SceneTree
## Campo de treino offline (scripts/training_ground.gd):
## confere pela colisão real que o nascimento e os bonecos estão livres, que
## dá para andar do nascimento até cada zona, que rampas, escada e torre sobem
## andando, que o túnel só passa deitado, que as placas de aço estão na linha
## de tiro, que a borda é murada e que os materiais do atlas continuam aplicados.
## godot --headless --path godot --script res://tests/training_ground.gd
const Ground = preload("res://scripts/training_ground.gd")
const Arena = preload("res://scripts/training_arena.gd")
const WALK_MASK := 1
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	root.get_node("Net").set("in_match", false)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Jaime")
	player.set_physics_process(false)
	await physics_frame
	await process_frame
	var ground: Node3D = scene.get_node_or_null("TrainingGround")
	_check(ground != null, "o treino offline monta o campo de treino")
	_check(scene.get_node_or_null("WorldPolish") == null, "o treino offline não monta a cidade online")
	if ground == null:
		_finish(scene)
		return
	# O atlas precisa sobreviver ao tratamento cel e conservar os mipmaps.
	var floor_mesh := ground.get_node("Geometry/Mesh_asphalt") as MeshInstance3D
	var material := floor_mesh.material_override as StandardMaterial3D
	_check(material == Ground.material("asphalt"), "cel preserva o material do asfalto")
	_check(material.albedo_texture.resource_path.ends_with("/asphalt_albedo.png"), "chão sem a grade Kenney")
	_check(material.albedo_texture.get_image().has_mipmaps(), "asfalto tem mipmaps")
	var sign_y := 0.0
	for child in ground.get_children():
		if child is Label3D and child.text == "ÁREA DE COBERTURA":
			sign_y = child.position.y
	_check(sign_y > 1.0, "placa de cobertura acima do chão")
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = WALK_MASK
	query.exclude = [player.get_rid()]
	player.global_position = Vector3(0, -40, 0) # fora do caminho das sondas
	await physics_frame
	var clear := func(p: Vector3) -> bool:
		query.motion = Vector3.ZERO
		query.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 0.95, p.z))
		return space.intersect_shape(query, 1).is_empty()
	_check(clear.call(Ground.SPAWN), "nascimento livre")
	for spot in Ground.DUMMIES:
		_check(clear.call(spot[0] + Vector3(0, 0, 1.0)), "frente do %s livre" % spot[1])
	# Inundação no chão (passo de 1 m) a partir do nascimento.
	var half := int(Ground.HALF) - 2
	var open: Dictionary = {}
	for x in range(-half, half + 1):
		for z in range(-half, half + 1):
			if clear.call(Vector3(x, 0, z)):
				open[Vector2i(x, z)] = true
	var origin := Vector2i(roundi(Ground.SPAWN.x), roundi(Ground.SPAWN.z))
	var seen: Dictionary = {origin: true}
	var todo: Array[Vector2i] = [origin]
	var i := 0
	while i < todo.size():
		var cell := todo[i]
		i += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + d
			if open.has(next) and not seen.has(next):
				query.transform = Transform3D(Basis.IDENTITY, Vector3(cell.x, 0.95, cell.y))
				query.motion = Vector3(d.x, 0, d.y)
				if space.cast_motion(query)[0] >= 0.999:
					seen[next] = true
					todo.append(next)
	query.motion = Vector3.ZERO
	var places := {
		"fundo do estande": Vector3(12, 0, -40), "boneco distante": Vector3(12, 0, -28),
		"pé da rampa da torre": Vector3(-30, 0, 36), "frente das placas longas": Vector3(-44, 0, -40),
		"porta sul da casa de tiro": Vector3(36, 0, -24), "dentro da casa de tiro": Vector3(38, 0, -28),
		"porta oeste da casa de tiro": Vector3(29, 0, -30), "entrada da arena": Arena.CENTER + Vector3(0, 0, -Arena.HALF - 1.5),
		"dentro da arena": Arena.CENTER + Vector3(0, 0, -1), "praça livre": Vector3(0, 0, 20),
		"pé das rampas": Vector3(-28, 0, -5), "pé da escada": Vector3(-14, 0, -5),
		"escadinha de blocos": Vector3(-36, 0, -35), "muretas": Vector3(-29, 0, -26),
		"campo de cobertura": Vector3(36, 0, 2),
	}
	for title in places:
		var p: Vector3 = places[title]
		_check(seen.has(Vector2i(roundi(p.x), roundi(p.z))), "dá para andar do nascimento até: " + title)
	# Túnel: em pé não cabe, deitado cabe.
	query.transform = Transform3D(Basis.IDENTITY, Vector3(-19, 0.95, -22))
	_check(not space.intersect_shape(query, 1).is_empty(), "túnel: em pé não passa")
	var prone := CapsuleShape3D.new()
	prone.radius = 0.36
	prone.height = 0.75
	query.shape = prone
	query.transform = Transform3D(Basis.IDENTITY, Vector3(-19, 0.42, -22))
	_check(space.intersect_shape(query, 1).is_empty(), "túnel: deitado passa")
	query.shape = capsule
	# Linha de tiro: placas do estande (do nascimento) e as longas (da torre).
	var plates := get_nodes_in_group("training_target")
	_check(plates.size() == 6, "seis placas de aço (%d)" % plates.size())
	for plate in plates:
		var target: Vector3 = (plate as Node3D).global_position
		var eye := Vector3(Ground.SPAWN.x, 1.6, Ground.SPAWN.z) if target.x > 0 else Vector3(Ground.TOWER.x, Ground.TOWER_TOP + 1.5, Ground.TOWER.y)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target + (target - eye).normalized(), WALK_MASK))
		_check(not hit.is_empty() and hit["collider"] == plate, "%s na linha de tiro (bateu em %s)" % [plate.get("title"), "nada" if hit.is_empty() else hit["collider"].name])
		plate.call("take_damage", 20.0)
		_check(int(plate.get("hits")) == 1, "%s conta o acerto" % plate.get("title"))
	# Borda murada: correndo para fora, o jogador para antes do fim do chão.
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		query.transform = Transform3D(Basis.IDENTITY, d * (Ground.HALF - 6.0) + Vector3(0, 0.95, 0) + (Vector3(0, 0, 20) if d.x != 0 else Vector3(20, 0, 0)))
		query.motion = d * 12.0
		_check(space.cast_motion(query)[0] < 0.999, "borda murada para %s" % d)
	query.motion = Vector3.ZERO
	# Caminhada de verdade (cápsula e física do Jaime): sobe andando e chega no alto.
	var walks := [
		["rampa 15°", Vector3(-34, 0, -4), Vector3(-34, 0, -15), 2.0],
		["rampa 30°", Vector3(-28, 0, -4), Vector3(-28, 0, -11), 2.0],
		["rampa 40°", Vector3(-22, 0, -4), Vector3(-22, 0, -9.5), 2.0],
		["escada", Vector3(-14, 0, -4), Vector3(-14, 0, -12.5), 3.0],
		["torre", Vector3(-29, 0, 36), Vector3(-45, 0, 36), Ground.TOWER_TOP],
		["rampa da plataforma", Vector3(-11, 0, -26), Vector3(-11, 0, -37.5), 3.0],
	]
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	for w in walks:
		var target: Vector3 = w[2]
		player.global_position = w[1] + Vector3(0, 0.1, 0)
		player.velocity = Vector3.ZERO
		await physics_frame
		for frame in 360:
			var flat := target - player.global_position
			flat.y = 0
			var v := flat.normalized() * minf(5.0, flat.length() * 8.0)
			player.velocity = Vector3(v.x, player.velocity.y - gravity / 60.0, v.z)
			player.move_and_slide()
			await physics_frame
		print("%s: chegou a y=%.2f (alto %.1f) em %s" % [w[0], player.global_position.y, w[3], player.global_position])
		_check(player.global_position.y > float(w[3]) - 0.3, "%s: sobe andando até %.1f m (parou em y=%.2f)" % [w[0], w[3], player.global_position.y])
	# Minimapa mostra os blocos do campo.
	var minimap: Node = scene.get("minimap")
	_check(minimap != null and (minimap.get("_buildings") as Array).size() > 20, "o minimapa mostra o campo de treino")
	_finish(scene)

func _finish(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	for failure in failures.slice(0, 20):
		printerr(failure)
	print("TRAINING GROUND: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
