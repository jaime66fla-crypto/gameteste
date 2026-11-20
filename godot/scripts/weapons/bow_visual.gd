extends Node3D
## Blender meshes in metres: +Y vertical, +Z arrow direction, grip at origin.
const BODY := preload("res://assets/weapons/bow/recurve_bow.glb")
const ARROW := preload("res://assets/weapons/bow/arrow.glb")
var _arrow: Node3D
var _string: MeshInstance3D
var _last_charge := -1.0
var _last_pull := -1.0

func _init() -> void:
	name = "RecurveBow"
	add_child(BODY.instantiate())
	_arrow = ARROW.instantiate()
	_arrow.name = "NockedArrow"
	add_child(_arrow)
	_string = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#e7ddbc")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_string.material_override = mat
	add_child(_string)
	set_draw(0.0)

func set_draw(charge: float, full_pull: float = 0.72) -> void:
	if is_equal_approx(charge, _last_charge) and is_equal_approx(full_pull, _last_pull):
		return
	_last_charge = charge
	_last_pull = full_pull
	var pull := lerpf(0.12, full_pull, clampf(charge, 0.0, 1.0))
	var nock := Vector3(0, 0.035, -pull)
	_arrow.position = nock
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in [Vector3(0, 0.61, -0.12), nock, nock, Vector3(0, -0.61, -0.12)]:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	_string.mesh = mesh

func arrow_origin() -> Vector3:
	return _arrow.global_position + global_basis.z.normalized() * 0.85

func set_nocked(value: bool) -> void:
	_arrow.visible = value
