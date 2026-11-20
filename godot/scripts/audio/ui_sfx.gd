extends Node
## Sons de interface (Kenney "UI Audio", CC0 — ver assets/audio/ui/LICENSE).
## Autoload "UiSfx": liga sozinho TODO botão que entra na árvore (clique e
## passar o mouse), então menu, loja, inventário, painéis etc. já saem com som.
## Para outros pontos chame UiSfx.play(&"open") / &"close" / &"toggle"...
## Um botão que não deve tocar nada: button.set_meta(&"no_ui_sfx", true).

const SOUNDS := {
	&"click": ["res://assets/audio/ui/click1.ogg", -9.0],
	&"confirm": ["res://assets/audio/ui/click3.ogg", -8.0],
	&"hover": ["res://assets/audio/ui/rollover2.ogg", -19.0],
	&"toggle": ["res://assets/audio/ui/switch2.ogg", -11.0],
	&"open": ["res://assets/audio/ui/switch7.ogg", -10.0],
	&"close": ["res://assets/audio/ui/switch34.ogg", -11.0],
	&"tab": ["res://assets/audio/ui/switch33.ogg", -13.0],
}
const HOVER_GAP_MS := 45 # passar o mouse rápido por uma lista não vira metralhadora

var _players: Dictionary = {}
var _last_hover_ms := 0
var _enabled := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # toca também com o jogo pausado
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	for key in SOUNDS:
		var entry: Array = SOUNDS[key]
		var stream := load(entry[0]) as AudioStream
		if stream == null:
			continue
		var p := AudioStreamPlayer.new()
		p.name = "Ui_%s" % key
		p.stream = stream
		p.volume_db = float(entry[1])
		p.max_polyphony = 3
		add_child(p)
		_players[key] = p
	get_tree().node_added.connect(_on_node_added)
	_hook_tree(get_tree().root)

func _hook_tree(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_hook_tree(child)

func play(kind: StringName, pitch_jitter: float = 0.04) -> void:
	if not _enabled or not _players.has(kind):
		return
	var p: AudioStreamPlayer = _players[kind]
	p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var b := node as BaseButton
		if b.has_meta(&"_ui_sfx") or b.has_meta(&"no_ui_sfx"):
			return
		b.set_meta(&"_ui_sfx", true)
		b.pressed.connect(_on_pressed.bind(b))
		b.mouse_entered.connect(_on_hover.bind(b))
	elif node is TabBar:
		(node as TabBar).tab_clicked.connect(func(_i): play(&"tab"))
	elif node is TabContainer:
		(node as TabContainer).tab_clicked.connect(func(_i): play(&"tab"))

func _on_pressed(b: BaseButton) -> void:
	if b.toggle_mode or b is CheckBox or b is CheckButton:
		play(&"toggle")
	elif b is OptionButton or b is MenuButton:
		play(&"open")
	else:
		play(&"click")

func _on_hover(b: BaseButton) -> void:
	if b.disabled or not b.is_visible_in_tree() or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hover_ms < HOVER_GAP_MS:
		return
	_last_hover_ms = now
	play(&"hover", 0.06)
