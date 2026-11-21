extends Node3D
## Um lote de brilhos sem luzes dinâmicas: branco, próximo e oculto por paredes.
const RANGE := 28.0
const EXTRA_SLOTS := 128 # O servidor limita os galhos naturais a 64.
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
varying float camera_distance;
varying float phase;
void vertex() {
    vec3 center = MODEL_MATRIX[3].xyz;
    camera_distance = distance(center, INV_VIEW_MATRIX[3].xyz);
    phase = dot(center.xz, vec2(0.37, 0.61));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(center, 1.0));
}
void fragment() {
    if (camera_distance > 28.0 || COLOR.a < 0.01) { discard; }
    vec2 p = UV * 2.0 - 1.0;
    float rays = exp(-abs(p.x) * 18.0 - abs(p.y) * 3.5) + exp(-abs(p.y) * 24.0 - abs(p.x) * 5.0);
    float halo = exp(-dot(p, p) * 7.0) * 0.16;
    float pulse = 0.60 + 0.25 * sin(TIME * 2.4 + phase);
    ALBEDO = vec3(1.0);
    EMISSION = vec3(1.0);
    ALPHA = clamp(rays + halo, 0.0, 1.0) * pulse * COLOR.a * (1.0 - smoothstep(20.0, 28.0, camera_distance));
}
"""
static var _material: ShaderMaterial
static var _quad: QuadMesh
var _multi: MultiMesh
var _slots: Dictionary = {}
var _active: Dictionary = {}
var _free: Array[int] = []
var _next := 0

static func marker_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(0.65, 0.95)
		var shader := Shader.new()
		shader.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = shader
		_quad.material = _material
	return _quad

static func make_marker(position: Vector3) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = "CollectibleGlow"
	marker.mesh = marker_mesh()
	marker.position = position
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visibility_range_end = RANGE
	return marker

func setup(resources: Dictionary) -> void:
	name = "CollectibleGlows"
	_multi = MultiMesh.new()
	_multi.transform_format = MultiMesh.TRANSFORM_3D
	_multi.use_colors = true
	_multi.mesh = marker_mesh()
	_multi.instance_count = resources.size() + EXTRA_SLOTS
	for i in _multi.instance_count:
		_multi.set_instance_color(i, Color(1, 1, 1, 0))
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = _multi
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)
	for id in resources:
		add_resource(str(id), resources[id])

func add_resource(id: String, resource: Dictionary) -> void:
	if _slots.has(id):
		return
	var index: int = _free.pop_back() if not _free.is_empty() else _next
	if index >= _multi.instance_count:
		return
	_next = maxi(_next, index + 1)
	_slots[id] = index
	var pos: Vector3 = resource.pos
	var height := 0.55
	match str(resource.kind):
		"tree":
			pos.x += 0.7
			height = 0.75
		"rock", "ore", "saltpeter": height = 1.5
		"car": height = 1.9
		"pond": height = 0.3
	_multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, pos + Vector3(0, height, 0)))
	set_active(id, not bool(resource.get("depleted", false)))

func set_active(id: String, active: bool) -> void:
	if _slots.has(id):
		_active[id] = active
		_multi.set_instance_color(int(_slots[id]), Color(1, 1, 1, 1 if active else 0))

func is_active(id: String) -> bool:
	return bool(_active.get(id, false))

func remove_resource(id: String) -> void:
	if not _slots.has(id):
		return
	set_active(id, false)
	_free.append(int(_slots[id]))
	_slots.erase(id)
	_active.erase(id)
