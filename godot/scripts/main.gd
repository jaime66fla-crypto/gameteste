extends Node3D

const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const PlayerScript = preload("res://scripts/player.gd")
const WorldPolishScript = preload("res://scripts/world_polish.gd")
const ScopeScript = preload("res://scripts/sniper_scope.gd")
const AmbientAudioScript = preload("res://scripts/ambient_audio.gd")
var player: CharacterBody3D
var hud: Label
var crosshair: Label
var scope_overlay: Control

func _ready() -> void:
    _register_inputs()
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
    _build_ui()

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
    crosshair = Label.new()
    crosshair.text = "+"
    crosshair.add_theme_font_size_override("font_size", 25)
    crosshair.set_anchors_preset(Control.PRESET_CENTER)
    crosshair.position = Vector2(-8,-15)
    layer.add_child(crosshair)

func _process(_delta: float) -> void:
    if player and hud:
        var scoped: bool = player.is_scope_active()
        scope_overlay.visible = scoped
        crosshair.visible = not scoped
        if scoped:
            scope_overlay.set_magnification(player.scope_zoom)
        hud.text = "CAMPO DE FOGO  |  REBUILD\n" + player.status_text() + "\nWASD andar  SHIFT correr  CTRL agachar  ESPACO pular\n1 FUZIL  2 SNIPER  3 PISTOLA  |  4 Escopeta  5 SMG\nR recarregar  Direito mirar  Esquerdo atirar"
