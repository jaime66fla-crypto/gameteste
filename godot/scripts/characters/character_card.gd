extends PanelContainer
const Registry = preload("res://scripts/characters/character_registry.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const WeaponVisuals = preload("res://scripts/weapon_visuals.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const StoreCatalog = preload("res://scripts/loja/store_catalog.gd")
signal selection_requested(id: String)
## Botões de arma da carta do Cofre: equipar/guardar e trocar a arma da prévia.
signal weapon_toggle_requested
signal weapon_cycle_requested
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
## Arma na mão da prévia (Cofre: "Equipar arma"), com a skin equipada; "" = sem arma.
var weapon_id := ""
## Mostra "Equipar arma" e a troca de arma (só a carta do Cofre).
var weapon_controls := false
## Mais de lado quando armado: a pose de mira de frente fica torta.
const ARMED_YAW := deg_to_rad(38.0)
const WEAPON_NAMES := {"pistol": "Pistola", "smg": "Submetralhadora", "shotgun": "Escopeta", "rifle": "Fuzil", "sniper": "Sniper"}
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
    var actions := HBoxContainer.new()
    actions.name = "CardActions"
    actions.add_theme_constant_override("separation", 10)
    column.add_child(actions)
    var button := Button.new()
    button.name = "Select_" + definition.id
    button.text = "Selecionado" if selected else "Selecionar"
    button.custom_minimum_size.y = 46
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.disabled = selected or not preview_ready
    UiTheme.primary(button, 16)
    button.pressed.connect(func(): selection_requested.emit(definition.id))
    actions.add_child(button)
    if weapon_controls and preview_ready and visual.has_method("bind_weapon"):
        var arm := Button.new()
        arm.name = "EquipWeaponButton"
        arm.text = "Guardar arma" if not weapon_id.is_empty() else "Equipar arma"
        arm.tooltip_text = "Ver o personagem com a arma e a skin equipada"
        arm.custom_minimum_size.y = 46
        arm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        if weapon_id.is_empty():
            UiTheme.primary(arm, 16)
        else:
            UiTheme.secondary(arm, 16)
        arm.pressed.connect(func(): weapon_toggle_requested.emit())
        actions.add_child(arm)

func _build_preview(column: VBoxContainer) -> void:
    # Prévia 3D com a troca de arma por cima (canto superior esquerdo).
    var stack := MarginContainer.new()
    stack.name = "PreviewStack"
    column.add_child(stack)
    var container := SubViewportContainer.new()
    container.custom_minimum_size = Vector2(360, 330) if featured else Vector2(300, 250)
    container.stretch = true
    container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    stack.add_child(container)
    if weapon_controls and not weapon_id.is_empty():
        var cycle := Button.new()
        cycle.name = "CycleWeaponButton"
        var skin := Registry.weapon_skin(weapon_id)
        cycle.text = "%s  ›" % WEAPON_NAMES.get(weapon_id, weapon_id)
        cycle.tooltip_text = ("Skin: %s" % StoreCatalog.item(skin).get("nome", skin)) if not skin.is_empty() else "Sem skin (original)"
        cycle.custom_minimum_size = Vector2(0, 34)
        cycle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
        cycle.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
        UiTheme.secondary(cycle, 13)
        cycle.pressed.connect(func(): weapon_cycle_requested.emit())
        var corner := MarginContainer.new()
        corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
        for side in ["margin_left", "margin_top"]:
            corner.add_theme_constant_override(side, 10)
        stack.add_child(corner)
        corner.add_child(cycle)
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
    if not weapon_id.is_empty() and visual.has_method("set_armed"):
        visual.rotation.y = ARMED_YAW
        if _arm_preview(weapon_id):
            visual.animate(1.0, 0.0, false, false, false, false, false)
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

## Arma do Cofre na mão do personagem, com a skin equipada para ela.
func _arm_preview(id: String) -> bool:
    var mount: Node3D = visual.get("weapon_mount")
    var imported := WeaponProportions.create_model(id, StoreCatalog.texture_path(Registry.weapon_skin(id)))
    if mount == null or imported == null or not visual.has_method("bind_weapon"):
        if imported != null:
            imported.free()
        return false
    var weapon := Node3D.new()
    weapon.name = "PreviewWeapon"
    mount.add_child(weapon)
    weapon.add_child(imported)
    WeaponProportions.apply(weapon, id, imported)
    visual.configure_weapon(id, weapon.scale.x)
    visual.call("bind_weapon", weapon)
    visual.call("set_armed", true)
    if visual.has_method("set_aim_target"):
        # Mira à frente do personagem, na altura do peito: arma erguida.
        visual.call("set_aim_target", visual.global_transform * Vector3(0.0, 1.4, -10.0), true)
    return true

func _process(delta: float) -> void:
    if preview_ready and is_instance_valid(visual):
        visual.animate(minf(delta, 0.075), 0.0, false, false, false, false, false)
