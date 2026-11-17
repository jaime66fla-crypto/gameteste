extends Node3D
## Sons de combate de um personagem (tiro, recarga, passos) e o retorno de
## acerto/dano do jogador local. Os sons vêm do SfxBank (síntese em camadas,
## gerada uma vez e compartilhada), sem arquivos de terceiros.
const SfxBank = preload("res://scripts/audio/sfx_bank.gd")
# Remote actors keep positional audio. The local player opts out before _ready.
@export var spatial_audio := true
var shot_player: Node
var reload_player: AudioStreamPlayer
var step_player: Node
var step_timer := 0.0
var _step_variant := 0
var _gun_variant := 0

func _ready() -> void:
	# Carrega o banco de sons de uma vez (o primeiro tiro não pode engasgar).
	SfxBank.warmup()
	shot_player = AudioStreamPlayer3D.new() if spatial_audio else AudioStreamPlayer.new()
	shot_player.name = "ShotAudio"
	shot_player.stream = SfxBank.gun("pistol", 0)
	# Rajada: cada tiro deixa a cauda do anterior terminar (antes cortava seco).
	shot_player.max_polyphony = 6
	if shot_player is AudioStreamPlayer3D:
		shot_player.unit_size = 10.0
		shot_player.max_distance = 160.0
		# Tiro distante chega abafado, como na vida real.
		shot_player.attenuation_filter_cutoff_hz = 3000.0
		shot_player.attenuation_filter_db = -20.0
	add_child(shot_player)
	reload_player = AudioStreamPlayer.new()
	reload_player.name = "ReloadAudio"
	reload_player.stream = SfxBank.reload_sound()
	reload_player.volume_db = -8.0
	add_child(reload_player)
	step_player = AudioStreamPlayer3D.new() if spatial_audio else AudioStreamPlayer.new()
	step_player.name = "FootstepAudio"
	step_player.stream = SfxBank.step(0)
	step_player.volume_db = -15.0
	step_player.max_polyphony = 2
	if step_player is AudioStreamPlayer3D:
		step_player.max_distance = 26.0
	add_child(step_player)

## Retorno (sempre 2D, criado no primeiro uso): acerto / cabeça / abate / dano.
var _feedback: Dictionary = {}

func _feedback_player(key: String, stream: AudioStream, volume: float) -> AudioStreamPlayer:
	if not _feedback.has(key):
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.max_polyphony = 4
		add_child(player)
		_feedback[key] = player
	var p: AudioStreamPlayer = _feedback[key]
	p.volume_db = volume
	return p

func hit_confirm(headshot: bool) -> void:
	var player := _feedback_player("head", SfxBank.hit_head(), -5.0) if headshot else _feedback_player("body", SfxBank.hit_body(), -8.0)
	player.pitch_scale = randf_range(0.96, 1.04)
	player.play()

func kill_confirm() -> void:
	var p := _feedback_player("kill", SfxBank.kill(), -6.0)
	p.pitch_scale = randf_range(0.98, 1.02)
	p.play()

## Levou dano. `amount` decide o peso: golpe forte = mais grave e zumbido no ouvido.
func hurt(amount: float = 10.0) -> void:
	var heavy := amount >= 25.0
	var player := _feedback_player("hurt_heavy" if heavy else "hurt", SfxBank.hurt(heavy), -3.0 if heavy else -5.0)
	player.pitch_scale = randf_range(0.92, 1.06)
	player.play()

## Zumbi acertou você: rasgo + o impacto do dano.
func zombie_bite(amount: float = 10.0) -> void:
	var p := _feedback_player("bite", SfxBank.zombie_bite(), -3.0)
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()
	hurt(amount)

## Golpe de arma branca / soco (no ar).
func melee_swing() -> void:
	var p := _feedback_player("swing", SfxBank.swing(), -9.0)
	p.pitch_scale = randf_range(0.9, 1.12)
	p.play()

## Arma branca acertou alguém.
func melee_impact(headshot: bool = false) -> void:
	var p := _feedback_player("melee", SfxBank.melee_impact(), -4.0)
	p.pitch_scale = randf_range(0.93, 1.07)
	p.play()
	hit_confirm(headshot)

func shot(weapon_id: String = "pistol") -> void:
	var id := weapon_id if SfxBank.GUNS.has(weapon_id) else "pistol"
	# Alterna variações e varia um pouco o tom: nenhum tiro soa idêntico ao anterior.
	_gun_variant = (_gun_variant + 1) % SfxBank.GUN_VARIANTS
	var p := _gun_player(id, _gun_variant)
	p.pitch_scale = randf_range(0.97, 1.03)
	p.volume_db = {"pistol": -3.0, "smg": -4.0, "rifle": -2.0, "shotgun": 0.0, "sniper": 1.0}.get(id, -3.0)
	p.play()

## Um tocador por som de arma (trocar o stream cortaria a cauda do tiro anterior).
var _gun_players: Dictionary = {}

func _gun_player(id: String, variant: int) -> Node:
	var key := "%s_%d" % [id, variant]
	if _gun_players.has(key):
		return _gun_players[key]
	var p: Node = shot_player
	if not _gun_players.is_empty():
		p = shot_player.duplicate()
		p.name = "ShotAudio_" + key
		add_child(p)
	p.set("stream", SfxBank.gun(id, variant))
	_gun_players[key] = p
	return p

func reload() -> void:
	reload_player.pitch_scale = randf_range(0.97, 1.03)
	reload_player.play()

func update_steps(delta: float, grounded: bool, moving: bool, sprinting: bool, crouching: bool) -> void:
	if not grounded or not moving:
		step_timer = 0.0
		return
	step_timer -= delta
	if step_timer > 0.0:
		return
	step_timer = 0.28 if sprinting else (0.65 if crouching else 0.43)
	_step_variant = (_step_variant + 1 + randi() % 2) % 3
	step_player.stream = SfxBank.step(_step_variant)
	step_player.pitch_scale = randf_range(0.9, 1.08)
	step_player.volume_db = -22.0 if crouching else (-13.0 if sprinting else -16.0)
	step_player.play()
