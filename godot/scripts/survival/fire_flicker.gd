extends OmniLight3D
## Luz de fogueira: intensidade, alcance e posição tremulam de forma irregular,
## como chama de verdade (ruído suave, não seno regular).
var _t := randf() * 10.0
var _base_energy := 2.2
var _base_range := 11.0
var _base_pos := Vector3.ZERO
var _noise := FastNoiseLite.new()

func _ready() -> void:
	_base_energy = light_energy
	_base_range = omni_range
	_base_pos = position
	_noise.seed = randi()
	_noise.frequency = 1.0

func _process(delta: float) -> void:
	_t += delta
	var n := _noise.get_noise_1d(_t * 6.0) * 0.7 + _noise.get_noise_1d(_t * 17.0 + 50.0) * 0.3
	light_energy = _base_energy * (1.0 + n * 0.3)
	omni_range = _base_range * (1.0 + n * 0.05)
	position = _base_pos + Vector3(_noise.get_noise_1d(_t * 4.0 + 100.0), 0.0, _noise.get_noise_1d(_t * 4.0 + 200.0)) * 0.08
