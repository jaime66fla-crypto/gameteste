extends PanelContainer
## Cofre de roupas da tela de Personagens: cada peça do 01 numa vitrine de
## vidro (prévia 3D girando num pedestal, com luz de cima), com Vestir/Tirar.
## A escolha fica salva (character_registry.gd save_outfit) e o jogador local
## entra vestido; a carta do 01 ao lado troca na hora via outfit_changed.
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Registry = preload("res://scripts/characters/character_registry.gd")
const MODEL := "res://assets/personagens/01/01_modelo.scn"
const PIECES := [
	{"id": "bone", "nome": "Boné", "tipo": "Cabeça"},
	{"id": "camiseta", "nome": "Camiseta grafite", "tipo": "Tronco"},
	{"id": "calca", "nome": "Calça jeans escura", "tipo": "Pernas"},
	{"id": "bermuda", "nome": "Bermuda oliva", "tipo": "Pernas"},
]
const CASE_SIZE := Vector2(112, 112)
const SPIN_SPEED := 0.6

signal outfit_changed(pieces: PackedStringArray)

var worn := PackedStringArray()
var _cases := {}        # id -> {"panel", "state", "button"}
var _spinners: Array[Node3D] = []
var _feedback: Label

func _ready() -> void:
	custom_minimum_size.x = 310
	add_theme_stylebox_override("panel", UiTheme.card(16))
	worn = Registry.load_outfit()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	column.add_child(UiTheme.caps("COFRE DE ROUPAS", 12, UiTheme.ACCENT))
	column.add_child(UiTheme.title("Vitrine do 01", 22))
	var hint := UiTheme.label("Escolha o que o personagem 01 veste. Fica salvo para a próxima partida.", 13, UiTheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 270
	column.add_child(hint)
	var model := load(MODEL) as PackedScene
	for piece in PIECES:
		column.add_child(_build_case(piece, model))
	_feedback = UiTheme.label("", 13, UiTheme.DANGER)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_feedback)
	_refresh()

func _build_case(piece: Dictionary, model: PackedScene) -> Control:
	var id: String = piece["id"]
	var panel := PanelContainer.new()
	panel.name = "Vitrine_" + id
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	# Vidro: a prévia 3D com um reflexo diagonal por cima.
	var glass := Control.new()
	glass.custom_minimum_size = CASE_SIZE
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(glass)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	_build_stage(viewport, id, model)
	var sheen := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.13), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.05)])
	gradient.offsets = PackedFloat32Array([0.0, 0.38, 0.8, 1.0])
	var sheen_tex := GradientTexture2D.new()
	sheen_tex.gradient = gradient
	sheen_tex.fill_from = Vector2(0, 0)
	sheen_tex.fill_to = Vector2(1, 1)
	sheen.texture = sheen_tex
	sheen.stretch_mode = TextureRect.STRETCH_SCALE
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.add_child(sheen)
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	info.add_child(UiTheme.caps(String(piece["tipo"]).to_upper(), 11, UiTheme.MUTED))
	info.add_child(UiTheme.label(piece["nome"], 15, UiTheme.TEXT, 600))
	var state := UiTheme.label("", 12, UiTheme.GOOD, 600)
	info.add_child(state)
	var button := Button.new()
	button.name = "Vestir_" + id
	button.custom_minimum_size = Vector2(120, 36)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(_toggle.bind(id))
	info.add_child(button)
	_cases[id] = {"panel": panel, "state": state, "button": button}
	return panel

## Pedestal escuro, luz de vitrine de cima e a peça sozinha, enquadrada.
func _build_stage(viewport: SubViewport, id: String, model: PackedScene) -> void:
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#1a2a30")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#8c9ba3")
	settings.ambient_light_energy = 0.3
	environment.environment = settings
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-60, -30, 0)
	key.light_energy = 1.0
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_color = Color("#9cc4e0")
	rim.light_energy = 0.9
	world.add_child(rim)
	if model == null:
		return
	var instance := model.instantiate() as Node3D
	var mesh_node: MeshInstance3D = null
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.visible = mi.name == "Roupa_" + id
		if mi.visible:
			mesh_node = mi
	if mesh_node == null:
		instance.free()
		return
	var box := mesh_node.mesh.get_aabb()
	var spinner := Node3D.new()
	world.add_child(spinner)
	spinner.add_child(instance)
	instance.position = -box.get_center()
	_spinners.append(spinner)
	spinner.rotation.y = 0.5
	var extent := maxf(box.size.y, maxf(box.size.x, box.size.z))
	var pedestal := MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = maxf(box.size.x, box.size.z) * 0.62
	disk.bottom_radius = disk.top_radius * 1.05
	disk.height = extent * 0.04
	pedestal.mesh = disk
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#1d282c")
	stone.roughness = 0.6
	pedestal.material_override = stone
	pedestal.position.y = -box.size.y * 0.5 - disk.height * 0.5 - extent * 0.01
	world.add_child(pedestal)
	var camera := Camera3D.new()
	camera.fov = 30.0
	world.add_child(camera)
	var distance := extent * 0.5 / tan(deg_to_rad(15.0)) * 1.3
	# A vitrine ainda não está na árvore aqui: look_at_from_position não exige.
	camera.look_at_from_position(Vector3(0, extent * 0.18, distance), Vector3(0, -extent * 0.04, 0))
	camera.current = true

func _toggle(id: String) -> void:
	var next := worn.duplicate()
	if id in next:
		next.remove_at(next.find(id))
	else:
		# Calça e bermuda ocupam o mesmo lugar.
		for other in [["calca", "bermuda"], ["bermuda", "calca"]]:
			if id == other[0] and other[1] in next:
				next.remove_at(next.find(other[1]))
		next.append(id)
	var error := Registry.save_outfit(next)
	if error != OK:
		_feedback.text = "Não foi possível salvar as roupas. A escolha anterior foi mantida."
		return
	_feedback.text = ""
	worn = next
	_refresh()
	outfit_changed.emit(worn)

func _refresh() -> void:
	for id in _cases:
		var on: bool = id in worn
		var parts: Dictionary = _cases[id]
		var style := UiTheme.box(Color(0.02, 0.035, 0.04, 0.9), UiTheme.ACCENT if on else UiTheme.LINE, 2 if on else 1, 8)
		style.content_margin_left = 8
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		(parts["panel"] as PanelContainer).add_theme_stylebox_override("panel", style)
		(parts["state"] as Label).text = "✓ VESTIDO" if on else "Na vitrine"
		(parts["state"] as Label).add_theme_color_override("font_color", UiTheme.GOOD if on else UiTheme.DIM)
		var button := parts["button"] as Button
		button.text = "Tirar" if on else "Vestir"
		if on:
			UiTheme.secondary(button, 13)
		else:
			UiTheme.primary(button, 13)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	for spinner in _spinners:
		if is_instance_valid(spinner):
			spinner.rotation.y += delta * SPIN_SPEED
