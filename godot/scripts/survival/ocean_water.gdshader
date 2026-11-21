shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
uniform vec4 deep_color : source_color = vec4(0.055,0.23,0.32,1.0);
uniform vec4 shallow_color : source_color = vec4(0.14,0.39,0.46,1.0);
varying vec2 world_xz;
void vertex() {
    world_xz = VERTEX.xz;
    VERTEX.y += sin(dot(world_xz, vec2(0.09,0.045)) + TIME*0.7)*0.045;
}
void fragment() {
    float a = dot(world_xz,vec2(0.09,0.045)) + TIME*0.7;
    float b = dot(world_xz,vec2(-0.035,0.07)) - TIME*0.5;
    vec2 slope = cos(a)*vec2(0.09,0.045)*0.15 + cos(b)*vec2(-0.035,0.07)*0.13;
    NORMAL = normalize((VIEW_MATRIX*vec4(normalize(vec3(-slope.x,1.0,-slope.y)),0.0)).xyz);
    float fresnel = pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
    float variation = sin(a)*sin(b)*0.5+0.5;
    ALBEDO = mix(deep_color.rgb,shallow_color.rgb,fresnel*0.65+variation*0.14);
    ROUGHNESS = 0.48;
    METALLIC = 0.0;
    SPECULAR = 0.3;
}
