extends Node
## Música de fundo (autoload "Music"). Faixas CC0 — ver assets/audio/music/LICENSE.txt.
## - Menu (scenes/menu.tscn): "Chill Main Menu music".
## - Sobrevivência: "Paranoid Truth" bem baixinha só perto das 3 cidades
##   abandonadas (data/survival_world.json "towns"), sumindo devagar ao sair.
const SurvivalData = preload("res://scripts/survival/survival_data.gd")

const MENU_TRACK := "res://assets/audio/music/menu_chill.ogg"
const CITY_TRACK := "res://assets/audio/music/city_paranoid_truth.mp3"
const MENU_DB := -14.0
const CITY_DB := -28.0 # bem baixo (o vento ambiente fica em -27 dB)
const SILENT_DB := -60.0
const FADE_DB_PER_SEC := 18.0
const CITY_FULL_RADIUS := 60.0 # dentro disso a música da cidade está no volume cheio
const CITY_FADE_RADIUS := 95.0 # daqui pra fora não toca

var _menu: AudioStreamPlayer
var _city: AudioStreamPlayer
var _towns: Array = [] # [Vector2]
var _check_left := 0.0
var _menu_target := SILENT_DB
var _city_target := SILENT_DB

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # continua com o jogo pausado
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_menu = _make_player("MenuMusic", MENU_TRACK)
	_city = _make_player("CityMusic", CITY_TRACK)

func _make_player(player_name: String, path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = player_name
	var stream := load(path) as AudioStream
	if stream != null and "loop" in stream:
		stream.set("loop", true)
	p.stream = stream
	p.volume_db = SILENT_DB
	add_child(p)
	return p

func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = 0.4
		_update_targets()
	_fade(_menu, _menu_target, delta)
	_fade(_city, _city_target, delta)

func _update_targets() -> void:
	var scene := get_tree().current_scene
	var in_menu := scene != null and scene.scene_file_path == "res://scenes/menu.tscn"
	_menu_target = MENU_DB if in_menu else SILENT_DB
	_city_target = SILENT_DB
	if in_menu or scene == null or scene.get_node_or_null("SurvivalWorld") == null:
		return
	var player := scene.get("player") as Node3D
	if player == null or not is_instance_valid(player):
		return
	if _towns.is_empty():
		for town in SurvivalData.world().get("towns", []):
			_towns.append(Vector2(float(town["center"][0]), float(town["center"][1])))
	var pos := Vector2(player.global_position.x, player.global_position.z)
	var nearest := INF
	for c in _towns:
		nearest = minf(nearest, pos.distance_to(c))
	if nearest >= CITY_FADE_RADIUS:
		return
	var t := clampf((CITY_FADE_RADIUS - nearest) / (CITY_FADE_RADIUS - CITY_FULL_RADIUS), 0.0, 1.0)
	_city_target = lerpf(SILENT_DB, CITY_DB, sqrt(t))

func _fade(p: AudioStreamPlayer, target: float, delta: float) -> void:
	if p == null or p.stream == null:
		return
	p.volume_db = move_toward(p.volume_db, target, FADE_DB_PER_SEC * delta)
	var audible := p.volume_db > SILENT_DB + 0.5
	if audible and not p.playing:
		p.play()
	elif not audible and target <= SILENT_DB and p.playing:
		p.stop()
