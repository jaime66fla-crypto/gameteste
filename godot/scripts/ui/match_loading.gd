extends CanvasLayer
## Permanece acima das duas cenas até o mundo e o jogador estarem prontos.
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const PointerMode = preload("res://scripts/pointer_mode.gd")
const GAME := "res://scenes/main.tscn"
var _message: Label
var _bar: ProgressBar
var _retry: Button
var _requested := false
var _entered := false
var _failed_state := false

static func begin(tree: SceneTree) -> CanvasLayer:
    var existing := tree.root.get_node_or_null("MatchLoading") as CanvasLayer
    if existing != null:
        return existing
    var screen := CanvasLayer.new()
    screen.set_script(load("res://scripts/ui/match_loading.gd"))
    screen.name = "MatchLoading"
    tree.root.add_child(screen)
    return screen

func _ready() -> void:
    layer = 100
    PointerMode.release()
    var backdrop := ColorRect.new()
    backdrop.color = UiTheme.PANEL_SOLID
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(backdrop)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.add_child(center)
    var column := VBoxContainer.new()
    column.custom_minimum_size.x = 440
    column.add_theme_constant_override("separation", 18)
    center.add_child(column)
    var title := UiTheme.title("Preparando partida", 32)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(title)
    _message = Label.new()
    _message.text = "Iniciando carregamento…"
    _message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _message.add_theme_color_override("font_color", UiTheme.MUTED)
    column.add_child(_message)
    _bar = ProgressBar.new()
    _bar.custom_minimum_size.y = 12
    _bar.show_percentage = false
    column.add_child(_bar)
    _retry = Button.new()
    _retry.text = "Voltar ao menu"
    UiTheme.secondary(_retry, 16)
    _retry.pressed.connect(func():
        var net := get_tree().root.get_node_or_null("Net")
        if net != null:
            net.call("leave")
        get_tree().change_scene_to_file("res://scenes/menu.tscn")
        queue_free())
    column.add_child(_retry)
    _retry.hide()
    var net := get_tree().root.get_node_or_null("Net")
    if net != null:
        net.connect("connection_lost", _connection_lost)
    _request.call_deferred()

func _request() -> void:
    # Dois quadros permitem desenhar a tela antes de compilar/carregar recursos.
    await get_tree().process_frame
    await get_tree().process_frame
    if _failed_state:
        return
    var error := ResourceLoader.load_threaded_request(GAME)
    if error != OK:
        _failed()
        return
    _requested = true

func set_progress(message: String, fraction: float) -> void:
    if _failed_state:
        return
    _message.text = message
    _bar.value = maxf(_bar.value, clampf(fraction, 0, 1) * 100.0)

func _process(_delta: float) -> void:
    if _entered:
        var scene := get_tree().current_scene
        if scene != null and bool(scene.get("match_ready")):
            queue_free()
        return
    if not _requested:
        return
    var progress: Array = []
    var status := ResourceLoader.load_threaded_get_status(GAME, progress)
    if status == ResourceLoader.THREAD_LOAD_LOADED:
        _requested = false
        _enter_game.call_deferred()
    elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
        _failed()
    elif not progress.is_empty():
        set_progress("Carregando recursos…", float(progress[0]) * 0.45)

func _enter_game() -> void:
    set_progress("Preparando o cenário…", 0.46)
    await get_tree().process_frame
    if _failed_state:
        return
    var packed := ResourceLoader.load_threaded_get(GAME) as PackedScene
    if packed == null or get_tree().change_scene_to_packed(packed) != OK:
        _failed()
        return
    _entered = true

func _connection_lost(message: String) -> void:
    _failed(message)

func _failed(message: String = "Não foi possível carregar a partida.") -> void:
    _failed_state = true
    _requested = false
    _entered = false
    _message.text = message
    _retry.show()
    var scene := get_tree().current_scene
    if scene != null and scene.scene_file_path == GAME:
        scene.process_mode = Node.PROCESS_MODE_DISABLED
    PointerMode.release()
