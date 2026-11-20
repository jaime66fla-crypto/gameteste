extends Node
## Treino offline: o modo de construção da Sobrevivência (B) sem servidor e com
## material infinito, para testar as peças no campo de treino. Faz o papel do
## survival_controller.gd para o survival_building.gd (ui, inv, avisos).
##
##  B entra/sai   •   roda / Z C troca   •   R gira   •   clique coloca
##  X (segure) desmonta   •   V conserta   •   E abre porta / acende fogueira
const PointerMode = preload("res://scripts/pointer_mode.gd")
const BuildingScript = preload("res://scripts/survival/survival_building.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

var main_node: Node
var player: CharacterBody3D
var ui: CanvasLayer
var inv: Dictionary = {} # treino: não usado (material infinito)
var local_dead := false
var building_ctl: Node

var _toast_label: Label
var _toast_left := 0.0
var _prompt: Label
var _target: Dictionary = {}
var _was_building := false
var _stashed_melee: Callable
var _forced_holster := false

func setup(main: Node, local_player: CharacterBody3D) -> void:
	main_node = main
	player = local_player

func _ready() -> void:
	name = "TrainingBuild"
	ui = CanvasLayer.new()
	ui.name = "BuildUi"
	ui.layer = 5
	add_child(ui)
	_toast_label = Label.new()
	_toast_label.anchor_left = 0.5
	_toast_label.anchor_right = 0.5
	_toast_label.anchor_top = 0.3
	_toast_label.offset_left = -400
	_toast_label.offset_right = 400
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 20)
	_toast_label.add_theme_font_override("font", UiTheme.font(700))
	_toast_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_toast_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.visible = false
	ui.add_child(_toast_label)
	_prompt = Label.new()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.62
	_prompt.offset_left = -400
	_prompt.offset_right = 400
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 15)
	_prompt.add_theme_color_override("font_color", UiTheme.TEXT)
	_prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	ui.add_child(_prompt)
	building_ctl = BuildingScript.new()
	building_ctl.set("offline", true)
	building_ctl.call("setup", self, main_node, player)
	add_child(building_ctl)
	building_ctl.call("start", {"tag": "treino"})

# ------------------------------------------- o que o survival_building usa ---

func is_driving() -> bool:
	return false

func ui_open() -> bool:
	return building_ctl != null and bool(building_ctl.call("ui_open"))

func is_building() -> bool:
	return building_ctl != null and bool(building_ctl.get("building"))

func _toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.visible = true
	_toast_left = 1.8

func _timed_action(_kind: String, _seconds: float) -> void:
	pass

func open_manual(_kind: String) -> void:
	_toast("MANUAL SÓ NA SOBREVIVÊNCIA")

# ------------------------------------------------------------------ laço ---

func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast_label.visible = false
	var on := is_building()
	if on != _was_building:
		_was_building = on
		_arm_for_building(on)
	_target = {} if on or ui_open() else building_ctl.call("interact_target", player.global_position)
	_prompt.visible = not _target.is_empty()
	if _prompt.visible:
		_prompt.text = str(_target.get("label", ""))

## No modo de construção o clique coloca a peça: guarda a arma e o bastão.
func _arm_for_building(on: bool) -> void:
	if on:
		_forced_holster = not bool(player.get("weapon_holstered"))
		if _forced_holster:
			player.call("_toggle_weapon_holster")
		_stashed_melee = player.get("melee_handler")
		player.set("melee_handler", Callable())
	else:
		if _stashed_melee.is_valid():
			player.set("melee_handler", _stashed_melee)
		_stashed_melee = Callable()
		if _forced_holster and bool(player.get("weapon_holstered")) and str(player.get("melee_weapon")).is_empty():
			player.call("_toggle_weapon_holster")
		_forced_holster = false

func _unhandled_input(event: InputEvent) -> void:
	if not PointerMode.is_captured() and not (event is InputEventKey):
		return
	if bool(building_ctl.call("handle_input", event)):
		get_viewport().set_input_as_handled()
		return
	if not _target.is_empty() and event.is_pressed() and not event.is_echo() and InputMap.has_action("interact") and event.is_action("interact"):
		building_ctl.call("interact", str(_target["id"]))
		get_viewport().set_input_as_handled()
