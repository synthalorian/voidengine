package voidengine

// ============================================================================
// gl3d — OpenGL 3.3 core backend for 3D sprite rendering
//
// Renders instanced, lit, normal-mapped billboard sprites into an HDR
// framebuffer, then runs a post chain (bright pass -> separable gaussian
// blur -> tonemap/bloom/vignette composite) to the default framebuffer.
//
// Usage:
//   config.use_opengl = true  (engine_init creates the GL context)
//   r := gl3d_init(width, height)
//   each frame:
//     gl3d_begin_frame(r)
//     gl3d_set_camera(r, &cam); gl3d_set_ambient(r, amb)
//     gl3d_clear_lights(r); gl3d_add_light(r, light); ...
//     gl3d_draw_sprite(r, diffuse_tex, normal_tex, pos, size, opts)  (xN)
//     gl3d_end_frame(r)   // flushes + post-processes to screen
// ============================================================================

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math/linalg"
import "core:image"
import _ "core:image/png"
import gl "vendor:OpenGL"
import SDL "vendor:sdl2"

// Called by engine_init when use_opengl is set.
gl3d_load_gl_procs :: proc() {
    gl.load_up_to(3, 3, SDL.gl_set_proc_address)
}

GL3D_Renderer :: struct {
    width, height:      i32,
    post_w, post_h:     i32,

    // programs
    sprite_prog:        u32,
    bright_prog:        u32,
    blur_prog:          u32,
    composite_prog:     u32,
    mesh_prog:          u32,

    // geometry
    vao:                u32,
    quad_vbo:           u32,
    quad_ebo:           u32,
    inst_vbo:           u32,
    fs_vao:             u32,
    fs_vbo:             u32,
    ubo:                u32,

    // HDR scene target (full res) + depth
    scene_fbo:          u32,
    scene_tex:          u32,
    scene_depth_rb:     u32,

    // post targets (half res)
    bright_fbo:         u32,
    bright_tex:         u32,
    blur_fbo:           [2]u32,
    blur_tex:           [2]u32,

    // batch state
    instances:          [dynamic]R3D_Instance,
    cur_diffuse:        u32,
    cur_normal:         u32,
    flat_normal_tex:    u32,

    // scene state
    camera:             R3D_Camera,
    ambient:            linalg.Vector3f32,
    lights:             [dynamic]R3D_Light,

    // post settings
    bloom:              bool,
    bloom_strength:     f32,
    bloom_threshold:    f32,
    exposure:           f32,
    vignette:           f32,

    // sun + shadows
    sun:                R3D_Sun,
    shadow_fbo:         u32,
    shadow_tex:         u32,
    shadow_prog:        u32,
    shadow_res:         i32,
}

// ----------------------------------------------------------------------------
// Shaders (GLSL 330 core)
// ----------------------------------------------------------------------------

GL3D_SPRITE_VERT :: `#version 330 core
layout(location=0) in vec2 a_corner;   // quad corner, -0.5..0.5
layout(location=1) in vec2 a_uv;
layout(location=2) in vec3 a_origin;
layout(location=3) in vec3 a_right;
layout(location=4) in vec3 a_up;
layout(location=5) in vec3 a_normal;
layout(location=6) in vec4 a_uv_rect;
layout(location=7) in vec4 a_color;
layout(location=8) in vec4 a_params;

layout(std140) uniform Frame {
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

out vec2 v_uv;
out vec3 v_world;
out vec3 v_normal;
out vec3 v_tangent;
out vec4 v_color;
out vec4 v_params;

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
`

GL3D_SPRITE_FRAG :: `#version 330 core
in vec2 v_uv;
in vec3 v_world;
in vec3 v_normal;
in vec3 v_tangent;
in vec4 v_color;
in vec4 v_params;

uniform sampler2D u_diffuse;
uniform sampler2D u_normal_map;
uniform int u_use_normal_map;
uniform sampler2D u_shadow_map;

layout(std140) uniform Frame {
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

out vec4 frag_color;

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
    vec4 tex = texture(u_diffuse, v_uv);
    vec4 base = tex * v_color;
    if (base.a < 0.5) discard;  // alpha cutout: depth-write safe

    // Normal mapping in the sprite's tangent frame.
    vec3 N;
    if (u_use_normal_map == 1) {
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
    frag_color = vec4(lit, base.a);
}
`

GL3D_SHADOW_VERT :: `#version 330 core
layout(location=0) in vec3 a_pos;
uniform mat4 u_light_vp;
uniform mat4 u_model;
void main() {
    gl_Position = u_light_vp * u_model * vec4(a_pos, 1.0);
}
`

GL3D_SHADOW_FRAG :: `#version 330 core
void main() {}
`

GL3D_POST_VERT :: `#version 330 core
layout(location=0) in vec2 a_pos;
layout(location=1) in vec2 a_uv;
out vec2 v_uv;
void main() {
    v_uv = a_uv;
    gl_Position = vec4(a_pos, 0.0, 1.0);
}
`

GL3D_BRIGHT_FRAG :: `#version 330 core
in vec2 v_uv;
uniform sampler2D u_tex;
uniform float u_threshold;
out vec4 frag_color;
void main() {
    vec3 c = texture(u_tex, v_uv).rgb;
    float br = max(max(c.r, c.g), c.b);
    float k = max(br - u_threshold, 0.0) / max(br, 1e-4);
    frag_color = vec4(c * k, 1.0);
}
`

GL3D_BLUR_FRAG :: `#version 330 core
in vec2 v_uv;
uniform sampler2D u_tex;
uniform vec2 u_dir;  // texel-scaled blur direction
out vec4 frag_color;
void main() {
    float w[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    vec3 c = texture(u_tex, v_uv).rgb * w[0];
    for (int i = 1; i < 5; ++i) {
        c += texture(u_tex, v_uv + u_dir * float(i)).rgb * w[i];
        c += texture(u_tex, v_uv - u_dir * float(i)).rgb * w[i];
    }
    frag_color = vec4(c, 1.0);
}
`

GL3D_COMPOSITE_FRAG :: `#version 330 core
in vec2 v_uv;
uniform sampler2D u_scene;
uniform sampler2D u_bloom;
uniform float u_bloom_enabled;
uniform float u_bloom_strength;
uniform float u_exposure;
uniform float u_vignette;
out vec4 frag_color;
void main() {
    vec3 c = texture(u_scene, v_uv).rgb;
    if (u_bloom_enabled > 0.5) {
        c += texture(u_bloom, v_uv).rgb * u_bloom_strength;
    }
    c = vec3(1.0) - exp(-c * u_exposure);          // filmic-ish tonemap
    vec2 d = v_uv - 0.5;
    c *= 1.0 - u_vignette * dot(d, d);              // vignette
    c = pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));    // gamma
    frag_color = vec4(c, 1.0);
}
`

// ----------------------------------------------------------------------------
// Shader compilation helpers
// ----------------------------------------------------------------------------

@(private)
gl3d_compile :: proc(src: string, kind: u32) -> (u32, bool) {
    shader := gl.CreateShader(kind)
    csrc := strings.clone_to_cstring(src)
    arr := [1]cstring{csrc}
    gl.ShaderSource(shader, 1, &arr[0], nil)
    gl.CompileShader(shader)
    status: i32
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &status)
    if status == 0 {
        buf: [1024]u8
        n: i32
        gl.GetShaderInfoLog(shader, 1024, &n, &buf[0])
        fmt.eprintln("gl3d shader compile error:", string(buf[:n]))
        return 0, false
    }
    return shader, true
}

@(private)
gl3d_link :: proc(vs, fs: u32) -> (u32, bool) {
    prog := gl.CreateProgram()
    gl.AttachShader(prog, vs)
    gl.AttachShader(prog, fs)
    gl.LinkProgram(prog)
    status: i32
    gl.GetProgramiv(prog, gl.LINK_STATUS, &status)
    if status == 0 {
        buf: [1024]u8
        n: i32
        gl.GetProgramInfoLog(prog, 1024, &n, &buf[0])
        fmt.eprintln("gl3d program link error:", string(buf[:n]))
        return 0, false
    }
    gl.DeleteShader(vs)
    gl.DeleteShader(fs)
    return prog, true
}

@(private)
gl3d_build_program :: proc(vert_src, frag_src: string) -> (u32, bool) {
    vs, ok_vs := gl3d_compile(vert_src, gl.VERTEX_SHADER)
    if !ok_vs { return 0, false }
    fs, ok_fs := gl3d_compile(frag_src, gl.FRAGMENT_SHADER)
    if !ok_fs { return 0, false }
    return gl3d_link(vs, fs)
}

// ----------------------------------------------------------------------------
// Init / shutdown
// ----------------------------------------------------------------------------

gl3d_init :: proc(width, height: i32) -> ^GL3D_Renderer {
    r := new(GL3D_Renderer)
    r.width  = width
    r.height = height
    r.instances = make([dynamic]R3D_Instance)
    r.lights    = make([dynamic]R3D_Light)

    // sensible synthwave defaults
    r.ambient         = {0.10, 0.07, 0.16}
    r.bloom           = true
    r.bloom_strength  = 0.7
    r.bloom_threshold = 1.0
    r.exposure        = 1.1
    r.vignette        = 0.35

    ok: bool
    r.sprite_prog, ok = gl3d_build_program(GL3D_SPRITE_VERT, GL3D_SPRITE_FRAG)
    if !ok { fmt.eprintln("gl3d: sprite program failed"); return nil }
    r.bright_prog, ok = gl3d_build_program(GL3D_POST_VERT, GL3D_BRIGHT_FRAG)
    if !ok { return nil }
    r.blur_prog, ok = gl3d_build_program(GL3D_POST_VERT, GL3D_BLUR_FRAG)
    if !ok { return nil }
    r.composite_prog, ok = gl3d_build_program(GL3D_POST_VERT, GL3D_COMPOSITE_FRAG)
    if !ok { return nil }
    if !gl3d_init_mesh_pipeline(r) { return nil }
    r.shadow_prog, ok = gl3d_build_program(GL3D_SHADOW_VERT, GL3D_SHADOW_FRAG)
    if !ok { return nil }

    // UBO: frame uniforms at binding point 0 in both sprite programs
    gl.GenBuffers(1, &r.ubo)
    gl.BindBuffer(gl.UNIFORM_BUFFER, r.ubo)
    gl.BufferData(gl.UNIFORM_BUFFER, size_of(R3D_Frame_Uniforms), nil, gl.DYNAMIC_DRAW)
    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, r.ubo)
    block_idx := gl.GetUniformBlockIndex(r.sprite_prog, "Frame")
    if block_idx != gl.INVALID_INDEX {
        gl.UniformBlockBinding(r.sprite_prog, block_idx, 0)
    }


    // --- sprite quad geometry (corner + uv interleaved, 4 verts) ---
    // uv y=0 maps to the first uploaded row (top of a PNG), so v is flipped
    // here to keep sprites right-side up. Normal maps generated by our tools
    // share the same convention.
    quad_verts := [?]f32{
        // corner x, corner y, u, v
        -0.5, -0.5, 0, 1,
         0.5, -0.5, 1, 1,
         0.5,  0.5, 1, 0,
        -0.5,  0.5, 0, 0,
    }
    quad_idx := [?]u16{0, 1, 2, 2, 3, 0}

    gl.GenVertexArrays(1, &r.vao)
    gl.BindVertexArray(r.vao)

    gl.GenBuffers(1, &r.quad_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, r.quad_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(quad_verts), &quad_verts[0], gl.STATIC_DRAW)

    gl.GenBuffers(1, &r.quad_ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, r.quad_ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(quad_idx), &quad_idx[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, false, 16, 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, false, 16, 8)

    // --- instance buffer (streaming) ---
    gl.GenBuffers(1, &r.inst_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, r.inst_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, 65536 * R3D_INSTANCE_STRIDE, nil, gl.STREAM_DRAW)

    stride := i32(R3D_INSTANCE_STRIDE)
    inst_attrs := [?]struct{loc: u32, size: i32, offset: uintptr}{
        {2, 3, offset_of(R3D_Instance, origin)},
        {3, 3, offset_of(R3D_Instance, right)},
        {4, 3, offset_of(R3D_Instance, up)},
        {5, 3, offset_of(R3D_Instance, normal)},
        {6, 4, offset_of(R3D_Instance, uv_rect)},
        {7, 4, offset_of(R3D_Instance, color)},
        {8, 4, offset_of(R3D_Instance, params)},
    }
    for a in inst_attrs {
        gl.EnableVertexAttribArray(a.loc)
        gl.VertexAttribPointer(a.loc, a.size, gl.FLOAT, false, stride, a.offset)
        gl.VertexAttribDivisor(a.loc, 1)
    }
    gl.BindVertexArray(0)

    // --- fullscreen triangle list (post passes), NDC positions + uv ---
    fs_verts := [?]f32{
        // x, y, u, v
        -1, -1, 0, 0,
         1, -1, 1, 0,
         1,  1, 1, 1,
        -1, -1, 0, 0,
         1,  1, 1, 1,
        -1,  1, 0, 1,
    }
    gl.GenVertexArrays(1, &r.fs_vao)
    gl.BindVertexArray(r.fs_vao)
    gl.GenBuffers(1, &r.fs_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, r.fs_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(fs_verts), &fs_verts[0], gl.STATIC_DRAW)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, false, 16, 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, false, 16, 8)
    gl.BindVertexArray(0)

    // sampler uniforms are fixed: unit 0 diffuse/scene, unit 1 normal/bloom
    gl.UseProgram(r.sprite_prog)
    gl.Uniform1i(gl.GetUniformLocation(r.sprite_prog, "u_diffuse"), 0)
    gl.Uniform1i(gl.GetUniformLocation(r.sprite_prog, "u_normal_map"), 1)
    gl.UseProgram(r.bright_prog)
    gl.Uniform1i(gl.GetUniformLocation(r.bright_prog, "u_tex"), 0)
    gl.UseProgram(r.blur_prog)
    gl.Uniform1i(gl.GetUniformLocation(r.blur_prog, "u_tex"), 0)
    gl.UseProgram(r.composite_prog)
    gl.Uniform1i(gl.GetUniformLocation(r.composite_prog, "u_scene"), 0)
    gl.Uniform1i(gl.GetUniformLocation(r.composite_prog, "u_bloom"), 1)

    // flat normal map fallback (tangent-space up)
    flat := [?]u8{128, 128, 255, 255}
    gl.GenTextures(1, &r.flat_normal_tex)
    gl.BindTexture(gl.TEXTURE_2D, r.flat_normal_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, &flat[0])
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

    // shadow map depth target
    r.shadow_res = 2048
    gl.GenTextures(1, &r.shadow_tex)
    gl.BindTexture(gl.TEXTURE_2D, r.shadow_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT24, r.shadow_res, r.shadow_res, 0, gl.DEPTH_COMPONENT, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.GenFramebuffers(1, &r.shadow_fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, r.shadow_fbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, r.shadow_tex, 0)
    gl.DrawBuffer(gl.NONE)
    gl.ReadBuffer(gl.NONE)
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

    // shadow map sampler binding is fixed at unit 2 in both lit programs
    gl.UseProgram(r.sprite_prog)
    gl.Uniform1i(gl.GetUniformLocation(r.sprite_prog, "u_shadow_map"), 2)
    gl.UseProgram(r.mesh_prog)
    gl.Uniform1i(gl.GetUniformLocation(r.mesh_prog, "u_shadow_map"), 2)

    gl3d_create_targets(r, width, height)
    return r
}

@(private)
gl3d_make_hdr_target :: proc(w, h: i32) -> (fbo, tex: u32) {
    gl.GenTextures(1, &tex)
    gl.BindTexture(gl.TEXTURE_2D, tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, w, h, 0, gl.RGBA, gl.FLOAT, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.GenFramebuffers(1, &fbo)
    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0)
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    return
}

@(private)
gl3d_create_targets :: proc(r: ^GL3D_Renderer, w, h: i32) {
    r.width, r.height = w, h
    r.post_w  = max(w / 2, 1)
    r.post_h  = max(h / 2, 1)

    // scene target + depth renderbuffer
    if r.scene_fbo != 0 {
        gl.DeleteFramebuffers(1, &r.scene_fbo)
        gl.DeleteTextures(1, &r.scene_tex)
        gl.DeleteRenderbuffers(1, &r.scene_depth_rb)
    }
    r.scene_fbo, r.scene_tex = gl3d_make_hdr_target(w, h)
    gl.BindFramebuffer(gl.FRAMEBUFFER, r.scene_fbo)
    gl.GenRenderbuffers(1, &r.scene_depth_rb)
    gl.BindRenderbuffer(gl.RENDERBUFFER, r.scene_depth_rb)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, w, h)
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, r.scene_depth_rb)
    if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
        fmt.eprintln("gl3d: scene framebuffer incomplete")
    }
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

    if r.bright_fbo != 0 {
        gl.DeleteFramebuffers(1, &r.bright_fbo)
        gl.DeleteTextures(1, &r.bright_tex)
        for i in 0 ..< 2 {
            gl.DeleteFramebuffers(1, &r.blur_fbo[i])
            gl.DeleteTextures(1, &r.blur_tex[i])
        }
    }
    r.bright_fbo, r.bright_tex = gl3d_make_hdr_target(r.post_w, r.post_h)
    for i in 0 ..< 2 {
        r.blur_fbo[i], r.blur_tex[i] = gl3d_make_hdr_target(r.post_w, r.post_h)
    }
}

gl3d_resize :: proc(r: ^GL3D_Renderer, w, h: i32) {
    if w <= 0 || h <= 0 { return }
    gl3d_create_targets(r, w, h)
}

gl3d_shutdown :: proc(r: ^GL3D_Renderer) {
    if r == nil { return }
    gl.DeleteFramebuffers(1, &r.scene_fbo)
    gl.DeleteTextures(1, &r.scene_tex)
    gl.DeleteRenderbuffers(1, &r.scene_depth_rb)
    gl.DeleteFramebuffers(1, &r.bright_fbo)
    gl.DeleteTextures(1, &r.bright_tex)
    for i in 0 ..< 2 {
        gl.DeleteFramebuffers(1, &r.blur_fbo[i])
        gl.DeleteTextures(1, &r.blur_tex[i])
    }
    gl.DeleteBuffers(1, &r.quad_vbo)
    gl.DeleteBuffers(1, &r.quad_ebo)
    gl.DeleteBuffers(1, &r.inst_vbo)
    gl.DeleteBuffers(1, &r.fs_vbo)
    gl.DeleteBuffers(1, &r.ubo)
    gl.DeleteVertexArrays(1, &r.vao)
    gl.DeleteVertexArrays(1, &r.fs_vao)
    gl.DeleteTextures(1, &r.flat_normal_tex)
    gl.DeleteProgram(r.sprite_prog)
    gl.DeleteProgram(r.bright_prog)
    gl.DeleteProgram(r.blur_prog)
    gl.DeleteProgram(r.composite_prog)
    gl.DeleteProgram(r.mesh_prog)
    gl.DeleteProgram(r.shadow_prog)
    gl.DeleteFramebuffers(1, &r.shadow_fbo)
    gl.DeleteTextures(1, &r.shadow_tex)
    delete(r.instances)
    delete(r.lights)
    free(r)
}

// ----------------------------------------------------------------------------
// Textures
// ----------------------------------------------------------------------------

// Upload raw RGBA8 pixels as a texture. repeat enables tiling (for uv_rect
// values > 1); mipmaps are generated for minification quality.
gl3d_upload_texture :: proc(pixels: []u8, w, h: i32, repeat := false) -> u32 {
    tex: u32
    gl.GenTextures(1, &tex)
    gl.BindTexture(gl.TEXTURE_2D, tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    wrap: i32 = repeat ? gl.REPEAT : gl.CLAMP_TO_EDGE
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap)
    gl.TexParameterf(gl.TEXTURE_2D, gl.TEXTURE_MAX_ANISOTROPY, 8)
    gl.GenerateMipmap(gl.TEXTURE_2D)
    return tex
}

// Load a PNG (or other image format) from disk as an RGBA8 texture.
gl3d_load_texture :: proc(path: string, repeat := false) -> (tex: u32, w, h: i32, ok: bool) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        fmt.eprintln("gl3d: cannot read texture file:", path)
        return 0, 0, 0, false
    }
    defer delete(data)

    img, err := image.load_from_bytes(data)
    if err != nil || img == nil {
        fmt.eprintln("gl3d: cannot decode texture:", path)
        return 0, 0, 0, false
    }
    w = i32(img.width)
    h = i32(img.height)
    src := img.pixels.buf[:]

    rgba: []u8
    if img.channels == 4 {
        rgba = src
    } else if img.channels == 3 {
        rgba = make([]u8, w * h * 4)
        for i in 0 ..< int(w * h) {
            rgba[i * 4 + 0] = src[i * 3 + 0]
            rgba[i * 4 + 1] = src[i * 3 + 1]
            rgba[i * 4 + 2] = src[i * 3 + 2]
            rgba[i * 4 + 3] = 255
        }
        defer delete(rgba)
    } else {
        fmt.eprintln("gl3d: unsupported channel count in:", path)
        return 0, 0, 0, false
    }

    tex = gl3d_upload_texture(rgba, w, h, repeat)
    return tex, w, h, true
}

gl3d_destroy_texture :: proc(tex: u32) {
    t := tex
    gl.DeleteTextures(1, &t)
}

// ----------------------------------------------------------------------------
// Frame API
// ----------------------------------------------------------------------------

gl3d_set_camera :: proc(r: ^GL3D_Renderer, cam: ^R3D_Camera) {
    r.camera = cam^
}

gl3d_set_ambient :: proc(r: ^GL3D_Renderer, ambient: linalg.Vector3f32) {
    r.ambient = ambient
}

gl3d_clear_lights :: proc(r: ^GL3D_Renderer) {
    clear(&r.lights)
}

gl3d_add_light :: proc(r: ^GL3D_Renderer, light: R3D_Light) {
    if len(r.lights) < R3D_MAX_LIGHTS {
        append(&r.lights, light)
    }
}

gl3d_begin_frame :: proc(r: ^GL3D_Renderer) {
    gl.BindFramebuffer(gl.FRAMEBUFFER, r.scene_fbo)
    gl.Viewport(0, 0, r.width, r.height)
    gl.Enable(gl.DEPTH_TEST)
    gl.DepthFunc(gl.LESS)
    gl.DepthMask(true)
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    gl.Disable(gl.CULL_FACE)
    gl.ClearColor(0.02, 0.01, 0.05, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
    clear(&r.instances)
    r.cur_diffuse = 0
    r.cur_normal  = 0
}

// Queue a sprite for rendering. diffuse is required; normal may be 0 (flat).
gl3d_draw_sprite_opts :: proc(
    r:       ^GL3D_Renderer,
    diffuse: u32,
    normal:  u32,
    pos:     linalg.Vector3f32,
    size:    linalg.Vector2f32,
    opts:    R3D_Sprite_Options,
) {
    if diffuse != r.cur_diffuse || normal != r.cur_normal {
        gl3d_flush(r)
        r.cur_diffuse = diffuse
        r.cur_normal  = normal
    }
    append(&r.instances, r3d_make_instance(&r.camera, pos, size, opts))
}

// Queue a sprite with default options.
gl3d_draw_sprite :: proc(r: ^GL3D_Renderer, diffuse: u32, normal: u32, pos: linalg.Vector3f32, size: linalg.Vector2f32) {
    gl3d_draw_sprite_opts(r, diffuse, normal, pos, size, r3d_default_sprite_options())
}

// Draw everything queued so far (called automatically on texture switch and
// at end_frame; call manually to force a batch boundary).
gl3d_flush :: proc(r: ^GL3D_Renderer) {
    if len(r.instances) == 0 || r.cur_diffuse == 0 { return }

    gl.UseProgram(r.sprite_prog)

    // frame uniforms
    aspect := f32(r.width) / f32(max(r.height, 1))
    uniforms := r3d_make_frame_uniforms(&r.camera, aspect, false, r.ambient, r.lights[:], &r.sun)
    gl.BindBuffer(gl.UNIFORM_BUFFER, r.ubo)
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(R3D_Frame_Uniforms), &uniforms)

    normal_tex := r.cur_normal != 0 ? r.cur_normal : r.flat_normal_tex
    gl.Uniform1i(gl.GetUniformLocation(r.sprite_prog, "u_use_normal_map"), r.cur_normal != 0 ? 1 : 0)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, r.cur_diffuse)
    gl.ActiveTexture(gl.TEXTURE1)
    gl.BindTexture(gl.TEXTURE_2D, normal_tex)
    gl.ActiveTexture(gl.TEXTURE2)
    gl.BindTexture(gl.TEXTURE_2D, r.shadow_tex)
    gl.ActiveTexture(gl.TEXTURE0)

    // stream instances (orphan + upload)
    gl.BindBuffer(gl.ARRAY_BUFFER, r.inst_vbo)
    n := len(r.instances)
    gl.BufferData(gl.ARRAY_BUFFER, n * R3D_INSTANCE_STRIDE, nil, gl.STREAM_DRAW)
    gl.BufferSubData(gl.ARRAY_BUFFER, 0, n * R3D_INSTANCE_STRIDE, raw_data(r.instances))

    gl.BindVertexArray(r.vao)
    gl.DrawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, nil, i32(n))
    gl.BindVertexArray(0)

    clear(&r.instances)
}

@(private)
gl3d_draw_fullscreen :: proc(r: ^GL3D_Renderer) {
    gl.BindVertexArray(r.fs_vao)
    gl.DrawArrays(gl.TRIANGLES, 0, 6)
    gl.BindVertexArray(0)
}

gl3d_end_frame :: proc(r: ^GL3D_Renderer) {
    gl3d_flush(r)

    gl.Disable(gl.DEPTH_TEST)
    gl.Disable(gl.BLEND)

    // bright pass (scene -> bright, half res)
    gl.BindFramebuffer(gl.FRAMEBUFFER, r.bright_fbo)
    gl.Viewport(0, 0, r.post_w, r.post_h)
    gl.UseProgram(r.bright_prog)
    gl.Uniform1f(gl.GetUniformLocation(r.bright_prog, "u_threshold"), r.bloom_threshold)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, r.scene_tex)
    gl3d_draw_fullscreen(r)

    // separable blur ping-pong (2 iterations)
    src := r.bright_tex
    for i in 0 ..< 4 {
        dst := i % 2
        gl.BindFramebuffer(gl.FRAMEBUFFER, r.blur_fbo[dst])
        gl.UseProgram(r.blur_prog)
        texel_x := 1.0 / f32(r.post_w)
        texel_y := 1.0 / f32(r.post_h)
        if i % 2 == 0 {
            gl.Uniform2f(gl.GetUniformLocation(r.blur_prog, "u_dir"), texel_x * 1.5, 0)
        } else {
            gl.Uniform2f(gl.GetUniformLocation(r.blur_prog, "u_dir"), 0, texel_y * 1.5)
        }
        gl.BindTexture(gl.TEXTURE_2D, src)
        gl3d_draw_fullscreen(r)
        src = r.blur_tex[dst]
    }

    // composite to screen
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    gl.Viewport(0, 0, r.width, r.height)
    gl.UseProgram(r.composite_prog)
    gl.Uniform1f(gl.GetUniformLocation(r.composite_prog, "u_bloom_enabled"), r.bloom ? 1.0 : 0.0)
    gl.Uniform1f(gl.GetUniformLocation(r.composite_prog, "u_bloom_strength"), r.bloom_strength)
    gl.Uniform1f(gl.GetUniformLocation(r.composite_prog, "u_exposure"), r.exposure)
    gl.Uniform1f(gl.GetUniformLocation(r.composite_prog, "u_vignette"), r.vignette)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, r.scene_tex)
    gl.ActiveTexture(gl.TEXTURE1)
    gl.BindTexture(gl.TEXTURE_2D, src)
    gl3d_draw_fullscreen(r)
    gl.ActiveTexture(gl.TEXTURE0)
}

// Read the back buffer (call between end_frame and the window swap).
// Pixels come out bottom-row first (GL convention); flip if needed.
gl3d_read_screen :: proc(r: ^GL3D_Renderer, pixels: []u8) {
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    gl.ReadPixels(0, 0, r.width, r.height, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
}

// ----------------------------------------------------------------------------
// Meshes
// ----------------------------------------------------------------------------

GL3D_MESH_VERT :: `#version 330 core
layout(location=0) in vec3 a_pos;
layout(location=1) in vec3 a_normal;
layout(location=2) in vec2 a_uv;

layout(std140) uniform Frame {
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

uniform mat4 u_model;
uniform vec4 u_color;
uniform vec4 u_params;    // spec_strength, shininess, emissive, -
uniform vec2 u_uv_tiling;

out vec2 v_uv;
out vec3 v_world;
out vec3 v_normal;
out vec4 v_color;
out vec4 v_params;

void main() {
    vec4 world = u_model * vec4(a_pos, 1.0);
    v_world  = world.xyz;
    v_normal = normalize(mat3(u_model) * a_normal);  // ok for rotation/uniform scale
    v_uv     = a_uv * u_uv_tiling;
    v_color  = u_color;
    v_params = u_params;
    gl_Position = u_view_proj * world;
}
`

GL3D_MESH_FRAG :: `#version 330 core
in vec2 v_uv;
in vec3 v_world;
in vec3 v_normal;
in vec4 v_color;
in vec4 v_params;

uniform sampler2D u_diffuse;
uniform int u_has_texture;
uniform sampler2D u_shadow_map;

layout(std140) uniform Frame {
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

out vec4 frag_color;

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
    if (u_has_texture == 1) {
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
    frag_color = vec4(lit, base.a);
}
`

GL3D_Mesh :: struct {
    vao:         u32,
    vbo:         u32,
    ebo:         u32,
    index_count: i32,
}

// Upload mesh data to the GPU. Indices are u32.
gl3d_upload_mesh :: proc(data: ^R3D_Mesh_Data) -> GL3D_Mesh {
    mesh: GL3D_Mesh
    mesh.index_count = i32(len(data.indices))

    gl.GenVertexArrays(1, &mesh.vao)
    gl.BindVertexArray(mesh.vao)

    gl.GenBuffers(1, &mesh.vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(data.vertices) * R3D_VERTEX_STRIDE, raw_data(data.vertices), gl.STATIC_DRAW)

    gl.GenBuffers(1, &mesh.ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(data.indices) * size_of(u32), raw_data(data.indices), gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, R3D_VERTEX_STRIDE, offset_of(R3D_Vertex, pos))
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, false, R3D_VERTEX_STRIDE, offset_of(R3D_Vertex, normal))
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 2, gl.FLOAT, false, R3D_VERTEX_STRIDE, offset_of(R3D_Vertex, uv))
    gl.BindVertexArray(0)
    return mesh
}

gl3d_destroy_mesh :: proc(mesh: ^GL3D_Mesh) {
    gl.DeleteBuffers(1, &mesh.vbo)
    gl.DeleteBuffers(1, &mesh.ebo)
    gl.DeleteVertexArrays(1, &mesh.vao)
    mesh^ = {}
}

// Draw a mesh immediately (depth-tested against sprites; texture may be 0
// for flat color). model is the full model matrix.
gl3d_draw_mesh_opts :: proc(r: ^GL3D_Renderer, mesh: ^GL3D_Mesh, texture: u32, model: linalg.Matrix4f32, opts: R3D_Mesh_Options) {
    if mesh.index_count == 0 { return }
    gl3d_flush(r)  // keep sprite batches in submission order

    gl.UseProgram(r.mesh_prog)

    aspect := f32(r.width) / f32(max(r.height, 1))
    uniforms := r3d_make_frame_uniforms(&r.camera, aspect, false, r.ambient, r.lights[:], &r.sun)
    gl.BindBuffer(gl.UNIFORM_BUFFER, r.ubo)
    gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(R3D_Frame_Uniforms), &uniforms)

    m := model
    gl.UniformMatrix4fv(gl.GetUniformLocation(r.mesh_prog, "u_model"), 1, false, &m[0][0])
    color := opts.color
    gl.Uniform4f(gl.GetUniformLocation(r.mesh_prog, "u_color"), color.x, color.y, color.z, color.w)
    gl.Uniform4f(gl.GetUniformLocation(r.mesh_prog, "u_params"), opts.spec_strength, opts.shininess, opts.emissive, 0)
    gl.Uniform2f(gl.GetUniformLocation(r.mesh_prog, "u_uv_tiling"), opts.uv_tiling.x, opts.uv_tiling.y)
    gl.Uniform1i(gl.GetUniformLocation(r.mesh_prog, "u_has_texture"), texture != 0 ? 1 : 0)
    gl.Uniform1i(gl.GetUniformLocation(r.mesh_prog, "u_diffuse"), 0)

    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.ActiveTexture(gl.TEXTURE2)
    gl.BindTexture(gl.TEXTURE_2D, r.shadow_tex)
    gl.ActiveTexture(gl.TEXTURE0)

    gl.BindVertexArray(mesh.vao)
    gl.DrawElements(gl.TRIANGLES, mesh.index_count, gl.UNSIGNED_INT, nil)
    gl.BindVertexArray(0)
}

// Draw a mesh with default options.
gl3d_draw_mesh :: proc(r: ^GL3D_Renderer, mesh: ^GL3D_Mesh, texture: u32, model: linalg.Matrix4f32) {
    gl3d_draw_mesh_opts(r, mesh, texture, model, r3d_default_mesh_options())
}

// ----------------------------------------------------------------------------
// Shadow pass (sun): depth-only rendering of shadow casters from the sun's
// orthographic view. Call BEFORE gl3d_begin_frame; draw casters with
// gl3d_draw_mesh_shadow; then begin the normal frame.
// ----------------------------------------------------------------------------

gl3d_set_sun :: proc(r: ^GL3D_Renderer, sun: R3D_Sun) {
    r.sun = sun
    if r.sun.shadow_bias == 0 { r.sun.shadow_bias = 0.0025 }
    if r.sun.shadow_radius == 0 { r.sun.shadow_radius = 12 }
}

gl3d_shadow_pass_begin :: proc(r: ^GL3D_Renderer, center: linalg.Vector3f32) {
    if !r.sun.enabled || !r.sun.cast_shadows { return }
    r3d_sun_view_proj(&r.sun, center, false)
    r.sun.shadow_texel = 1.0 / f32(r.shadow_res)

    gl.BindFramebuffer(gl.FRAMEBUFFER, r.shadow_fbo)
    gl.Viewport(0, 0, r.shadow_res, r.shadow_res)
    gl.Enable(gl.DEPTH_TEST)
    gl.Disable(gl.BLEND)
    gl.Clear(gl.DEPTH_BUFFER_BIT)
    gl.Enable(gl.POLYGON_OFFSET_FILL)
    gl.PolygonOffset(2.0, 4.0)
    gl.UseProgram(r.shadow_prog)
    lvp := r.sun.light_view_proj
    gl.UniformMatrix4fv(gl.GetUniformLocation(r.shadow_prog, "u_light_vp"), 1, false, &lvp[0][0])
}

gl3d_draw_mesh_shadow :: proc(r: ^GL3D_Renderer, mesh: ^GL3D_Mesh, model: linalg.Matrix4f32) {
    if !r.sun.enabled || !r.sun.cast_shadows || mesh.index_count == 0 { return }
    m := model
    gl.UniformMatrix4fv(gl.GetUniformLocation(r.shadow_prog, "u_model"), 1, false, &m[0][0])
    gl.BindVertexArray(mesh.vao)
    gl.DrawElements(gl.TRIANGLES, mesh.index_count, gl.UNSIGNED_INT, nil)
    gl.BindVertexArray(0)
}

gl3d_shadow_pass_end :: proc(r: ^GL3D_Renderer) {
    gl.Disable(gl.POLYGON_OFFSET_FILL)
    // gl3d_begin_frame rebinds the scene target, viewport, and state
}

// Init the mesh program (called from gl3d_init).
@(private)
gl3d_init_mesh_pipeline :: proc(r: ^GL3D_Renderer) -> bool {
    prog, ok := gl3d_build_program(GL3D_MESH_VERT, GL3D_MESH_FRAG)
    if !ok {
        fmt.eprintln("gl3d: mesh program failed")
        return false
    }
    r.mesh_prog = prog
    block_idx := gl.GetUniformBlockIndex(r.mesh_prog, "Frame")
    if block_idx != gl.INVALID_INDEX {
        gl.UniformBlockBinding(r.mesh_prog, block_idx, 0)
    }
    return true
}
