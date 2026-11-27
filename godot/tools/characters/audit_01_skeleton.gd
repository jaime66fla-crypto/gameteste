extends SceneTree
## Auditoria do esqueleto do 01 (Zero One) contra o Ch31 (rig onde os clipes
## foram feitos), o SkeletonProfileHumanoid do Godot e os nomes do Mixamo.
## Gera um JSON com ossos, rest pose, proporções, malhas/skins e o erro de
## direção dos membros quando os clipes rodam no 01 (cópia direta de rotação).
## godot --headless --path godot --script res://tools/characters/audit_01_skeleton.gd -- --out=C:/pasta/audit.json
const MODEL_01 := "res://assets/personagens/01/01_modelo.scn"
const MODEL_CH31 := "res://assets/personagens/downloaded/avatar.fbx"
const Avatar = preload("res://scripts/characters/downloaded_avatar.gd")

## Mixamo (sem prefixo) -> SkeletonProfileHumanoid.
const PROFILE_MAP := {
	"Hips": "Hips", "Spine": "Spine", "Spine1": "Chest", "Spine2": "UpperChest", "Neck": "Neck", "Head": "Head",
	"LeftEye": "LeftEye", "RightEye": "RightEye",
	"LeftShoulder": "LeftShoulder", "LeftArm": "LeftUpperArm", "LeftForeArm": "LeftLowerArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightArm": "RightUpperArm", "RightForeArm": "RightLowerArm", "RightHand": "RightHand",
	"LeftUpLeg": "LeftUpperLeg", "LeftLeg": "LeftLowerLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToes",
	"RightUpLeg": "RightUpperLeg", "RightLeg": "RightLowerLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToes",
	"LeftHandThumb1": "LeftThumbMetacarpal", "LeftHandThumb2": "LeftThumbProximal", "LeftHandThumb3": "LeftThumbDistal",
	"LeftHandIndex1": "LeftIndexProximal", "LeftHandIndex2": "LeftIndexIntermediate", "LeftHandIndex3": "LeftIndexDistal",
	"LeftHandMiddle1": "LeftMiddleProximal", "LeftHandMiddle2": "LeftMiddleIntermediate", "LeftHandMiddle3": "LeftMiddleDistal",
	"LeftHandRing1": "LeftRingProximal", "LeftHandRing2": "LeftRingIntermediate", "LeftHandRing3": "LeftRingDistal",
	"LeftHandPinky1": "LeftLittleProximal", "LeftHandPinky2": "LeftLittleIntermediate", "LeftHandPinky3": "LeftLittleDistal",
	"RightHandThumb1": "RightThumbMetacarpal", "RightHandThumb2": "RightThumbProximal", "RightHandThumb3": "RightThumbDistal",
	"RightHandIndex1": "RightIndexProximal", "RightHandIndex2": "RightIndexIntermediate", "RightHandIndex3": "RightIndexDistal",
	"RightHandMiddle1": "RightMiddleProximal", "RightHandMiddle2": "RightMiddleIntermediate", "RightHandMiddle3": "RightMiddleDistal",
	"RightHandRing1": "RightRingProximal", "RightHandRing2": "RightRingIntermediate", "RightHandRing3": "RightRingDistal",
	"RightHandPinky1": "RightLittleProximal", "RightHandPinky2": "RightLittleIntermediate", "RightHandPinky3": "RightLittleDistal",
}
## Segmentos medidos (de -> até), em metros já na escala de 1,8 m do jogo.
const SEGMENTS := {
	"braço (Arm->ForeArm)": ["LeftArm", "LeftForeArm"], "antebraço (ForeArm->Hand)": ["LeftForeArm", "LeftHand"],
	"coxa (UpLeg->Leg)": ["LeftUpLeg", "LeftLeg"], "canela (Leg->Foot)": ["LeftLeg", "LeftFoot"],
	"pescoço (Neck->Head)": ["Neck", "Head"], "tronco (Hips->Neck)": ["Hips", "Neck"],
	"ombros (LeftArm<->RightArm)": ["LeftArm", "RightArm"], "quadril (LeftUpLeg<->RightUpLeg)": ["LeftUpLeg", "RightUpLeg"],
	"altura do quadril (chão->Hips)": ["", "Hips"],
}
## Ossos cujo erro de direção nos clipes é medido (osso -> filho que dá a direção).
const LIMBS := {
	"Spine": "Spine1", "Spine2": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "LeftHand": "LeftHandMiddle1",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand", "RightHand": "RightHandMiddle1",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase",
}
const CLIPS := ["idle_unarmed", "walk_unarmed", "jog_unarmed", "run_in_place", "idle_with_rifle", "walk_with_rifle"]

var out_path := "user://audit_01.json"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	call_deferred("_run")

func _run() -> void:
	var a01 = _avatar(MODEL_01, 1.858)
	var ach = _avatar(MODEL_CH31, 1.782)
	root.add_child(a01)
	root.add_child(ach)
	await process_frame
	var s01: Skeleton3D = a01.get("skeleton")
	var sch: Skeleton3D = ach.get("skeleton")
	var p01 := str(a01.get("bone_prefix"))
	var pch := str(ach.get("bone_prefix"))
	var report := {
		"godot": Engine.get_version_info().string,
		"ready_01": a01.get("ready_ok"), "ready_ch31": ach.get("ready_ok"),
		"prefix_01": p01, "prefix_ch31": pch,
		"scale_01": (a01.get_node("Avatar") as Node3D).scale.x, "scale_ch31": (ach.get_node("Avatar") as Node3D).scale.x,
		"bone_count_01": s01.get_bone_count(), "bone_count_ch31": sch.get_bone_count(),
		"skeleton_path_01": str(a01.get_path_to(s01)),
		"bones": [], "profile": [], "segments": {}, "meshes": [], "clips": {}, "rest_global_dirs": {},
	}
	# Ossos: hierarquia, rest local, comparação com o Ch31.
	for i in s01.get_bone_count():
		var name := s01.get_bone_name(i)
		var suffix := name.trim_prefix(p01)
		var parent := s01.get_bone_parent(i)
		var rest := s01.get_bone_rest(i)
		var entry := {
			"i": i, "name": name, "suffix": suffix, "parent": s01.get_bone_name(parent) if parent >= 0 else "",
			"depth": _depth(s01, i), "origin": _v(rest.origin), "euler_deg": _v(rest.basis.get_euler() * (180.0 / PI)),
			"length": _length(s01, i),
		}
		var j := sch.find_bone(pch + suffix)
		if j >= 0:
			var rch := sch.get_bone_rest(j)
			entry["rest_rot_diff_deg"] = rad_to_deg(rest.basis.get_rotation_quaternion().angle_to(rch.basis.get_rotation_quaternion()))
			var gch := sch.get_bone_global_rest(j).basis.get_rotation_quaternion()
			var g01 := s01.get_bone_global_rest(i).basis.get_rotation_quaternion()
			entry["global_rest_rot_diff_deg"] = rad_to_deg(g01.angle_to(gch))
			entry["length_ch31"] = _length(sch, j)
			var pj := sch.get_bone_parent(j)
			entry["parent_ch31"] = sch.get_bone_name(pj).trim_prefix(pch) if pj >= 0 else ""
		else:
			entry["missing_in_ch31"] = true
		report["bones"].append(entry)
	for i in sch.get_bone_count():
		var suffix := sch.get_bone_name(i).trim_prefix(pch)
		if s01.find_bone(p01 + suffix) < 0:
			report.get_or_add("missing_in_01", []).append(suffix)
	# Perfil humanoide do Godot.
	var profile := SkeletonProfileHumanoid.new()
	var inverse := {}
	for k in PROFILE_MAP:
		inverse[PROFILE_MAP[k]] = k
	for b in profile.bone_size:
		var pname := profile.get_bone_name(b)
		var mixamo: String = inverse.get(pname, "")
		report["profile"].append({"profile": pname, "group": profile.get_group(b), "mixamo": mixamo,
			"found": mixamo != "" and s01.find_bone(p01 + mixamo) >= 0, "required": profile.is_required(b)})
	# Proporções (escala do jogo).
	var k01: float = report["scale_01"]
	var kch: float = report["scale_ch31"]
	for label in SEGMENTS:
		var pair: Array = SEGMENTS[label]
		report["segments"][label] = {"01": _segment(s01, p01, pair) * k01, "ch31": _segment(sch, pch, pair) * kch}
	# Direção global de repouso (T-pose esperada: braços em ±X, pernas em -Y).
	for bone in ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm", "LeftUpLeg", "LeftLeg", "Spine", "Neck"]:
		var child: String = LIMBS.get(bone, "")
		report["rest_global_dirs"][bone] = {
			"01": _v(_dir_rest(s01, p01, bone, child)), "ch31": _v(_dir_rest(sch, pch, bone, child))}
	# Malhas e skins: roupas no mesmo esqueleto? bind pose bate com o rest?
	for mesh in a01.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var info := {"name": mi.name, "skeleton_ok": skel == s01, "surfaces": mi.mesh.get_surface_count() if mi.mesh else 0,
			"binds": mi.skin.get_bind_count() if mi.skin else 0, "visible": mi.visible}
		if mi.skin and skel:
			var worst := 0.0
			var worst_bone := ""
			for b in mi.skin.get_bind_count():
				var bname := str(mi.skin.get_bind_name(b))
				var bi := skel.find_bone(bname) if bname != "" else mi.skin.get_bind_bone(b)
				if bi < 0:
					info.get_or_add("unknown_binds", []).append(bname)
					continue
				var expected := skel.get_bone_global_rest(bi).affine_inverse()
				var bind := mi.skin.get_bind_pose(b)
				var d := (expected.origin - bind.origin).length() + rad_to_deg(expected.basis.get_rotation_quaternion().angle_to(bind.basis.get_rotation_quaternion())) * 0.01
				if d > worst:
					worst = d
					worst_bone = bname
			info["bind_vs_rest_worst"] = worst
			info["bind_vs_rest_bone"] = worst_bone
		report["meshes"].append(info)
		if mi.name == "01" and mi.skin and skel:
			report["joint_vs_mesh"] = _joint_vs_mesh(mi, skel, p01, k01)
	# Clipes: rotações copiadas para o 01 vs o mesmo clipe no Ch31.
	var ap01: AnimationPlayer = a01.get("animation_player")
	var apch: AnimationPlayer = ach.get("animation_player")
	report["clip_list_01"] = Array(ap01.get_animation_list())
	for clip_name in CLIPS:
		if not ap01.has_animation(clip_name) or not apch.has_animation(clip_name):
			continue
		var c01 := ap01.get_animation(clip_name)
		var cch := apch.get_animation(clip_name)
		var per_bone := {}
		var samples := 12
		var foot_min := 99.0
		for n in samples:
			var t := c01.length * n / samples
			_apply(s01, c01, t)
			_apply(sch, cch, t)
			for bone in LIMBS:
				var e := rad_to_deg(_dir_pose(s01, p01, bone, LIMBS[bone]).angle_to(_dir_pose(sch, pch, bone, LIMBS[bone])))
				per_bone[bone] = maxf(per_bone.get(bone, 0.0), e)
			# Pé mais baixo em relação ao chão de repouso (negativo = atravessa).
			for foot in ["LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"]:
				var fi := s01.find_bone(p01 + foot)
				if fi >= 0:
					foot_min = minf(foot_min, (s01.get_bone_global_pose(fi).origin.y - s01.get_bone_global_rest(fi).origin.y) * k01)
			# Cotovelo/joelho: ângulo entre segmentos (180 = reto).
			for chain in [["LeftArm", "LeftForeArm", "LeftHand"], ["RightArm", "RightForeArm", "RightHand"], ["LeftUpLeg", "LeftLeg", "LeftFoot"], ["RightUpLeg", "RightLeg", "RightFoot"]]:
				var key := "joint_" + str(chain[1])
				var ang := _joint_angle(s01, p01, chain)
				var rng: Array = per_bone.get(key, [999.0, -999.0])
				per_bone[key] = [minf(rng[0], ang), maxf(rng[1], ang)]
		per_bone["foot_drop_m"] = foot_min
		# Mesmo clipe no Ch31: quanto o pé dele desce (referência) e torção da mão
		# (eixo indicador->mindinho) e do pé (eixo dedão) do 01 contra o Ch31.
		var foot_min_ch := 99.0
		var twist := {}
		for n in samples:
			var t := c01.length * n / samples
			_apply(s01, c01, t)
			_apply(sch, cch, t)
			for foot in ["LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"]:
				var fc := sch.find_bone(pch + foot)
				if fc >= 0:
					foot_min_ch = minf(foot_min_ch, (sch.get_bone_global_pose(fc).origin.y - sch.get_bone_global_rest(fc).origin.y) * kch)
			for side in ["Left", "Right"]:
				var e := rad_to_deg(_dir_pose(s01, p01, side + "HandIndex1", side + "HandPinky1").angle_to(_dir_pose(sch, pch, side + "HandIndex1", side + "HandPinky1")))
				twist[side + "Hand"] = maxf(twist.get(side + "Hand", 0.0), e)
				# Joelho: dobra para a frente (+Z do Mixamo)? componente Z do joelho
				# em relação à linha quadril->tornozelo.
				var hip := s01.get_bone_global_pose(s01.find_bone(p01 + side + "UpLeg")).origin
				var knee := s01.get_bone_global_pose(s01.find_bone(p01 + side + "Leg")).origin
				var ankle := s01.get_bone_global_pose(s01.find_bone(p01 + side + "Foot")).origin
				var off := knee.z - (hip.z + ankle.z) * 0.5
				twist[side + "KneeForwardMin"] = minf(twist.get(side + "KneeForwardMin", 99.0), off * k01)
		per_bone["foot_drop_ch31_m"] = foot_min_ch
		per_bone["twist"] = twist
		report["clips"][clip_name] = per_bone
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("AUDIT 01: ", out_path)
	quit()

## Onde a malha "dobra": vértices divididos entre o osso de cima e o de baixo
## (ambos com peso >= 0,3) ficam na articulação. Compara o centro deles com a
## posição do osso de baixo (cotovelo, punho, joelho, tornozelo), em metros.
func _joint_vs_mesh(mi: MeshInstance3D, skel: Skeleton3D, prefix: String, k: float) -> Dictionary:
	const JOINTS := {"cotovelo E": ["LeftArm", "LeftForeArm"], "punho E": ["LeftForeArm", "LeftHand"],
		"cotovelo D": ["RightArm", "RightForeArm"], "punho D": ["RightForeArm", "RightHand"],
		"joelho E": ["LeftUpLeg", "LeftLeg"], "tornozelo E": ["LeftLeg", "LeftFoot"],
		"joelho D": ["RightUpLeg", "RightLeg"], "tornozelo D": ["RightLeg", "RightFoot"],
		"ombro E": ["LeftShoulder", "LeftArm"], "pescoço": ["Spine2", "Neck"], "cabeça": ["Neck", "Head"]}
	# bind index -> bone index
	var bind_bone := {}
	for b in mi.skin.get_bind_count():
		var bname := str(mi.skin.get_bind_name(b))
		bind_bone[b] = skel.find_bone(bname) if bname != "" else mi.skin.get_bind_bone(b)
	var sums := {}
	var mesh := mi.mesh as ArrayMesh
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if bones == null or weights == null or verts.is_empty():
			continue
		var per := int(bones.size() / verts.size())
		for v in verts.size():
			var w := {}
			for n in per:
				var wt: float = weights[v * per + n]
				if wt > 0.0:
					var bi: int = bind_bone.get(int(bones[v * per + n]), -1)
					if bi >= 0:
						w[skel.get_bone_name(bi).trim_prefix(prefix)] = w.get(skel.get_bone_name(bi).trim_prefix(prefix), 0.0) + wt
			for label in JOINTS:
				var pair: Array = JOINTS[label]
				if w.get(pair[0], 0.0) >= 0.3 and w.get(pair[1], 0.0) >= 0.3:
					var s: Array = sums.get(label, [Vector3.ZERO, 0])
					sums[label] = [s[0] + verts[v], s[1] + 1]
	var result := {}
	for label in JOINTS:
		var lower := skel.find_bone(prefix + str(JOINTS[label][1]))
		var joint := (mi.transform * skel.get_bone_global_rest(lower)).origin if lower >= 0 else Vector3.ZERO
		if not sums.has(label):
			result[label] = {"vertices": 0}
			continue
		var center: Vector3 = sums[label][0] / float(sums[label][1])
		var upper := skel.find_bone(prefix + str(JOINTS[label][0]))
		var axis := (joint - (mi.transform * skel.get_bone_global_rest(upper)).origin).normalized()
		result[label] = {"vertices": sums[label][1], "offset_m": (center - joint).length() * k,
			"along_bone_m": (center - joint).dot(axis) * k, "joint": _v(joint * k), "mesh_bend": _v(center * k)}
	return result

func _avatar(path: String, height: float) -> Node3D:
	var a: Node3D = Avatar.new()
	a.set("model_path", path)
	a.set("source_height", height)
	return a

func _apply(s: Skeleton3D, clip: Animation, t: float) -> void:
	s.reset_bone_poses()
	for track in clip.get_track_count():
		var bone := s.find_bone(String(clip.track_get_path(track)).get_slice(":", 1))
		if bone < 0:
			continue
		match clip.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				s.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(track, t))
			Animation.TYPE_POSITION_3D:
				s.set_bone_pose_position(bone, clip.position_track_interpolate(track, t))

func _depth(s: Skeleton3D, i: int) -> int:
	var d := 0
	while s.get_bone_parent(i) >= 0:
		i = s.get_bone_parent(i)
		d += 1
	return d

func _length(s: Skeleton3D, i: int) -> float:
	var kids := s.get_bone_children(i)
	if kids.is_empty():
		return 0.0
	return s.get_bone_rest(kids[0]).origin.length()

func _segment(s: Skeleton3D, prefix: String, pair: Array) -> float:
	var b := s.find_bone(prefix + pair[1])
	if b < 0:
		return -1.0
	if pair[0] == "":
		return s.get_bone_global_rest(b).origin.y - _floor(s, prefix)
	var a := s.find_bone(prefix + pair[0])
	return -1.0 if a < 0 else s.get_bone_global_rest(a).origin.distance_to(s.get_bone_global_rest(b).origin)

func _floor(s: Skeleton3D, prefix: String) -> float:
	var y := 0.0
	for foot in ["LeftToeBase", "LeftToe_End", "LeftFoot"]:
		var f := s.find_bone(prefix + foot)
		if f >= 0:
			y = minf(y, s.get_bone_global_rest(f).origin.y) if y != 0.0 else s.get_bone_global_rest(f).origin.y
	return y

func _dir_rest(s: Skeleton3D, prefix: String, a: String, b: String) -> Vector3:
	var ia := s.find_bone(prefix + a)
	var ib := s.find_bone(prefix + b)
	if ia < 0 or ib < 0:
		return Vector3.ZERO
	return (s.get_bone_global_rest(ib).origin - s.get_bone_global_rest(ia).origin).normalized()

func _dir_pose(s: Skeleton3D, prefix: String, a: String, b: String) -> Vector3:
	var ia := s.find_bone(prefix + a)
	var ib := s.find_bone(prefix + b)
	if ia < 0 or ib < 0:
		return Vector3.FORWARD
	return (s.get_bone_global_pose(ib).origin - s.get_bone_global_pose(ia).origin).normalized()

func _joint_angle(s: Skeleton3D, prefix: String, chain: Array) -> float:
	var p := []
	for n in chain:
		var i := s.find_bone(prefix + n)
		if i < 0:
			return -1.0
		p.append(s.get_bone_global_pose(i).origin)
	return rad_to_deg((p[0] - p[1]).angle_to(p[2] - p[1]))

func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
