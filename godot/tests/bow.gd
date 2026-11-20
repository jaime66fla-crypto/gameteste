extends SceneTree
## Input contract: no shot on press, exactly one on release, safe cancellation.
var failures := 0
var _tip_z: Array[float] = []
var _limb_z: Array[float] = []

func inspect_bow_mesh(node: Node3D, parent_transform: Transform3D = Transform3D.IDENTITY) -> void:
	var placement := parent_transform * node.transform
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for v in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = placement * v
				if absf(point.y) > 0.59:
					_tip_z.append(point.z)
				elif absf(point.y) > 0.35 and absf(point.y) < 0.45:
					_limb_z.append(point.z)
	for child in node.get_children():
		if child is Node3D:
			inspect_bow_mesh(child, placement)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
	else:
		print("ok: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ResourceLoader.exists("res://scripts/weapons/bow_draw.gd"):
		check(false, "bow draw/release behavior exists")
		quit(1)
		return
	var draw = load("res://scripts/weapons/bow_draw.gd").new()
	check(draw.release() == 0.0, "release without press does not fire")
	draw.press()
	draw.advance(0.5)
	check(draw.drawing and draw.charge > 0.0, "holding aims and draws without firing")
	check(draw.release() > 0.0, "release of a drawn bow fires")
	check(draw.release() == 0.0, "a second release cannot fire another arrow")
	draw.press()
	draw.advance(5.0)
	check(is_equal_approx(draw.charge, 1.0), "holding longer keeps full draw without auto firing")
	draw.cancel()
	check(draw.release() == 0.0 and not draw.drawing, "menu/focus cancellation prevents a delayed shot")
	draw.press()
	check(draw.release() == 0.0, "an accidental instant click cannot launch a charged arrow")
	var bow_mesh: Node3D = load("res://assets/weapons/bow/recurve_bow.glb").instantiate()
	inspect_bow_mesh(bow_mesh)
	var tips_back := not _tip_z.is_empty()
	for z in _tip_z:
		tips_back = tips_back and z < -0.02
	var limbs_front := not _limb_z.is_empty()
	for z in _limb_z:
		limbs_front = limbs_front and z > 0.04
	check(tips_back and limbs_front, "recurve limbs face the target with string tips toward the archer")
	bow_mesh.free()
	var p: Node = load("res://scripts/player.gd").new()
	root.add_child(p)
	await physics_frame
	var controller = load("res://scripts/weapons/bow_controller.gd").new()
	p.add_child(controller)
	controller.setup(p)
	controller.equip()
	check(controller.equipped and p.weapon_holstered and p.has_sights(), "equipping bow hides gun and enables its crosshair")
	check(p.bow_controller == controller, "player routes bow input through its controller")
	p.set_physics_process(false)
	var pointer = load("res://scripts/pointer_mode.gd")
	pointer._touch = 1
	pointer.capture()
	var press := InputEventAction.new()
	press.action = "fire"
	press.pressed = true
	var release := InputEventAction.new()
	release.action = "fire"
	release.pressed = false
	controller._unhandled_input(press)
	controller.draw.advance(0.6)
	check((controller.get_node("BowAudio/BowDraw") as AudioStreamPlayer).playing, "bow controller starts pull foley on trigger press")
	check(controller.shots == 0 and controller.draw.drawing, "actual trigger press holds aim without firing")
	controller._unhandled_input(release)
	check(controller.shots == 1, "actual trigger release launches exactly one arrow")
	check((controller.get_node("BowAudio/BowRelease") as AudioStreamPlayer).playing, "bow controller plays release foley when arrow launches")
	controller._unhandled_input(release)
	check(controller.shots == 1, "duplicate input release cannot fire twice")
	controller.draw.press()
	controller.draw.advance(0.6)
	p.attack_blocked = true
	controller._unhandled_input(release)
	check(controller.shots == 1 and not controller.draw.drawing, "blocked input cancels rather than firing")
	p.attack_blocked = false
	p.current_weapon = "sniper"
	p.aiming = true
	check(not p.is_scope_active(), "bow draw never opens a previously equipped sniper scope")
	p.aiming = false
	controller.unequip()
	check(not controller.equipped and not p.has_sights(), "putting bow away restores empty hands")
	# Sweep a fast arrow through a thin wall: it must stop rather than tunnel.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.02)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 2, -3)
	root.add_child(wall)
	# A muzzle past nearby cover must not launch from the far side of it.
	wall.position.z = -0.4
	p.position = Vector3.ZERO
	controller.equip()
	var active_avatar: Node3D = p.get("humanoid_avatar")
	var active_model: Node3D = active_avatar.get("_bow_model")
	active_model.global_position = Vector3(0, 1.35, -0.7)
	await physics_frame
	controller._fire(1.0)
	var cover_arrow: Node3D = root.get_child(root.get_child_count() - 1)
	check(cover_arrow.global_position.z > -0.4, "nearby cover cannot be bypassed by a bow tip beyond the wall")
	cover_arrow.free()
	controller.unequip()
	wall.position.z = -3.0
	p.position = Vector3(8, 0, 0)
	await physics_frame
	var arrow = load("res://scripts/weapons/bow_arrow.gd").new()
	root.add_child(arrow)
	arrow.launch(p, Vector3(0, 2, 0), Vector3(0, 0, -100), 55.0)
	for i in 12:
		await physics_frame
	check(arrow.stuck and arrow.global_position.z > -3.03, "fast arrow sticks in thin wall without tunneling")
	check(arrow.global_position.y < 2.0, "arrow flight follows gravity")
	arrow.free()
	wall.free()
	# Real training hitbox and dummy damage feedback (no replacement collider).
	var dummy: Node3D = load("res://scripts/training_dummy.gd").new()
	dummy.position = Vector3(0, 0, -5)
	root.add_child(dummy)
	for i in 5:
		await physics_frame
	var hit_arrow = load("res://scripts/weapons/bow_arrow.gd").new()
	root.add_child(hit_arrow)
	hit_arrow.launch(p, Vector3(0, 1.25, 0), Vector3(0, 0, -48), 55.0)
	for i in 16:
		await physics_frame
	check(dummy.hits == 1 and dummy.total > 0.0, "bow arrow damages the real training dummy once")
	hit_arrow.free()
	dummy.free()
	p.free()
	print("BOW: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
