#version 450
// void3d sprite vertex shader (Vulkan) — instanced world-space-basis quads.
// Matches R3D_Instance (96-byte stride) and R3D_Frame_Uniforms (std140).

layout(location=0) in vec2 a_corner;   // quad corner, -0.5..0.5
layout(location=1) in vec2 a_uv;
layout(location=2) in vec3 a_origin;
layout(location=3) in vec3 a_right;
layout(location=4) in vec3 a_up;
layout(location=5) in vec3 a_normal;
layout(location=6) in vec4 a_uv_rect;
layout(location=7) in vec4 a_color;
layout(location=8) in vec4 a_params;

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

layout(location=0) out vec2 v_uv;
layout(location=1) out vec3 v_world;
layout(location=2) out vec3 v_normal;
layout(location=3) out vec3 v_tangent;
layout(location=4) out vec4 v_color;
layout(location=5) out vec4 v_params;

void main() {
    vec3 world = a_origin + a_right * a_corner.x + a_up * a_corner.y;
    v_world   = world;
    v_uv      = a_uv_rect.xy + a_uv * a_uv_rect.zw;
    v_normal  = a_normal;
    v_tangent = normalize(a_right);
    v_color   = a_color;
    v_params  = a_params;
    gl_Position = u_view_proj * vec4(world, 1.0);
}
