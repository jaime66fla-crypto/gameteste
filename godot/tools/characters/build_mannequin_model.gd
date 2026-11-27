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
## "-- --id=atacante" / "-- --id=defensor": same conversion for the Linha de Fogo
## soldiers (fps-tatico/tools/build_soldiers.py -> assets/personagens/<id>/<id>.glb,
## MPFB humans whose rig already has Mixamo names).
var SOURCE := "res://assets/personagens/ual2/UAL2_Standard.glb"
const REFERENCE := "res://assets/personagens/downloaded/avatar.fbx"
var OUT_DIR := "res://assets/personagens/manequim"
var OUT_SCENE := "res://assets/personagens/manequim/manequim_modelo.scn"
## Source rig already uses Mixamo bone names with this prefix ("" = UAL2 names).
var SOURCE_PREFIX := ""
## Single flat colour for every surface (alpha 0 = keep the source materials).
var ALBEDO := Color(0, 0, 0, 0)
## Skin texture for surfaces whose material is named "Pele*" (MPFB skin baked in
## the MakeHuman UV layout; unused by the current characters).
var SKIN_TEXTURE := ""
var MODEL_NAME := "Manequim"
## Keep the source (glTF) materials as they are: textures, normal maps; alpha
## surfaces (hair, brows, lashes) drawn with a depth pre-pass, both sides.
var KEEP_MATERIALS := false
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
var ROUGHNESS := 0.42
var SPECULAR := 0.55

func _initialize() -> void:
	var soldier := ""
	for arg in OS.get_cmdline_user_args():
		if arg in ["--id=atacante", "--id=defensor"]:
			soldier = arg.substr(5)
	if not soldier.is_empty():
		# Soldados do Linha de Fogo (fps-tatico/tools/build_soldiers.py): MakeHuman
		# realista com rig "mixamo", roupa do time, colete e capacete, numa malha só
		# com os materiais/texturas do MakeHuman (como o 02).
		SOURCE = "res://assets/personagens/%s/%s.glb" % [soldier, soldier]
		OUT_DIR = "res://assets/personagens/" + soldier
		OUT_SCENE = "res://assets/personagens/%s/%s_modelo.scn" % [soldier, soldier]
		SOURCE_PREFIX = "mixamorig_"
		MODEL_NAME = soldier
		KEEP_MATERIALS = true
	elif "--id=02" in OS.get_cmdline_user_args():
		# 02 (tools/blender/build_02.py): MakeHuman realista, uma malha só com
		# os materiais/texturas do próprio MakeHuman (pele, olhos, cabelo, roupa).
		SOURCE = "res://assets/personagens/02/02.glb"
		OUT_DIR = "res://assets/personagens/02"
		OUT_SCENE = "res://assets/personagens/02/02_modelo.scn"
		SOURCE_PREFIX = "mixamorig_"
		MODEL_NAME = "02"
		KEEP_MATERIALS = true
	var ok := _build()
	quit(0 if ok else 1)

func _source_name(suffix: String) -> String:
	if not SOURCE_PREFIX.is_empty():
		return SOURCE_PREFIX + suffix
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
	# Roupas trocáveis: malhas "Roupa_*" no mesmo rig (o 01, removido, usava; os soldados não têm).
	var clothes: Array[MeshInstance3D] = []
	for node in src_root.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin == null:
			continue
		if String(node.name).begins_with("Roupa_"):
			clothes.append(node)
		elif mesh_node == null:
			mesh_node = node
	if ref == null or src == null or mesh_node == null:
		printerr("MANEQUIM: modelo de referência ou manequim não carregou")
		return false
	# Turn the mannequin so it faces like the Mixamo reference (+Z).
	var Clips = load("res://tools/characters/build_ual2_clips.gd")
	var s_fwd: Vector3 = Clips.forward_of(src, _source_name("LeftUpLeg"), _source_name("RightUpLeg"), _source_name("LeftFoot"), _source_name("LeftToeBase"))
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
	var size_ratio := (align * src.get_bone_global_rest(src.find_bone(_source_name("Hips"))).origin).y / ref.get_bone_global_rest(ref.find_bone(REF_PREFIX + "Hips")).origin.y
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
	var model := Node3D.new()
	model.name = MODEL_NAME + "Modelo"
	model.add_child(skeleton)
	skeleton.owner = model
	var mi := _add_mesh(model, skeleton, mesh_node, MODEL_NAME, src, new_of_src, align, globals)
	var mesh := mi.mesh as ArrayMesh
	var skin := mi.skin
	for piece in clothes:
		var cmi := _add_mesh(model, skeleton, piece, String(piece.name), src, new_of_src, align, globals)
		cmi.visible = false # o script do personagem veste conforme a skin escolhida
		print("roupa %s: %d tris" % [piece.name, cmi.mesh.get_faces().size() / 3])
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

## Copies one skinned mesh onto the new skeleton: binds move to the Mixamo bone
## that replaces their bone, materials get the character's look.
func _add_mesh(model: Node3D, skeleton: Skeleton3D, mesh_node: MeshInstance3D, node_name: String, src: Skeleton3D, new_of_src: Dictionary, align: Transform3D, globals: Array[Transform3D]) -> MeshInstance3D:
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
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := mesh_node.mesh.duplicate() as ArrayMesh
	for s in mesh.get_surface_count():
		var source_mat := mesh.surface_get_material(s) as BaseMaterial3D
		if KEEP_MATERIALS and source_mat != null:
			var kept := source_mat.duplicate() as BaseMaterial3D
			# MPFB's game-engine material wires the texture alpha everywhere:
			# only strand/card surfaces need it (skin and cloth stay opaque).
			# 02: "02_Hair"; soldados: "Hair_short02" (tipo do asset antes do nome).
			var strands := ["Hair", "Eyebrows", "Eyelashes"].any(func(part): return kept.resource_name.ends_with(part) or kept.resource_name.begins_with(part + "_"))
			if strands:
				kept.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				kept.cull_mode = BaseMaterial3D.CULL_DISABLED
			else:
				kept.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			print("material %d %s: textura %s normal %s alpha %d" % [s, kept.resource_name, kept.albedo_texture != null, kept.normal_enabled, kept.transparency])
			mesh.surface_set_material(s, kept)
			continue
		var mat := StandardMaterial3D.new()
		mat.resource_name = "%s_%d" % [MODEL_NAME, s]
		if ALBEDO.a > 0.0:
			mat.albedo_color = ALBEDO
		elif source_mat != null:
			mat.albedo_color = source_mat.albedo_color
			mat.albedo_texture = source_mat.albedo_texture
			print("material %d: cor %s textura %s" % [s, source_mat.albedo_color, source_mat.albedo_texture != null])
		mat.roughness = ROUGHNESS
		if source_mat != null and not SKIN_TEXTURE.is_empty() and source_mat.resource_name.begins_with("Pele"):
			mat.resource_name = source_mat.resource_name
			mat.albedo_color = Color.WHITE
			mat.albedo_texture = load(SKIN_TEXTURE)
		elif source_mat != null and source_mat.resource_name.begins_with("Roupa_"):
			# Tecido fosco; a textura (layout UV do MakeHuman) é a "skin" da peça.
			var piece := source_mat.resource_name.trim_prefix("Roupa_")
			mat.resource_name = source_mat.resource_name
			mat.albedo_color = Color.WHITE
			mat.albedo_texture = load(OUT_DIR + "/roupas/" + piece + ".png")
			mat.roughness = 0.92
			mat.metallic_specular = 0.2
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED # dentro da manga/barra
			mesh.surface_set_material(s, mat)
			continue
		elif source_mat != null and source_mat.resource_name.begins_with("Olho"):
			mat.resource_name = source_mat.resource_name
			mat.roughness = 0.25 # olho úmido, com reflexo
		mat.metallic_specular = SPECULAR
		mesh.surface_set_material(s, mat)
	mi.mesh = mesh
	mi.skin = skin
	skeleton.add_child(mi)
	mi.owner = model
	mi.skeleton = NodePath("..")
	return mi
