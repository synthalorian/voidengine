#version 450
// Debug lines (Vulkan): unlit colored world-space lines, drawn in the scene
// pass after all geometry. Same Frame UBO as every other vk3d program.

layout(location=0) in vec3 a_pos;
layout(location=1) in vec4 a_color;

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
    vec4 u_fog_color;
    vec4 u_fog_params;
    vec4 u_sky_zenith;
    vec4 u_sky_horizon;
};

layout(location=0) out vec4 v_color;

void main() {
    v_color = a_color;
    gl_Position = u_view_proj * vec4(a_pos, 1.0);
}
