extends Node3D

const GameSettings = preload("res://scripts/game_settings.gd")
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const PlayerScript = preload("res://scripts/player.gd")
const WorldPolishScript = preload("res://scripts/world_polish.gd")
const ScopeScript = preload("res://scripts/sniper_scope.gd")
const AmbientAudioScript = preload("res://scripts/ambient_audio.gd")
const MatchControllerScript = preload("res://scripts/net/match_controller.gd")
const TrainingDummyScript = preload("res://scripts/training_dummy.gd")
const SurvivalWorldScript = preload("res://scripts/survival/survival_world.gd")
const SurvivalControllerScript = preload("res://scripts/survival/survival_controller.gd")
var player: CharacterBody3D
var hud: Label
var crosshair: Control
## Dynamic crosshair: gap (px from centre) follows the real shot spread; the
## four arms fade out once the sights are up (first-person ADS), dot stays.
var crosshair_gap := 2.5
var crosshair_arm_alpha := 1.0
## 0 = white centre dot, 1 = red-dot reticle (aiming through an optic).
var crosshair_red_dot := 0.0
const CROSSHAIR_MIN_GAP := 2.5
const CROSSHAIR_MAX_GAP := 70.0
const CROSSHAIR_ARM_LENGTH := 6.0
var action_clock: Control
var action_state: Dictionary = {}
var scope_overlay: Control
var menu_button: Button
var match_controller: Node3D # online matches only
var minimap: Control
var ammo_hud: Control
const MinimapScript = preload("res://scripts/ui/minimap.gd")
const AmmoHudScript = preload("res://scripts/ui/ammo_hud.gd")
const HELP_TEXT := "WASD mover  ALT andar devagar  SHIFT correr  CTRL agachar  ESPAÇO pular  |  Direito mirar (+Q/E inclinar)  Esquerdo atirar  R recarregar  H guardar arma\n1-5 armas  Q soco  E interagir  F curar  G granada (segure)  |  Sobrevivência: TAB inventário  M mapa  |  ESC liberar o mouse"

func _ready() -> void:
    _register_inputs()
    Input.action_release("fire")
    Input.action_release("aim")
    var settings := GameSettings.load_settings()
    GameSettings.apply(settings,get_viewport())
    _build_world()
    var survival := Net.in_match and bool(Net.start_info.get("survival", false))
    var world_polish := Node3D.new()
    world_polish.name = "WorldPolish"
    world_polish.set_script(WorldPolishScript)
    world_polish.set("open_world", survival)
    add_child(world_polish)
    var survival_world: Node3D = null
    if survival:
        # Sobrevivência: mundo aberto em volta da cidade do Campo de Fogo.
        survival_world = SurvivalWorldScript.new()
        add_child(survival_world)
    var ambient := Node3D.new()
    ambient.name = "EnvironmentAudio"
    ambient.set_script(AmbientAudioScript)
    add_child(ambient)
    player = CharacterBody3D.new()
    player.name = "Jaime"
    player.set_script(PlayerScript)
    player.position = Vector3(12, 0.1, -10) # Clear pedestrian plaza beside the avenues
    add_child(player)
    player.mouse_sensitivity *= float(settings["sensitivity"])
    _build_ui()
    if survival:
        match_controller = SurvivalControllerScript.new()
        match_controller.call("setup", self, player, survival_world)
        add_child(match_controller)
    elif Net.in_match:
        match_controller = Node3D.new()
        match_controller.set_script(MatchControllerScript)
        match_controller.call("setup", self, player)
        add_child(match_controller)
    else:
        _spawn_training_dummies()
    _build_hud(survival)
    _build_quit_dialog(survival)
    # O mouse não é recapturado enquanto a mochila ou a confirmação estão abertas.
    player.set("ui_blocking", func() -> bool:
        if quit_dialog != null and quit_dialog.visible:
            return true
        return match_controller != null and match_controller.has_method("ui_open") and bool(match_controller.call("ui_open")))
    # Fechar a janela (X / Alt+F4) também pergunta antes de sair da partida.
    get_tree().set_auto_accept_quit(false)

func _exit_tree() -> void:
    get_tree().set_auto_accept_quit(true)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _ask_quit(true)

var quit_dialog: ConfirmationDialog
var _quit_to_desktop := false

## "Tem certeza?" antes de sair da partida (menu principal ou fechar o jogo).
func _build_quit_dialog(survival: bool) -> void:
    quit_dialog = ConfirmationDialog.new()
    quit_dialog.title = "Sair da partida"
    if survival:
        quit_dialog.dialog_text = "Tem certeza que quer sair?\n\nSeu personagem fica dormindo aqui no mundo e você volta neste mesmo lugar."
    elif Net.in_match:
        quit_dialog.dialog_text = "Tem certeza que quer sair da partida?\n\nSair conta como eliminação."
    else:
        quit_dialog.dialog_text = "Tem certeza que quer sair do treino?"
    quit_dialog.ok_button_text = "Sair"
    quit_dialog.cancel_button_text = "Continuar jogando"
    quit_dialog.exclusive = true
    add_child(quit_dialog)
    quit_dialog.confirmed.connect(func():
        if _quit_to_desktop:
            Net.leave()
            get_tree().quit()
        else:
            return_to_menu())
    quit_dialog.canceled.connect(func():
        var busy: bool = match_controller != null and match_controller.has_method("ui_open") and bool(match_controller.call("ui_open"))
        if not busy and not bool(match_controller != null and match_controller.get("local_dead")):
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)

func _ask_quit(to_desktop: bool) -> void:
    if quit_dialog == null:
        get_tree().quit()
        return
    _quit_to_desktop = to_desktop
    Input.action_release("fire")
    Input.action_release("aim")
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    quit_dialog.popup_centered()

## HUD enxuto: minimapa redondo (canto superior esquerdo) e munição (inferior
## direito). Os controles aparecem segurando F1.
func _build_hud(survival: bool) -> void:
    var layer := CanvasLayer.new()
    layer.name = "Hud"
    layer.layer = 4
    add_child(layer)
    minimap = MinimapScript.new()
    minimap.call("setup", player, survival)
    if match_controller != null and match_controller.has_method("ally_nodes"):
        minimap.set("allies", Callable(match_controller, "ally_nodes"))
    layer.add_child(minimap)
    ammo_hud = AmmoHudScript.new()
    ammo_hud.set("player", player)
    if match_controller != null and match_controller.has_method("hud_extra"):
        ammo_hud.set("extra", Callable(match_controller, "hud_extra"))
    layer.add_child(ammo_hud)
    # A legenda de controles (F1) fica centralizada, longe do minimapa.
    hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    hud.offset_left = -520
    hud.offset_right = 520
    hud.offset_top = -120
    hud.offset_bottom = -70

var _hint_time := 0.0

## Offline practice: dummies in front of the spawn (two close, one at 20 m)
## that show the damage of every weapon and body zone.
func _spawn_training_dummies() -> void:
    for spot in [[Vector3(8, 0, -16), "BONECO 1"], [Vector3(16, 0, -16), "BONECO 2"], [Vector3(12, 0, -30), "BONECO DISTANTE (20 m)"]]:
        var dummy := Node3D.new()
        dummy.name = "TrainingDummy"
        dummy.set_script(TrainingDummyScript)
        dummy.set("title", spot[1])
        dummy.set("sound_fx", player.get("sound_fx"))
        dummy.position = spot[0]
        add_child(dummy)

func _register_inputs() -> void:
    var keys := {
        "move_forward": KEY_W,
        "move_back": KEY_S,
        "move_left": KEY_A,
        "move_right": KEY_D,
        "jump": KEY_SPACE,
        "sprint": KEY_SHIFT,
        "walk": KEY_ALT, # segurar: anda devagar (estilo GTA)
        "crouch": KEY_CTRL,
        "reload": KEY_R
    }
    for action in keys.keys():
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        var key := InputEventKey.new()
        key.physical_keycode = keys[action]
        InputMap.action_add_event(action, key)
    for action in ["aim", "fire"]:
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        var mouse := InputEventMouseButton.new()
        mouse.button_index = MOUSE_BUTTON_RIGHT if action == "aim" else MOUSE_BUTTON_LEFT
        InputMap.action_add_event(action, mouse)

func _build_world() -> void:
    var world_environment := WorldEnvironment.new()
    world_environment.name = "WorldEnvironment"
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.55, 0.72, 0.85)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.65, 0.72, 0.8)
    env.ambient_light_energy = 0.8
    world_environment.environment = env
    add_child(world_environment)
    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-45, -30, 0)
    sun.light_energy = 1.3
    sun.shadow_enabled = true
    add_child(sun)
    _block(Vector3(0,-0.5,0), Vector3(120,1,120), Color(0.28,0.39,0.26), true)

func _block(pos: Vector3, size: Vector3, color: Color, solid: bool) -> void:
    var root := StaticBody3D.new() if solid else Node3D.new()
    root.position = pos
    add_child(root)
    var mesh := MeshInstance3D.new()
    var cube := BoxMesh.new()
    cube.size = size
    mesh.mesh = cube
    mesh.material_override = SurfaceMaterials.make("grass", color)
    root.add_child(mesh)
    if solid:
        var collider := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        collider.shape = shape
        root.add_child(collider)

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    scope_overlay = Control.new()
    scope_overlay.name = "SniperScope"
    scope_overlay.set_script(ScopeScript)
    layer.add_child(scope_overlay)
    scope_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    scope_overlay.visible = false
    hud = Label.new()
    hud.position = Vector2(18, 16)
    hud.add_theme_font_size_override("font_size", 15)
    hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
    hud.add_theme_constant_override("shadow_offset_x", 1)
    hud.add_theme_constant_override("shadow_offset_y", 2)
    layer.add_child(hud)
    # Drawn "+" exactly on the screen centre, where the shot ray goes (a "+"
    # text label sat a few pixels low and left of it).
    crosshair = Control.new()
    crosshair.name = "Crosshair"
    crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(crosshair)
    crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    crosshair.draw.connect(func():
        var c := crosshair.size * 0.5
        var gap := crosshair_gap
        if crosshair_arm_alpha > 0.01:
            for pass_index in 2:
                var color := Color(0, 0, 0, 0.75) if pass_index == 0 else Color(1, 1, 1, 0.95)
                color.a *= crosshair_arm_alpha
                var width := 4.0 if pass_index == 0 else 2.0
                var arm := gap + CROSSHAIR_ARM_LENGTH + (1.0 if pass_index == 0 else 0.0)
                crosshair.draw_line(c + Vector2(-arm, 0), c + Vector2(-gap, 0), color, width)
                crosshair.draw_line(c + Vector2(gap, 0), c + Vector2(arm, 0), color, width)
                crosshair.draw_line(c + Vector2(0, -arm), c + Vector2(0, -gap), color, width)
                crosshair.draw_line(c + Vector2(0, gap), c + Vector2(0, arm), color, width)
        if crosshair_red_dot > 0.01:
            # Red-dot reticle: soft glow plus a bright core, centred on the shot axis.
            var red := crosshair_red_dot
            crosshair.draw_circle(c, 4.5, Color(1.0, 0.1, 0.05, 0.22 * red))
            crosshair.draw_circle(c, 2.6, Color(1.0, 0.15, 0.08, 0.55 * red))
            crosshair.draw_circle(c, 1.5, Color(1.0, 0.35, 0.25, red))
        if crosshair_red_dot < 0.99:
            var white := 1.0 - crosshair_red_dot
            crosshair.draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0, 0, 0, 0.6 * white))
            crosshair.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, 0.95 * white)))
    crosshair.resized.connect(crosshair.queue_redraw)
    # Action clock under the crosshair: reload / medkit progress (3 s).
    action_clock = Control.new()
    action_clock.name = "ActionClock"
    action_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
    action_clock.visible = false
    layer.add_child(action_clock)
    action_clock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    action_clock.draw.connect(_draw_action_clock)
    menu_button = Button.new()
    menu_button.name = "ReturnToMenuButton"
    menu_button.text = "Menu principal"
    menu_button.custom_minimum_size = Vector2(150,40)
    layer.add_child(menu_button)
    menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    menu_button.offset_left = -170
    menu_button.offset_right = -20
    menu_button.offset_top = 16
    menu_button.offset_bottom = 56
    menu_button.pressed.connect(func(): _ask_quit(false))

## Simple clock: dark disc, a sweep that fills clockwise, label and seconds left.
func _draw_action_clock() -> void:
    if action_state.is_empty():
        return
    var c := action_clock.size * 0.5 + Vector2(0, 70)
    var radius := 22.0
    var fraction := float(action_state.get("fraction", 0.0))
    action_clock.draw_circle(c, radius + 3.0, Color(0, 0, 0, 0.55))
    if fraction > 0.0:
        var points := PackedVector2Array([c])
        var steps := maxi(2, int(48 * fraction))
        for i in steps + 1:
            var angle := -PI * 0.5 + TAU * fraction * float(i) / steps
            points.append(c + Vector2(cos(angle), sin(angle)) * radius)
        action_clock.draw_colored_polygon(points, Color(1.0, 0.85, 0.35, 0.85))
    action_clock.draw_arc(c, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 2.0)
    action_clock.draw_line(c, c + Vector2(0, -radius * 0.8), Color(1, 1, 1, 0.9), 2.0) # clock hand at 12
    var font := ThemeDB.fallback_font
    var text := "%s  %.1f s" % [action_state.get("label", ""), float(action_state.get("left", 0.0))]
    var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
    action_clock.draw_string(font, c + Vector2(-width * 0.5 + 1, radius + 23), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, 0.9))
    action_clock.draw_string(font, c + Vector2(-width * 0.5, radius + 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))

## Spread (tangent of the cone half-angle) -> pixels at the current vertical FOV.
func _update_crosshair(delta: float) -> void:
    var camera: Camera3D = player.get("camera")
    var spread: float = player.call("current_spread")
    var half_height := crosshair.size.y * 0.5
    var target_gap := spread * half_height / tan(deg_to_rad(camera.fov) * 0.5) if camera != null else CROSSHAIR_MIN_GAP
    target_gap = clampf(target_gap, CROSSHAIR_MIN_GAP, CROSSHAIR_MAX_GAP)
    var ads := float(player.call("ads_amount"))
    var target_alpha := 1.0 - ads
    # The red dot appears only once the sights are nearly up.
    var target_red := smoothstep(0.6, 1.0, ads) if bool(player.call("ads_optic")) else 0.0
    var blend := 1.0 - exp(-delta * 18.0)
    var gap := lerpf(crosshair_gap, target_gap, blend)
    var alpha := lerpf(crosshair_arm_alpha, target_alpha, blend)
    var red := lerpf(crosshair_red_dot, target_red, blend)
    if absf(gap - crosshair_gap) > 0.01 or absf(alpha - crosshair_arm_alpha) > 0.005 or absf(red - crosshair_red_dot) > 0.005:
        crosshair_gap = gap
        crosshair_arm_alpha = alpha
        crosshair_red_dot = red
        crosshair.queue_redraw()

func return_to_menu() -> void:
    Input.action_release("fire")
    Input.action_release("aim")
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    Net.leave() # leaving an online match counts as elimination on the server
    get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _process(_delta: float) -> void:
    if player and hud:
        menu_button.visible = Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not quit_dialog.visible
        var scoped: bool = player.is_scope_active()
        scope_overlay.visible = scoped
        action_state = player.action_progress()
        action_clock.visible = not action_state.is_empty()
        if action_clock.visible:
            action_clock.queue_redraw()
        crosshair.visible = not scoped
        _update_crosshair(_delta)
        if scoped:
            scope_overlay.set_magnification(player.scope_zoom)
        var out := false
        if match_controller != null:
            out = match_controller.get("local_dead") or match_controller.get("finished")
            crosshair.visible = crosshair.visible and not out
        if ammo_hud != null:
            var in_car: bool = match_controller != null and match_controller.has_method("is_driving") and match_controller.call("is_driving")
            ammo_hud.set("suppressed", out or scoped or in_car)
            crosshair.visible = crosshair.visible and not in_car
        # Sem textos fixos na tela: controles só segurando F1 (dica nos primeiros segundos).
        _hint_time += _delta
        if Input.is_physical_key_pressed(KEY_F1):
            hud.text = HELP_TEXT
            hud.modulate.a = 1.0
        elif _hint_time < 8.0 and not out:
            hud.text = "F1: controles"
            hud.modulate.a = clampf(8.0 - _hint_time, 0.0, 1.0) * 0.8
        else:
            hud.text = ""
