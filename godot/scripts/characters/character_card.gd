extends PanelContainer
const Registry = preload("res://scripts/characters/character_registry.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const WeaponVisuals = preload("res://scripts/weapon_visuals.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
signal selection_requested(id: String)
## Enquadramento da prévia: corpo inteiro ocupando o quadro, câmera um pouco
## abaixo do peito (o personagem parece mais imponente) e de frente-direita.
const PREVIEW_CAMERA := Vector3(0.3, 1.05, -3.7)
const PREVIEW_LOOK := Vector3(0.0, 0.9, 0.0)
## O modelo olha para -Z (para a câmera); girado só um pouco, quase de frente.
const PREVIEW_YAW := deg_to_rad(18.0)
const SHOWCASE_CLIP := "idle_foldarms"
var definition: Resource
var selected := false
## Carta grande do carrossel (prévia maior).
var featured := false
var visual: Node3D
var preview_ready := false

func _ready() -> void:
    # Mesmo visual do menu principal (scripts/ui/ui_theme.gd).
    custom_minimum_size.x = 0 if featured else 390
    var style := UiTheme.card(18 if featured else 16)
    if selected:
        style.border_color = UiTheme.ACCENT
        style.set_border_width_all(2)
        style.shadow_color = Color(UiTheme.ACCENT, 0.18)
    add_theme_stylebox_override("panel", style)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    add_child(column)
    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 10)
    column.add_child(head)
    var title := UiTheme.title(definition.display_name, 26 if featured else 21)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(title)
    _build_preview(column)
    var state := UiTheme.caps("✓ Seu personagem" if selected else "Disponível", 12, UiTheme.ACCENT if selected else UiTheme.DIM)
    state.name = "SelectionState"
    state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    if not preview_ready:
        state.text = "Recursos indisponíveis"
        state.add_theme_color_override("font_color", UiTheme.DANGER)
    head.add_child(state)
    var description := UiTheme.label(definition.description, 14, UiTheme.MUTED)
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    description.custom_minimum_size = Vector2(0, 40)
    if featured:
        description.custom_minimum_size.x = 330
    column.add_child(description)
    var button := Button.new()
    button.name = "Select_" + definition.id
    button.text = "Selecionado" if selected else "Selecionar"
    button.custom_minimum_size.y = 46
    button.disabled = selected or not preview_ready
    UiTheme.primary(button, 16)
    button.pressed.connect(func(): selection_requested.emit(definition.id))
    column.add_child(button)

func _build_preview(column: VBoxContainer) -> void:
    var container := SubViewportContainer.new()
    container.custom_minimum_size = Vector2(330, 300) if featured else Vector2(300, 250)
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
    settings.background_color = UiTheme.PANEL_SOLID
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
    camera.position = PREVIEW_CAMERA
    camera.fov = 32
    camera.look_at(PREVIEW_LOOK)
    camera.current = true
    visual = Registry.create_visual(definition.id)
    if visual == null:
        return
    if visual.has_method("vestir"):
        visual.call("vestir", Registry.load_outfit()) # cofre de roupas
    world.add_child(visual)
    preview_ready = not visual.has_method("is_visual_ready") or bool(visual.call("is_visual_ready"))
    if not preview_ready:
        return
    visual.rotation.y = PREVIEW_YAW
    if visual.has_method("play_overlay") and visual.has_method("set_armed"):
        # Pose de vitrine: em pé, braços cruzados (UAL2 idle_foldarms), sem arma.
        # A pose de mira do jogo é feita para ser vista por trás e fica torta de frente.
        visual.call("set_armed", false)
        # Só tronco e braços: as pernas do clipe ficam abertas demais nos modelos Mixamo.
        visual.call("play_overlay", SHOWCASE_CLIP, "upper", 1.0, 1.0, 1.0e9)
        visual.animate(1.0, 0.0, false, false, false, false, false)
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
