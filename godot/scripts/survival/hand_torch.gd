extends Node3D
## Tocha acesa na mão: segue a mão esquerda do personagem (sempre em pé, como
## quem segura uma tocha), com chama e uma luz quente que tremula.
## Serve para o jogador local e para os outros (net_actor, flag "tc" do estado).
const Model = preload("res://scripts/survival/building_model.gd")
const NODE_NAME := "HandTorch"
const LENGTH := 0.5
const LIGHT_RANGE := 9.0

var _skeleton: Skeleton3D
var _bone := -1
var _retry := 0.0

## Acende (cria) ou apaga (tira) a tocha da mão de `character`.
static func set_on(character: Node, on: bool) -> void:
	if character == null:
		return
	var torch := character.get_node_or_null(NODE_NAME)
	if on and torch == null:
		torch = (load("res://scripts/survival/hand_torch.gd") as GDScript).new()
		torch.name = NODE_NAME
		character.add_child(torch)
	elif not on and torch != null:
		torch.queue_free()

static func is_on(character: Node) -> bool:
	return character != null and character.get_node_or_null(NODE_NAME) != null

func _ready() -> void:
	top_level = true
	var handle := CylinderMesh.new()
	handle.top_radius = 0.022
	handle.bottom_radius = 0.018
	handle.height = LENGTH
	handle.radial_segments = 6
	Model._mesh(self, handle, Transform3D(Basis.IDENTITY, Vector3(0, LENGTH * 0.35, 0)), Model._mat("wood_dark"))
	var head := CylinderMesh.new()
	head.top_radius = 0.042
	head.bottom_radius = 0.032
	head.height = 0.11
	head.radial_segments = 6
	var tip := Vector3(0, LENGTH * 0.85, 0)
	Model._mesh(self, head, Transform3D(Basis.IDENTITY, tip - Vector3(0, 0.04, 0)), Model._mat("ash"))
	for m in find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(Model._fire_fx(tip, 0.2, tip, false))
	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.position = tip + Vector3(0, 0.15, 0)
	light.light_color = Color("#ff9a4a")
	light.light_energy = 1.6
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	light.set_script(preload("res://scripts/survival/fire_flicker.gd"))
	add_child(light)
	_find_hand()
	_follow()

func _find_hand() -> void:
	_skeleton = null
	_bone = -1
	var owner_node := get_parent()
	if owner_node == null:
		return
	for s in owner_node.find_children("*", "Skeleton3D", true, false):
		var sk := s as Skeleton3D
		for i in sk.get_bone_count():
			var bone := String(sk.get_bone_name(i))
			if bone == "LeftHand" or bone.ends_with("_LeftHand") or bone.ends_with(":LeftHand") or bone.ends_with("mixamorigLeftHand"):
				_skeleton = sk
				_bone = i
				return

func _process(delta: float) -> void:
	if _bone < 0 or not is_instance_valid(_skeleton):
		_retry -= delta
		if _retry <= 0.0:
			_retry = 1.0
			_find_hand() # o avatar pode carregar depois
	_follow()

func _follow() -> void:
	var character := get_parent() as Node3D
	if character == null:
		return
	var yaw := Basis(Vector3.UP, character.global_rotation.y)
	if _bone >= 0 and is_instance_valid(_skeleton) and _skeleton.is_inside_tree():
		var hand: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone).origin
		global_transform = Transform3D(yaw, hand - Vector3(0, 0.08, 0))
	else:
		# Sem esqueleto ainda: na altura da mão esquerda, à frente do corpo.
		global_transform = Transform3D(yaw, character.global_position + yaw * Vector3(-0.3, 1.0, -0.25))
