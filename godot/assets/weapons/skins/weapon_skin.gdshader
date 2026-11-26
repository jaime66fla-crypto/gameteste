shader_type spatial;
// Acabamento das skins de arma da loja (scripts/weapons/weapon_skins.gd).
// Os desenhos (camuflagem, veio de madeira, oxidação, desgaste) são calculados
// no espaço do próprio modelo: atravessam as ilhas de UV sem costura.
// A textura da skin (skin_map) só diz o que é "corpo pintado" (claro) e o que é
// "metal/peças" (escuro), além de guardar o sombreado das peças.

uniform sampler2D skin_map : source_color, filter_linear_mipmap, repeat_disable;

// Máscara corpo × metal, pela luminância da skin_map.
uniform float mask_lo = 0.08;
uniform float mask_hi = 0.16;
uniform float detail = 0.35; // quanto do sombreado da skin_map fica

// Desenho do corpo: 0 cerakote liso, 1 camuflagem orgânica, 2 camuflagem
// digital, 3 madeira, 4 aço oxidado com têmpera.
uniform int pattern = 0;
uniform float pattern_scale = 6.0;
uniform vec3 color_a : source_color = vec3(0.3);
uniform vec3 color_b : source_color = vec3(0.25);
uniform vec3 color_c : source_color = vec3(0.2);
uniform vec3 color_d : source_color = vec3(0.1);
uniform float body_metallic = 0.0;
uniform float body_roughness = 0.6;
uniform float stipple = 0.0; // relevo granulado (empunhadura texturizada)

// Peças de metal (onde a skin_map é escura).
uniform vec3 metal_color : source_color = vec3(0.06);
uniform float metal_metallic = 0.8;
uniform float metal_roughness = 0.38;
uniform float brushed = 0.0; // riscos de aço escovado ao longo do cano
uniform int metal_pattern = 0; // 0 metal comum, 4 aço oxidado com têmpera

// Têmpera (aço azul): cores do calor ao longo do comprimento.
uniform vec3 heat_a : source_color = vec3(0.55, 0.42, 0.2);
uniform vec3 heat_b : source_color = vec3(0.32, 0.14, 0.3);
uniform vec3 heat_c : source_color = vec3(0.08, 0.14, 0.32);
uniform float heat = 0.0;

// Uso.
uniform float wear = 0.0; // lascas mostrando o aço por baixo
uniform vec3 bare_steel : source_color = vec3(0.55, 0.56, 0.58);
uniform float rust = 0.0; // ferrugem sobre o metal
uniform vec3 rust_a : source_color = vec3(0.36, 0.15, 0.06);
uniform vec3 rust_b : source_color = vec3(0.18, 0.08, 0.04);

// Filete de destaque (gravação) — fino, quase sempre desligado.
uniform vec3 inlay_color : source_color = vec3(0.7, 0.52, 0.25);
uniform float inlay = 0.0;

// Brilho especial animado de cada skin: 1 reluzir (reflexo que varre a arma),
// 2 corrente (energia correndo pelo aço), 3 brasa (ferrugem incandescente),
// 4 areia dourada (cintilação), 5 mata viva (veios da camuflagem pulsando).
uniform int fx = 0;
uniform vec3 fx_color : source_color = vec3(1.0, 0.85, 0.5);
uniform float fx_strength = 1.0;
uniform float fx_speed = 1.0;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Manchas de camuflagem: quatro tons, bordas firmes mas não serrilhadas.
vec3 camo(vec3 p, out float h) {
	float aa = 0.02;
	float n1 = fbm(p);
	float n2 = fbm(p * 1.3 + vec3(5.2, 1.3, 7.7));
	float n3 = fbm(p * 1.9 + vec3(2.9, 8.1, 4.4));
	vec3 c = color_a;
	c = mix(c, color_b, smoothstep(0.5 - aa, 0.5 + aa, n1));
	c = mix(c, color_c, smoothstep(0.54 - aa, 0.54 + aa, n2));
	c = mix(c, color_d, smoothstep(0.6 - aa, 0.6 + aa, n3));
	h = smoothstep(0.5 - aa, 0.5 + aa, n1) * 0.3 + smoothstep(0.6 - aa, 0.6 + aa, n3) * 0.4;
	return c;
}

vec3 heat_tint(vec3 p, vec3 base) {
	float t = clamp(p.x * 1.7 + 0.5 + (fbm(p * 3.0) - 0.5) * 0.7, 0.0, 1.0);
	vec3 h = mix(heat_a, heat_b, smoothstep(0.0, 0.45, t));
	h = mix(h, heat_c, smoothstep(0.4, 0.85, t));
	return mix(base, h, heat);
}

void fragment() {
	vec4 skin = texture(skin_map, UV);
	float lum = luma(skin.rgb);
	float body = smoothstep(mask_lo, mask_hi, lum);
	vec3 p = lpos * pattern_scale;
	float height = 0.0;

	// Corpo pintado.
	vec3 bc = color_a;
	float b_rough = body_roughness;
	float b_metal = body_metallic;
	if (pattern == 1) {
		bc = camo(p, height);
	} else if (pattern == 2) {
		vec3 q = floor(p * 3.0) / 3.0;
		bc = camo(q, height);
		height *= 0.4;
	} else if (pattern == 3) {
		// Madeira: anéis ao longo do comprimento (eixo X), com poros.
		float warp = fbm(p * vec3(0.25, 3.0, 3.0)) * 2.2;
		float rings = fract(length(p.yz * vec2(1.0, 1.6)) * 18.0 + warp);
		float grain = smoothstep(0.0, 0.5, rings) * smoothstep(1.0, 0.55, rings);
		float fibre = vnoise(p * vec3(1.5, 60.0, 60.0));
		bc = mix(color_b, color_a, grain);
		bc = mix(bc, color_c, smoothstep(0.65, 0.95, fibre) * 0.6);
		bc *= 0.85 + 0.3 * fbm(p * vec3(0.3, 1.0, 1.0));
		height = grain * 0.25 + fibre * 0.15;
		b_rough = body_roughness + (1.0 - grain) * 0.12;
	} else if (pattern == 4) {
		bc = heat_tint(lpos, color_a);
	}
	float tone = mix(1.0, clamp(lum / max(mask_hi * 2.2, 0.05), 0.45, 1.25), detail);
	if (mask_hi <= 0.0) {
		tone = mix(1.0, clamp(0.55 + lum * 2.0, 0.55, 1.2), detail);
	}
	bc *= tone;
	if (stipple > 0.0) {
		height += vnoise(lpos * 300.0) * stipple * body;
		b_rough = min(1.0, b_rough + stipple * 0.4);
	}

	// Metal.
	vec3 mc = metal_color * mix(1.0, clamp(lum / 0.08, 0.6, 1.5), detail);
	float m_rough = metal_roughness;
	if (metal_pattern == 4) {
		mc = heat_tint(lpos, mc);
	}
	if (brushed > 0.0) {
		float streak = vnoise(lpos * vec3(4.0, 220.0, 220.0));
		m_rough = clamp(m_rough + (streak - 0.5) * brushed * 0.25, 0.05, 1.0);
		mc *= 1.0 + (streak - 0.5) * brushed * 0.25;
	}
	float m_metal = metal_metallic;
	float rm = 0.0;
	if (rust > 0.0) {
		float r = fbm(lpos * 9.0 + vec3(3.0)) * 0.8 + vnoise(lpos * 70.0) * 0.2;
		rm = smoothstep(0.6 - rust * 0.15, 0.66 - rust * 0.15, r);
		float pit = vnoise(lpos * 260.0);
		vec3 rc = mix(rust_a, rust_b, pit);
		mc = mix(mc, rc, rm);
		m_rough = mix(m_rough, 0.92, rm);
		m_metal = mix(m_metal, 0.05, rm);
		height += rm * (0.2 + pit * 0.35);
	}

	vec3 albedo = mix(mc, bc, body);
	float rough = mix(m_rough, b_rough, body);
	float metal = mix(m_metal, b_metal, body);

	// Lascas: o acabamento gasta e mostra o aço (só no corpo pintado).
	float chip = 0.0;
	if (wear > 0.0) {
		float w = fbm(lpos * 38.0) * 0.75 + vnoise(lpos * 160.0) * 0.25;
		chip = smoothstep(0.74 - wear * 0.2, 0.76 - wear * 0.2, w) * body;
		albedo = mix(albedo, bare_steel, chip);
		rough = mix(rough, 0.4, chip);
		metal = mix(metal, 0.55, chip);
		height -= chip * 0.35;
	}

	// Filete gravado: linhas finas que seguem o comprimento.
	if (inlay > 0.0) {
		float line = abs(fract(lpos.y * 22.0 + fbm(lpos * 4.0) * 0.6) - 0.5);
		float m = (1.0 - smoothstep(0.015, 0.035, line)) * body * inlay;
		albedo = mix(albedo, inlay_color, m);
		metal = mix(metal, 1.0, m);
		rough = mix(rough, 0.25, m);
		height += m * 0.3;
	}

	// Relevo procedural (bump por derivadas de tela).
	vec3 n = NORMAL;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float hs = height * 0.0015;
	float dhdx = dFdx(hs);
	float dhdy = dFdy(hs);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	if (abs(det) > 1e-9) {
		vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
		n = normalize(abs(det) * n - grad);
	}
	NORMAL = n;

	if (fx > 0) {
		float t = TIME * fx_speed;
		float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
		// Reflexo diagonal que atravessa a arma e some, a cada ~4 s.
		float phase = fract(t * 0.25);
		float d = lpos.x + lpos.y * 0.6 + lpos.z * 0.5 - mix(-1.4, 1.4, phase);
		float sweep = exp(-d * d * 900.0) + exp(-d * d * 60.0) * 0.25;
		vec3 glow = vec3(0.0);
		if (fx == 1) {
			glow = fx_color * sweep * (1.0 + metal) + fx_color * chip * sweep * 3.0;
		} else if (fx == 2) {
			float flow = vnoise(vec3(lpos.x * 9.0 + t * 2.5, lpos.y * 45.0, lpos.z * 45.0));
			float arc = smoothstep(0.78, 0.92, flow) * (0.6 + 0.4 * sin(t * 9.0 + lpos.x * 30.0));
			float pulse = 0.5 + 0.5 * sin(t * 2.2);
			glow = fx_color * (arc * 1.6 + fres * pulse * 0.9 + sweep * 0.8);
		} else if (fx == 3) {
			float heatn = vnoise(lpos * 45.0 + vec3(0.0, t * 0.7, t * 0.3));
			float flick = 0.65 + 0.35 * sin(t * 6.0 + heatn * 12.0);
			float ember = rm * smoothstep(0.55, 0.85, heatn) * flick;
			glow = fx_color * ember * 2.2 + vec3(1.0, 0.6, 0.3) * sweep * 0.6;
		} else if (fx == 4) {
			vec3 cell = floor(lpos * 140.0);
			float r = hash3(cell);
			float twinkle = pow(max(0.0, sin(t * 2.5 + r * 60.0)), 24.0) * step(0.9, r);
			glow = fx_color * (twinkle * 4.0 * body + sweep * 0.9);
		} else if (fx == 5) {
			vec3 q = floor(lpos * pattern_scale * 3.0) / 3.0;
			float vein = 1.0 - smoothstep(0.0, 0.03, abs(fbm(q) - 0.5));
			float wave = pow(0.5 + 0.5 * sin(lpos.x * 9.0 - t * 2.8), 4.0);
			glow = fx_color * vein * wave * body * 1.8 + vec3(0.85, 1.0, 0.8) * sweep * 0.9 + fx_color * fres * 0.25;
		}
		EMISSION = glow * fx_strength;
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
}
