#version 450
// void3d mesh fragment shader (Vulkan) — Blinn-Phong + HDR point lights.

layout(location=0) in vec2 v_uv;
layout(location=1) in vec3 v_world;
layout(location=2) in vec3 v_normal;
layout(location=3) in vec4 v_color;
layout(location=4) in vec4 v_params;

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

layout(set=1, binding=0) uniform sampler2D u_diffuse;

layout(push_constant) uniform Push {
    mat4 model;
    vec4 color;
    vec4 params;
    vec4 misc;
} pc;

layout(location=0) out vec4 frag_color;


layout(set=0, binding=1) uniform sampler2D u_shadow_map;

float shadow_factor(vec3 world) {
    if (u_shadow_params.x < 0.5) return 1.0;
    vec4 lp = u_light_view_proj * vec4(world, 1.0);
    vec3 proj = lp.xyz / lp.w;
    vec2 suv = proj.xy * 0.5 + 0.5;
    if (suv.x <= 0.0 || suv.x >= 1.0 || suv.y <= 0.0 || suv.y >= 1.0) return 1.0;
    float current = u_shadow_params.w > 0.5 ? proj.z * 0.5 + 0.5 : proj.z;
    float bias  = u_shadow_params.y;
    float texel = u_shadow_params.z;
    float sum = 0.0;
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            float d = texture(u_shadow_map, suv + vec2(x, y) * texel).r;
            sum += (current - bias > d) ? 0.0 : 1.0;
        }
    }
    return sum / 9.0;
}

void main() {
    vec4 base = v_color;
    if (v_params.w > 0.5) {
        base *= texture(u_diffuse, v_uv);
    }
    if (base.a < 0.5) discard;

    vec3 N = normalize(v_normal);
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

    // sun (directional, shadowed)
    {
        vec3 sunL = normalize(-u_sun_dir.xyz);
        float shadow = shadow_factor(v_world);
        diffuse_acc += u_sun_color.rgb * max(dot(N, sunL), 0.0) * shadow;
        vec3 Hs = normalize(sunL + V);
        spec_acc += u_sun_color.rgb * pow(max(dot(N, Hs), 0.0), shininess) * shadow;
    }
    vec3 lit = base.rgb * diffuse_acc;
    lit += spec_acc * spec_strength;
    lit += base.rgb * emissive;
    // squared-distance fog toward the horizon color
    float fog_dist = length(u_camera_pos.xyz - v_world);
    float fog_f = 1.0 - exp(-u_fog_params.x * u_fog_params.x * fog_dist * fog_dist);
    lit = mix(lit, u_fog_color.rgb, clamp(fog_f, 0.0, 1.0));

    frag_color = vec4(lit, base.a);
}
