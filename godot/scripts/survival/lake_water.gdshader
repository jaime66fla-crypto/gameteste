shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.055, 0.19, 0.21, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.19, 0.37, 0.34, 1.0);
uniform vec4 ripple_color : source_color = vec4(0.42, 0.65, 0.61, 1.0);
uniform float wave_height : hint_range(0.0, 0.04) = 0.018;
uniform float time_offset = 0.0;
varying vec2 world_xz;

void vertex() {
    world_xz = VERTEX.xz;
    float t = TIME + time_offset;
    float edge = 1.0 - smoothstep(0.78, 1.0, length(UV * 2.0 - 1.0));
    float a = sin(dot(world_xz, vec2(1.25, 0.62)) + t * 1.15);
    float b = sin(dot(world_xz, vec2(-0.72, 1.66)) - t * 0.88);
    VERTEX.y += (a + b * 0.55) * wave_height * edge;
}

void fragment() {
    float t = TIME + time_offset;
    float a = dot(world_xz, vec2(1.25, 0.62)) + t * 1.15;
    float b = dot(world_xz, vec2(-0.72, 1.66)) - t * 0.88;
    vec2 slope = cos(a) * vec2(1.25, 0.62) * 0.055 + cos(b) * vec2(-0.72, 1.66) * 0.035;
    vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
    NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
    float radius = length(UV * 2.0 - 1.0);
    float bank = smoothstep(0.65, 1.0, radius);
    float ripple = smoothstep(0.60, 0.92, sin(radius * 75.0 - t * 1.7 + sin(a) * 0.7));
    float crest = smoothstep(0.63, 0.98, sin(a) * sin(b));
    vec3 base = mix(deep_color.rgb, shallow_color.rgb, bank * 0.55 + fresnel * 0.40);
    ALBEDO = mix(base, ripple_color.rgb, crest * 0.10 + ripple * bank * 0.13);
    ROUGHNESS = 0.17 + bank * 0.10;
    METALLIC = 0.10;
    SPECULAR = 0.65;
}
