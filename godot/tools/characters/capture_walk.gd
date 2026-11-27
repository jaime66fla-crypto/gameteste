extends SceneTree
## Fotos da locomoção no mapa, de uma câmera de lado/frente parada: andando para a
## frente, de lado (direita), de ré, andando com Shift e agachado andando.
## Várias fotos por movimento (fases do passo).
## godot --path godot --script res://tools/characters/capture_walk.gd -- --id=atacante --out=C:/pasta/andar
const Registry = preload("res://scripts/characters/character_registry.gd")
const SELECTION := "user://capture_walk_selection.cfg"
const MOVES := [
	["frente", ["move_forward"], false],
	["direita", ["move_right"], false],
	["re", ["move_back"], false],
	["shift_andar", ["move_forward", "sprint"], false],
	["agachado", ["move_forward"], true],
]

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func _run() -> void:
	var id := "atacante"
	var out := "user://andar"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="):
			id = arg.substr(5)
		elif arg.begins_with("--out="):
			out = arg.substr(6)
	Registry.storage_path = SELECTION
	if Registry.select_character(id) != OK:
		quit(1)
		return
	root.size = Vector2i(900, 700)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 30:
		await process_frame
	var player := scene.get_node("Jaime") as CharacterBody3D
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.call("_equip_weapon", "rifle")
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	# Câmera filha do jogador: anda junto (fica de lado-frente, olhando o corpo).
	var cam := Camera3D.new()
	player.add_child(cam)
	cam.fov = 50
	cam.position = Vector3(2.7, 1.1, -2.0)
	cam.current = true
	for move in MOVES:
		player.set("yaw", 0.0)
		player.set("pitch", 0.0)
		if move[2]:
			Input.action_press("crouch")
		for action in move[1]:
			Input.action_press(action)
		for i in 45:
			await physics_frame
		for shot in 3:
			for i in 6:
				await physics_frame
			# câmera ao lado-frente do corpo do jogador
			var body: Node3D = player.get("humanoid_avatar")
			cam.position = Vector3(2.7, 1.1, -2.0)
			cam.look_at(player.global_position + Vector3(0, 0.9, 0), Vector3.UP)
			if shot == 1:
				print("%s: clipe %s velocidade %.2f re %s" % [move[0], body.get("_clean_clip"), float(body.get("_planar_speed")), str(body.get("_clean_backward"))])
			await process_frame
			await process_frame
			root.get_texture().get_image().save_png("%s_%s_%d.png" % [out, move[0], shot])
		for action in move[1]:
			Input.action_release(action)
		if move[2]:
			Input.action_release("crouch")
		for i in 30:
			await physics_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SELECTION))
	quit(0)
