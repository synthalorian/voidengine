#version 450
// Fullscreen triangle (no vertex buffers). v_uv has v=0 at NDC y=-1 so it
// samples scene attachments rendered with the Y-flipped projection correctly.
layout(location=0) out vec2 v_uv;
void main() {
    v_uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(v_uv * 2.0 - 1.0, 0.0, 1.0);
}
