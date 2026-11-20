extends SceneTree
## Remy (modelado no Blender, rig Ch31 "mixamorig9_") no adaptador compartilhado e na rede.
## godot --headless --path godot --script res://tests/remy_character.gd
const Registry = preload("res://scripts/characters/character_registry.gd")
const NetActorScript = preload("res://scripts/net/net_actor.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
var failures: Array[String] = []

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
	_check(Registry.definition("remy") != null, "Remy must be in the catalog")
	_check(Registry.is_available("remy"), "Remy resources must exist")
	# --- adapter: model, bones, clips ---------------------------------------
	var visual := Registry.create_visual("remy")
	root.add_child(visual)
	await _frames(1)
	_check(bool(visual.call("is_visual_ready")), "Remy visual must be ready")
	var skeleton := visual.get("skeleton") as Skeleton3D
	var player := visual.get("animation_player") as AnimationPlayer
	var prefix := str(visual.get("bone_prefix"))
	_check(prefix == "mixamorig9_", "Remy must share the Ch31 rig (prefix %s)" % prefix)
	var head := skeleton.find_bone(prefix + "HeadTop_End")
	var top := (skeleton.global_transform * skeleton.get_bone_global_rest(head).origin).y
	_check(absf(top - 1.78) < 0.08, "Head top must be near 1.78 m (got %.2f)" % top)
	var expected := ["run_in_place", "idle_with_rifle", "walk_with_rifle", "run_to_stop", "punch", "elbow_punch", "idle_unarmed", "walk_unarmed", "jog_unarmed_left", "walk_unarmed_backward_right"]
	for clip_name in expected:
		_check(player.has_animation(clip_name), "Missing clip " + clip_name)
	var broken := 0
	var root_node := player.get_node(player.root_node)
	for clip_name in player.get_animation_list():
		var clip := player.get_animation(clip_name)
		for t in clip.get_track_count():
			var path := clip.track_get_path(t)
			var node := root_node.get_node_or_null(NodePath(String(path).get_slice(":", 0)))
			if node != skeleton or skeleton.find_bone(String(path).get_slice(":", 1)) < 0:
				broken += 1
	_check(broken == 0, "Every clip track must target a Remy bone (%d broken)" % broken)
	# Walking for a while keeps the body over the origin and the feet on the ground.
	visual.call("set_armed", false)
	for i in 90:
		visual.call("animate", 1.0 / 60.0, 0.5, false, false, false, false, false, Vector2(0, -1), Vector3(0, 0, -1.4))
		await process_frame
	var hips := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(prefix + "Hips")).origin
	_check(Vector2(hips.x, hips.z).length() < 0.2, "Hips must stay over the origin while walking")
	var lowest := INF
	for side in ["Left", "Right"]:
		var toe := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(prefix + "%sToeBase" % side)).origin
		lowest = minf(lowest, toe.y)
	_check(lowest > -0.05 and lowest < 0.12, "A foot must touch the ground while walking (lowest toe %.2f)" % lowest)
	visual.queue_free()
	# --- network: a remote player that picked Remy ----------------------------
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	(scene.get_node("Jaime") as Node).set_physics_process(false)
	var actor: CharacterBody3D = NetActorScript.new()
	actor.call("setup", "probe", "Alvo", false)
	actor.position = Vector3(0, 0, 20)
	actor.rotation.y = PI
	scene.add_child(actor)
	await _frames(5)
	_check(str(actor.get("character_id")) == Registry.DEFAULT_ID, "Players start with the default body")
	actor.call("apply_state", {"p": [0.0, 0.0, 20.0], "y": PI, "w": "rifle", "h": false, "ch": "remy"})
	await _frames(20)
	_check(str(actor.get("character_id")) == "remy", "State 'ch' must switch the body to Remy")
	_check((actor.get("visual") as Node).get_script() == load("res://scripts/characters/remy_avatar.gd"), "Visual must be the Remy adapter")
	var bodies: Array = actor.get("hitboxes")
	_check(bodies.size() >= 12, "Remy needs head, torso, arm and leg hitboxes (got %d)" % bodies.size())
	var alive := 0
	for body in bodies:
		alive += 1 if is_instance_valid(body) else 0
	_check(alive == bodies.size(), "Hitbox list must only hold the new body's hitboxes")
	var space := actor.get_world_3d().direct_space_state
	var base := actor.global_position
	_check(_zone_at(space, base + Vector3(0, 1.66, 3), base + Vector3(0, 1.66, -3)) == "head", "Head height must hit Remy's head")
	var chest := _zone_at(space, base + Vector3(0, 1.32, 3), base + Vector3(0, 1.32, -3))
	_check(chest == "chest" or chest == "arm", "Chest height must hit Remy's torso (got %s)" % chest)
	_check(_zone_at(space, base + Vector3(0, 2.0, 3), base + Vector3(0, 2.0, -3)) == "", "Above Remy's head must not hit")
	_check(actor.get("weapon_model") != null and is_instance_valid(actor.get("weapon_model")), "Gun must be re-bound to the new body")
	actor.call("apply_state", {"p": [0.0, 0.0, 20.0], "y": PI, "ch": "nao_existe"})
	await _frames(2)
	_check(str(actor.get("character_id")) == "remy", "Unknown character ids keep the current body")
	# --- bots: stable pick from the id, same on every client --------------------
	var picks := {}
	for i in 40:
		var id := "bot%d" % i
		var pick: String = NetActorScript.bot_character(id)
		_check(pick == NetActorScript.bot_character(id), "Bot pick must be deterministic")
		picks[pick] = true
	_check(picks.has("remy") and picks.has(Registry.DEFAULT_ID), "Bots must use every available character")
	scene.queue_free()
	await process_frame
	for failure in failures:
		printerr(failure)
	print("REMY CHARACTER: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
