extends Node3D
const Hydro = preload("res://scripts/survival/hydrology.gd")
const Hitbox = preload("res://scripts/net/hitbox.gd")
var player: Node3D
var world: Node3D
var elapsed := 0.0
var rain := 0.0
var _timer := 0.0
var _drops: CPUParticles3D
var _sound: AudioStreamPlayer
var sheltered := false
## Gotas por nível de chuva (0–7). Celular: metade — são riscos transparentes
## e a sobreposição deles pesa na GPU do aparelho.
var drops_per_step := 50 if OS.has_feature("mobile") else 100

func _ready() -> void:
	name = "RainWeather"
	_drops = CPUParticles3D.new()
	_drops.amount = 7 * drops_per_step
	_drops.lifetime = 0.65
	_drops.local_coords = false
	_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drops.emission_box_extents = Vector3(17, 1, 17)
	_drops.direction = Vector3(0.1, -1, 0.06)
	_drops.spread = 3.0
	_drops.initial_velocity_min = 24
	_drops.initial_velocity_max = 30
	_drops.gravity = Vector3(0, -8, 0)
	_drops.emitting = false
	_drops.visibility_aabb = AABB(Vector3(-22,-24,-22), Vector3(44,30,44))
	var streak := BoxMesh.new()
	streak.size = Vector3(0.018, 0.5, 0.018)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.65, 0.8, 0.9, 0.6)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.material = material
	_drops.mesh = streak
	add_child(_drops)
	_sound = AudioStreamPlayer.new()
	_sound.stream = _rain_sound()
	_sound.volume_db = -70
	add_child(_sound)
	_sound.play()

func sync_weather(snapshot: Dictionary) -> void:
	if snapshot.has("elapsed"): elapsed = float(snapshot.elapsed)

func _process(delta: float) -> void:
	elapsed += delta * 1000.0
	var state := Hydro.weather_at(elapsed)
	rain = float(state.rain)
	_timer -= delta
	if player != null:
		global_position = player.global_position + Vector3(0, 13, 0)
	if _timer <= 0:
		_timer = 0.3
		var amount := maxi(1, roundi(rain * 7.0) * drops_per_step)
		if _drops.amount != amount: _drops.amount = amount
		if world != null: world.call("set_wetness", float(state.wet))
		if player != null and is_inside_tree():
			var eye := player.global_position + Vector3.UP * 1.6
			var query := PhysicsRayQueryParameters3D.create(eye, eye + Vector3.UP * 25, Hitbox.LAYER_WORLD)
			query.exclude = [player.get_rid()] if player is CollisionObject3D else []
			sheltered = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	_drops.emitting = rain > 0.02 and not sheltered
	_sound.volume_db = lerpf(_sound.volume_db, (-26.0 if sheltered else -13.0) + linear_to_db(maxf(0.001, rain)), minf(1, delta * 3))

static func _rain_sound() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 44100
	var bytes := PackedByteArray()
	bytes.resize(44100 * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1905
	var low := 0.0
	for i in 44100:
		var noise := rng.randf_range(-1, 1)
		low = lerpf(low, noise, 0.35)
		bytes.encode_s16(i * 2, int((low * 0.65 + noise * 0.15) * 18000))
	stream.data = bytes
	return stream
