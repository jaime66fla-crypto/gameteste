extends PanelContainer
const Registry = preload("res://scripts/characters/character_registry.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const WeaponVisuals = preload("res://scripts/weapon_visuals.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const StoreCatalog = preload("res://scripts/loja/store_catalog.gd")
const SharpViewport = preload("res://scripts/ui/sharp_viewport.gd")
signal selection_requested(id: String)
## Botões de arma da carta do Cofre: equipar/guardar e trocar a arma da prévia.
signal weapon_toggle_requested
signal weapon_cycle_requested
## Pose da prévia trocada ("idle", "aim", "fire"); sem arma, o Cofre equipa uma.
signal pose_changed(pose: String)
const POSES := ["idle", "aim", "fire"]
const POSE_NAMES := {"idle": "Parado", "aim": "Mirando", "fire": "Atirando"}
## Rajadas da pose "Atirando": [intervalo entre tiros, tiros por rajada, pausa].
const FIRE_PATTERN := {"pistol": [0.32, 2, 0.75], "smg": [0.08, 6, 0.7], "rifle": [0.11, 4, 0.7], "shotgun": [0.95, 1, 0.0], "sniper": [1.4, 1, 0.0]}
## Mirando, o personagem vira mais de lado: o cano não aponta para a câmera.
const AIM_YAW := deg_to_rad(52.0)
const FLASH_TIME := 0.055
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
const ARMED_YAW := deg_to_rad(30.0)
const WEAPON_NAMES := {"pistol": "Pistola", "smg": "Submetralhadora", "shotgun": "Escopeta", "rifle": "Fuzil", "sniper": "Sniper"}
var visual: Node3D
var preview_ready := false
## Pose da prévia armada (só vale com arma na mão).
var pose := "idle"
var _armed_preview := false
var _pose_buttons := {}
var _fire_timer := 0.0
var _burst_left := 0
var _flash_left := 0.0
## Quadros mínimos do clarão: com o menu a poucos FPS ele não some num quadro só.
var _flash_frames := 0
var _flash_spin := 0.0
var _flash_mesh: MeshInstance3D
var _flash_light: OmniLight3D
var shots_fired := 0

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
    var container := SharpViewport.new()
    container.custom_minimum_size = Vector2(360, 330) if featured else Vector2(300, 250)
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
    if weapon_controls:
        # Parado / Mirando / Atirando, embaixo da prévia.
        var bottom := MarginContainer.new()
        bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bottom.add_theme_constant_override("margin_bottom", 10)
        stack.add_child(bottom)
        var poses := HBoxContainer.new()
        poses.name = "PoseButtons"
        poses.alignment = BoxContainer.ALIGNMENT_CENTER
        poses.size_flags_vertical = Control.SIZE_SHRINK_END
        poses.add_theme_constant_override("separation", 6)
        bottom.add_child(poses)
        for id in POSES:
            var b := Button.new()
            b.name = "Pose_" + id
            b.text = POSE_NAMES[id]
            b.tooltip_text = "Ver o personagem %s" % POSE_NAMES[id].to_lower()
            b.pressed.connect(_on_pose_pressed.bind(id))
            poses.add_child(b)
            _pose_buttons[id] = b
        _style_pose_buttons()
    var viewport := container.viewport # nítido na resolução real da tela
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
            _armed_preview = true
            _build_flash(world)
            set_pose(pose, true)
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
    if "showcase_ready" in visual:
        # Pose tática de vitrine ("low ready", downloaded_avatar.gd).
        visual.set("showcase_ready", true)
    return true

## Troca a pose da prévia armada (sem refazer a carta). `snap` pula a transição.
func set_pose(value: String, snap: bool = false) -> void:
    pose = value if value in POSES else "idle"
    _style_pose_buttons()
    if not _armed_preview or not is_instance_valid(visual):
        return
    visual.set("showcase_aim", pose != "idle")
    if snap:
        visual.set("_showcase_aim_weight", 1.0 if pose != "idle" else 0.0)
        visual.rotation.y = AIM_YAW if pose != "idle" else ARMED_YAW
    _fire_timer = 0.35 if not snap else 0.0
    _burst_left = 0

func _on_pose_pressed(id: String) -> void:
    if _armed_preview:
        set_pose(id)
    else:
        pose = id
    pose_changed.emit(id)

func _style_pose_buttons() -> void:
    for id in _pose_buttons:
        var on: bool = id == (pose if _armed_preview else "idle")
        UiTheme.tab(_pose_buttons[id], on, 12)

## Clarão do cano: bola de fogo esticada na direção do tiro e uma luz laranja.
func _build_flash(world: Node3D) -> void:
    # Halo laranja translúcido com um núcleo quase branco dentro.
    _flash_mesh = _flash_ball("PreviewMuzzleFlash", 0.045, Color(1.0, 0.62, 0.2, 0.78))
    _flash_mesh.add_child(_flash_ball("FlashCore", 0.022, Color("#fff4d6")))
    _flash_mesh.visible = false
    world.add_child(_flash_mesh)
    _flash_light = OmniLight3D.new()
    _flash_light.name = "PreviewMuzzleLight"
    _flash_light.light_color = Color(1, 0.65, 0.25)
    _flash_light.omni_range = 2.5
    _flash_light.light_energy = 0.0
    _flash_light.visible = false
    world.add_child(_flash_light)

func _flash_ball(node_name: String, radius: float, color: Color) -> MeshInstance3D:
    var ball := MeshInstance3D.new()
    ball.name = node_name
    var sphere := SphereMesh.new()
    sphere.radius = radius
    sphere.height = radius * 2.0
    sphere.radial_segments = 12
    sphere.rings = 6
    ball.mesh = sphere
    var glow := StandardMaterial3D.new()
    glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    glow.albedo_color = color
    if color.a < 1.0:
        glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    ball.material_override = glow
    ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return ball

## Um disparo da prévia: coice no avatar e clarão no cano.
func fire_once() -> void:
    if not _armed_preview or not is_instance_valid(visual):
        return
    shots_fired += 1
    visual.call("showcase_fire")
    _flash_left = FLASH_TIME
    _flash_frames = 3
    _flash_spin = randf() * TAU
    if _flash_mesh != null:
        var big := weapon_id in ["shotgun", "sniper"]
        _flash_mesh.scale = Vector3(1.0, 1.0, 2.4) * (1.5 if big else 1.0) * randf_range(0.85, 1.15)

func is_flash_visible() -> bool:
    return _flash_mesh != null and _flash_mesh.visible

func _update_fire(delta: float) -> void:
    if pose == "fire" and _showcase_aim_ready():
        _fire_timer -= delta
        if _fire_timer <= 0.0:
            var pattern: Array = FIRE_PATTERN.get(weapon_id, FIRE_PATTERN["rifle"])
            if _burst_left <= 0:
                _burst_left = int(pattern[1])
            fire_once()
            _burst_left -= 1
            _fire_timer = float(pattern[0]) + (float(pattern[2]) if _burst_left <= 0 else 0.0)
    _flash_left = maxf(_flash_left - delta, 0.0)
    _flash_frames = maxi(_flash_frames - 1, 0)
    var bound: Node3D = visual.get("bound_weapon")
    var muzzle := bound.get_node_or_null("Muzzle") as Marker3D if is_instance_valid(bound) else null
    var on := (_flash_left > 0.0 or _flash_frames > 0) and muzzle != null
    if _flash_mesh != null:
        _flash_mesh.visible = on
        _flash_light.visible = on
        _flash_light.light_energy = 2.6 if on else 0.0
        if on:
            var barrel := -bound.global_basis.z.normalized()
            # O fundo do halo encosta na boca do cano.
            var tip := muzzle.global_position + barrel * 0.04 * _flash_mesh.scale.z
            _flash_mesh.global_position = tip
            _flash_mesh.look_at(tip + barrel, Vector3.UP if absf(barrel.y) < 0.95 else Vector3.RIGHT)
            _flash_mesh.rotate_object_local(Vector3.FORWARD, _flash_spin)
            _flash_light.global_position = tip

## Só atira depois de levantar a arma (não no meio da transição).
func _showcase_aim_ready() -> bool:
    return float(visual.get("_showcase_aim_weight")) > 0.9

func _process(delta: float) -> void:
    if preview_ready and is_instance_valid(visual):
        var step := minf(delta, 0.075)
        if _armed_preview:
            var yaw := AIM_YAW if pose != "idle" else ARMED_YAW
            visual.rotation.y = move_toward(visual.rotation.y, yaw, step * 1.6)
        visual.animate(step, 0.0, false, false, false, false, false)
        if _armed_preview:
            _update_fire(step)
