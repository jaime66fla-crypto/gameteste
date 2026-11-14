extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const WorldPolishScript = preload("res://scripts/world_polish.gd")
const AmbientAudioScript = preload("res://scripts/ambient_audio.gd")
var player: CharacterBody3D
var hud: Label
var crosshair: Label

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
    player.position = Vector3(0, 2, 0)
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
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.55, 0.72, 0.85)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.65, 0.72, 0.8)
    env.ambient_light_energy = 0.8
    world_environment.environment = env
    add_child(world_environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-45, -30, 0)
    sun.light_energy = 1.3
    sun.shadow_enabled = true
    add_child(sun)
    _block(Vector3(0,-0.5,0), Vector3(120,1,120), Color(0.28,0.39,0.26), true)
    for i in range(24):
        var x := float((i * 37) % 98 - 49)
        var z := float((i * 61) % 98 - 49)
        if absf(x) < 9 and absf(z) < 9:
            continue
        _block(Vector3(x, 0.35, z), Vector3(2.8, 0.7, 2.8), Color(0.38,0.42,0.38), true)
        _block(Vector3(x, 2.0, z), Vector3(0.75, 2.9, 0.75), Color(0.33,0.29,0.22), false)
        _block(Vector3(x, 3.9, z), Vector3(3.4, 2.5, 3.4), Color(0.16,0.35,0.19), false)
    for i in range(9):
        _block(Vector3(-15 + i * 4, 1, -18), Vector3(2.4, 2, 2.4), Color(0.39,0.37,0.30), true)

func _block(pos: Vector3, size: Vector3, color: Color, solid: bool) -> void:
    var root := StaticBody3D.new() if solid else Node3D.new()
    root.position = pos
    add_child(root)
    var mesh := MeshInstance3D.new()
    var cube := BoxMesh.new()
    cube.size = size
    mesh.mesh = cube
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mesh.material_override = mat
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
    hud = Label.new()
    hud.position = Vector2(22, 16)
    hud.add_theme_font_size_override("font_size", 18)
    layer.add_child(hud)
    crosshair = Label.new()
    crosshair.text = "+"
    crosshair.add_theme_font_size_override("font_size", 25)
    crosshair.set_anchors_preset(Control.PRESET_CENTER)
    crosshair.position = Vector2(-8,-15)
    layer.add_child(crosshair)

func _process(_delta: float) -> void:
    if player and hud:
        hud.text = "CAMPO DE FOGO | JAIME | GODOT\nWASD mover  SHIFT correr  ESPACO pular  CTRL agachar\n1 Pistola  2 SMG  3 Fuzil  4 Escopeta  5 Sniper\nDIREITO mirar  ESQUERDO atirar  R recarregar  ESC mouse\n" + player.status_text()
