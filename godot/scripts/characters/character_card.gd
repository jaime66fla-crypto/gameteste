extends PanelContainer
const Registry = preload("res://scripts/characters/character_registry.gd")
const WeaponVisuals = preload("res://scripts/weapon_visuals.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
signal selection_requested(id: String)
var definition: Resource
var selected := false
var visual: Node3D
var preview_ready := false

func _ready() -> void:
    custom_minimum_size.x = 390
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#1b3035")
    style.border_color = Color("#b8ca91") if selected else Color("#3a565b")
    style.set_border_width_all(2 if selected else 1)
    style.set_corner_radius_all(10)
    for edge in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
        style.set_content_margin(edge, 16)
    add_theme_stylebox_override("panel", style)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    add_child(column)
    var title := Label.new()
    title.text = definition.display_name
    title.add_theme_font_size_override("font_size", 21)
    column.add_child(title)
    _build_preview(column)
    var description := Label.new()
    description.text = definition.description
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    description.custom_minimum_size.y = 44
    description.add_theme_font_size_override("font_size", 14)
    column.add_child(description)
    var state := Label.new()
    state.name = "SelectionState"
    state.text = "✓ SELECIONADO" if selected else "Disponível"
    if not preview_ready:
        state.text = "Recursos indisponíveis — escolha o Jaime Original"
    state.add_theme_color_override("font_color", Color("#c8dca1") if selected else Color("#a6bbc0"))
    state.add_theme_font_size_override("font_size", 14)
    column.add_child(state)
    var button := Button.new()
    button.name = "Select_" + definition.id
    button.text = "Selecionado" if selected else "Selecionar"
    button.custom_minimum_size.y = 44
    button.disabled = selected or not preview_ready
    button.pressed.connect(func(): selection_requested.emit(definition.id))
    column.add_child(button)

func _build_preview(column: VBoxContainer) -> void:
    var container := SubViewportContainer.new()
    container.custom_minimum_size = Vector2(300, 210)
    container.stretch = true
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.add_child(container)
    var viewport := SubViewport.new()
    viewport.name = "PreviewViewport"
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
    viewport.msaa_3d = Viewport.MSAA_2X
    container.add_child(viewport)
    var world := Node3D.new()
    viewport.add_child(world)
    var environment := WorldEnvironment.new()
    var settings := Environment.new()
    settings.background_mode = Environment.BG_COLOR
    settings.background_color = Color("#0d1b22")
    settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    settings.ambient_light_color = Color("#b2c2cd")
    settings.ambient_light_energy = 0.7
    environment.environment = settings
    world.add_child(environment)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-35, -25, 0)
    light.light_energy = 1.5
    world.add_child(light)
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-25, 150, 0)
    fill.light_color = Color("#c3d8ec")
    fill.light_energy = 1.6
    world.add_child(fill)
    var camera := Camera3D.new()
    world.add_child(camera)
    camera.position = Vector3(1.8, 1.2, -2.6)
    camera.fov = 37
    camera.look_at(Vector3(0, 0.95, 0))
    camera.current = true
    visual = Registry.create_visual(definition.id)
    if visual == null:
        return
    world.add_child(visual)
    preview_ready = not visual.has_method("is_visual_ready") or bool(visual.call("is_visual_ready"))
    if not preview_ready:
        return
    visual.configure_weapon("rifle", 0.7)
    var mount: Node3D = visual.get("weapon_mount")
    if mount:
        var weapon := Node3D.new()
        mount.add_child(weapon)
        if visual.has_method("bind_weapon"):
            var imported := WeaponProportions.create_model("rifle")
            if imported:
                weapon.add_child(imported)
                WeaponProportions.apply(weapon,"rifle",imported)
                visual.call("bind_weapon",weapon)
        else:
            weapon.scale = Vector3.ONE * 0.7
            WeaponVisuals.build(weapon, "rifle")
    visual.animate(1.0, 0.0, false, false, false, false, false)

func _process(delta: float) -> void:
    if preview_ready and is_instance_valid(visual):
        visual.animate(minf(delta, 0.075), 0.0, false, false, false, false, false)
