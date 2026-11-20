extends Node
## Real offline scene: station pickup, weapon switching, pose, camera and cancel.
const Tools = preload("res://scripts/training_tools.gd")
const PointerMode = preload("res://scripts/pointer_mode.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
	else:
		print("ok: " + message)

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Net.in_match = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	var p: CharacterBody3D = main.get("player")
	var station: Node = main.get_node("TrainingTools")
	p.global_position = Tools.BOW_RACK + Vector3(0, 0.1, -1.2)
	await frames(3)
	check(station.call("_interact"), "E reaches the bow station")
	await frames(4)
	check(p.has_bow(), "offline station equips bow")
	var avatar: Node3D = p.get("humanoid_avatar")
	check(bool(avatar.get("bow_active")), "selected avatar holds Blender bow")
	var mesh: Node3D = avatar.get("_bow_model")
	check(mesh != null and mesh.visible, "equipped bow is visible")
	var bow: Node = p.get("bow_controller")
	PointerMode._touch = 1
	PointerMode.capture()
	Input.action_press("fire")
	var press := InputEventAction.new()
	press.action = "fire"
	press.pressed = true
	bow.call("_unhandled_input", press)
	await frames(15)
	check(bool(p.get("aiming")) and not bool(p.get("first_person_view")), "hold aims over the shoulder with visible avatar")
	check(int(bow.get("shots")) == 0, "holding does not shoot")
	bow.get("draw").advance(1.0)
	await frames(30)
	var rig: Skeleton3D = avatar.get("skeleton")
	var grip_helper = load("res://scripts/characters/swat_grip.gd")
	var head_bone: int = grip_helper._bone(rig, "Head")
	var right_bone: int = grip_helper._bone(rig, "RightHand")
	var right_arm: int = grip_helper._bone(rig, "RightArm")
	var head_pos := rig.get_bone_global_pose(head_bone).origin
	var right_pos := rig.get_bone_global_pose(right_bone).origin
	var aim_dir := (rig.to_local(p.call("crosshair_point")) - head_pos).normalized()
	var right_side := aim_dir.cross(Vector3.UP).normalized()
	check((right_pos - head_pos).dot(right_side) > 0.025 and right_pos.distance_to(head_pos) < 0.24, "right hand anchors on the right cheek instead of crossing behind the back")
	PointerMode.release()
	await frames(2)
	check(not bow.get("draw").drawing, "leaving gameplay cancels draw")
	Input.action_release("fire")
	var slot := InputEventAction.new()
	slot.action = "weapon_1"
	slot.pressed = true
	p.call("_unhandled_input", slot)
	await frames(3)
	check(not p.has_bow() and not bool(avatar.get("bow_active")), "firearm selection removes bow pose")
	station.call("_interact")
	await frames(2)
	check(p.has_bow(), "bow can be equipped again")
	station.call("_interact")
	await frames(2)
	check(not p.has_bow(), "E returns bow to its stand")
	print("BOW TRAINING: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
