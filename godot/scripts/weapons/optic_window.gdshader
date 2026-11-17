shader_type spatial;
// First-person viewmodel only: the original weapon look (albedo texture,
// colour, roughness, metallic) with a see-through window cut through the solid
// low-poly optic, so the red dot can be seen through it (CoD-style ADS).
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 0.8;
uniform float metallic = 0.0;
// glTF ORM maps: scalar * dot(texture, channel) like BaseMaterial3D.
uniform sampler2D roughness_texture : hint_roughness_gray, filter_linear_mipmap;
uniform bool use_roughness_texture = false;
uniform vec4 roughness_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap;
uniform bool use_metallic_texture = false;
uniform vec4 metallic_channel = vec4(0.0, 0.0, 1.0, 0.0);
// Window box in mesh-local space.
uniform vec3 cut_min;
uniform vec3 cut_max;

varying vec3 local_pos;

void vertex() {
    local_pos = VERTEX;
}

void fragment() {
    if (all(greaterThan(local_pos, cut_min)) && all(lessThan(local_pos, cut_max))) {
        discard;
    }
    vec4 color = albedo_color;
    if (use_texture) {
        color *= texture(albedo_texture, UV);
    }
    // Inner walls of the housing (back faces) read darker, giving the frame depth.
    ALBEDO = FRONT_FACING ? color.rgb : color.rgb * 0.35;
    float rough = roughness;
    if (use_roughness_texture) {
        rough *= dot(texture(roughness_texture, UV), roughness_channel);
    }
    float metal = metallic;
    if (use_metallic_texture) {
        metal *= dot(texture(metallic_texture, UV), metallic_channel);
    }
    ROUGHNESS = rough;
    METALLIC = metal;
}
