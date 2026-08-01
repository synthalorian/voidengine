#version 450
// void3d mesh vertex shader (Vulkan) — lit textured meshes.
// Push constants: model matrix + color + params (96 bytes, both stages).

layout(location=0) in vec3 a_pos;
layout(location=1) in vec3 a_normal;
layout(location=2) in vec2 a_uv;

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
    vec4 color;
    vec4 params;   // spec_strength, shininess, emissive, has_texture
    vec4 misc;     // uv_tiling.xy, -, -
} pc;

layout(location=0) out vec2 v_uv;
layout(location=1) out vec3 v_world;
layout(location=2) out vec3 v_normal;
layout(location=3) out vec4 v_color;
layout(location=4) out vec4 v_params;

void main() {
    vec4 world = pc.model * vec4(a_pos, 1.0);
    v_world  = world.xyz;
    v_normal = normalize(mat3(pc.model) * a_normal);
    v_uv     = a_uv * pc.misc.xy;
    v_color  = pc.color;
    v_params = pc.params;
    gl_Position = u_view_proj * world;
}
