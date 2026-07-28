#version 450
layout(location=0) in vec2 v_uv;
layout(set=0, binding=0) uniform sampler2D u_scene;
layout(set=0, binding=1) uniform sampler2D u_bloom;
// p1 = (bloom_enabled, bloom_strength, exposure, vignette)
layout(push_constant) uniform Push { vec4 p0; vec4 p1; } pc;
layout(location=0) out vec4 frag_color;
void main() {
    vec3 c = texture(u_scene, v_uv).rgb;
    if (pc.p1.x > 0.5) {
        c += texture(u_bloom, v_uv).rgb * pc.p1.y;
    }
    c = vec3(1.0) - exp(-c * pc.p1.z);              // filmic-ish tonemap
    vec2 d = v_uv - 0.5;
    c *= 1.0 - pc.p1.w * dot(d, d);                  // vignette
    c = pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));     // gamma
    frag_color = vec4(c, 1.0);
}
