extends SceneTree
## UAL2 (Quaternius) clips on every catalog character, the action layer,
## idle fidgets, the mannequin as a networked body and the zombie legs.
## godot --headless --path godot --script res://tests/ual2_actions.gd
const Registry = preload("res://scripts/characters/character_registry.gd")
const Avatar = preload("res://scripts/characters/downloaded_avatar.gd")
const NetActorScript = preload("res://scripts/net/net_actor.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const ZombieAvatar = preload("res://scripts/survival/zombie_avatar.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(200.0).timeout.connect(func():
		printerr("UAL2 ACTIONS: timeout")
		quit(2))
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _step(visual: Node, frames: int, move: float = 0.0, velocity := Vector3.ZERO) -> void:
	for i in frames:
		visual.call("animate", 1.0 / 60.0, move, false, false, false, false, false, Vector2(0, -1), velocity)
		await process_frame

func _run() -> void:
	for id in ["avatar_ch31", "remy", "manequim"]:
		_check(Registry.is_available(id), id + " must be available")
		var visual := Registry.create_visual(id)
		root.add_child(visual)
		await process_frame
		_check(bool(visual.call("is_visual_ready")), id + " visual must be ready")
		var clips: Dictionary = visual.get("ual_clips")
		_check(clips.size() == Avatar.UAL_CLIPS.size(), "%s must load all %d UAL2 clips (got %d)" % [id, Avatar.UAL_CLIPS.size(), clips.size()])
		for clip_name in clips:
			_check((clips[clip_name][1] as Array).size() >= 50, "%s/%s must drive the rig (%d tracks)" % [id, clip_name, (clips[clip_name][1] as Array).size()])
		# Armed with a rifle: an action hides the gun while the hands are busy.
		visual.call("configure_weapon", "rifle", 1.0)
		var weapon := Node3D.new()
		(visual.get("weapon_mount") as Node3D).add_child(weapon)
		var model := WeaponProportions.create_model("rifle")
		if model:
			weapon.add_child(model)
			WeaponProportions.apply(weapon, "rifle", model)
		visual.call("bind_weapon", weapon)
		visual.call("set_armed", true)
		await _step(visual, 10)
		_check(bool(visual.call("play_action", "throw")), id + " must play the grenade throw")
		await _step(visual, 25)
		_check(not weapon.visible, id + ": gun must be put away during the throw")
		await _step(visual, 90)
		_check(not bool(visual.call("is_overlay_playing")), id + ": throw must end by itself")
		_check(weapon.visible, id + ": gun must come back after the throw")
		# Every gameplay action plays and ends; the walk keeps going under upper-body ones.
		for action in Avatar.ACTIONS:
			_check(bool(visual.call("has_action", action)), "%s: action %s missing" % [id, action])
			visual.call("play_action", action)
			await _step(visual, 6, 0.5, Vector3(0, 0, -1.4))
			_check(bool(visual.call("is_overlay_playing")), "%s: %s must be playing" % [id, action])
			await _step(visual, 320, 0.5, Vector3(0, 0, -1.4))
			_check(not bool(visual.call("is_overlay_playing")), "%s: %s must finish" % [id, action])
		# Network acts (survival) map onto actions and do not restart every packet.
		visual.call("set_action", "open", "")
		await _step(visual, 30)
		var t_open := float(visual.get("_overlay_time"))
		visual.call("set_action", "open", "")
		await _step(visual, 1)
		_check(float(visual.get("_overlay_time")) > t_open, id + ": repeated 'open' must not restart the clip")
		_check(str(visual.get("work_action")) == "", id + ": 'open' is not a tool loop")
		visual.call("set_action", "", "")
		await _step(visual, 120)
		# Idle fidget: unarmed and still for a while plays one, moving cancels it.
		visual.call("set_armed", false)
		await _step(visual, int((Avatar.IDLE_FIDGET_DELAY + 1.0) * 60.0))
		_check(bool(visual.call("is_overlay_playing")), id + ": standing still unarmed must start an idle fidget")
		await _step(visual, 30, 0.5, Vector3(0, 0, -1.4))
		_check(not bool(visual.call("is_overlay_playing")), id + ": walking must cancel the fidget")
		visual.queue_free()
		await process_frame
	# The mannequin as a remote player's body: hitboxes on its bones.
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	(scene.get_node("Jaime") as Node).set_physics_process(false)
	var actor: CharacterBody3D = NetActorScript.new()
	actor.call("setup", "probe", "Alvo", false)
	actor.position = Vector3(0, 0, 20)
	actor.rotation.y = PI
	scene.add_child(actor)
	await process_frame
	actor.call("apply_state", {"p": [0.0, 0.0, 20.0], "y": PI, "w": "rifle", "h": false, "ch": "manequim"})
	for i in 20:
		await physics_frame
	_check(str(actor.get("character_id")) == "manequim", "State 'ch' must switch the body to the mannequin")
	var space := actor.get_world_3d().direct_space_state
	var base := actor.global_position
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3(0, 1.62, 3), base + Vector3(0, 1.62, -3), HitboxScript.SHOT_MASK))
	_check(not hit.is_empty() and str(hit["collider"].get("zone")) == "head", "Mannequin head must be hittable")
	var picks := {}
	for i in 60:
		picks[NetActorScript.bot_character("bot%d" % i)] = true
	_check(picks.has("manequim") and picks.has("remy") and picks.has("avatar_ch31"), "Bots must use all three characters")
	scene.queue_free()
	await process_frame
	# Zombie legs: UAL2 shamble and idle, and the run without opening Ch31's FBX.
	var zombie: Node3D = ZombieAvatar.new()
	root.add_child(zombie)
	await process_frame
	var lib: AnimationPlayer = zombie.get("player")
	for clip_name in ["idle", "walk", "run", "attack"]:
		_check(lib.has_animation(clip_name), "Zombie needs clip " + clip_name)
	_check(str(lib.get_animation("walk").get_meta("source", "")).contains("Zombie_Walk_Fwd"), "Zombie walk must be the UAL2 shamble")
	for i in 30:
		zombie.call("animate", 1.0 / 60.0, 1, 0.75, 0)
		await process_frame
	zombie.queue_free()
	await process_frame
	for failure in failures:
		printerr(failure)
	print("UAL2 ACTIONS: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
