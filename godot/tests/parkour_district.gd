extends SceneTree
## Só o que o jogador pisa/esbarra (os degraus da camada dos pés não contam).
const WALK_MASK := 1
## Bairro de parkour: confere em cada lote que as rotas sobem em degraus que
## o pulo alcança (<= 1,5 m; o pulo sobe ~1,64 m) e que o jogador cabe em pé
## em cada degrau, pela colisão real.
## godot --headless --path godot --script res://tests/parkour_district.gd
const District = preload("res://scripts/parkour_district.gd")
const MAX_STEP := 1.5
var failures: Array[String] = []

# Rotas em coordenadas locais do lote (frente +Z): pontos [x, z] em ordem.
const ROUTES := {
	"sobrado": [
		[[5.9, 6.5], [5.9, 4.95], [5.9, 3.0], [5.9, 1.3], [5.6, -0.6], [5.6, -1.5], [4.0, -1.5]],
		[[2.3, 6.0], [2.3, 4.6], [1.0, 4.6], [0.0, 3.3]],
	],
	"terrea": [[[3.0, 7.5], [3.0, 5.75], [3.0, 4.65], [3.0, 2.0]]],
	"pista": [[[-4.5, 6.0], [-4.5, 4.0], [-4.5, 2.5], [-4.5, 1.0], [-4.5, -0.5], [-4.5, -3.6], [-1.0, -3.6]]],
}

# Base: chão > caçamba > caixote > andaime > viga > andaime > caixotes > chão.
const BASE_ROUTE := [[-3.5, 2.6], [-3.5, 1.4], [-3.5, -0.3], [-1.4, -1.4], [0.8, -1.4], [3.0, -1.4], [3.0, 0.5], [3.0, 1.6], [3.0, 2.5]]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Jaime")
	player.set_physics_process(false)
	player.global_position = Vector3(0, -40, 0)
	await physics_frame
	await process_frame
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule
	shape_query.collision_mask = WALK_MASK
	var lots := District.lots()
	if lots.size() < 40:
		failures.append("Bairro precisa de 40+ lotes, tem %d" % lots.size())
	if get_nodes_in_group("parkour_house").size() < 25:
		failures.append("Poucas casas no bairro")
	for lot in lots:
		var basis := Basis(Vector3.UP, float(lot["yaw"]))
		var origin := Vector3(lot["center"].x, 0, lot["center"].y)
		for route in ROUTES[lot["kind"]]:
			var last := -1.0
			for point in route:
				var world := origin + basis * Vector3(point[0], 0, point[1])
				# O raio parte logo acima do alcance do pulo (não do telhado, em pontos internos).
				var from_y := 12.0 if last < 0.0 else last + 1.9
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(world + Vector3(0, from_y, 0), world + Vector3(0, -1, 0), WALK_MASK))
				var top: float = hit["position"].y if not hit.is_empty() else 0.0
				# Telhado/andar acima do ponto: desce até achar onde o jogador cabe.
				shape_query.transform = Transform3D(Basis.IDENTITY, Vector3(world.x, top + 0.9, world.z))
				if not space.intersect_shape(shape_query, 1).is_empty():
					failures.append("%s %d: jogador não cabe em %s (y=%.2f)" % [lot["kind"], lot["index"], point, top])
				if last >= 0.0 and top - last > MAX_STEP:
					failures.append("%s %d: degrau de %.2f m em %s" % [lot["kind"], lot["index"], top - last, point])
				last = top
			if lot["kind"] == "sobrado" and route == ROUTES["sobrado"][0] and last < 6.5:
				failures.append("sobrado %d: rota não chega à laje (%.2f)" % [lot["index"], last])
	# Escadas: a rampa invisível sobe suave (nada de degrau > 0,35 m entre
	# pontos a cada 0,5 m), o jogador cabe em pé e sai no alto.
	for lot in lots:
		var basis := Basis(Vector3.UP, float(lot["yaw"]))
		var origin := Vector3(lot["center"].x, 0, lot["center"].y)
		var stairs: Array = []
		if lot["kind"] == "sobrado":
			stairs.append([-4.15, 2.2, -3.5, 3.4, Vector2(-3.0, -3.0)]) # interna: até o 1º andar
			if int(lot["index"]) % 2 == 0:
				stairs.append([-5.6, 5.0, -3.6, 6.6, Vector2(-4.2, -3.6)]) # externa: até a laje
		elif lot["kind"] == "terrea":
			stairs.append([-5.05, 3.6, -3.4, 3.6, Vector2(-3.6, -3.4)])
		for s in stairs:
			var last := 0.0
			var z: float = s[1]
			while z >= float(s[2]) - 0.01:
				var world := origin + basis * Vector3(float(s[0]), 0, z)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(world + Vector3(0, last + 1.0, 0), world + Vector3(0, -1, 0), WALK_MASK))
				var top: float = hit["position"].y if not hit.is_empty() else 0.0
				if top - last > 0.5: # mais íngreme que 45° (o limite de piso do CharacterBody)
					failures.append("%s %d: escada trava em z=%.1f (%.2f -> %.2f)" % [lot["kind"], lot["index"], z, last, top])
				# Cápsula um pouco acima: numa rampa de 39° ela encosta na inclinação.
				shape_query.transform = Transform3D(Basis.IDENTITY, Vector3(world.x, top + 1.05, world.z))
				if not space.intersect_shape(shape_query, 1).is_empty():
					failures.append("%s %d: sem espaço na escada em z=%.1f (y=%.2f)" % [lot["kind"], lot["index"], z, top])
				last = top
				z -= 0.5
			if last < float(s[3]) - 0.3:
				failures.append("%s %d: escada não chega a %.1f (%.2f)" % [lot["kind"], lot["index"], s[3], last])
			var exit: Vector2 = s[4]
			var landing := origin + basis * Vector3(exit.x, 0, exit.y)
			var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(landing + Vector3(0, last + 1.0, 0), landing + Vector3(0, -1, 0), WALK_MASK))
			if hit2.is_empty() or absf(hit2["position"].y - float(s[3])) > 0.35:
				failures.append("%s %d: saída da escada sem piso em %s" % [lot["kind"], lot["index"], exit])
	# Caminhada de verdade: o próprio Jaime (cápsula e física do jogo) anda
	# escada acima e tem que chegar no alto.
	var walks := [] # [lote, pé local, alvo local, altura esperada]
	var got_sobrado := false
	var got_terrea := false
	for lot in lots:
		if lot["kind"] == "sobrado" and not got_sobrado and int(lot["index"]) % 2 == 0:
			got_sobrado = true
			walks.append([lot, Vector3(-5.6, 0, 5.6), Vector3(-5.6, 0, -3.4), 6.6])
			walks.append([lot, Vector3(-4.15, 0, 2.8), Vector3(-4.15, 0, -3.3), 3.4])
		if lot["kind"] == "terrea" and not got_terrea:
			got_terrea = true
			walks.append([lot, Vector3(-5.05, 0, 4.5), Vector3(-5.05, 0, -3.2), 3.6])
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	for w in walks:
		var lot: Dictionary = w[0]
		var basis := Basis(Vector3.UP, float(lot["yaw"]))
		var origin := Vector3(lot["center"].x, 0, lot["center"].y)
		var target: Vector3 = origin + basis * w[2]
		player.global_position = origin + basis * w[1] + Vector3(0, 0.1, 0)
		player.velocity = Vector3.ZERO
		await physics_frame
		for frame in 240:
			var flat := target - player.global_position
			flat.y = 0
			var v := flat.normalized() * minf(5.0, flat.length() * 8.0)
			player.velocity = Vector3(v.x, player.velocity.y - gravity / 60.0, v.z)
			player.move_and_slide()
			await physics_frame
		print("escada %s %d: subiu até y=%.2f (alto %.1f)" % [lot["kind"], lot["index"], player.global_position.y, w[3]])
		if player.global_position.y < float(w[3]) - 0.3:
			failures.append("%s %d: andando, a escada para em y=%.2f (alto %.1f) em %s" % [lot["kind"], lot["index"], player.global_position.y, w[3], player.global_position])
	player.global_position = Vector3(0, -40, 0)
	# Bases da faixa da cidade (as mesmas do mata-mata e da sala personalizada).
	if get_nodes_in_group("parkour_base").size() != District.bases().size():
		failures.append("Bases de parkour faltando")
	for spot in District.bases():
		var basis := Basis(Vector3.UP, float(spot[1]))
		var origin := Vector3(spot[0].x, 0, spot[0].y)
		var last := -1.0
		for point in BASE_ROUTE:
			var world := origin + basis * Vector3(point[0], 0, point[1])
			var from_y := 12.0 if last < 0.0 else last + 1.9
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(world + Vector3(0, from_y, 0), world + Vector3(0, -1, 0), WALK_MASK))
			var top: float = hit["position"].y if not hit.is_empty() else 0.0
			shape_query.transform = Transform3D(Basis.IDENTITY, Vector3(world.x, top + 0.9, world.z))
			if not space.intersect_shape(shape_query, 1).is_empty():
				failures.append("base %s: jogador não cabe em %s (y=%.2f)" % [spot[0], point, top])
			if last >= 0.0 and absf(top - last) > MAX_STEP:
				failures.append("base %s: degrau de %.2f m em %s" % [spot[0], top - last, point])
			last = top
	scene.queue_free()
	await process_frame
	for failure in failures.slice(0, 15):
		printerr(failure)
	print("PARKOUR DISTRICT: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
