#version 450
// Sky (Vulkan): fullscreen triangle, inverse view-proj via push constant.

layout(push_constant) uniform Push {
    mat4 inv_vp;
} pc;

layout(location=0) out vec2 v_ndc;

void main() {
    vec2 p = vec2(gl_VertexIndex == 1 ? 3.0 : -1.0, gl_VertexIndex == 2 ? 3.0 : -1.0);
    v_ndc = p;
    gl_Position = vec4(p, 0.0, 1.0);
}
