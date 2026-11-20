extends RefCounted
## Materiais PBR dos mapas, feitos com o atlas de texturas urbanas
## (assets/textures/maps, recortado por tools/import_map_atlas.gd).
## - Mapas online (match_map.gd): cada cor da paleta de data/match_maps.json
##   vira uma superfície — for_colour().
## - Sobrevivência (survival_world.gd e world_polish.gd): os tipos de chão e
##   parede de SurfaceMaterials passam a usar estas texturas — surface().
## Superfícies que repetem usam triplanar no espaço do mundo (o grão tem sempre
## o mesmo tamanho); caixotes usam a imagem inteira em cada face (UV da caixa).
const TEX := "res://assets/textures/maps/%s_%s.png"
## tipo: [metros cobertos por uma textura (0 = uma por face), relevo, metálico]
const KINDS := {
	"grass": [3.5, 0.35, 0.0],
	"asphalt": [3.0, 0.7, 0.0],
	"pavers": [2.4, 0.9, 0.0],
	"concrete": [3.0, 0.7, 0.0],
	"brick": [1.2, 0.9, 0.0],
	"roof": [1.5, 0.9, 0.3],
	"dirt": [3.0, 0.8, 0.0],
	"gravel": [1.5, 1.0, 0.0],
	"leaves": [2.0, 0.8, 0.0],
	"hazard": [1.0, 0.5, 0.0],
	"plaster": [3.0, 0.3, 0.0],
	"crate_wood": [0.0, 0.9, 0.0],
	"crate_metal": [0.0, 0.9, 0.4],
}
## Cor da paleta dos mapas online -> superfície.
const BY_COLOUR := {
	"grass": "grass", "road": "asphalt", "base": "pavers", "border": "concrete",
	"stone": "brick", "roof": "roof", "wood": "crate_wood", "orange": "crate_metal",
	"wall": "concrete",
	"red": "plaster", "blue": "plaster", "yellow": "plaster", "teal": "plaster",
}
## Tipos da Sobrevivência (nomes de SurfaceMaterials) -> superfície do atlas.
const SURVIVAL := {
	"asphalt": "asphalt", "concrete": "concrete", "grass": "grass",
	"plaster": "plaster", "roof": "roof", "dirt": "dirt",
}
## Só o reboco recebe a cor cheia (é tinta); o resto tem cor própria na foto.
const PAINTED := ["plaster"]
## Tintas trocadas por tons escuros, no clima do atlas (casas azuis).
const DARK_PAINT := {"blue": "#34495e", "teal": "#2f4f4c"}

static var _cache: Dictionary = {}

static func kind_for(colour: String) -> String:
	return BY_COLOUR.get(colour, "plaster")

static func per_face(kind: String) -> bool:
	return float(KINDS[kind][0]) <= 0.0

## Tinta de fachada mais sóbria: tira o excesso de saturação da paleta de
## brinquedo e puxa um pouco para o quente, como tinta de parede ao sol.
static func paint(hex: String) -> Color:
	var c := Color(hex)
	var lum := c.get_luminance()
	c = c.lerp(Color(lum, lum, lum), 0.28)
	c = c.lerp(Color(0.93, 0.89, 0.82), 0.08)
	if lum > 0.85: # branco puro estoura no sol
		c = c.darkened(0.08)
	return c

## Só o matiz da cor pedida, de leve, sobre a cor da textura (a mancha de grama
## mais seca continua mais seca, o telhado do celeiro continua avermelhado).
static func hue_hint(hex: String, amount: float = 0.35) -> Color:
	var c := Color(hex)
	var lum := maxf(c.get_luminance(), 0.05)
	var hue := Color(minf(c.r / lum, 2.0), minf(c.g / lum, 2.0), minf(c.b / lum, 2.0))
	return Color.WHITE.lerp(hue, amount)

## Mapas online.
static func for_colour(colour: String, hex: String) -> StandardMaterial3D:
	var kind := kind_for(colour)
	if not kind in PAINTED:
		return _make(kind, Color.WHITE, true)
	var tint := Color(DARK_PAINT[colour]) if DARK_PAINT.has(colour) else paint(hex)
	return _make(kind, tint, true)

## Sobrevivência: null quando o tipo não é do atlas (madeira, metal, tecido...).
static func surface(kind: String, hex: String) -> StandardMaterial3D:
	if not SURVIVAL.has(kind):
		return null
	var atlas: String = SURVIVAL[kind]
	if not atlas in PAINTED:
		return _make(atlas, hue_hint(hex), false)
	return _make(atlas, dark_blue(Color(hex)), false)

## Parede azulada fica num azul-ardósia escuro (o resto da tinta não muda).
static func dark_blue(c: Color) -> Color:
	if c.b > c.r + 0.08 and c.b >= c.g:
		return c.darkened(0.55)
	return c

static func _make(kind: String, tint: Color, double_sided: bool) -> StandardMaterial3D:
	var key := kind + tint.to_html() + str(double_sided)
	if _cache.has(key):
		return _cache[key]
	var spec: Array = KINDS[kind]
	var m := StandardMaterial3D.new()
	m.resource_name = "map_" + kind
	m.albedo_color = tint
	m.albedo_texture = load(TEX % [kind, "albedo"])
	m.normal_enabled = true
	m.normal_texture = load(TEX % [kind, "normal"])
	m.normal_scale = spec[1]
	m.roughness = 1.0
	m.roughness_texture = load(TEX % [kind, "rough"])
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = spec[2]
	m.metallic_specular = 0.4
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if per_face(kind):
		m.texture_repeat = false
	else:
		m.texture_repeat = true
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_triplanar_sharpness = 12.0 # caixas: quase sem mistura entre faces
		m.uv1_scale = Vector3.ONE / float(spec[0])
	if double_sided:
		# As faces das caixas do mapa online são montadas à mão: sem culling,
		# nenhuma some por causa da ordem dos vértices.
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m
