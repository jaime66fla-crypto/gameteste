extends SceneTree
## Diagnóstico das mãos na postura de tiro: closes de 4 ângulos por arma e medidas
## do esqueleto (pulso no ponto de empunhadura, dobra do pulso, palma, cotovelo, mão dentro da arma).
## godot --path godot --script res://tools/characters/capture_hands.gd -- --id=atacante --out=C:/pasta/maos [--weapons=rifle,pistol]
const Registry = preload("res://scripts/characters/character_registry.gd")
const Grip = preload("res://scripts/characters/swat_grip.gd")
const SELECTION := "user://capture_hands_selection.cfg"
const VIEWS := {
	"direita": Vector3(1.0, 0.15, 0.0),
	"esquerda": Vector3(-1.0, 0.15, 0.1),
	"cima": Vector3(0.35, 1.0, 0.25),
	"baixo_frente": Vector3(0.45, -0.55, -1.0),
}

var player: CharacterBody3D
var out := "user://maos"


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): quit(2))
	_run.call_deferred()


func _run() -> void:
	var id := "atacante"
	var weapons := ["pistol", "smg", "rifle", "shotgun", "sniper"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="):
			id = arg.substr(5)
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--weapons="):
			weapons = arg.substr(10).split(",")
	Registry.storage_path = SELECTION
	if Registry.select_character(id) != OK:
		quit(1)
		return
	root.size = Vector2i(900, 900)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 30:
		await process_frame
	player = scene.get_node_or_null("Jaime") as CharacterBody3D
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 38
	for weapon in weapons:
		player.call("_equip_weapon", weapon)
		player.set("pitch", 0.0)
		for i in 70:
			await process_frame
		for n in root.find_children("*", "CanvasLayer", true, false):
			(n as CanvasLayer).visible = false
		var avatar = player.get("humanoid_avatar")
		var sk: Skeleton3D = avatar.get("skeleton")
		_report(weapon, avatar, sk)
		var rh := sk.to_global(sk.get_bone_global_pose(Grip._bone(sk, "RightHand")).origin)
		var lh := sk.to_global(sk.get_bone_global_pose(Grip._bone(sk, "LeftHand")).origin)
		var centre := (rh + lh) * 0.5
		var basis: Basis = player.global_basis
		for view in VIEWS:
			var d: Vector3 = (basis * VIEWS[view]).normalized()
			cam.global_position = centre + d * 0.62
			cam.look_at(centre, Vector3.UP if absf(d.y) < 0.95 else basis.z)
			cam.current = true
			await process_frame
			await process_frame
			root.get_texture().get_image().save_png("%s_%s_%s.png" % [out, weapon, view])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SELECTION))
	quit(0)


func _deg(a: float) -> String:
	return "%.0f°" % rad_to_deg(a)


func _report(weapon: String, avatar, sk: Skeleton3D) -> void:
	var mount: Node3D = avatar.get("weapon_mount")
	var gun: Node3D = avatar.get("bound_weapon")
	var barrel := -gun.global_basis.z.normalized()
	print("== %s (postura %.2f)" % [weapon, float(avatar.get("_stance"))])
	for side in ["Right", "Left"]:
		var hand := Grip._bone(sk, side + "Hand")
		var fore := Grip._bone(sk, side + "ForeArm")
		var arm := Grip._bone(sk, side + "Arm")
		var hp := sk.get_bone_global_pose(hand)
		var fp := sk.get_bone_global_pose(fore)
		var ap := sk.get_bone_global_pose(arm)
		var has_marker := mount.get_node_or_null(side + "Grip") != null and gun.get_node_or_null(side + "Grip") != null
		var err := -1.0
		if has_marker:
			err = hp.origin.distance_to(Grip.wrist_target(sk, mount, side))
		var forearm_dir := (hp.origin - fp.origin).normalized()
		var hand_dir := (hp.basis * sk.get_bone_rest(Grip._bone(sk, side + "HandMiddle1")).origin).normalized()
		var wrist_bend := forearm_dir.angle_to(hand_dir)
		# palma: normal = eixo Z local da mão no referencial calibrado (dedos x travessa)
		var across := hp.basis * (sk.get_bone_rest(Grip._bone(sk, side + "HandIndex1")).origin - sk.get_bone_rest(Grip._bone(sk, side + "HandPinky1")).origin)
		var palm_n := hand_dir.cross(across).normalized() * (1.0 if side == "Right" else -1.0)
		var reach := ap.origin.distance_to(hp.origin) / (sk.get_bone_rest(fore).origin.length() + sk.get_bone_rest(hand).origin.length())
		var elbow_out := (fp.origin - (ap.origin + hp.origin) * 0.5)
		var palm_w := sk.to_global(hp * Grip.palm_offset(sk, side))
		var gun_local := gun.global_transform.affine_inverse() * palm_w
		var aabb := _gun_aabb(gun)
		var inside := aabb.grow(-0.004).has_point(gun_local)
		if avatar.has_method("_stance_wrist") and float(avatar.get("_stance")) > 0.5:
			err = hp.origin.distance_to(avatar.call("_stance_wrist", side))
		# Eixos da arma no espaço do esqueleto: r (direita), u (cima), b (cano).
		var inv := sk.global_basis.orthonormalized().inverse()
		var b := (inv * -gun.global_basis.z).normalized()
		var u := inv * gun.global_basis.y
		u = (u - b * u.dot(b)).normalized()
		var r := b.cross(u).normalized()
		var m1 := sk.get_bone_global_pose(Grip._bone(sk, side + "HandMiddle1")).origin
		var m3 := sk.get_bone_global_pose(Grip._bone(sk, side + "HandMiddle3")).origin
		var i1 := sk.get_bone_global_pose(Grip._bone(sk, side + "HandIndex1")).origin
		var p1 := sk.get_bone_global_pose(Grip._bone(sk, side + "HandPinky1")).origin
		var fdir := (m1 - hp.origin).normalized()
		var curl := (m3 - m1)
		curl = (curl - fdir * curl.dot(fdir)).normalized()
		var idx := (i1 - p1)
		idx = (idx - fdir * idx.dot(fdir)).normalized()
		# Polegar fica do lado da palma: se o polegar está do lado para onde os dedos fecham, o fechamento é anatômico.
		var t2 := sk.get_bone_global_pose(Grip._bone(sk, side + "HandThumb2")).origin
		var thumb_side := (t2 - hp.origin).dot(curl)
		var rel := curl.dot(fdir.cross(idx))
		print("        dedos (r %.2f, u %.2f, b %.2f) | palma/fecha (r %.2f, u %.2f, b %.2f) | indicador (r %.2f, u %.2f, b %.2f) | polegar no lado da palma %.3f | fecha.(dedos x indic.) %.2f" % [
			fdir.dot(r), fdir.dot(u), fdir.dot(b), curl.dot(r), curl.dot(u), curl.dot(b), idx.dot(r), idx.dot(u), idx.dot(b), thumb_side, rel])
		print("  %-5s erro pulso %s | alcance %.0f%% | dobra pulso %s | dedos x cano %s | palma . cima %.2f | cotovelo (x %.2f, y %.2f) | palma dentro da arma: %s" % [
			side, ("%.3f m" % err) if err >= 0 else "sem marcador", reach * 100.0, _deg(wrist_bend),
			_deg(sk.global_basis * hand_dir if false else (sk.global_basis * hand_dir).angle_to(barrel)),
			(sk.global_basis * palm_n).dot(Vector3.UP), elbow_out.x, elbow_out.y, str(inside)])


func _gun_aabb(gun: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var inv := gun.global_transform.affine_inverse()
	for m in gun.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var a: AABB = mi.get_aabb()
		for i in 8:
			var p := inv * (mi.global_transform * a.get_endpoint(i))
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box
