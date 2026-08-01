#version 450
// Shadow pass (Vulkan): depth-only mesh rendering from the sun's ortho view.
// Vertex-only pipeline — no fragment stage.

layout(location=0) in vec3 a_pos;

layout(set=0, binding=0, std140) uniform Frame {
    mat4 u_view_proj;
    mat4 u_light_view_proj;
    vec4 u_camera_pos;
    vec4 u_ambient;
    vec4 u_light_pos[16];
    vec4 u_light_color[16];
    vec4 u_meta;
    vec4 u_sun_dir;
    vec4 u_sun_color;
    vec4 u_shadow_params;
};

layout(push_constant) uniform Push {
    mat4 model;
} pc;

void main() {
    gl_Position = u_light_view_proj * pc.model * vec4(a_pos, 1.0);
}
