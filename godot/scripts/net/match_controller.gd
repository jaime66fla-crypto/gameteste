extends Node3D
## Runs an online elimination match inside main.tscn (added by main.gd when
## Net.in_match is set). The server owns health; this node mirrors it.
const NetActorScript = preload("res://scripts/net/net_actor.gd")
const WeaponData = preload("res://scripts/weapon_data.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const CombatFeedbackScript = preload("res://scripts/net/combat_feedback.gd")
const STATE_RATE := 1.0 / 15.0
const BOT_RATE := 1.0 / 10.0
const MatchLayout = preload("res://scripts/net/match_layout.gd")
const LootCrateScript = preload("res://scripts/net/loot_crate.gd")
const LOOT_REACH := 2.4 # metres; the server allows a little more for latency
const LABEL_RANGE := 9.0

var main_node: Node
var player: CharacterBody3D
var actors: Dictionary = {} # id -> NetActor
var crates: Dictionary = {} # id -> LootCrate
var loot_prompt: Label
var _pending_loot := ""
var names: Dictionary = {} # id -> display name
var my_id := ""
var alive_count := 8
var my_hp := 100.0
var my_kills := 0
var local_dead := false
var finished := false
var _state_timer := 0.0
var _bot_timer := 0.0
# Spectator camera after death.
var spectate_camera: Camera3D
var spectate_index := 0
# UI
var ui: CanvasLayer
var status_label: Label
var health_bar: ProgressBar
var feed: VBoxContainer
var center_panel: PanelContainer
var center_title: Label
var center_body: Label
var damage_flash: ColorRect
var combat_feedback: Control

func setup(main: Node, local_player: CharacterBody3D) -> void:
	main_node = main
	player = local_player

func _ready() -> void:
	name = "MatchController"
	my_id = Net.my_id
	_build_ui()
	var info: Dictionary = Net.start_info
	alive_count = int(info.get("alive", 8))
	for crate_data in info.get("crates", []):
		_add_crate(crate_data)
	player.call("start_unarmed")
	player.set("interact_handler", _try_loot)
	for entry in info.get("roster", []):
		var id := str(entry["id"])
		names[id] = str(entry["name"])
		# Everyone starts inside a building, facing its door (+Z).
		var spawn: Vector3 = MatchLayout.spawn_point(int(entry.get("spawn", 0)))
		var facing := PI
		if id == my_id:
			player.global_position = spawn + Vector3(0, 0.1, 0)
			player.set("yaw", facing)
			player.rotation.y = facing
			continue
		var actor: CharacterBody3D = NetActorScript.new()
		actor.call("setup", id, str(entry["name"]), bool(entry.get("bot", false)))
		actor.position = spawn + Vector3(0, 0.1, 0)
		actor.rotation.y = facing
		actor.set("combatants", _combatants)
		actor.set("crate_targets", _crate_targets)
		actor.connect("damaged", _on_actor_damaged)
		actor.connect("bot_fired", _on_bot_fired)
		actor.connect("bot_hit", _on_bot_hit)
		actor.connect("bot_loot", _on_bot_loot)
		main_node.add_child(actor)
		actors[id] = actor
	player.connect("shot_fired", _on_local_shot)
	Net.message.connect(_on_message)
	Net.connection_lost.connect(_on_connection_lost)
	_apply_host()
	Net.attach_consumer()
	_feed("Partida iniciada! %d combatentes — o último vivo vence." % alive_count)
	_feed("Você começa sem arma: procure as caixas de suprimento (E para coletar).")

func _exit_tree() -> void:
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)
	if Net.connection_lost.is_connected(_on_connection_lost):
		Net.connection_lost.disconnect(_on_connection_lost)

func is_host() -> bool:
	return Net.host_id == my_id and not my_id.is_empty()

func _apply_host() -> void:
	for actor in actors.values():
		actor.call("set_controlled", is_host() and actor.is_bot)

## Everyone still alive, as targets for the bots this client simulates.
func _combatants() -> Array:
	var list: Array = []
	if not local_dead:
		list.append({"id": my_id, "node": player})
	for id in actors:
		var actor = actors[id]
		if not actor.dead:
			list.append({"id": id, "node": actor})
	return list

# ------------------------------------------------------------ networking ---

func _physics_process(delta: float) -> void:
	if finished:
		return
	_state_timer -= delta
	if _state_timer <= 0.0 and not local_dead:
		_state_timer = STATE_RATE
		var p := player.global_position
		var v := player.get_real_velocity()
		var move := clampf(Vector2(v.x, v.z).length() / 5.0, 0.0, 1.0)
		Net.send({"t": "s", "p": [p.x, p.y, p.z], "y": player.get("yaw"), "pi": player.get("pitch"),
			"w": player.get("current_weapon"), "m": move, "r": player.get("sprinting"),
			"c": player.get("crouching"), "a": player.get("aiming"), "f": not player.is_on_floor(),
			"rl": player.get("reloading"), "h": player.get("weapon_holstered"), "v": [v.x, v.z]})
	_bot_timer -= delta
	if _bot_timer <= 0.0 and is_host():
		_bot_timer = BOT_RATE
		var list: Array = []
		for actor in actors.values():
			if actor.is_bot and actor.controlled and not actor.dead:
				list.append(actor.call("bot_state"))
		if not list.is_empty():
			Net.send({"t": "b", "l": list})

func _on_message(data: Dictionary) -> void:
	match str(data.get("t", "")):
		"s":
			var actor = actors.get(str(data.get("id", "")))
			if actor != null:
				actor.call("apply_state", data)
		"b":
			for entry in data.get("l", []):
				var actor = actors.get(str(entry.get("id", "")))
				if actor != null:
					actor.call("apply_state", entry)
		"shot":
			var origin = _vec(data.get("o"))
			var end = _vec(data.get("e"))
			if origin != null and end != null:
				_tracer(origin, end)
				var shooter = actors.get(str(data.get("id", "")))
				if shooter != null:
					shooter.call("play_remote_shot", str(data.get("w", "rifle")))
		"hp":
			_on_health(data)
		"host":
			_apply_host()
			if is_host():
				_feed("Você agora controla os bots desta partida.")
		"leave":
			var who := str(data.get("id", ""))
			if names.has(who):
				_feed("%s saiu da partida." % names[who])
		"end":
			_on_end(data)
		"looted":
			_on_looted(data)
		"crate":
			_add_crate(data.get("crate", {}))
			var crate_data: Dictionary = data.get("crate", {})
			if bool(crate_data.get("drop", false)):
				_feed("%s deixou uma caixa com as armas." % str(crate_data.get("name", "")))

# ------------------------------------------------------------------ loot ---

func _add_crate(data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	if id.is_empty() or crates.has(id):
		return
	var p: Array = data.get("p", [0, 0, 0])
	var crate: StaticBody3D = LootCrateScript.new()
	crate.call("setup", data)
	crate.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	main_node.add_child(crate)
	crates[id] = crate
	if bool(data.get("open", false)):
		crate.call("mark_opened")

## Unopened crates, for the bots this client simulates.
func _crate_targets() -> Array:
	var list: Array = []
	for id in crates:
		var crate = crates[id]
		if not crate.opened:
			list.append({"id": id, "pos": crate.global_position})
	return list

func _closest_crate(reach: float) -> Node3D:
	var best: Node3D = null
	var best_distance := reach
	for crate in crates.values():
		if crate.opened:
			continue
		var offset: Vector3 = crate.global_position - player.global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance < best_distance and absf(offset.y) < 2.0:
			best_distance = distance
			best = crate
	return best

## Player pressed E. Returns true when a crate was in reach (no elbow strike).
func _try_loot() -> bool:
	if local_dead or finished:
		return false
	var crate := _closest_crate(LOOT_REACH)
	if crate == null:
		return false
	_pending_loot = crate.get("crate_id")
	Net.send({"t": "loot", "crate": _pending_loot})
	return true

func _on_bot_loot(actor_id: String, crate_id: String) -> void:
	if is_host():
		Net.send({"t": "loot", "crate": crate_id, "bot": actor_id})

func _on_looted(data: Dictionary) -> void:
	var crate_id := str(data.get("crate", ""))
	var by := str(data.get("by", ""))
	var items: Dictionary = data.get("items", {})
	if crates.has(crate_id):
		crates[crate_id].call("mark_opened")
	if by == my_id:
		var picked: Array[String] = []
		for weapon_id in items:
			player.call("give_weapon", weapon_id, int(items[weapon_id]))
			picked.append("%s +%d" % [WeaponData.stats(weapon_id)["name"], int(items[weapon_id])])
		player.get("sound_fx").call("reload")
		_toast("PEGOU " + ", ".join(picked))
	elif actors.has(by):
		for weapon_id in items:
			actors[by].call("give_weapon", weapon_id)
	elif crate_id == _pending_loot:
		_toast("Alguém pegou primeiro")
	if crate_id == _pending_loot:
		_pending_loot = ""

func _update_loot_ui() -> void:
	var nearest := _closest_crate(LOOT_REACH) if not local_dead and not finished else null
	for crate in crates.values():
		var distance: float = crate.global_position.distance_to(player.global_position)
		crate.call("show_label", distance < LABEL_RANGE and not local_dead)
	if nearest != null:
		loot_prompt.text = "[E] Coletar: " + str(nearest.call("contents_text")).replace("\n", " — ")
		loot_prompt.visible = true
	else:
		loot_prompt.visible = false

func _vec(value) -> Variant:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null

func _on_health(data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	var hp := float(data.get("hp", 0))
	var killed := bool(data.get("killed", false))
	var by := str(data.get("by", ""))
	alive_count = int(data.get("alive", alive_count))
	if id == my_id:
		if hp < my_hp:
			_on_local_damaged(my_hp - hp, by)
		my_hp = hp
		if killed:
			_on_local_death(by)
	elif actors.has(id):
		actors[id].call("set_hp", hp, killed)
	if by == my_id and killed and id != my_id:
		my_kills = int(data.get("kills", my_kills + 1))
		combat_feedback.call("show_hit", false, true)
		player.get("sound_fx").call("kill_confirm")
		_toast("ELIMINOU %s" % str(names.get(id, "")).to_upper())
	if killed:
		var killer: String = names.get(by, "") if by != "saiu" else ""
		var victim: String = names.get(id, "?")
		if by == "saiu":
			_feed("%s desconectou." % victim)
		else:
			var weapon := str(data.get("w", ""))
			var weapon_name := str(WeaponData.stats(weapon)["name"]) if not weapon.is_empty() else "BOT"
			var head_tag := "  (CABEÇA)" if str(data.get("zone", "")) == "head" else ""
			_feed("%s  [%s]  %s%s" % [killer, weapon_name, victim, head_tag])

func _on_actor_damaged(actor_id: String, zone: String, point: Vector3, normal: Vector3, weapon: String) -> void:
	if local_dead or finished:
		return
	if weapon.is_empty():
		weapon = str(player.get("current_weapon"))
	var base := float(WeaponData.stats(weapon)["damage"])
	var damage := base * float(HitboxScript.MULTIPLIER.get(zone, 1.0))
	Net.send({"t": "hit", "target": actor_id, "zone": zone, "dmg": damage, "w": weapon})
	# Immediate feedback (the server confirms health a moment later).
	var headshot := zone == "head"
	combat_feedback.call("show_hit", headshot)
	player.get("sound_fx").call("hit_confirm", headshot)
	_blood_burst(point, normal, headshot)
	_damage_number(point, damage, headshot)

func _on_local_damaged(amount: float, attacker_id: String) -> void:
	damage_flash.color.a = clampf(0.18 + amount / 60.0, 0.2, 0.55)
	player.call("add_hit_shake", clampf(amount / 25.0, 0.25, 1.0))
	player.get("sound_fx").call("hurt")
	var attacker = actors.get(attacker_id)
	if attacker != null:
		var camera := get_viewport().get_camera_3d()
		var forward := -camera.global_basis.z
		forward.y = 0.0
		var right := camera.global_basis.x
		right.y = 0.0
		var to: Vector3 = attacker.global_position - player.global_position
		to.y = 0.0
		combat_feedback.call("show_damage_from", atan2(to.dot(right.normalized()), to.dot(forward.normalized())))

func _blood_burst(point: Vector3, normal: Vector3, headshot: bool) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 22 if headshot else 12
	particles.lifetime = 0.45
	particles.explosiveness = 1.0
	particles.direction = normal if normal.length_squared() > 0.01 else Vector3.UP
	particles.spread = 38.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 3.4 if headshot else 2.4
	particles.gravity = Vector3(0, -9.0, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	var drop := SphereMesh.new()
	drop.radius = 0.022
	drop.height = 0.044
	drop.radial_segments = 6
	drop.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#7a0b0b")
	material.roughness = 0.4
	drop.material = material
	particles.mesh = drop
	main_node.add_child(particles)
	particles.global_position = point
	particles.emitting = true
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)

func _damage_number(point: Vector3, damage: float, headshot: bool) -> void:
	var label := Label3D.new()
	label.text = ("%d" % roundi(damage)) + ("!" if headshot else "")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 64 if headshot else 46
	label.outline_size = 12
	label.modulate = Color("#ff4d3d") if headshot else Color("#ffe08a")
	main_node.add_child(label)
	label.global_position = point + Vector3(randf_range(-0.15, 0.15), 0.2, 0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3(0, 0.7, 0), 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)

func _toast(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("#ff6a55"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_left = -260
	label.offset_right = 260
	label.offset_top = 48
	label.offset_bottom = 80
	var tween := label.create_tween()
	tween.tween_interval(1.1)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)

func _on_local_shot(weapon_id: String, from: Vector3, to: Vector3) -> void:
	Net.send({"t": "shot", "w": weapon_id, "o": [from.x, from.y, from.z], "e": [to.x, to.y, to.z]})

func _on_bot_fired(actor_id: String, weapon_id: String, from: Vector3, to: Vector3) -> void:
	_tracer(from, to)
	Net.send({"t": "shot", "bot": actor_id, "w": weapon_id, "o": [from.x, from.y, from.z], "e": [to.x, to.y, to.z]})

func _on_bot_hit(actor_id: String, target_id: String, damage: float) -> void:
	var bot = actors.get(actor_id)
	var weapon: String = bot.weapon_id if bot != null else "rifle"
	Net.send({"t": "hit", "bot": actor_id, "target": target_id, "dmg": damage, "w": weapon})

func _on_connection_lost(reason: String) -> void:
	if finished:
		return
	finished = true
	_show_center("CONEXÃO PERDIDA", reason)

# ------------------------------------------------------- death / ending ---

func _on_local_death(killer_id: String) -> void:
	if local_dead:
		return
	local_dead = true
	player.set("aiming", false)
	Input.action_release("aim")
	Input.action_release("fire")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.collision_layer = 0
	(player.get("avatar") as Node3D).visible = false
	var viewmodel := player.get("viewmodel") as Node3D
	if viewmodel != null:
		viewmodel.visible = false
	spectate_camera = Camera3D.new()
	spectate_camera.fov = 72
	add_child(spectate_camera)
	spectate_camera.current = true
	var killer: String = names.get(killer_id, "alguém")
	_feed("Você foi eliminado por %s. Clique para trocar de câmera." % killer)

func _process(delta: float) -> void:
	damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, delta * 1.2)
	_update_loot_ui()
	var my_name: String = names.get(my_id, "Você")
	if finished:
		status_label.text = ""
	elif local_dead:
		var target := _spectate_target()
		status_label.text = "ELIMINADO  |  VIVOS: %d  |  ASSISTINDO: %s" % [alive_count, names.get(target.get("actor_id"), "—") if target else "—"]
	else:
		status_label.text = "%s  |  VIVOS: %d  |  ABATES: %d" % [my_name, alive_count, my_kills]
	health_bar.value = my_hp
	health_bar.visible = not local_dead and not finished
	if local_dead and spectate_camera != null:
		var target := _spectate_target()
		if target != null:
			var back := target.global_basis.z.normalized()
			var goal: Vector3 = target.global_position + back * 3.6 + Vector3(0, 2.4, 0)
			spectate_camera.global_position = spectate_camera.global_position.lerp(goal, minf(1.0, delta * 5.0))
			spectate_camera.look_at(target.global_position + Vector3(0, 1.4, 0))

func _spectate_target() -> Node3D:
	var living: Array = []
	for actor in actors.values():
		if not actor.dead:
			living.append(actor)
	if living.is_empty():
		return null
	return living[spectate_index % living.size()]

func _unhandled_input(event: InputEvent) -> void:
	if local_dead and not finished and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		spectate_index += 1

func _on_end(data: Dictionary) -> void:
	finished = true
	Input.action_release("fire")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var won := str(data.get("winner", "")) == my_id
	var lines: Array[String] = []
	if str(data.get("reason", "")) == "tempo":
		lines.append("Tempo esgotado: venceu quem tinha mais abates.")
	var rank := 1
	for row in data.get("board", []):
		lines.append("%d. %s — %d abate(s)%s" % [rank, row["name"], int(row["kills"]), "  (bot)" if row.get("bot", false) else ""])
		rank += 1
	_show_center("VITÓRIA!" if won else "%s VENCEU" % str(data.get("name", "")).to_upper(), "\n".join(lines))

# -------------------------------------------------------------------- UI ---

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.75, 0.05, 0.05, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(damage_flash)
	damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	combat_feedback = CombatFeedbackScript.new()
	ui.add_child(combat_feedback)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(status_label)
	status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status_label.offset_left = -300
	status_label.offset_right = 300
	status_label.offset_top = 14
	health_bar = ProgressBar.new()
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(260, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#c7e08c")
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	back.set_corner_radius_all(4)
	health_bar.add_theme_stylebox_override("fill", fill)
	health_bar.add_theme_stylebox_override("background", back)
	ui.add_child(health_bar)
	health_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	health_bar.offset_left = -130
	health_bar.offset_right = 130
	health_bar.offset_top = -46
	health_bar.offset_bottom = -28
	loot_prompt = Label.new()
	loot_prompt.visible = false
	loot_prompt.add_theme_font_size_override("font_size", 19)
	loot_prompt.add_theme_color_override("font_color", Color("#ffe08a"))
	loot_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	loot_prompt.add_theme_constant_override("shadow_offset_y", 2)
	loot_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(loot_prompt)
	loot_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	loot_prompt.offset_left = -320
	loot_prompt.offset_right = 320
	loot_prompt.offset_top = 90
	loot_prompt.offset_bottom = 120
	feed = VBoxContainer.new()
	feed.alignment = BoxContainer.ALIGNMENT_END
	ui.add_child(feed)
	feed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	feed.offset_left = 18
	feed.offset_right = 560
	feed.offset_top = -240
	feed.offset_bottom = -18
	center_panel = PanelContainer.new()
	center_panel.visible = false
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.1, 0.11, 0.92)
	box.set_corner_radius_all(12)
	box.content_margin_left = 30
	box.content_margin_right = 30
	box.content_margin_top = 24
	box.content_margin_bottom = 24
	center_panel.add_theme_stylebox_override("panel", box)
	ui.add_child(center_panel)
	center_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	center_panel.add_child(column)
	center_title = Label.new()
	center_title.add_theme_font_size_override("font_size", 34)
	center_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(center_title)
	center_body = Label.new()
	center_body.add_theme_font_size_override("font_size", 17)
	column.add_child(center_body)
	var back_button := Button.new()
	back_button.text = "Voltar ao menu"
	back_button.custom_minimum_size = Vector2(220, 46)
	back_button.pressed.connect(_back_to_menu)
	column.add_child(back_button)

func _show_center(title: String, body: String) -> void:
	center_title.text = title
	center_body.text = body
	center_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _back_to_menu() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _feed(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_y", 1)
	feed.add_child(label)
	while feed.get_child_count() > 6:
		var oldest := feed.get_child(0)
		feed.remove_child(oldest)
		oldest.queue_free()
	get_tree().create_timer(8.0).timeout.connect(func():
		if is_instance_valid(label):
			label.queue_free())

func _tracer(from: Vector3, to: Vector3) -> void:
	var delta_pos := to - from
	var length := minf(delta_pos.length(), 60.0)
	if length < 0.1:
		return
	var tracer := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.012
	cylinder.bottom_radius = 0.012
	cylinder.height = length
	cylinder.radial_segments = 5
	tracer.mesh = cylinder
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("#ffd08c")
	tracer.material_override = glow
	main_node.add_child(tracer)
	tracer.global_position = from + delta_pos.normalized() * length * 0.5
	tracer.quaternion = Quaternion(Vector3.UP, delta_pos.normalized())
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "transparency", 1.0, 0.09)
	tween.tween_callback(tracer.queue_free)
