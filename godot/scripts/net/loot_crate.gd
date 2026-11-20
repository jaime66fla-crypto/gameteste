extends StaticBody3D
## A loot crate in an online match (Eliminatória and Mata-mata; team rooms use
## the shop). Contents and ownership live on the server; this node only shows
## the crate, its contents and the opened state. Compact: about knee height.
const WeaponData = preload("res://scripts/weapon_data.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const SIZE := Vector3(0.62, 0.38, 0.44)

var crate_id := ""
var items: Dictionary = {} # weapon id -> reserve ammo
var is_drop := false # dropped by an eliminated player
var is_med := false # medkit: restores health instead of weapons
var heal := 0
var medkits := 0 # carried kits left in a dropped crate
var nades := 0
var owner_name := ""
var opened := false
var label: Label3D
var lid: Node3D

func setup(data: Dictionary) -> void:
	crate_id = str(data.get("id", ""))
	items = data.get("items", {})
	is_drop = bool(data.get("drop", false))
	owner_name = str(data.get("name", ""))
	is_med = bool(data.get("med", false))
	heal = int(data.get("heal", 0))
	medkits = int(data.get("medkits", 0))
	nades = int(data.get("nades", 0))
	name = "Crate_" + crate_id

func _ready() -> void:
	collision_layer = HitboxScript.LAYER_WORLD
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = SIZE.y * 0.5
	add_child(collision)
	if is_med:
		_build_medkit()
	else:
		_build_ammo_box()
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 10
	label.pixel_size = 0.004
	label.position.y = SIZE.y + 0.45
	label.modulate = Color("#8cf0a0") if is_med else (Color("#ff9a7a") if is_drop else Color("#ffe08a"))
	label.visible = false
	add_child(label)
	label.text = contents_text()
	_settle()

## Olive military case with dark straps and a brass (or red, when dropped) latch.
func _build_ammo_box() -> void:
	var body_color := Color("#3f4a33") if is_drop else Color("#5d6b3d")
	var band_color := Color("#23271f")
	_part(self, Vector3(0, SIZE.y * 0.42, 0), Vector3(SIZE.x, SIZE.y * 0.84, SIZE.z), body_color)
	for x in [-SIZE.x * 0.34, SIZE.x * 0.34]:
		_part(self, Vector3(x, SIZE.y * 0.42, 0), Vector3(0.05, SIZE.y * 0.86, SIZE.z + 0.015), band_color)
	# Stencilled stripe on the front.
	_part(self, Vector3(0, SIZE.y * 0.42, SIZE.z * 0.5 + 0.004), Vector3(SIZE.x * 0.4, 0.035, 0.006), Color("#d9b44a"))
	# Lid hinged on the back edge; it swings open when looted.
	lid = Node3D.new()
	lid.position = Vector3(0, SIZE.y * 0.84, -SIZE.z * 0.5)
	add_child(lid)
	_part(lid, Vector3(0, SIZE.y * 0.08, SIZE.z * 0.5), Vector3(SIZE.x + 0.03, SIZE.y * 0.16, SIZE.z + 0.03), body_color.darkened(0.15))
	_part(lid, Vector3(0, SIZE.y * 0.17, SIZE.z * 0.5), Vector3(0.11, 0.025, 0.11), Color("#b03a2e") if is_drop else Color("#d9b44a"))

## White case with red crosses on the lid and front, lid opens when used.
func _build_medkit() -> void:
	var white := Color("#e9ecea")
	var red := Color("#c8261f")
	var s := SIZE.x
	_part(self, Vector3(0, SIZE.y * 0.42, 0), Vector3(SIZE.x, SIZE.y * 0.84, SIZE.z), white)
	_part(self, Vector3(0, SIZE.y * 0.45, SIZE.z * 0.5 + 0.005), Vector3(s * 0.34, s * 0.1, 0.008), red)
	_part(self, Vector3(0, SIZE.y * 0.45, SIZE.z * 0.5 + 0.005), Vector3(s * 0.1, s * 0.34, 0.008), red)
	lid = Node3D.new()
	lid.position = Vector3(0, SIZE.y * 0.84, -SIZE.z * 0.5)
	add_child(lid)
	_part(lid, Vector3(0, SIZE.y * 0.08, SIZE.z * 0.5), Vector3(SIZE.x + 0.03, SIZE.y * 0.16, SIZE.z + 0.03), white.darkened(0.08))
	_part(lid, Vector3(0, SIZE.y * 0.165, SIZE.z * 0.5), Vector3(s * 0.4, 0.01, s * 0.12), red)
	_part(lid, Vector3(0, SIZE.y * 0.165, SIZE.z * 0.5), Vector3(s * 0.12, 0.01, s * 0.4), red)

func _settle() -> void:
	# Rest on whatever surface is below (roads and sidewalks are a few cm high).
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 3.0, 0)
	var query := PhysicsRayQueryParameters3D.create(from, global_position + Vector3(0, -3.0, 0), HitboxScript.LAYER_WORLD)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = (hit["position"] as Vector3).y

func contents_text() -> String:
	if is_med:
		return "Kit médico (+%d de vida)\nE guardar  •  F usar" % heal
	var names: Array[String] = []
	for weapon_id in items:
		names.append(str(WeaponData.stats(weapon_id)["name"]))
	if medkits > 0:
		names.append("Kit médico ×%d" % medkits)
	if nades > 0:
		names.append("Granada ×%d" % nades)
	var title := ("Caixa de " + owner_name) if is_drop and not owner_name.is_empty() else "Suprimentos"
	return "%s\n%s" % [title, ", ".join(names)]

func show_label(value: bool) -> void:
	label.visible = value and not opened

func mark_opened() -> void:
	if opened:
		return
	opened = true
	label.visible = false
	var tween := create_tween()
	tween.tween_property(lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Mata-mata: the server refilled this crate (new contents, lid closes again).
func refill(data: Dictionary) -> void:
	items = data.get("items", {})
	nades = int(data.get("nades", 0))
	opened = false
	if label != null:
		label.text = contents_text()
	if lid != null:
		var tween := create_tween()
		tween.tween_property(lid, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_SINE)

func _part(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material_override = material
	parent.add_child(mesh)
