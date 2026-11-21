extends Node
## Shared release-fired bow for training and online modes.
const Draw = preload("res://scripts/weapons/bow_draw.gd")
const BowAudio = preload("res://scripts/audio/bow_audio.gd")
const Arrow = preload("res://scripts/weapons/bow_arrow.gd")
const PointerMode = preload("res://scripts/pointer_mode.gd")
var player: CharacterBody3D
var equipped := false
var draw := Draw.new()
var shots := 0
var last_arrow_id := ""
var last_hit_arrow_id := ""
var _cooldown := 0.0
var _audio: Node

func setup(p: CharacterBody3D) -> void:
	player = p
	player.set("bow_controller", self)
	process_physics_priority = -1
	if not is_instance_valid(_audio):
		_audio = BowAudio.new()
		add_child(_audio)

func equip() -> void:
	if not bool(player.get("weapon_holstered")):
		player.call("_toggle_weapon_holster")
	player.set("melee_weapon", "")
	player.set("reloading", false)
	equipped = true
	draw.cancel()
	if is_instance_valid(_audio):
		_audio.call("cancel_draw")
	_sync_pose()

func unequip() -> void:
	equipped = false
	draw.cancel()
	if is_instance_valid(_audio):
		_audio.call("cancel_draw")
	_sync_pose()

func cancel_draw() -> void:
	draw.cancel()
	if is_instance_valid(_audio):
		_audio.call("cancel_draw")
	_sync_pose()

func has_ammo() -> bool:
	return not bool(player.get("loadout_limited")) or int(player.get("reserve_ammo").get("bow", 0)) > 0

func _allowed() -> bool:
	return equipped and PointerMode.is_captured() and not bool(player.get("attack_blocked")) and not bool(player.get("climbing")) and not bool(player.get("grenade_aiming")) and float(player.get("channel_left")) <= 0.0 and not (player.get("ui_blocking").is_valid() and bool(player.get("ui_blocking").call()))

func _unhandled_input(event: InputEvent) -> void:
	if not equipped or player == null:
		return
	if event.is_action_pressed("fire") and _allowed() and _cooldown <= 0.0 and has_ammo():
		draw.press()
		_audio.call("begin_draw")
		get_viewport().set_input_as_handled()
	elif event.is_action_released("fire"):
		var power := draw.release() if _allowed() else 0.0
		if power > 0.0:
			_fire(power)
		else:
			cancel_draw()
		_sync_pose()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_draw()

func _physics_process(delta: float) -> void:
	if player == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if equipped and (not bool(player.get("weapon_holstered")) or not str(player.get("melee_weapon")).is_empty()):
		unequip()
	if equipped:
		if not _allowed():
			cancel_draw()
		elif draw.drawing:
			draw.advance(delta)
			_audio.call("update_tension", draw.charge)
			player.call("face_aim", 0.15)
		_sync_pose()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_draw()

func _sync_pose() -> void:
	if not is_instance_valid(player):
		return
	var avatar: Node3D = player.get("humanoid_avatar")
	if avatar != null and avatar.has_method("set_bow_state"):
		avatar.call("set_bow_state", equipped, draw.charge, draw.drawing, player.call("crosshair_point"))

func _fire(power: float) -> void:
	if not has_ammo():
		cancel_draw()
		return
	var avatar: Node3D = player.get("humanoid_avatar")
	var origin: Vector3 = player.global_position + Vector3(0, 1.35, 0) - player.global_basis.z * 0.65
	if avatar != null and avatar.has_method("bow_arrow_origin"):
		origin = avatar.call("bow_arrow_origin")
	# Keep launch on the player's side of nearby cover, even if the bow clips it.
	var chest := player.global_position + Vector3.UP * float(player.get("height")) * 0.75
	var cover: Dictionary = player.call("_shot_ray", chest, origin)
	if not cover.is_empty():
		origin = cover["position"] + (chest - origin).normalized() * 0.025
	var target: Vector3 = player.call("crosshair_point")
	var arrow := Arrow.new()
	var scene: Node = player.get_tree().current_scene
	(scene if scene != null else player.get_tree().root).add_child(arrow)
	var launch_velocity := (target - origin).normalized() * lerpf(20.0, 48.0, power)
	last_arrow_id = "%s_%s" % [Time.get_ticks_usec(), shots]
	arrow.arrow_id = last_arrow_id
	arrow.launch(player, origin, launch_velocity, 55.0)
	# Launch is sent before reserve consumption, including the final arrow.
	player.emit_signal("shot_fired", "bow", origin, origin + launch_velocity)
	if bool(player.get("loadout_limited")):
		player.get("reserve_ammo")["bow"] -= 1
	if is_instance_valid(_audio):
		_audio.call("release_arrow", power)
	shots += 1
	_cooldown = 0.35
