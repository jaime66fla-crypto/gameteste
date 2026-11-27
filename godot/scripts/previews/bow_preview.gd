extends Node3D
## Inspect the real selected avatar with the Blender bow. Space toggles draw.
const Stage = preload("res://scripts/previews/preview_stage.gd")
const Registry = preload("res://scripts/characters/character_registry.gd")
var avatar: Node3D
var camera: Camera3D
var drawn := true
var charge := 1.0
var hint: Label
var walking := false
var running := false
var _motion_step := 0.0

func _ready() -> void:
	camera = Stage.build(self)
	avatar = Registry.create_visual(Registry.load_selection())
	if avatar == null or not avatar.has_method("set_bow_state"):
		avatar = load("res://scenes/characters/atacante.tscn").instantiate()
	add_child(avatar)
	avatar.call("set_armed", false)
	hint = Stage.hint(self, "ARCO E FLECHA · modelo Blender em escala real\nESPAÇO: puxar/relaxar | arco 1,25 m · flecha 0,85 m · avatar 1,80 m")
	camera.position = Vector3(2.3, 1.65, -3.3)
	camera.look_at(Vector3(0, 1.15, -0.2))
	if not Stage.capture_folder().is_empty():
		_capture.call_deferred(Stage.capture_folder())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		drawn = not drawn

func _process(delta: float) -> void:
	charge = move_toward(charge, 1.0 if drawn else 0.0, delta * 1.5)
	avatar.call("set_bow_state", true, charge, drawn, Vector3(0, 1.45, -20))
	var step := _motion_step if _motion_step > 0.0 else delta
	avatar.call("animate", step, 1.0 if walking else 0.0, running, false, drawn, false, false, Vector2(0, -1) if walking else Vector2.ZERO, Vector3(0, 0, 5.0 if running else 1.6) if walking else Vector3.ZERO)

func _capture(folder: String) -> void:
	for i in 45:
		await get_tree().process_frame
	Stage.save_shot(get_viewport(), folder, "arco_pose_frente")
	camera.position = Vector3(3.4, 1.65, 0.5)
	camera.look_at(Vector3(0, 1.15, -0.25))
	for i in 4:
		await get_tree().process_frame
	Stage.save_shot(get_viewport(), folder, "arco_pose_lado")
	camera.position = Vector3(1.7, 1.85, 3.0)
	camera.look_at(Vector3(0, 1.25, -0.25))
	for i in 4:
		await get_tree().process_frame
	Stage.save_shot(get_viewport(), folder, "arco_pose_costas")
	camera.position = Vector3(3.4, 1.65, 0.5)
	camera.look_at(Vector3(0, 1.15, -0.25))
	drawn = false
	for i in 55:
		await get_tree().process_frame
	Stage.save_shot(get_viewport(), folder, "arco_relaxado")
	camera.position = Vector3(2.3, 1.65, -3.3)
	camera.look_at(Vector3(0, 1.05, -0.1))
	walking = true
	for i in 35:
		await get_tree().process_frame
	Stage.save_shot(get_viewport(), folder, "arco_carregando_ao_andar")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--motion="):
			await _capture_run(arg.substr(9))
	get_tree().quit()

func _capture_run(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	walking = true
	running = true
	drawn = false
	_motion_step = 1.0 / 18.0
	camera.position = Vector3(-2.4, 1.55, 2.8)
	camera.look_at(Vector3(0, 1.0, 0))
	for i in 12:
		await get_tree().process_frame
	for i in 36:
		await get_tree().process_frame
		var frame := get_viewport().get_texture().get_image()
		if i == 0:
			frame.save_png(folder.path_join("run_reference.png"))
		frame.resize(480, 282, Image.INTERPOLATE_LANCZOS)
		frame.convert(Image.FORMAT_RGB8)
		var file := FileAccess.open(folder.path_join("%03d.rgb" % i), FileAccess.WRITE)
		file.store_buffer(frame.get_data())
		file.close()
