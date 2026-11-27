extends RefCounted
## Materiais PBR dos mapas, no gráfico do Linha de Fogo: texturas procedurais
## repetíveis com normal map (assets/textures/lf, geradas por tools/gen_lf_textures.gd
## a partir do gerador do fps-tatico, com as superfícies que só o Campo de Fogo tem).
## - Mapas online (match_map.gd): cada cor da paleta de data/match_maps.json
##   vira uma superfície — for_colour().
## - Sobrevivência (survival_world.gd e world_polish.gd): os tipos de chão e
##   parede de SurfaceMaterials passam a usar estas texturas — surface().
## - Treino (training_ground.gd): as peças de grade usam lf() direto.
## Superfícies que repetem usam triplanar no espaço do mundo (o grão tem sempre
## o mesmo tamanho); caixotes usam a imagem inteira em cada face (UV da caixa).
## (Antes: atlas de texturas urbanas escuras, assets/textures/maps.)
const TEX := "res://assets/textures/lf/%s.png"
const NORMAL := "res://assets/textures/lf/%s_n.png"
## textura do Linha: [metros cobertos por uma textura, relevo, rugosidade, metálico]
const LF := {
	"floor": [4.0, 1.0, 0.95, 0.0], # lajotas de 1 m
	"plaster": [4.0, 1.0, 0.95, 0.0],
	"stone": [2.4, 1.0, 0.9, 0.0],
	"stone_dark": [2.4, 1.0, 0.9, 0.0],
	"concrete": [2.0, 1.0, 0.9, 0.0],
	"crate": [1.0, 1.0, 0.85, 0.0],
	"metal": [2.0, 1.0, 0.6, 0.35],
	"trim": [2.0, 1.0, 0.9, 0.0],
	"grass": [3.5, 0.8, 0.95, 0.0],
	"asphalt": [3.0, 0.8, 0.9, 0.0],
	"dirt": [3.0, 1.0, 0.95, 0.0],
	"gravel": [1.5, 1.0, 0.95, 0.0],
	"leaves": [2.0, 1.0, 0.95, 0.0],
	"hazard": [1.0, 0.6, 0.8, 0.0],
}
## Superfície do jogo -> textura do Linha de Fogo.
const KINDS := {
	"grass": "grass", "asphalt": "asphalt", "pavers": "floor", "concrete": "concrete",
	"brick": "stone", "roof": "metal", "dirt": "dirt", "gravel": "gravel",
	"leaves": "leaves", "hazard": "hazard", "plaster": "plaster",
	"crate_wood": "crate", "crate_metal": "metal",
}
## Caixotes: uma imagem inteira por face (UV da caixa).
const PER_FACE := ["crate_wood", "crate_metal"]
## Cor da paleta dos mapas online -> superfície.
const BY_COLOUR := {
	"grass": "grass", "road": "asphalt", "base": "pavers", "border": "concrete",
	"stone": "brick", "roof": "roof", "wood": "crate_wood", "orange": "crate_metal",
	"wall": "concrete",
	"red": "plaster", "blue": "plaster", "yellow": "plaster", "teal": "plaster",
}
## Tipos da Sobrevivência (nomes de SurfaceMaterials) -> superfície.
const SURVIVAL := {
	"asphalt": "asphalt", "concrete": "concrete", "grass": "grass",
	"plaster": "plaster", "roof": "roof", "dirt": "dirt",
}
## Só o reboco recebe a cor cheia (é tinta); o resto tem cor própria na textura.
const PAINTED := ["plaster"]

static var _cache: Dictionary = {}

static func kind_for(colour: String) -> String:
	return BY_COLOUR.get(colour, "plaster")

static func per_face(kind: String) -> bool:
	return kind in PER_FACE

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
	return _make(kind, paint(hex), true)

## Sobrevivência: null quando o tipo não é dos mapas (madeira, metal, tecido...).
static func surface(kind: String, hex: String) -> StandardMaterial3D:
	if not SURVIVAL.has(kind):
		return null
	var mapped: String = SURVIVAL[kind]
	if not mapped in PAINTED:
		return _make(mapped, hue_hint(hex), false)
	return _make(mapped, paint(hex), false)

static func _make(kind: String, tint: Color, double_sided: bool) -> StandardMaterial3D:
	var m := lf(KINDS[kind], tint, true, per_face(kind), double_sided)
	m.resource_name = "map_" + kind
	return m

## Material do Linha de Fogo (textura de assets/textures/lf). world = false: a
## textura acompanha o objeto (peças que se mexem). per_face: uma imagem por face.
static func lf(texture: String, tint: Color = Color.WHITE, world: bool = true, face: bool = false, double_sided: bool = false) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [texture, tint.to_html(), world, face, double_sided]
	if _cache.has(key):
		return _cache[key]
	var spec: Array = LF[texture]
	var m := StandardMaterial3D.new()
	m.resource_name = "lf_" + texture
	m.albedo_color = tint
	m.albedo_texture = load(TEX % texture)
	m.normal_enabled = true
	m.normal_texture = load(NORMAL % texture)
	m.normal_scale = spec[1]
	m.roughness = spec[2]
	m.metallic = spec[3]
	m.metallic_specular = 0.4
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if face:
		m.texture_repeat = false
	else:
		m.texture_repeat = true
		m.uv1_triplanar = true
		m.uv1_world_triplanar = world
		m.uv1_triplanar_sharpness = 12.0 # caixas: quase sem mistura entre faces
		m.uv1_scale = Vector3.ONE / float(spec[0])
	if double_sided:
		# As faces das caixas do mapa online são montadas à mão: sem culling,
		# nenhuma some por causa da ordem dos vértices.
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m
