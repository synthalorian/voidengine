#version 450
layout(location=0) in vec2 v_uv;
layout(set=0, binding=0) uniform sampler2D u_tex;
layout(push_constant) uniform Push { vec4 p0; vec4 p1; } pc; // p1.x = threshold
layout(location=0) out vec4 frag_color;
void main() {
    vec3 c = texture(u_tex, v_uv).rgb;
    float br = max(max(c.r, c.g), c.b);
    float k = max(br - pc.p1.x, 0.0) / max(br, 1e-4);
    frag_color = vec4(c * k, 1.0);
}
