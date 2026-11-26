extends Node
## Shared, non-destructive cel treatment for existing and newly spawned meshes.
## Imported meshes, skeletons, UI, transparent foliage and custom effects stay intact.
const PALETTE := {
	"grass": Color("#62913c"), "asphalt": Color("#454f63"),
	"pavers": Color("#e1c99c"), "concrete": Color("#d8c9ad"),
	"brick": Color("#ad674a"), "roof": Color("#53657a"),
	"dirt": Color("#a77e48"), "gravel": Color("#a1a095"),
	"leaves": Color("#619b2f"), "hazard": Color("#dfad35"),
	"crate_wood": Color("#ad793b"), "crate_metal": Color("#6b7f90")
}
const SURFACES := ["grass", "asphalt", "concrete", "wood", "bark", "leaf", "metal", "roof", "fabric", "paint", "plaster", "dirt"]
var _materials: Dictionary = {}
var _batch_meshes: Dictionary = {}
var _prune_left := 2.0

func _process(delta: float) -> void:
	_prune_left -= delta
	if _prune_left <= 0.0:
		_prune_left = 2.0
		_prune(_materials)
		_prune(_batch_meshes)

func _prune(cache: Dictionary) -> void:
	for key in cache.keys():
		if cache[key].get_ref() == null:
			cache.erase(key)

func _ready() -> void:
	name = "CelStyle"
	get_tree().node_added.connect(_node_added)
	_style_branch(get_parent())
	_tune_environment()

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_node_added):
		get_tree().node_added.disconnect(_node_added)

func _style_branch(node: Node) -> void:
	if node is MeshInstance3D:
		_style_mesh(node)
	elif node is MultiMeshInstance3D:
		_style_batch(node)
	for child in node.get_children():
		_style_branch(child)

func _node_added(node: Node) -> void:
	if node is MeshInstance3D:
		# Materials are often assigned immediately after add_child().
		_style_added.call_deferred(node.get_instance_id())
	elif node is MultiMeshInstance3D:
		_style_added.call_deferred(node.get_instance_id())

func _style_added(instance_id: int) -> void:
	var node := instance_from_id(instance_id)
	if node is MeshInstance3D:
		_style_mesh(node)
	elif node is MultiMeshInstance3D:
		_style_batch(node)

func _style_batch(node: MultiMeshInstance3D) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or not get_parent().is_ancestor_of(node):
		return
	if node.multimesh == null or node.multimesh.mesh == null:
		return
	if node.material_override != null:
		node.material_override = material_for(node.material_override)
		return
	var original := node.multimesh.mesh
	if not original is ArrayMesh or original.has_meta("cel_styled"):
		return
	# Keep the MultiMesh itself: survival stores it to hide harvested instances.
	# Duplicate only the shared mesh, retaining every surface's vertex colors.
	var outline := 0.018 if str(node.name).ends_with("_lod0") else 0.0
	var key := str(original.get_instance_id()) + ":" + str(outline)
	var mesh: ArrayMesh
	if _batch_meshes.has(key):
		mesh = _batch_meshes[key].get_ref()
	if mesh == null:
		mesh = original.duplicate() as ArrayMesh
		mesh.set_meta("cel_styled", true)
		for surface in mesh.get_surface_count():
			var source := original.surface_get_material(surface)
			if source != null:
				mesh.surface_set_material(surface, material_for(source, outline))
		_batch_meshes[key] = weakref(mesh)
	node.multimesh.mesh = mesh

func _style_mesh(node: MeshInstance3D) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	# Online map batches retain their authored atlas, normals and roughness.
	if bool(node.get_meta("preserve_authored_material", false)):
		return
	if not get_parent().is_ancestor_of(node) or node.mesh == null:
		return
	# These targets animate their privately held material on each hit.
	if node.get_parent().is_in_group("training_target"):
		return
	var scale_size := Vector3(node.global_basis.x.length(), node.global_basis.y.length(), node.global_basis.z.length())
	var world_size := node.get_aabb().size * scale_size
	# No hulls on ground slabs, huge terrain, tiny details or distant objects.
	# Local grow is compensated for imported model scales (including centimetres).
	var outline := 0.0
	if not get_parent().has_node("TrainingGround") and world_size.y > 0.08 \
		and world_size.length() > 0.30 and world_size.length() < 45.0:
		outline = 0.012 / maxf(0.001, maxf(scale_size.x, maxf(scale_size.y, scale_size.z)))
	if node.material_override != null:
		node.material_override = material_for(node.material_override, outline)
	else:
		for surface in node.mesh.get_surface_count():
			var source := node.get_active_material(surface)
			if source != null:
				node.set_surface_override_material(surface, material_for(source, outline))

func material_for(source: Material, outline: float = 0.0) -> Material:
	if not source is StandardMaterial3D or source.has_meta("cel_styled") \
		or source.has_meta("preserve_authored_material"):
		return source
	var original := source as StandardMaterial3D
	# Glass, alpha-scissored leaf cards, lamps, collectible glows and optics
	# must keep their authored rendering and existing additional passes.
	if original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
		or original.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
		or original.emission_enabled or original.next_pass != null:
		return source
	var grow := snappedf(outline, 0.0001)
	var key := str(source.get_instance_id()) + ":" + str(grow)
	if _materials.has(key):
		var cached: Material = _materials[key].get_ref()
		if cached != null:
			return cached
	var m := original.duplicate() as StandardMaterial3D
	m.set_meta("cel_styled", true)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.metallic = 0.0
	m.roughness = 0.15
	m.normal_enabled = false
	m.normal_texture = null
	m.roughness_texture = null
	var kind := original.resource_name.get_slice("_", 0)
	if original.resource_name.begins_with("map_"):
		kind = original.resource_name.trim_prefix("map_")
		m.albedo_texture = null
		m.albedo_color = PALETTE.get(kind, original.albedo_color.lightened(0.12))
	elif kind in SURFACES:
		# Procedural grain is removed; retain each object's authored tint.
		m.albedo_texture = null
		m.albedo_color = original.albedo_color
	if grow > 0.0:
		var hull := StandardMaterial3D.new()
		hull.resource_name = "cel_outline"
		hull.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hull.cull_mode = BaseMaterial3D.CULL_FRONT
		hull.albedo_color = Color("#18212a")
		hull.grow = true
		hull.grow_amount = grow
		m.next_pass = hull
	_materials[key] = weakref(m)
	return m

func _tune_environment() -> void:
	# Each of these maps configures its own daylight.
	if get_parent().has_node("MatchMap") or get_parent().has_node("TrainingGround"):
		return
	var world := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	var env := world.environment
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#2785d6")
	sky_material.sky_horizon_color = Color("#a9d9f1")
	sky_material.ground_bottom_color = Color("#4c6340")
	sky_material.ground_horizon_color = Color("#a9d9f1")
	sky_material.sun_angle_max = 1.5
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a3bce0")
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	# SurvivalController continues to own time of day, fog and night lighting.
	if not bool(Net.start_info.get("survival", false)) or not Net.in_match:
		env.ambient_light_energy = 0.25
		var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
		if sun != null:
			sun.light_energy = 0.95
			sun.light_color = Color("#fff4dc")
