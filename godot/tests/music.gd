extends SceneTree
## Música de fundo: as faixas carregam em loop e a da cidade só sobe perto das cidades.
const MusicScript = preload("res://scripts/audio/music.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	var music: Node = MusicScript.new()
	root.add_child(music)
	# Em headless o autoload fica mudo; aqui montamos os players na mão.
	music.set("_menu", music.call("_make_player", "MenuMusic", MusicScript.MENU_TRACK))
	music.set("_city", music.call("_make_player", "CityMusic", MusicScript.CITY_TRACK))
	for p_name in ["_menu", "_city"]:
		var p: AudioStreamPlayer = music.get(p_name)
		check(p.stream != null, "%s: faixa carregada" % p_name)
		check(p.stream != null and bool(p.stream.get("loop")), "%s: em loop" % p_name)

	# Cena falsa de jogo: SurvivalWorld + player.
	var scene_script := GDScript.new()
	scene_script.source_code = "extends Node3D\nvar player: Node3D\n"
	scene_script.reload()
	var scene := Node3D.new()
	scene.set_script(scene_script)
	var world := Node3D.new()
	world.name = "SurvivalWorld"
	scene.add_child(world)
	var player := Node3D.new()
	scene.add_child(player)
	scene.set("player", player)
	root.add_child(scene)
	current_scene = scene

	var town: Array = SurvivalData.world()["towns"][0]["center"]
	player.global_position = Vector3(float(town[0]), 0, float(town[1]))
	music.call("_update_targets")
	var near_db: float = music.get("_city_target")
	check(is_equal_approx(near_db, MusicScript.CITY_DB), "no centro da cidade: volume da cidade (%s)" % near_db)
	check(float(music.get("_menu_target")) <= MusicScript.SILENT_DB, "no jogo o menu fica mudo")

	player.global_position = Vector3(0, 0, 0)
	music.call("_update_targets")
	check(float(music.get("_city_target")) <= MusicScript.SILENT_DB, "longe das cidades: sem música")

	if failures.is_empty():
		print("MUSIC OK")
		quit(0)
	else:
		for f in failures:
			push_error(f)
		quit(1)
