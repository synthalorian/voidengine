#version 450
// Sky (Vulkan): gradient + sun disc + stars from the Frame UBO. Drawn first
// in the scene pass with depth off; geometry renders over it.

layout(location=0) in vec2 v_ndc;
layout(location=0) out vec4 frag_color;

layout(push_constant) uniform Push {
    mat4 inv_vp;
} pc;

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

void main() {
    vec4 far_pt = pc.inv_vp * vec4(v_ndc, 1.0, 1.0);
    vec3 dir = normalize(far_pt.xyz / far_pt.w - u_camera_pos.xyz);
    float elev = dir.y;

    float t = pow(clamp(elev, 0.0, 1.0), 0.55);
    vec3 sky = mix(u_sky_horizon.rgb, u_sky_zenith.rgb, t);
    if (elev < 0.0) {
        sky = mix(u_sky_horizon.rgb, u_fog_color.rgb * 0.4, clamp(-elev * 4.0, 0.0, 1.0));
    }

    // sun disc + halo
    vec3 sun_l = -u_sun_dir.xyz;
    float sd = clamp(dot(dir, sun_l), 0.0, 1.0);
    sky += u_sun_color.rgb * (pow(sd, 900.0) * 2.5 + pow(sd, 20.0) * 0.20 * u_fog_params.y);

    // stars fade in when the sun is down
    float night = 1.0 - clamp(dot(u_sun_color.rgb, vec3(0.333)), 0.0, 1.0);
    if (night > 0.05 && elev > 0.02) {
        vec3 q = floor(dir * 240.0);
        float h = fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
        sky += vec3(step(0.9986, h)) * night * 0.7;
    }

    frag_color = vec4(sky, 1.0);
}
