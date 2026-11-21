extends SceneTree
## Compare complete gait cycles with an unarmed avatar, not one static pose.
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
	else:
		print("ok: " + message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var registry = load("res://scripts/characters/character_registry.gd")
	var a: Node3D = registry.create_visual(registry.load_selection())
	var reference: Node3D = registry.create_visual(registry.load_selection())
	root.add_child(a)
	root.add_child(reference)
	a.call("set_armed", false)
	reference.call("set_armed", false)
	a.call("set_bow_state", true, 0.0, false, Vector3(0, 1.5, -20))
	var rig: Skeleton3D = a.get("skeleton")
	var ref_rig: Skeleton3D = reference.get("skeleton")
	var grip = load("res://scripts/characters/swat_grip.gd")
	var left: int = grip._bone(rig, "LeftHand")
	var right: int = grip._bone(rig, "RightHand")
	for gait in ["idle", "walk", "run"]:
		var natural_arms := true
		var attached := true
		var min_z := INF
		var max_z := -INF
		var min_hand_z := INF
		var max_hand_z := -INF
		var downward_sum := 0.0
		for i in 150:
			var amount := 0.0 if gait == "idle" else 1.0
			var speed := 0.0 if gait == "idle" else (5.0 if gait == "run" else 1.6)
			for actor in [a, reference]:
				actor.call("animate", 1.0 / 60.0, amount, gait == "run", false, false, false, false, Vector2(0, -1), Vector3(0, 0, speed))
			if i < 30:
				continue
			for suffix in ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]:
				var bone: int = grip._bone(rig, suffix)
				var ref_bone: int = grip._bone(ref_rig, suffix)
				var actual := rig.get_bone_global_pose(bone)
				var expected := ref_rig.get_bone_global_pose(ref_bone)
				natural_arms = natural_arms and actual.origin.distance_to(expected.origin) < 0.003
				natural_arms = natural_arms and actual.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion()) < 0.025
			var hand := rig.get_bone_global_pose(left).origin
			var bow: Node3D = a.get("_bow_model")
			attached = attached and bow.position.distance_to(hand) < 0.16
			min_z = minf(min_z, bow.position.z)
			max_z = maxf(max_z, bow.position.z)
			min_hand_z = minf(min_hand_z, hand.z)
			max_hand_z = maxf(max_hand_z, hand.z)
			downward_sum += bow.basis.z.normalized().dot(Vector3.DOWN)
		check(natural_arms, gait + ": both arms retain the original unarmed animation")
		check(attached, gait + ": bow stays in the animated left hand")
		if gait != "idle":
			check(max_hand_z - min_hand_z > 0.12 and max_z - min_z > 0.12, gait + ": hand and bow visibly swing throughout the stride")
		else:
			check(downward_sum / 120.0 > 0.35, "resting carry points down with a relaxed wrist")
	var model: Node3D = a.get("_bow_model")
	check(not (model.get("_arrow") as Node3D).visible, "carry keeps arrow put away")
	a.call("set_bow_state", true, 1.0, true, Vector3(0, 1.5, -20))
	for i in 60:
		a.call("animate", 1.0 / 60.0, 0.0, false, false, true, false, false)
	var head := rig.get_bone_global_pose(grip._bone(rig, "Head")).origin
	var hand := rig.get_bone_global_pose(right).origin
	var direction := (rig.to_local(Vector3(0, 1.5, -20)) - head).normalized()
	check(hand.distance_to(head) < 0.24 and (hand - head).dot(direction.cross(Vector3.UP)) > 0.025, "drawing keeps the approved right-cheek anchor")
	check((model.get("_arrow") as Node3D).visible, "drawing nocks the arrow again")
	a.free()
	reference.free()
	print("BOW CARRY: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
