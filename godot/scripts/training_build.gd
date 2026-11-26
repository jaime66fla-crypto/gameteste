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
const InventoryUI = preload("res://scripts/survival/inventory_ui.gd")
const ManualUI = preload("res://scripts/survival/survival_manual.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const HandTorch = preload("res://scripts/survival/hand_torch.gd")
const CARRY_CAP := 60.0 # kg que o jogador carrega no treino
const CHEST_REACH := 4.5 # longe disso o baú aberto fecha

var main_node: Node
var player: CharacterBody3D
var ui: CanvasLayer
## Treino: construir é grátis; esta mochila de exemplo só serve para testar o baú.
var inv: Dictionary = {"wood": 20, "stone": 15, "fiber": 20, "rope": 6, "stick": 10, "scrap": 6, "iron_bar": 4, "canned_food": 3, "water_bottle": 2, "torch": 5, "wood_shield": 1, "tactical_shield": 1}
var torch_in_hand := false
var shield_in_arm := ""
var inventory: Control # tela do inventário (com o baú do lado)
var manual: Control # manual de sobrevivência (só leitura no treino)
var _chest_id := ""
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
	inventory = InventoryUI.new()
	ui.add_child(inventory)
	inventory.connect("take_requested", func(k, item, _all): _take(str(k), str(item)))
	inventory.connect("take_all_requested", func(k):
		for item in _chest_items(str(k)).keys():
			_take(str(k), str(item)))
	inventory.connect("store_requested", func(k, item): _store(str(k), str(item)))
	inventory.connect("drop_requested", func(item, _all):
		inv.erase(item)
		_sync_inventory())
	inventory.connect("use_requested", func(item):
		if str(item) == "torch":
			set_torch(not torch_in_hand)
		elif SurvivalData.item(str(item)).has("shield"):
			set_shield("" if shield_in_arm == str(item) else str(item))
		else:
			_toast("SÓ NA SOBREVIVÊNCIA"))
	inventory.connect("place_requested", func(item):
		inventory.call("close")
		building_ctl.call("pick_bench", str(item)))
	for sig in ["craft_requested", "equip_requested", "unequip_requested"]:
		inventory.connect(sig, func(_x): _toast("SÓ NA SOBREVIVÊNCIA"))
	manual = ManualUI.new()
	ui.add_child(manual)
	manual.connect("craft_requested", func(_r): _toast("FABRICAR SÓ NA SOBREVIVÊNCIA"))
	_sync_inventory()

# ------------------------------------------- o que o survival_building usa ---

func is_driving() -> bool:
	return false

func ui_open() -> bool:
	return (building_ctl != null and bool(building_ctl.call("ui_open"))) or _panels_open()

func _panels_open() -> bool:
	return (inventory != null and inventory.visible) or (manual != null and manual.visible)

func is_building() -> bool:
	return building_ctl != null and bool(building_ctl.get("building"))

func _toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.visible = true
	_toast_left = 1.8

func _timed_action(_kind: String, _seconds: float) -> void:
	pass

func open_manual(kind: String = "") -> void:
	if inventory.visible:
		inventory.call("close")
	manual.call("open", kind)

# ------------------------------------------------------------ baú (treino) ---

## E no baú: abre o inventário com o baú do lado; clique guarda/pega a pilha.
func open_chest(id: String) -> void:
	if manual.visible:
		manual.call("close")
	_chest_id = id
	_show_chest()
	inventory.call("open")

func _chest_items(id: String) -> Dictionary:
	var piece: Dictionary = building_ctl.get("rules").pieces.get(id, {})
	if piece.is_empty():
		return {}
	if not piece.has("items"):
		piece["items"] = {}
	return piece["items"]

func _chest_cap() -> float:
	return float(SurvivalData.build_def("chest").get("carry", 80))

func _show_chest() -> void:
	var items := _chest_items(_chest_id)
	var title := "%s  (%.0f / %.0f kg)" % [SurvivalData.build_def("chest").get("name", "Baú"), SurvivalData.inventory_weight(items), _chest_cap()]
	inventory.call("show_container", _chest_id, title, items, true)

## Move até `n` de `item` de `from` para `to`, sem passar de `cap` kg em `to`.
func _move(from: Dictionary, to: Dictionary, item: String, cap: float) -> int:
	var w := float(SurvivalData.item(item).get("weight", 0.0))
	var n := int(from.get(item, 0))
	if w > 0.0:
		n = mini(n, floori((cap - SurvivalData.inventory_weight(to)) / w + 0.0001))
	if n <= 0:
		return 0
	to[item] = int(to.get(item, 0)) + n
	from[item] = int(from[item]) - n
	if int(from[item]) <= 0:
		from.erase(item)
	return n

func _store(k: String, item: String) -> void:
	if _move(inv, _chest_items(k), item, _chest_cap()) == 0:
		_toast("BAÚ CHEIO")
	_sync_inventory()

func _take(k: String, item: String) -> void:
	if _move(_chest_items(k), inv, item, CARRY_CAP) == 0:
		_toast("PESO DEMAIS")
	_sync_inventory()

func _sync_inventory() -> void:
	if torch_in_hand and int(inv.get("torch", 0)) <= 0:
		set_torch(false)
	if not shield_in_arm.is_empty() and int(inv.get(shield_in_arm, 0)) <= 0:
		set_shield("")
	inventory.call("set_inventory", inv, SurvivalData.inventory_weight(inv), CARRY_CAP)
	manual.call("set_inventory", inv)
	if not _chest_id.is_empty():
		_show_chest()

## Escudo no braço esquerdo (treino). Tira a tocha: a mão esquerda é uma só.
func set_shield(id: String) -> void:
	shield_in_arm = id if not id.is_empty() and int(inv.get(id, 0)) > 0 else ""
	if not shield_in_arm.is_empty() and torch_in_hand:
		set_torch(false)
	player.call("set_shield", shield_in_arm)
	inventory.set("shield_on", shield_in_arm)
	if inventory.visible:
		inventory.call("_refresh")

## Tocha na mão (treino): só aparece/some aqui, sem servidor.
func set_torch(on: bool) -> void:
	torch_in_hand = on and int(inv.get("torch", 0)) > 0
	if torch_in_hand and not shield_in_arm.is_empty():
		set_shield("")
	HandTorch.set_on(player, torch_in_hand)
	inventory.set("torch_lit", torch_in_hand)
	if inventory.visible:
		inventory.call("_refresh")

func _close_chest() -> void:
	_chest_id = ""
	inventory.call("clear_container")

# ------------------------------------------------------------------ laço ---

func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast_label.visible = false
	if not _chest_id.is_empty():
		var piece: Dictionary = building_ctl.get("rules").pieces.get(_chest_id, {})
		if piece.is_empty() or player.global_position.distance_to(building_ctl.get("rules").center(piece)) > CHEST_REACH:
			_close_chest()
		elif not inventory.visible:
			_close_chest()
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
	player.set("attack_blocked", on)
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
	# Inventório/manual abertos: Esc, Tab, L ou E fecham; o resto do jogo não recebe.
	if _panels_open():
		if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_ESCAPE or _is(event, "inventory") or _is(event, "manual") or _is(event, "interact")):
			if inventory.visible:
				inventory.call("close")
			if manual.visible:
				manual.call("close")
			get_viewport().set_input_as_handled()
		return
	if _is(event, "manual") and not is_building() and not bool(building_ctl.call("ui_open")):
		open_manual()
		get_viewport().set_input_as_handled()
		return
	if _is(event, "inventory") and not is_building() and not bool(building_ctl.call("ui_open")):
		inventory.call("open")
		get_viewport().set_input_as_handled()
		return
	if not PointerMode.is_captured() and not (event is InputEventKey):
		return
	if bool(building_ctl.call("handle_input", event)):
		get_viewport().set_input_as_handled()
		return
	if not _target.is_empty() and event.is_pressed() and not event.is_echo() and InputMap.has_action("interact") and event.is_action("interact"):
		building_ctl.call("interact", str(_target["id"]))
		get_viewport().set_input_as_handled()

func _is(event: InputEvent, action: String) -> bool:
	return event.is_pressed() and not event.is_echo() and InputMap.has_action(action) and event.is_action(action)
