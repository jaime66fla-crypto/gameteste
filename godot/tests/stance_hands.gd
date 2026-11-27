extends SceneTree
## Mãos na postura de tiro (downloaded_avatar.gd: _stance_hands), para cada arma de fogo:
## - os dois pulsos chegam ao ponto calculado (erro < 1 cm);
## - braço de apoio com folga (cotovelo não trava reto) e o do gatilho não estica além do limite;
## - pulso sem quebrar (dobra entre antebraço e mão <= 55°);
## - mão do gatilho fecha para o punho (palma para a esquerda da arma);
## - arma longa: mão de apoio por baixo, palma para cima; pistola: palma de apoio para a mão do gatilho.
const Grip = preload("res://scripts/characters/swat_grip.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print(("ok: " if ok else "FALHOU: ") + message)
	if not ok:
		failures.append(message)

func _run() -> void:
	var registry = load("res://scripts/characters/character_registry.gd")
	registry.storage_path = "user://stance_hands_%s.cfg" % OS.get_process_id()
	registry.select_character("atacante")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var player: Node3D = load("res://scripts/player.gd").new()
	scene.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(0, 20, 0)
	var avatar: Node3D = player.get("humanoid_avatar")
	for weapon in ["pistol", "smg", "rifle", "shotgun", "sniper"]:
		player.call("_equip_weapon", weapon)
		avatar.call("set_weapon_ready", true)
		avatar.call("set_aim_target", player.global_position + Vector3(0, 1.5, -30), true)
		for frame in range(60):
			avatar.animate(1.0 / 60.0, 0.0, false, false, true, false, false)
		var sk: Skeleton3D = avatar.get("skeleton")
		var gun: Node3D = avatar.get("bound_weapon")
		_check(float(avatar.get("_stance")) > 0.99, "%s: na postura de tiro" % weapon)
		var inv := sk.global_basis.orthonormalized().inverse()
		var b := (inv * -gun.global_basis.z).normalized()
		var u := inv * gun.global_basis.y
		u = (u - b * u.dot(b)).normalized()
		var r := b.cross(u).normalized()
		for side in ["Right", "Left"]:
			var hand := Grip._bone(sk, side + "Hand")
			var fore := Grip._bone(sk, side + "ForeArm")
			var arm := Grip._bone(sk, side + "Arm")
			var hp := sk.get_bone_global_pose(hand)
			var fp := sk.get_bone_global_pose(fore)
			var ap := sk.get_bone_global_pose(arm)
			var err: float = hp.origin.distance_to(avatar.call("_stance_wrist", side))
			_check(err < 0.01, "%s %s: pulso no ponto da empunhadura (%.3f m)" % [weapon, side, err])
			var reach := ap.origin.distance_to(hp.origin) / (sk.get_bone_rest(fore).origin.length() + sk.get_bone_rest(hand).origin.length())
			var max_reach: float = 0.9 if side == "Left" else 0.98
			_check(reach <= max_reach, "%s %s: braço com folga (%.0f%%)" % [weapon, side, reach * 100.0])
			var m1 := sk.get_bone_global_pose(Grip._bone(sk, side + "HandMiddle1")).origin
			var m3 := sk.get_bone_global_pose(Grip._bone(sk, side + "HandMiddle3")).origin
			var fdir := (m1 - hp.origin).normalized()
			var bend := rad_to_deg((hp.origin - fp.origin).normalized().angle_to(fdir))
			_check(bend <= 55.0, "%s %s: pulso sem quebrar (%.0f°)" % [weapon, side, bend])
			var curl := m3 - m1
			curl = (curl - fdir * curl.dot(fdir)).normalized()
			if side == "Right":
				_check(curl.dot(r) < -0.5, "%s: mão do gatilho fecha para o punho (%.2f)" % [weapon, curl.dot(r)])
			elif weapon == "pistol":
				_check(curl.dot(r) > 0.5, "pistol: mão de apoio voltada para a mão do gatilho (%.2f)" % curl.dot(r))
			else:
				_check(curl.dot(u) > 0.7, "%s: mão de apoio por baixo, palma para cima (%.2f)" % [weapon, curl.dot(u)])
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
	print("STANCE HANDS: ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
