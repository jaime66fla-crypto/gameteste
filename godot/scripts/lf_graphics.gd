extends RefCounted
## Luz e céu do Linha de Fogo (fps-tatico/tools/gen_level.ps1) para todos os mapas do
## Campo de Fogo: céu procedural azul, ambiente do céu com tom quente, ACES, glow leve,
## névoa de distância com perspectiva aérea, contraste +8% e sol quente com sombra suave.
## Chamado por match_map.gd, training_ground.gd e world_polish.gd (_tune_environment);
## a qualidade gráfica (GameSettings) desliga glow e névoa na Baixa (main._shadow_quality).

static func apply(env: Environment, sun: DirectionalLight3D) -> void:
	if env == null:
		return
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.3, 0.46, 0.72)
	sky_material.sky_horizon_color = Color(0.76, 0.77, 0.78)
	sky_material.sky_curve = 0.12
	sky_material.ground_bottom_color = Color(0.32, 0.27, 0.21)
	sky_material.ground_horizon_color = Color(0.66, 0.66, 0.64)
	sky_material.sun_angle_max = 8.0
	sky_material.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_color = Color(0.62, 0.57, 0.5)
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.74, 0.74)
	env.fog_density = 0.0012 # metade da do Linha: os mapas do Campo de Fogo são bem maiores
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.0
	if sun != null:
		sun.rotation_degrees = Vector3(-52, 35, 0)
		sun.light_color = Color(1, 0.9, 0.76)
		sun.light_energy = 1.6
		sun.shadow_enabled = true
		sun.shadow_bias = 0.04
		sun.shadow_blur = 1.5
		sun.directional_shadow_max_distance = 70.0

## Qualidade Baixa: sem glow e sem névoa (como no Linha de Fogo).
static func apply_quality(env: Environment, quality: int) -> void:
	if env == null:
		return
	env.glow_enabled = quality > 0
	env.fog_enabled = quality > 0
