extends SceneTree
## Builds the third character, the UAL2 mannequin (Quaternius, CC0), as a
## Mixamo-rigged model so downloaded_avatar.gd drives it like Ch31 and Remy:
## - new skeleton with Ch31's bone names ("mixamorig_" prefix) and hierarchy;
## - joints at the mannequin's own positions (turned to face +Z like Mixamo);
## - each bone keeps Ch31's rest orientation, swung so its main-child axis
##   follows the mannequin's bone: Mixamo clips then bend the limbs the same way;
## - skin bind poses recomputed so the mesh rests exactly where it was.
## Output: assets/personagens/manequim/manequim_modelo.scn
## godot --headless --path godot --script res://tools/characters/build_mannequin_model.gd
const SOURCE := "res://assets/personagens/ual2/UAL2_Standard.glb"
const REFERENCE := "res://assets/personagens/downloaded/avatar.fbx"
const OUT_DIR := "res://assets/personagens/manequim"
const OUT_SCENE := "res://assets/personagens/manequim/manequim_modelo.scn"
const REF_PREFIX := "mixamorig9_"
const PREFIX := "mixamorig_"
const BONE_MAP := {
	"Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Spine2": "spine_03", "Neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l", "LeftToe_End": "ball_leaf_l",
	"RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r", "RightToe_End": "ball_leaf_r",
}
const FINGERS := {"Thumb": "thumb", "Index": "index", "Middle": "middle", "Ring": "ring", "Pinky": "pinky"}
## Plastic look of the example mannequin: yellow shell, purple joints.
const ROUGHNESS := 0.42
const SPECULAR := 0.55

func _initialize() -> void:
	var ok := _build()
	quit(0 if ok else 1)

func _source_name(suffix: String) -> String:
	if BONE_MAP.has(suffix):
		return BONE_MAP[suffix]
	for side in ["Left", "Right"]:
		for finger in FINGERS:
			for index in range(1, 5):
				if suffix == "%sHand%s%d" % [side, finger, index]:
					var tail := "_0%d_" % index if index < 4 else "_04_leaf_"
					return FINGERS[finger] + tail + ("l" if side == "Left" else "r")
	return ""

func _main_child(skeleton: Skeleton3D, bone: int, prefix: String) -> int:
	var name := String(skeleton.get_bone_name(bone)).trim_prefix(prefix)
	var preferred: String = {"Hips": "Spine", "Spine2": "Neck"}.get(name, "")
	if name.ends_with("Hand") and not name.contains("Hand_"):
		preferred = name + "Middle1"
	if preferred != "" and skeleton.find_bone(prefix + preferred) >= 0:
		return skeleton.find_bone(prefix + preferred)
	var children := skeleton.get_bone_children(bone)
	return children[0] if not children.is_empty() else -1

func _build() -> bool:
	var ref_root := (load(REFERENCE) as PackedScene).instantiate()
	var ref := ref_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var src_root := (load(SOURCE) as PackedScene).instantiate()
	var src := src_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var mesh_node: MeshInstance3D = null
	for node in src_root.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null:
			mesh_node = node
			break
	if ref == null or src == null or mesh_node == null:
		printerr("MANEQUIM: modelo de referência ou manequim não carregou")
		return false
	# Turn the mannequin so it faces like the Mixamo reference (+Z).
	var Clips = load("res://tools/characters/build_ual2_clips.gd")
	var s_fwd: Vector3 = Clips.forward_of(src, "thigh_l", "thigh_r", "foot_l", "ball_l")
	var r_fwd: Vector3 = Clips.forward_of(ref, REF_PREFIX + "LeftUpLeg", REF_PREFIX + "RightUpLeg", REF_PREFIX + "LeftFoot", REF_PREFIX + "LeftToeBase")
	var align := Transform3D(Basis(Vector3.UP, atan2(s_fwd.cross(r_fwd).y, s_fwd.dot(r_fwd))), Vector3.ZERO)
	var count := ref.get_bone_count()
	var src_of := PackedInt32Array()
	src_of.resize(count)
	var positions: Array[Vector3] = []
	positions.resize(count)
	var src_height := 0.0
	var ref_height := 0.0
	for b in count:
		var suffix := String(ref.get_bone_name(b)).trim_prefix(REF_PREFIX)
		src_of[b] = src.find_bone(_source_name(suffix))
		ref_height = maxf(ref_height, ref.get_bone_global_rest(b).origin.y)
	for b in src.get_bone_count():
		src_height = maxf(src_height, (align * src.get_bone_global_rest(b).origin).y)
	# Body size from the hip height (the top joint differs: Ch31 has HeadTop_End).
	var size_ratio := (align * src.get_bone_global_rest(src.find_bone("pelvis")).origin).y / ref.get_bone_global_rest(ref.find_bone(REF_PREFIX + "Hips")).origin.y
	# Joint positions: the mannequin's; bones it lacks (HeadTop_End) follow the
	# reference offset from their parent, scaled to the mannequin's size.
	for b in count:
		if src_of[b] >= 0:
			positions[b] = align * src.get_bone_global_rest(src_of[b]).origin
	for b in count:
		if src_of[b] < 0:
			var p := ref.get_bone_parent(b)
			var offset := ref.get_bone_global_rest(b).origin - (ref.get_bone_global_rest(p).origin if p >= 0 else Vector3.ZERO)
			positions[b] = (positions[p] if p >= 0 else Vector3.ZERO) + offset * size_ratio
	# Orientations: reference rest, swung onto the mannequin's bone direction.
	var globals: Array[Transform3D] = []
	globals.resize(count)
	var swings: Array[Quaternion] = []
	swings.resize(count)
	for b in count:
		var child := _main_child(ref, b, REF_PREFIX)
		var swing := Quaternion.IDENTITY
		if child >= 0:
			var ref_dir := ref.get_bone_global_rest(child).origin - ref.get_bone_global_rest(b).origin
			var new_dir := positions[child] - positions[b]
			if ref_dir.length() > 0.0001 and new_dir.length() > 0.0001:
				swing = Quaternion(ref_dir.normalized(), new_dir.normalized())
		elif ref.get_bone_parent(b) >= 0:
			swing = swings[ref.get_bone_parent(b)]
		swings[b] = swing
		globals[b] = Transform3D(Basis(swing) * ref.get_bone_global_rest(b).basis.orthonormalized(), positions[b])
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	for b in count:
		skeleton.add_bone(PREFIX + String(ref.get_bone_name(b)).trim_prefix(REF_PREFIX))
	for b in count:
		var p := ref.get_bone_parent(b)
		skeleton.set_bone_parent(b, p)
		var local := globals[p].affine_inverse() * globals[b] if p >= 0 else globals[b]
		skeleton.set_bone_rest(b, local)
	skeleton.reset_bone_poses()
	# Skin: every source bind moves to the Mixamo bone that replaces its bone
	# (or the nearest mapped ancestor), keeping each vertex where it rests now.
	var new_of_src := {}
	for b in count:
		if src_of[b] >= 0:
			new_of_src[src_of[b]] = b
	var src_skin := mesh_node.skin
	var skin := Skin.new()
	for i in src_skin.get_bind_count():
		var sb := src_skin.get_bind_bone(i)
		var bind_name := String(src_skin.get_bind_name(i))
		if not bind_name.is_empty():
			sb = src.find_bone(bind_name)
		var walk := sb
		while walk >= 0 and not new_of_src.has(walk):
			walk = src.get_bone_parent(walk)
		var nb: int = new_of_src.get(walk, 0)
		var rest_vertex_space := align * src.get_bone_global_rest(sb) * src_skin.get_bind_pose(i)
		skin.add_named_bind(skeleton.get_bone_name(nb), globals[nb].affine_inverse() * rest_vertex_space)
	var model := Node3D.new()
	model.name = "ManequimModelo"
	model.add_child(skeleton)
	skeleton.owner = model
	var mi := MeshInstance3D.new()
	mi.name = "Manequim"
	var mesh := mesh_node.mesh.duplicate() as ArrayMesh
	for s in mesh.get_surface_count():
		var source_mat := mesh.surface_get_material(s) as BaseMaterial3D
		var mat := StandardMaterial3D.new()
		mat.resource_name = "Manequim_%d" % s
		if source_mat != null:
			mat.albedo_color = source_mat.albedo_color
			mat.albedo_texture = source_mat.albedo_texture
			print("material %d: cor %s textura %s" % [s, source_mat.albedo_color, source_mat.albedo_texture != null])
		mat.roughness = ROUGHNESS
		mat.metallic_specular = SPECULAR
		mesh.surface_set_material(s, mat)
	mi.mesh = mesh
	mi.skin = skin
	skeleton.add_child(mi)
	mi.owner = model
	mi.skeleton = NodePath("..")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene := PackedScene.new()
	var err := scene.pack(model)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_SCENE, ResourceSaver.FLAG_COMPRESS)
	var hips := skeleton.find_bone(PREFIX + "Hips")
	var top := skeleton.get_bone_global_rest(skeleton.find_bone(PREFIX + "HeadTop_End")).origin.y
	print("MANEQUIM: malha %.3f m  topo da cabeça %.3f m  quadril %.3f m  ossos %d  binds %d  cena %s" % [mesh.get_aabb().end.y, top, skeleton.get_bone_global_rest(hips).origin.y, count, skin.get_bind_count(), error_string(err)])
	model.free()
	ref_root.free()
	src_root.free()
	return err == OK
