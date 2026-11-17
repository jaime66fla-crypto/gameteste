extends StaticBody3D
## A loot crate in an online match. Contents and ownership live on the server;
## this node only shows the crate, its contents and the opened state.
const WeaponData = preload("res://scripts/weapon_data.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const SIZE := Vector3(1.0, 0.62, 0.7)

var crate_id := ""
var items: Dictionary = {} # weapon id -> reserve ammo
var is_drop := false # dropped by an eliminated player
var is_med := false # medkit: restores health instead of weapons
var heal := 0
var medkits := 0 # carried kits left in a dropped crate
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
		return
	var body_color := Color("#3f4a33") if is_drop else Color("#8a6a42")
	var band_color := Color("#2b2f2a") if is_drop else Color("#4a4f52")
	_part(self, Vector3(0, SIZE.y * 0.42, 0), Vector3(SIZE.x, SIZE.y * 0.84, SIZE.z), body_color)
	for x in [-0.36, 0.36]:
		_part(self, Vector3(x, SIZE.y * 0.42, 0), Vector3(0.07, SIZE.y * 0.86, SIZE.z + 0.02), band_color)
	# Lid hinged on the back edge; it swings open when looted.
	lid = Node3D.new()
	lid.position = Vector3(0, SIZE.y * 0.84, -SIZE.z * 0.5)
	add_child(lid)
	_part(lid, Vector3(0, SIZE.y * 0.08, SIZE.z * 0.5), Vector3(SIZE.x + 0.04, SIZE.y * 0.16, SIZE.z + 0.04), body_color.darkened(0.15))
	_part(lid, Vector3(0, SIZE.y * 0.17, SIZE.z * 0.5), Vector3(0.18, 0.03, 0.18), Color("#d9b44a") if not is_drop else Color("#b03a2e"))
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.004
	label.position.y = SIZE.y + 0.55
	label.modulate = Color("#ffe08a") if not is_drop else Color("#ff9a7a")
	label.visible = false
	add_child(label)
	label.text = contents_text()
	_settle()

## White case with red crosses on the lid and front, lid opens when used.
func _build_medkit() -> void:
	var white := Color("#e9ecea")
	var red := Color("#c8261f")
	_part(self, Vector3(0, SIZE.y * 0.42, 0), Vector3(SIZE.x, SIZE.y * 0.84, SIZE.z), white)
	_part(self, Vector3(0, SIZE.y * 0.45, SIZE.z * 0.5 + 0.006), Vector3(0.34, 0.1, 0.01), red)
	_part(self, Vector3(0, SIZE.y * 0.45, SIZE.z * 0.5 + 0.006), Vector3(0.1, 0.34, 0.01), red)
	lid = Node3D.new()
	lid.position = Vector3(0, SIZE.y * 0.84, -SIZE.z * 0.5)
	add_child(lid)
	_part(lid, Vector3(0, SIZE.y * 0.08, SIZE.z * 0.5), Vector3(SIZE.x + 0.04, SIZE.y * 0.16, SIZE.z + 0.04), white.darkened(0.08))
	_part(lid, Vector3(0, SIZE.y * 0.165, SIZE.z * 0.5), Vector3(0.4, 0.012, 0.12), red)
	_part(lid, Vector3(0, SIZE.y * 0.165, SIZE.z * 0.5), Vector3(0.12, 0.012, 0.4), red)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.004
	label.position.y = SIZE.y + 0.55
	label.modulate = Color("#8cf0a0")
	label.visible = false
	add_child(label)
	label.text = contents_text()
	_settle()

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
