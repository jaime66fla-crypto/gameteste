extends SceneTree
## Body-part hitboxes on online actors, and third-person shot direction.
## godot --headless --path godot --script res://tests/hitboxes.gd
const NetActorScript = preload("res://scripts/net/net_actor.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
var failures: Array[String] = []

class Target extends StaticBody3D:
	var damage := 0.0
	func take_damage(amount: float) -> void:
		damage += amount

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _zone_at(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> String:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, HitboxScript.SHOT_MASK))
	if hit.is_empty():
		return ""
	return str(hit["collider"].get("zone")) if hit["collider"] is HitboxScript else "world"

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Jaime")
	player.set_physics_process(false)
	# An actor standing on the clear avenue, facing +Z (toward the probe rays).
	var actor: CharacterBody3D = NetActorScript.new()
	actor.call("setup", "probe", "Alvo", false)
	actor.position = Vector3(0, 0, 20)
	actor.rotation.y = PI
	scene.add_child(actor)
	await _frames(20)
	var space := actor.get_world_3d().direct_space_state
	var base := actor.global_position
	var front := Vector3(0, 0, 3)
	_check((actor.get("hitboxes") as Array).size() >= 12, "Actor needs head, torso, arm and leg hitboxes")
	# Probe the body from the front at several heights (x = body centre line).
	_check(_zone_at(space, base + Vector3(0, 1.68, 3), base + Vector3(0, 1.68, -3)) == "head", "Head height must hit the head zone")
	var chest := _zone_at(space, base + Vector3(0, 1.32, 3), base + Vector3(0, 1.32, -3))
	_check(chest == "chest" or chest == "arm", "Chest height must hit the torso (got %s)" % chest)
	var hips := _zone_at(space, base + Vector3(0, 0.98, 3), base + Vector3(0, 0.98, -3))
	_check(hips == "pelvis" or hips == "arm", "Hip height must hit the pelvis (got %s)" % hips)
	_check(_zone_at(space, base + Vector3(-0.12, 0.45, 3), base + Vector3(-0.12, 0.45, -3)) == "leg" or _zone_at(space, base + Vector3(0.12, 0.45, 3), base + Vector3(0.12, 0.45, -3)) == "leg", "Shin height must hit a leg")
	# Gaps that the old fat capsule (r = 0.34) used to count as hits.
	# The rifle stance crosses the legs, so probe just outside them instead.
	var outside := _zone_at(space, base + Vector3(0.4, 0.45, 3), base + Vector3(0.4, 0.45, -3))
	_check(outside == "", "Air beside the legs must not hit (got %s)" % outside)
	# Body is centred on the character origin (no animation drift).
	var hips_ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3(3, 0.98, 0), base + Vector3(-3, 0.98, 0), HitboxScript.SHOT_MASK))
	_check(not hips_ray.is_empty() and absf((hips_ray["position"] as Vector3).z - base.z) < 0.25, "Visible body must stay centred on the actor origin")
	_check(_zone_at(space, base + Vector3(0.45, 1.5, 3), base + Vector3(0.45, 1.5, -3)) == "", "Air beside the shoulder must not hit")
	_check(_zone_at(space, base + Vector3(0, 2.0, 3), base + Vector3(0, 2.0, -3)) == "", "Above the head must not hit")
	# The movement capsule is invisible to bullets.
	var capsule_only := space.intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3(0.3, 1.0, 3), base + Vector3(0.3, 1.0, -3), HitboxScript.LAYER_CHARACTERS))
	_check(not capsule_only.is_empty(), "Movement capsule still exists for walking collisions")
	# Hit reporting: zone, point and weapon reach the match layer.
	var reports: Array = []
	actor.connect("damaged", func(id, zone, point, normal, weapon): reports.append([id, zone, weapon]))
	var head_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3(0, 1.68, 3), base + Vector3(0, 1.68, -3), HitboxScript.SHOT_MASK))
	head_hit["collider"].call("take_hit", 27.0, head_hit["position"], head_hit["normal"], "rifle")
	_check(reports.size() == 1 and reports[0][1] == "head" and reports[0][2] == "rifle", "Hitbox must report zone and weapon")
	# Dead actors stop absorbing bullets.
	actor.call("die")
	await _frames(2)
	_check(_zone_at(space, base + Vector3(0, 1.32, 3), base + Vector3(0, 1.32, -3)) == "", "Dead actor hitboxes must be disabled")

	# Third-person direction: a wall between the shoulder camera and the
	# player must not swallow a shot aimed at a target in front.
	player.position = Vector3(0, 0.1, -20)
	player.set("yaw", 0.0)
	player.set("pitch", 0.0)
	player.rotation.y = 0.0
	player.set_physics_process(true)
	await _frames(30)
	player.set_physics_process(false)
	var camera: Camera3D = player.get("camera")
	var forward := -camera.global_basis.z
	var behind := StaticBody3D.new()
	var behind_shape := CollisionShape3D.new()
	var behind_box := BoxShape3D.new()
	behind_box.size = Vector3(3, 3, 0.2)
	behind_shape.shape = behind_box
	behind.add_child(behind_shape)
	scene.add_child(behind)
	# Halfway between camera and player, across the aim line.
	behind.global_transform = Transform3D(camera.global_basis, camera.global_position + forward * (camera.global_position.distance_to(player.global_position + Vector3(0, 1.4, 0)) * 0.5))
	var target := Target.new()
	var target_shape := CollisionShape3D.new()
	var target_box := BoxShape3D.new()
	target_box.size = Vector3(2.5, 2.5, 0.4)
	target_shape.shape = target_box
	target.add_child(target_shape)
	scene.add_child(target)
	target.global_position = camera.global_position + forward * 18.0
	await _frames(2)
	player.call("_shoot")
	_check(target.damage > 0.0, "Shot must reach the target the crosshair is on, not a wall behind the player")
	scene.queue_free()
	await process_frame
	for failure in failures:
		printerr(failure)
	print("HITBOXES: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
