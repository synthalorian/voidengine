#version 450
layout(location=0) in vec2 v_uv;
layout(set=0, binding=0) uniform sampler2D u_scene;
layout(set=0, binding=1) uniform sampler2D u_bloom;
// p1 = (bloom_enabled, bloom_strength, exposure, vignette)
// p0 = (saturation, grain, frame, unused)
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
    float lum = dot(c, vec3(0.299, 0.587, 0.114));   // grade: saturation
    c = mix(vec3(lum), c, pc.p0.x);
    float g = fract(sin(dot(v_uv + fract(pc.p0.z * 0.61803), vec2(12.9898, 78.233))) * 43758.5453);
    c += (g - 0.5) * pc.p0.y;                        // film grain
    c = pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));     // gamma
    frag_color = vec4(c, 1.0);
}
