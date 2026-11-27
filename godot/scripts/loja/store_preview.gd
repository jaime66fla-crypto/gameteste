extends "res://scripts/ui/sharp_viewport.gd"
## Prévia 3D de um item da loja (data/store.json), usada na Loja e no Cofre:
## personagem parado de braços cruzados ou arma com a skin girando.
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Registry = preload("res://scripts/characters/character_registry.gd")
const StoreCatalog = preload("res://scripts/loja/store_catalog.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const SPIN_SPEED := 0.6
const SHOWCASE_CLIP := "idle_foldarms"

var item_id := ""
var _spinner: Node3D
var _visual: Node3D

func _init(id: String = "", size: Vector2 = Vector2(96, 96)) -> void:
	super()
	item_id = id
	custom_minimum_size = size

func _ready() -> void:
	super() # SubViewport nítido (scripts/ui/sharp_viewport.gd)
	var world := Node3D.new()
	viewport.add_child(world)
	_lights(world)
	match StoreCatalog.group_of(item_id):
		"personagens":
			_character(world)
		"skins_armas":
			_weapon(world)

func _lights(world: Node3D) -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#1a2a30")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#9fb0b8")
	settings.ambient_light_energy = 0.45
	# Reflexos de estúdio (céu só para o metal refletir; o fundo segue liso):
	# sem isso aço polido e verniz ficam pretos na vitrine.
	var studio := ProceduralSkyMaterial.new()
	studio.sky_top_color = Color("#c9d6de")
	studio.sky_horizon_color = Color("#6d7d86")
	studio.ground_horizon_color = Color("#3a3430")
	studio.ground_bottom_color = Color("#141414")
	var sky := Sky.new()
	sky.sky_material = studio
	settings.sky = sky
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.environment = settings
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -30, 0)
	key.light_energy = 1.2
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_color = Color("#9cc4e0")
	rim.light_energy = 1.0
	world.add_child(rim)

func _camera(world: Node3D, from: Vector3, to: Vector3, fov: float) -> void:
	var camera := Camera3D.new()
	camera.fov = fov
	world.add_child(camera)
	camera.look_at_from_position(from, to)
	camera.current = true

## Personagem inteiro, de frente-direita, braços cruzados (mesma pose da carta).
func _character(world: Node3D) -> void:
	_camera(world, Vector3(0.3, 1.0, -3.9), Vector3(0.0, 0.9, 0.0), 32.0)
	_visual = Registry.create_visual(item_id)
	if _visual == null:
		return
	world.add_child(_visual)
	_visual.rotation.y = deg_to_rad(18.0)
	if _visual.has_method("play_overlay") and _visual.has_method("set_armed"):
		_visual.call("set_armed", false)
		_visual.call("play_overlay", SHOWCASE_CLIP, "upper", 1.0, 1.0, 1.0e9)
	_visual.animate(1.0, 0.0, false, false, false, false, false)

## Arma com a skin, deitada de lado e girando.
func _weapon(world: Node3D) -> void:
	var model := WeaponProportions.create_model(StoreCatalog.weapon(item_id), StoreCatalog.texture_path(item_id))
	if model == null:
		return
	_spinner = Node3D.new()
	world.add_child(_spinner)
	var holder := Node3D.new()
	_spinner.add_child(holder)
	holder.add_child(model)
	var box := _bounds(model)
	var extent := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if extent <= 0.0:
		return
	holder.scale = Vector3.ONE / extent # a arma inteira cabe em 1 m
	holder.position = -box.get_center() / extent
	_spinner.rotation.y = 0.6
	_camera(world, Vector3(0, 0.25, 1.45), Vector3(0, 0, 0), 36.0)

## Caixa de todas as malhas, no espaço do próprio modelo.
func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var local := _relative(root, mi) * mi.mesh.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box

func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return root.transform * transform

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if is_instance_valid(_spinner):
		_spinner.rotation.y += delta * SPIN_SPEED
	if is_instance_valid(_visual):
		_visual.animate(minf(delta, 0.075), 0.0, false, false, false, false, false)
