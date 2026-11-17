extends Node3D

const GameSettings = preload("res://scripts/game_settings.gd")
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const PlayerScript = preload("res://scripts/player.gd")
const WorldPolishScript = preload("res://scripts/world_polish.gd")
const ScopeScript = preload("res://scripts/sniper_scope.gd")
const AmbientAudioScript = preload("res://scripts/ambient_audio.gd")
const MatchControllerScript = preload("res://scripts/net/match_controller.gd")
const TrainingDummyScript = preload("res://scripts/training_dummy.gd")
var player: CharacterBody3D
var hud: Label
var crosshair: Control
var action_clock: Control
var action_state: Dictionary = {}
var scope_overlay: Control
var menu_button: Button
var match_controller: Node3D # online matches only

func _ready() -> void:
    _register_inputs()
    Input.action_release("fire")
    Input.action_release("aim")
    var settings := GameSettings.load_settings()
    GameSettings.apply(settings,get_viewport())
    _build_world()
    var world_polish := Node3D.new()
    world_polish.name = "WorldPolish"
    world_polish.set_script(WorldPolishScript)
    add_child(world_polish)
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
    if Net.in_match:
        match_controller = Node3D.new()
        match_controller.set_script(MatchControllerScript)
        match_controller.call("setup", self, player)
        add_child(match_controller)
    else:
        _spawn_training_dummies()

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
        for pass_index in 2:
            var color := Color(0, 0, 0, 0.75) if pass_index == 0 else Color(1, 1, 1, 0.95)
            var width := 4.0 if pass_index == 0 else 2.0
            var arm := 9.0 if pass_index == 0 else 8.0
            crosshair.draw_line(c + Vector2(-arm, 0), c + Vector2(-2.5, 0), color, width)
            crosshair.draw_line(c + Vector2(2.5, 0), c + Vector2(arm, 0), color, width)
            crosshair.draw_line(c + Vector2(0, -arm), c + Vector2(0, -2.5), color, width)
            crosshair.draw_line(c + Vector2(0, 2.5), c + Vector2(0, arm), color, width)
        crosshair.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, 0.95)))
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
    menu_button.pressed.connect(return_to_menu)

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

func return_to_menu() -> void:
    Input.action_release("fire")
    Input.action_release("aim")
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    Net.leave() # leaving an online match counts as elimination on the server
    get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _process(_delta: float) -> void:
    if player and hud:
        menu_button.visible = Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
        var scoped: bool = player.is_scope_active()
        scope_overlay.visible = scoped
        action_state = player.action_progress()
        action_clock.visible = not action_state.is_empty()
        if action_clock.visible:
            action_clock.queue_redraw()
        crosshair.visible = not scoped
        if scoped:
            scope_overlay.set_magnification(player.scope_zoom)
        if match_controller != null:
            var out: bool = match_controller.get("local_dead") or match_controller.get("finished")
            crosshair.visible = crosshair.visible and not out
            hud.text = "" if out else player.status_text() + "\n1-5 armas (ordem em que pegou)  E coletar  F kit médico  G granada (segure p/ mirar)  R recarregar  Direito mirar (+Q/E inclinar)  |  ESC: sair da partida"
            return
        hud.text = "CAMPO DE FOGO  |  REBUILD\n" + player.status_text() +"\nWASD andar  SHIFT correr  CTRL agachar  ESPACO pular\nQ soco  E cotovelada  G granada (segure p/ mirar)  |  mirando: Q/E inclinar\n1 FUZIL  2 SNIPER  3 PISTOLA  |  4 Escopeta  5 SMG\nR recarregar  Direito mirar  Esquerdo atirar  |  ESC: liberar cursor"
