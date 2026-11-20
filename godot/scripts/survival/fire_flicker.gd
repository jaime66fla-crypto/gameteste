extends OmniLight3D
## Luz de fogueira: a intensidade e o alcance tremulam um pouco, como chama.
var _t := randf() * 10.0
var _base_energy := 2.2
var _base_range := 11.0

func _ready() -> void:
	_base_energy = light_energy
	_base_range = omni_range

func _process(delta: float) -> void:
	_t += delta
	var n := sin(_t * 9.0) * 0.5 + sin(_t * 23.0 + 1.3) * 0.3 + sin(_t * 3.1) * 0.2
	light_energy = _base_energy * (1.0 + n * 0.12)
	omni_range = _base_range * (1.0 + n * 0.03)
