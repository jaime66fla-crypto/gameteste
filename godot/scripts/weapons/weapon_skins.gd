extends RefCounted
## Acabamento de cada skin de arma da loja (data/store.json, grupo skins_armas).
## A PNG da skin ("textura") separa corpo pintado × peças de metal; o shader
## assets/weapons/skins/weapon_skin.gdshader desenha por cima, no espaço do
## modelo: camuflagem, madeira, aço oxidado, relevo, desgaste e um brilho
## especial animado (fx) diferente em cada skin.
## Chave = nome da PNG sem extensão (= id do item).
const SHADER := preload("res://assets/weapons/skins/weapon_skin.gdshader")

const SKINS := {
	# Pistola: armação de polímero oliva com empunhadura granulada, ferrolho de
	# aço nitretado escovado e lascas onde a mão gasta.
	"pistol_oliva": {
		"fx": 1, "fx_color": Color("#fff1c9"), "fx_strength": 1.4,
		"mask_lo": 0.10, "mask_hi": 0.18, "detail": 0.3,
		"pattern": 0,
		"color_a": Color("#4f5a3a"),
		"body_roughness": 0.72, "stipple": 0.35,
		"metal_color": Color("#2a2c2e"), "metal_metallic": 0.9, "metal_roughness": 0.32,
		"brushed": 0.8,
		"wear": 0.45, "bare_steel": Color("#8d9196"),
	},
	# Submetralhadora: aço oxidado azul com têmpera (dourado → violeta → azul)
	# ao longo do corpo, riscos de usinagem e peças pretas foscas.
	"smg_azul_aco": {
		"fx": 2, "fx_color": Color("#4fb6ff"), "fx_strength": 1.3, "fx_speed": 1.0,
		"mask_lo": 0.035, "mask_hi": 0.09, "detail": 0.25,
		"pattern": 4,
		"color_a": Color("#24324e"),
		"heat_a": Color("#866a3a"), "heat_b": Color("#46305a"), "heat_c": Color("#2e4a80"),
		"heat": 0.8,
		"body_metallic": 0.95, "body_roughness": 0.22,
		"metal_color": Color("#161a22"), "metal_metallic": 0.85, "metal_roughness": 0.3,
		"metal_pattern": 0, "brushed": 0.8,
		"wear": 0.25, "bare_steel": Color("#b9bec6"),
	},
	# Escopeta: coronha e telha em nogueira envernizada (veio de verdade) e metal
	# velho com ferrugem nas emendas.
	"shotgun_ferrugem": {
		"fx": 3, "fx_color": Color("#ff5a14"), "fx_strength": 1.5,
		"mask_lo": 0.2, "mask_hi": 0.3, "detail": 0.2,
		"pattern": 3, "pattern_scale": 5.0,
		"color_a": Color("#6e3e20"), "color_b": Color("#3a1d0f"), "color_c": Color("#22100a"),
		"body_roughness": 0.38,
		"metal_color": Color("#34312e"), "metal_metallic": 0.85, "metal_roughness": 0.45,
		"brushed": 0.4,
		"rust": 0.85, "rust_a": Color("#8a4520"), "rust_b": Color("#4a2410"),
	},
	# Fuzil: camuflagem árida de quatro tons (areia, cáqui, terra e marrom),
	# pintura gasta nas quinas mostrando o aço, metal preto fosco.
	"rifle_deserto": {
		"fx": 4, "fx_color": Color("#ffcf6a"), "fx_strength": 1.4,
		"mask_lo": -1.0, "mask_hi": 0.0, "detail": 0.45,
		"pattern": 1, "pattern_scale": 6.0,
		"color_a": Color("#8c7a58"), "color_b": Color("#6e5d42"), "color_c": Color("#4f4130"),
		"color_d": Color("#a39272"),
		"body_roughness": 0.78, "stipple": 0.12,
		"metal_color": Color("#1b1b1a"), "metal_metallic": 0.6, "metal_roughness": 0.55,
		"wear": 0.35, "bare_steel": Color("#9a9a96"),
	},
	# Sniper (a mais cara): camuflagem de mata em pixels, gravação em bronze ao
	# longo do corpo, metal escovado e um reflexo de vitrine que corre a arma.
	"sniper_floresta": {
		"fx": 5, "fx_color": Color("#5dff86"), "fx_strength": 1.3,
		"mask_lo": 0.165, "mask_hi": 0.2, "detail": 0.2,
		"pattern": 2, "pattern_scale": 18.0,
		"color_a": Color("#4a5634"), "color_b": Color("#2c3622"), "color_c": Color("#6b6444"),
		"color_d": Color("#1a1e16"),
		"body_roughness": 0.7, "stipple": 0.15,
		"metal_color": Color("#202320"), "metal_metallic": 0.9, "metal_roughness": 0.3,
		"brushed": 0.7,
		"inlay": 1.0, "inlay_color": Color("#a57a3a"),
		"wear": 0.3, "bare_steel": Color("#8f938e"),
	},
}

static func id_from_path(path: String) -> String:
	return path.get_file().get_basename()

static func has_finish(path: String) -> bool:
	return SKINS.has(id_from_path(path))

## Material da skin para a PNG dada (null se a skin não tem acabamento).
static func material(path: String, texture: Texture2D) -> ShaderMaterial:
	var params: Dictionary = SKINS.get(id_from_path(path), {})
	if params.is_empty():
		return null
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("skin_map", texture)
	for key in params:
		var value: Variant = params[key]
		if value is Color:
			var c: Color = value
			value = Vector3(c.r, c.g, c.b)
		mat.set_shader_parameter(key, value)
	mat.set_meta("skin_path", path)
	return mat
