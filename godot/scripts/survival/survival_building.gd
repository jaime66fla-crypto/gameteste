extends Node
## Construção da Sobrevivência (lado do jogo). O servidor (src/godot-survival.js)
## é dono das peças; aqui elas são desenhadas, e o modo de construção (B)
## mostra a prévia encaixada na grade e pede cada peça ao servidor.
##
##  B          entra/sai do modo de construção
##  roda / Z C troca a peça      R gira      clique coloca
##  X (segure) desmonta a sua peça na mira      V conserta
##  Fora do modo: E abre porta/baú/fogueira, V na sua porta libera a base para amigos.
const PointerMode = preload("res://scripts/pointer_mode.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const Rules = preload("res://scripts/survival/building_rules.gd")
const Model = preload("res://scripts/survival/building_model.gd")
const ORDER := ["foundation", "wall", "doorway", "window", "door", "floor", "stairs", "roof", "campfire", "chest", "bed"]
const DEMOLISH_TIME := 1.5
const USE_REACH := 2.6 # porta/baú/fogueira com E

var controller: Node # survival_controller.gd
var main_node: Node
var player: CharacterBody3D
var rules = Rules.new()
var nodes: Dictionary = {} # id -> Node3D
var my_tag := ""
var auth: Array = [] # quem eu liberei: [{tag, name}]
var allowed: Array = [] # donos que me liberaram
var building := false
var selected := 0
var rotation_step := 0
var bed_ready_at := 0.0 # Time (s) em que a minha cama fica pronta

var _ghost: Node3D
var _ghost_key := ""
var _candidate: Dictionary = {}
var _candidate_error := ""
var _aimed_id := "" # peça na mira (modo de construção)
var _bar: PanelContainer
var _bar_row: HBoxContainer
var _hint: Label
var _status: Label
var _auth_panel: PanelContainer
var _auth_list: VBoxContainer
var _timer := 0.0

func setup(survival: Node, main: Node, local_player: CharacterBody3D) -> void:
	controller = survival
	main_node = main
	player = local_player

func _ready() -> void:
	name = "SurvivalBuilding"
	_build_ui()

# ------------------------------------------------------------------- rede ---

func start(info: Dictionary) -> void:
	my_tag = str(info.get("tag", ""))
	auth = info.get("auth", [])
	allowed = info.get("allowed", [])
	for entry in info.get("builds", []):
		_place(entry)

## Mensagens do servidor sobre construções. Devolve true se tratou.
func on_message(data: Dictionary) -> bool:
	match str(data.get("t", "")):
		"bp":
			_place(data.get("b", {}))
		"bhp":
			var id := str(data.get("id", ""))
			var piece: Dictionary = rules.pieces.get(id, {})
			if not piece.is_empty():
				var old := float(piece.get("hp", 0))
				piece["hp"] = float(data.get("hp", old))
				if float(piece["hp"]) < old and nodes.has(id):
					_chips(rules.center(piece))
		"bgone":
			for id in data.get("l", []):
				_remove(str(id))
		"auth":
			auth = data.get("l", [])
			_refresh_auth()
		"allowed":
			allowed = data.get("l", [])
		_:
			return false
	return true

func _place(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	if id.is_empty():
		return
	var old: Dictionary = rules.pieces.get(id, {})
	rules.add(entry)
	if str(entry.get("kind", "")) == "bed" and str(entry.get("ow", "")) == my_tag:
		bed_ready_at = Time.get_ticks_msec() / 1000.0 + float(entry.get("cd", 0))
	# Atualização (porta abriu, fogueira acendeu): mexe só no que mudou.
	if not old.is_empty() and nodes.has(id):
		match str(entry.get("kind", "")):
			"door":
				if bool(old.get("open", false)) != bool(entry.get("open", false)):
					Model.set_door_open(nodes[id], bool(entry.get("open", false)), int(entry.get("r", 0)))
					_door_sound(rules.center(entry))
			"campfire":
				Model.set_fire(nodes[id], bool(entry.get("on", false)))
		return
	var node := Model.build(entry, rules)
	main_node.add_child(node)
	nodes[id] = node
	if old.is_empty() and str(entry.get("ow", "")) == my_tag:
		_build_sound(rules.center(entry))

func _remove(id: String) -> void:
	var piece: Dictionary = rules.pieces.get(id, {})
	rules.erase(id)
	if nodes.has(id):
		var node: Node3D = nodes[id]
		nodes.erase(id)
		if not piece.is_empty():
			_dust(rules.center(piece), str(piece.get("kind", "")))
		node.queue_free()
	if id == _aimed_id:
		_aimed_id = ""

func owns(piece: Dictionary) -> bool:
	var ow := str(piece.get("ow", ""))
	return ow == my_tag or allowed.has(ow)

func has_bed() -> bool:
	for piece in rules.pieces.values():
		if str(piece.get("kind", "")) == "bed" and str(piece.get("ow", "")) == my_tag:
			return true
	return false

func bed_wait() -> float:
	return maxf(0.0, bed_ready_at - Time.get_ticks_msec() / 1000.0)

## Id da peça de um corpo atingido (raio, golpe, zumbi), ou "".
static func build_id_of(collider: Object) -> String:
	if collider != null and collider is Node and (collider as Node).has_meta("build_id"):
		return str((collider as Node).get_meta("build_id"))
	return ""

# -------------------------------------------------------- uso fora do modo ---

## Porta, baú ou fogueira perto (para o E do controlador): {} se nada.
func interact_target(me: Vector3) -> Dictionary:
	var best := {}
	var best_d := USE_REACH
	for id in rules.pieces:
		var piece: Dictionary = rules.pieces[id]
		var kind := str(piece.get("kind", ""))
		if not kind in ["door", "chest", "campfire"]:
			continue
		var c: Vector3 = rules.center(piece)
		if absf(c.y - me.y) > 2.2:
			continue
		var d := Vector2(c.x - me.x, c.z - me.z).length()
		if d >= best_d:
			continue
		best_d = d
		var label := ""
		match kind:
			"door":
				if owns(piece):
					label = "[E] " + ("Fechar" if bool(piece.get("open", false)) else "Abrir") + " a porta"
					if str(piece.get("ow", "")) == my_tag:
						label += "   •   [%s] Liberar a base para amigos" % _key("build_repair")
				else:
					label = "Porta trancada (de outro jogador)"
			"chest":
				label = "[E] Abrir o baú"
			"campfire":
				label = "[E] " + ("Apagar" if bool(piece.get("on", false)) else "Acender") + " a fogueira"
		best = {"type": "build", "id": id, "kind": kind, "label": label + _hp_note(piece)}
	return best

func interact(id: String) -> void:
	var piece: Dictionary = rules.pieces.get(id, {})
	match str(piece.get("kind", "")):
		"door":
			if owns(piece):
				Net.send({"t": "door", "b": id})
			else:
				controller.call("_toast", "PORTA TRANCADA")
		"chest":
			if player.call("start_channel", "ABRINDO", 0.5, func(): Net.send({"t": "search", "k": id})):
				controller.call("_timed_action", "open", 0.5)
		"campfire":
			Net.send({"t": "fire", "b": id})

func _hp_note(piece: Dictionary) -> String:
	var max_hp := float(rules.defs.get(str(piece.get("kind", "")), {}).get("hp", 100))
	var hp := float(piece.get("hp", max_hp))
	return "" if hp >= max_hp else "   (%d%%)" % roundi(hp / max_hp * 100.0)

# --------------------------------------------------------- modo construção ---

func toggle() -> void:
	set_building(not building)

func set_building(on: bool) -> void:
	building = on
	_bar.visible = on
	_status.visible = on
	if not on:
		_clear_ghost()
	else:
		_refresh_bar()

func _clear_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_ghost_key = ""
	_candidate = {}

func selected_kind() -> String:
	return ORDER[selected]

func cycle(step: int) -> void:
	selected = posmod(selected + step, ORDER.size())
	rotation_step = 0
	_refresh_bar()

## Teclas do modo (e V fora dele). Devolve true se usou o evento.
func handle_input(event: InputEvent) -> bool:
	if _auth_panel.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			close_auth()
			return true
		return false
	if _pressed(event, "build"):
		toggle()
		return true
	if not building:
		if _pressed(event, "build_repair"):
			var target := interact_target(player.global_position)
			if not target.is_empty() and str(target["kind"]) == "door" and str(rules.pieces[target["id"]].get("ow", "")) == my_tag:
				open_auth()
				return true
		return false
	if event is InputEventMouseButton and event.pressed and PointerMode.is_captured():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle(-1)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle(1)
			return true
	if _pressed(event, "build_next"):
		cycle(1)
		return true
	if _pressed(event, "build_prev"):
		cycle(-1)
		return true
	if _pressed(event, "build_rotate"):
		rotation_step = (rotation_step + 1) % 4
		_ghost_key = ""
		return true
	if _pressed(event, "fire") and PointerMode.is_captured():
		_place_selected()
		return true
	if _pressed(event, "build_remove"):
		_demolish_aimed()
		return true
	if _pressed(event, "build_repair"):
		_repair_aimed()
		return true
	return false

func _pressed(event: InputEvent, action: String) -> bool:
	return (event is InputEventKey or event is InputEventMouseButton or event is InputEventAction) and event.is_pressed() and not event.is_echo() and InputMap.has_action(action) and event.is_action(action)

func _place_selected() -> void:
	if _candidate.is_empty():
		controller.call("_toast", "MIRE ONDE QUER CONSTRUIR")
		return
	if not _candidate_error.is_empty():
		controller.call("_toast", _candidate_error.to_upper())
		return
	var msg := {"t": "build"}
	msg.merge(_candidate)
	Net.send(msg)

func _demolish_aimed() -> void:
	var piece: Dictionary = rules.pieces.get(_aimed_id, {})
	if piece.is_empty():
		controller.call("_toast", "MIRE NUMA PEÇA SUA PARA DESMONTAR")
		return
	if str(piece.get("ow", "")) != my_tag:
		controller.call("_toast", "SÓ O DONO PODE DESMONTAR")
		return
	var id := _aimed_id
	player.call("start_channel", "DESMONTANDO", DEMOLISH_TIME, func(): Net.send({"t": "bdel", "b": id}))

func _repair_aimed() -> void:
	var piece: Dictionary = rules.pieces.get(_aimed_id, {})
	if piece.is_empty():
		controller.call("_toast", "MIRE NUMA PEÇA PARA CONSERTAR")
		return
	Net.send({"t": "brep", "b": _aimed_id})

# ------------------------------------------------------------------ mira ---

func _process(delta: float) -> void:
	if not building:
		return
	if bool(controller.get("local_dead")) or bool(controller.call("is_driving")):
		set_building(false)
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.05
	var aim := _aim()
	_aimed_id = str(aim.get("build", ""))
	var kind := selected_kind()
	_candidate = _candidate_for(kind, aim)
	_candidate_error = ""
	if _candidate.is_empty():
		_clear_ghost()
		_status.text = _aimed_text()
		return
	_candidate_error = rules.check(_candidate, owns)
	if _candidate_error.is_empty():
		var c: Vector3 = rules.center(_candidate)
		if Vector2(c.x - player.global_position.x, c.z - player.global_position.z).length() > float(SurvivalData.catalog().get("build_rules", {}).get("reach", 7.0)):
			_candidate_error = "Longe demais."
	if _candidate_error.is_empty():
		var missing := _missing(kind)
		if not missing.is_empty():
			_candidate_error = missing
	var key := "%s|%s" % [kind, str(_candidate)]
	if key != _ghost_key:
		_clear_ghost_node()
		_ghost = Model.make_ghost(_candidate, rules)
		main_node.add_child(_ghost)
		_ghost_key = key
	Model.paint_ghost(_ghost, _candidate_error.is_empty())
	var title := str(rules.defs[kind].get("name", kind))
	_status.text = (title + ": " + (_candidate_error if not _candidate_error.is_empty() else "clique para construir")) + _aimed_text()

func _clear_ghost_node() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null

func _aimed_text() -> String:
	var piece: Dictionary = rules.pieces.get(_aimed_id, {})
	if piece.is_empty():
		return ""
	var name_text := str(rules.defs.get(str(piece.get("kind", "")), {}).get("name", ""))
	var mine := str(piece.get("ow", "")) == my_tag
	var text := "\nNa mira: %s%s" % [name_text, _hp_note(piece)]
	if mine:
		text += "   •   [%s] desmontar (segure)   [%s] consertar" % [_key("build_remove"), _key("build_repair")]
	elif owns(piece):
		text += "   •   [%s] consertar" % _key("build_repair")
	else:
		text += "  (de outro jogador)"
	return text

func _missing(kind: String) -> String:
	var cost: Dictionary = rules.defs[kind].get("cost", {})
	var inv: Dictionary = controller.get("inv")
	for item in cost:
		if int(inv.get(item, 0)) < int(cost[item]):
			return "falta %s (%d/%d)" % [SurvivalData.item_name(str(item)).to_lower(), int(inv.get(item, 0)), int(cost[item])]
	return ""

## Raio da câmera pela mira: ponto (um pouco antes da superfície), normal e peça atingida.
func _aim() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var reach := float(SurvivalData.catalog().get("build_rules", {}).get("reach", 7.0))
	var length := from.distance_to(player.global_position + Vector3(0, 1.4, 0)) + reach
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * length, HitboxScript.LAYER_WORLD)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"point": from + dir * length, "surface": from + dir * length, "normal": Vector3.ZERO, "build": "", "dir": dir}
	return {"point": (hit["position"] as Vector3) - dir * 0.05, "surface": hit["position"], "normal": hit["normal"], "build": build_id_of(hit["collider"]), "dir": dir, "hit": true}

## Giro automático (escada sobe e telhado cai para longe de quem constrói) + o giro de R.
func _auto_rotation() -> int:
	var cam := get_viewport().get_camera_3d()
	var f := -cam.global_basis.z
	# r gira o -Z local: r = 0 aponta -Z, r = 1 aponta -X, r = 2 +Z, r = 3 +X.
	var yaw := atan2(-f.x, -f.z)
	return posmod(roundi(yaw / (PI * 0.5)) + rotation_step, 4)

## Lugar da peça na grade para onde se está mirando ({} = nenhum).
func _candidate_for(kind: String, aim: Dictionary) -> Dictionary:
	if aim.is_empty():
		return {}
	var S: float = rules.S
	var H: float = rules.H
	var slot: String = rules.slot_type(kind)
	var a: Vector3 = aim["point"]
	var aimed: Dictionary = rules.pieces.get(str(aim.get("build", "")), {})
	var aimed_slot: String = rules.slot_type(str(aimed.get("kind", ""))) if not aimed.is_empty() else ""
	var i := floori(a.x / S)
	var j := floori(a.z / S)
	match slot:
		"cell":
			if kind == "foundation":
				if not bool(aim.get("hit", false)):
					return {}
				var p := {"kind": kind, "i": i, "j": j, "k": 0}
				if rules.slots.has(rules.slot_of(p)):
					p = _neighbor(p, a)
				return p
			var k := clampi(roundi((a.y - rules.base) / H), 1, Rules.MAX_LEVEL)
			var p := {"kind": kind, "i": i, "j": j, "k": k, "r": _auto_rotation()}
			if aimed_slot == "edge":
				# Mirando uma parede: o teto vai em cima dela, do lado de quem constrói.
				var best := []
				var best_d := INF
				for c in Rules.edge_cells(str(aimed["o"]), int(aimed["i"]), int(aimed["j"])):
					var cc := Vector2((c[0] + 0.5) * S, (c[1] + 0.5) * S)
					var d := cc.distance_to(Vector2(player.global_position.x, player.global_position.z))
					if d < best_d:
						best_d = d
						best = c
				p = {"kind": kind, "i": best[0], "j": best[1], "k": int(aimed["k"]) + 1, "r": _auto_rotation()}
			elif aimed_slot == "cell":
				p["k"] = maxi(1, int(aimed["k"]))
				p["i"] = int(aimed["i"])
				p["j"] = int(aimed["j"])
				if rules.slots.has(rules.slot_of(p)):
					p = _neighbor(p, a)
			return p
		"stairs":
			if not aimed.is_empty() and aimed_slot == "cell" and str(aimed["kind"]) in ["foundation", "floor"]:
				return {"kind": kind, "i": int(aimed["i"]), "j": int(aimed["j"]), "k": int(aimed["k"]), "r": _auto_rotation()}
			var k := clampi(floori((a.y - rules.base + 0.5) / H), 0, Rules.MAX_LEVEL)
			return {"kind": kind, "i": i, "j": j, "k": k, "r": _auto_rotation()}
		"edge", "door":
			if kind == "door" and str(aimed.get("kind", "")) == "doorway":
				return {"kind": kind, "i": int(aimed["i"]), "j": int(aimed["j"]), "k": int(aimed["k"]), "o": str(aimed["o"]), "r": rotation_step % 2}
			var k := clampi(floori((a.y - rules.base) / H), 0, Rules.MAX_LEVEL)
			var u := a.x / S - i
			var v := a.z / S - j
			var options := [[v, "h", i, j], [1.0 - v, "h", i, j + 1], [u, "v", i, j], [1.0 - u, "v", i + 1, j]]
			options.sort_custom(func(x, y): return x[0] < y[0])
			var o: String = options[0][1]
			var p := {"kind": kind, "i": int(options[0][2]), "j": int(options[0][3]), "k": k, "o": o}
			if kind == "door":
				p["r"] = rotation_step % 2
				return p
			# Parede em cima de parede: mirando uma parede, sobe um andar.
			if not rules.edge_at(o, int(p["i"]), int(p["j"]), k).is_empty():
				p["k"] = k + 1
			return p
	# Peça livre: no chão ou em cima de piso, virada para quem constrói.
	if not bool(aim.get("hit", false)) or (aim["normal"] as Vector3).y < 0.7:
		return {}
	var s: Vector3 = aim["surface"]
	var y := 0.0 if s.y < 0.15 else s.y
	var cam := get_viewport().get_camera_3d()
	var f := -cam.global_basis.z
	var yaw := atan2(f.x, f.z) + PI + rotation_step * PI * 0.5
	return {"kind": kind, "p": [snappedf(s.x, 0.01), snappedf(y, 0.01), snappedf(s.z, 0.01)], "y": snappedf(wrapf(yaw, -PI, PI), 0.01)}

## Célula vizinha na direção em que se mira (para emendar fundação/piso).
func _neighbor(p: Dictionary, a: Vector3) -> Dictionary:
	var S: float = rules.S
	var dx := a.x - (int(p["i"]) + 0.5) * S
	var dz := a.z - (int(p["j"]) + 0.5) * S
	var out := p.duplicate()
	if absf(dx) > absf(dz):
		out["i"] = int(p["i"]) + (1 if dx > 0 else -1)
	else:
		out["j"] = int(p["j"]) + (1 if dz > 0 else -1)
	return out

# ------------------------------------------------------------- liberar base ---

func open_auth() -> void:
	_auth_panel.visible = true
	_refresh_auth()
	PointerMode.release()

func close_auth() -> void:
	_auth_panel.visible = false
	PointerMode.capture()

func ui_open() -> bool:
	return _auth_panel != null and _auth_panel.visible

func _refresh_auth() -> void:
	if _auth_list == null:
		return
	for child in _auth_list.get_children():
		child.queue_free()
	if auth.is_empty():
		var empty := Label.new()
		empty.text = "Ninguém liberado ainda."
		empty.add_theme_color_override("font_color", Color("#8e979e"))
		_auth_list.add_child(empty)
	for entry in auth:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(entry.get("name", "?"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Tirar"
		remove.focus_mode = Control.FOCUS_NONE
		var tag := str(entry.get("tag", ""))
		remove.pressed.connect(func(): Net.send({"t": "auth_del", "tag": tag}))
		row.add_child(remove)
		_auth_list.add_child(row)

# ------------------------------------------------------------------- tela ---

func _key(action: String) -> String:
	var events := InputMap.action_get_events(action) if InputMap.has_action(action) else []
	if events.is_empty():
		return "?"
	var e: InputEvent = events[0]
	if e is InputEventKey:
		return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	if e is InputEventMouseButton:
		return "Clique" if (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT else "Mouse"
	return "?"

func _build_ui() -> void:
	var ui: CanvasLayer = controller.get("ui")
	_bar = PanelContainer.new()
	_bar.visible = false
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.offset_bottom = -14
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.1, 0.82)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_bar.add_theme_stylebox_override("panel", style)
	ui.add_child(_bar)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_bar.add_child(column)
	_bar_row = HBoxContainer.new()
	_bar_row.add_theme_constant_override("separation", 6)
	column.add_child(_bar_row)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color("#c9c4b4"))
	column.add_child(_hint)
	_status = Label.new()
	_status.visible = false
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.anchor_top = 0.56
	_status.offset_left = -420
	_status.offset_right = 420
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color("#ffe08a"))
	_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_status)
	# Janela "liberar a base".
	_auth_panel = PanelContainer.new()
	_auth_panel.visible = false
	_auth_panel.set_anchors_preset(Control.PRESET_CENTER)
	_auth_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_auth_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_auth_panel.custom_minimum_size = Vector2(420, 260)
	var panel_style := style.duplicate() as StyleBoxFlat
	panel_style.bg_color = Color("#14181c")
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color("#323b44")
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 14
	panel_style.content_margin_bottom = 14
	_auth_panel.add_theme_stylebox_override("panel", panel_style)
	ui.add_child(_auth_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_auth_panel.add_child(box)
	var title := Label.new()
	title.text = "LIBERAR A BASE"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#d9b44a"))
	box.add_child(title)
	var about := Label.new()
	about.text = "Quem você liberar abre todas as suas portas, constrói junto e conserta. Só você desmonta."
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.add_theme_font_size_override("font_size", 13)
	about.add_theme_color_override("font_color", Color("#c9c4b4"))
	box.add_child(about)
	_auth_list = VBoxContainer.new()
	_auth_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_auth_list)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var add := Button.new()
	add.text = "Liberar quem está perto (6 m)"
	add.focus_mode = Control.FOCUS_NONE
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.pressed.connect(func(): Net.send({"t": "auth_add"}))
	buttons.add_child(add)
	var close := Button.new()
	close.text = "Fechar"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_auth)
	buttons.add_child(close)

func _refresh_bar() -> void:
	for child in _bar_row.get_children():
		child.queue_free()
	var inv: Dictionary = controller.get("inv")
	for index in ORDER.size():
		var kind: String = ORDER[index]
		var def: Dictionary = rules.defs.get(kind, {})
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(6)
		s.bg_color = Color("#3b3326") if index == selected else Color("#20262c")
		s.border_color = Color("#d9b44a") if index == selected else Color("#323b44")
		s.set_border_width_all(2 if index == selected else 1)
		s.content_margin_left = 8
		s.content_margin_right = 8
		s.content_margin_top = 4
		s.content_margin_bottom = 4
		card.add_theme_stylebox_override("panel", s)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		card.add_child(col)
		var name_label := Label.new()
		name_label.text = str(def.get("name", kind))
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_color_override("font_color", Color("#f0e6c8") if index == selected else Color("#c9c4b4"))
		col.add_child(name_label)
		var parts: Array[String] = []
		var enough := true
		var cost: Dictionary = def.get("cost", {})
		for item in cost:
			parts.append("%d %s" % [int(cost[item]), _short(str(item))])
			enough = enough and int(inv.get(item, 0)) >= int(cost[item])
		var cost_label := Label.new()
		cost_label.text = " · ".join(parts)
		cost_label.add_theme_font_size_override("font_size", 11)
		cost_label.add_theme_color_override("font_color", Color("#8fbf8a") if enough else Color("#b36a5e"))
		col.add_child(cost_label)
		_bar_row.add_child(card)
	_hint.text = "Clique constrói  •  roda do mouse / %s %s troca  •  %s gira  •  %s (segure) desmonta  •  %s conserta  •  %s sai" % [
		_key("build_prev"), _key("build_next"), _key("build_rotate"), _key("build_remove"), _key("build_repair"), _key("build")]

static func _short(item: String) -> String:
	return str({"wood": "tora", "stone": "pedra", "fiber": "fibra", "rope": "corda", "stick": "galho"}.get(item, SurvivalData.item_name(item).to_lower()))

## O inventário mudou: o custo na barra muda de cor.
func inventory_changed() -> void:
	if building:
		_refresh_bar()

# --------------------------------------------------------------- efeitos ---

func _chips(at: Vector3) -> void:
	_burst(at, Color("#6a5640"), 10, 0.05)

func _dust(at: Vector3, kind: String) -> void:
	_burst(at, Color("#4a4036") if kind != "foundation" else Color("#6e6a62"), 28, 0.12)

func _burst(at: Vector3, color: Color, amount: int, size: float) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = 0.8
	particles.explosiveness = 0.95
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 3.5
	particles.scale_amount_min = size * 0.6
	particles.scale_amount_max = size
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	particles.mesh = mesh
	main_node.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	get_tree().create_timer(1.4).timeout.connect(particles.queue_free)

func _build_sound(at: Vector3) -> void:
	var fx = player.get("sound_fx")
	if fx != null and fx.has_method("melee_impact"):
		fx.call("melee_impact", false)
	_chips(at)

func _door_sound(_at: Vector3) -> void:
	var fx = player.get("sound_fx")
	if fx != null and fx.has_method("reload"):
		fx.call("reload")
