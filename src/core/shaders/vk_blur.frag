#version 450
layout(location=0) in vec2 v_uv;
layout(set=0, binding=0) uniform sampler2D u_tex;
layout(push_constant) uniform Push { vec4 p0; vec4 p1; } pc; // p0.xy = texel-scaled dir
layout(location=0) out vec4 frag_color;
void main() {
    float w[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    vec3 c = texture(u_tex, v_uv).rgb * w[0];
    for (int i = 1; i < 5; ++i) {
        c += texture(u_tex, v_uv + pc.p0.xy * float(i)).rgb * w[i];
        c += texture(u_tex, v_uv - pc.p0.xy * float(i)).rgb * w[i];
    }
    frag_color = vec4(c, 1.0);
}
