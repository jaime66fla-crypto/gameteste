shader_type spatial;
// Pato tático: um só material para corpo e equipamento.
// COLOR.rgb = cor base (sRGB); COLOR.a = tipo de pintura:
//   1.0 liso | 0.0 camuflado da camisa (escuro) | 0.33 calça (mata) | 0.66 equipamento
// UV.x = rugosidade; UV2 = posição de repouso (o camuflado não "escorre" na animação).

uniform vec4 shirt_base : source_color = vec4(0.075, 0.075, 0.07, 1.0);
uniform vec4 shirt_a : source_color = vec4(0.16, 0.15, 0.12, 1.0);
uniform vec4 shirt_b : source_color = vec4(0.25, 0.23, 0.17, 1.0);
uniform vec4 pants_base : source_color = vec4(0.36, 0.32, 0.21, 1.0);
uniform vec4 pants_a : source_color = vec4(0.22, 0.22, 0.13, 1.0);
uniform vec4 pants_b : source_color = vec4(0.12, 0.10, 0.07, 1.0);
uniform vec4 pants_c : source_color = vec4(0.05, 0.05, 0.045, 1.0);

varying vec2 camo_uv;
varying float rough;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.6 + noise(p * 2.13 + 4.7) * 0.28 + noise(p * 4.37 + 9.1) * 0.12;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	camo_uv = UV2;
	rough = UV.x;
}

void fragment() {
	float kind = round(COLOR.a * 3.0);
	vec3 albedo = srgb_to_linear(COLOR.rgb);
	vec2 p = camo_uv * 6.5;
	float n1 = fbm(p);
	float n2 = fbm(p * 1.3 + vec2(17.3, 5.1));
	float n3 = fbm(p * 1.7 + vec2(3.9, 23.7));
	if (kind < 0.5) {
		albedo = shirt_base.rgb;
		albedo = mix(albedo, shirt_a.rgb, step(0.56, n1));
		albedo = mix(albedo, shirt_b.rgb, step(0.62, n2) * 0.8);
	} else if (kind < 2.5) {
		albedo = pants_base.rgb;
		albedo = mix(albedo, pants_a.rgb, step(0.5, n1));
		albedo = mix(albedo, pants_b.rgb, step(0.58, n2));
		albedo = mix(albedo, pants_c.rgb, step(0.66, n3));
		if (kind > 1.5) {
			albedo *= 0.62; // bolsos e cachecol um pouco mais escuros que a calça
		}
	}
	// Leve variação de tecido.
	albedo *= 0.92 + 0.16 * noise(camo_uv * 90.0);
	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.4;
}
