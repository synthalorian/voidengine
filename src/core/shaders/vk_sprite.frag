#version 450
// void3d sprite fragment shader (Vulkan) — Blinn-Phong + normal maps + HDR.

layout(location=0) in vec2 v_uv;
layout(location=1) in vec3 v_world;
layout(location=2) in vec3 v_normal;
layout(location=3) in vec3 v_tangent;
layout(location=4) in vec4 v_color;
layout(location=5) in vec4 v_params;

layout(set=0, binding=0, std140) uniform Frame {
    mat4 u_view_proj;
    vec4 u_camera_pos;
    vec4 u_ambient;
    vec4 u_light_pos[16];
    vec4 u_light_color[16];
    vec4 u_meta;
};

layout(set=1, binding=0) uniform sampler2D u_diffuse;
layout(set=1, binding=1) uniform sampler2D u_normal_map;

layout(push_constant) uniform Push {
    int use_normal_map;
} pc;

layout(location=0) out vec4 frag_color;

void main() {
    vec4 tex = texture(u_diffuse, v_uv);
    vec4 base = tex * v_color;
    if (base.a < 0.5) discard;  // alpha cutout: depth-write safe

    vec3 N;
    if (pc.use_normal_map == 1) {
        vec3 nm = texture(u_normal_map, v_uv).xyz * 2.0 - 1.0;
        vec3 T  = normalize(v_tangent);
        vec3 Ng = normalize(v_normal);
        vec3 B  = normalize(cross(Ng, T));
        N = normalize(mat3(T, B, Ng) * nm);
    } else {
        N = normalize(v_normal);
    }

    vec3 V = normalize(u_camera_pos.xyz - v_world);
    float spec_strength = v_params.x;
    float shininess     = v_params.y;
    float emissive      = v_params.z;

    vec3 diffuse_acc = u_ambient.rgb;
    vec3 spec_acc    = vec3(0.0);
    int num_lights = int(u_meta.x);
    for (int i = 0; i < num_lights; ++i) {
        vec3  lv     = u_light_pos[i].xyz - v_world;
        float dist   = length(lv);
        vec3  L      = lv / max(dist, 1e-4);
        float radius = max(u_light_pos[i].w, 1e-4);
        float att    = clamp(1.0 - dist / radius, 0.0, 1.0);
        att *= att;
        vec3 lc = u_light_color[i].rgb;
        diffuse_acc += lc * max(dot(N, L), 0.0) * att;
        vec3 H = normalize(L + V);
        spec_acc += lc * pow(max(dot(N, H), 0.0), shininess) * att;
    }

    vec3 lit = base.rgb * diffuse_acc;
    lit += spec_acc * spec_strength;
    lit += base.rgb * emissive;
    frag_color = vec4(lit, base.a);
}
