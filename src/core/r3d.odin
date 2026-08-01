package voidengine

// ============================================================================
// r3d — shared 3D sprite rendering core (backend-agnostic)
//
// Used by both the OpenGL (gl3d) and Vulkan (vk3d) backends. Contains the
// camera model, light model, billboard math, and the GPU instance layout that
// both backends upload to the vertex stage.
//
// Design: sprites are 3D quads. The CPU resolves each sprite into a world
// space basis (right/up vectors, scaled and rotated) so the vertex shader is
// trivial and identical across backends.
// ============================================================================

import "core:math"
import "core:math/linalg"

R3D_MAX_LIGHTS :: 16

// How a sprite quad orients itself in 3D space.
R3D_Billboard :: enum i32 {
    Spherical,   // fully camera-facing (classic billboard)
    Cylindrical, // camera-facing around the world Y axis only (trees, characters)
    FlatXZ,      // horizontal quad in world space (floors, ground decals), normal +Y
    FlatXY,      // vertical quad in world space (walls, backdrop), normal +Z
}

R3D_Camera :: struct {
    position: linalg.Vector3f32,
    yaw:      f32, // radians; 0 looks down -Z, positive turns toward +X
    pitch:    f32, // radians; positive looks up
    fov_y:    f32, // radians
    near_z:   f32,
    far_z:    f32,
}

// Point light. color is linear HDR intensity (values > 1 feed bloom).
R3D_Light :: struct {
    position: linalg.Vector3f32,
    color:    linalg.Vector3f32,
    radius:   f32, // attenuation range; intensity falls to 0 at this distance
}

R3D_Sprite_Options :: struct {
    color:         linalg.Vector4f32, // RGBA tint (linear-ish; multiplies texture)
    rotation:      f32,               // in-plane rotation, radians
    uv_rect:       linalg.Vector4f32, // u, v, u_size, v_size (atlas subrect or tiling)
    spec_strength: f32,               // Blinn-Phong specular multiplier
    shininess:     f32,               // specular exponent
    emissive:      f32,               // self-illumination multiplier (feeds bloom)
    billboard:     R3D_Billboard,
}

r3d_default_sprite_options :: proc "contextless" () -> R3D_Sprite_Options {
    return R3D_Sprite_Options{
        color         = {1, 1, 1, 1},
        rotation      = 0,
        uv_rect       = {0, 0, 1, 1},
        spec_strength = 0.5,
        shininess     = 32,
        emissive      = 0,
        billboard     = .Spherical,
    }
}

// GPU instance layout — uploaded verbatim as per-instance vertex attributes.
// Stride is 96 bytes; attribute offsets are shared by both backends.
R3D_Instance :: struct {
    origin:  linalg.Vector3f32, // world center
    right:   linalg.Vector3f32, // world right basis, scaled by width
    up:      linalg.Vector3f32, // world up basis, scaled by height
    normal:  linalg.Vector3f32, // geometric normal (pre normal-map)
    uv_rect: linalg.Vector4f32,
    color:   linalg.Vector4f32,
    params:  linalg.Vector4f32, // x: spec_strength, y: shininess, z: emissive, w: unused
}

R3D_INSTANCE_STRIDE :: size_of(R3D_Instance) // 96

// CPU-side debug line vertex — accumulated per frame by both backends and
// drawn depth-tested after all scene geometry, then cleared.
R3D_Debug_Vertex :: struct {
    pos:   linalg.Vector3f32,
    color: linalg.Vector4f32,
}

R3D_DEBUG_VERTEX_STRIDE :: size_of(R3D_Debug_Vertex) // 28

// Frame uniforms — std140-compatible, bound as a UBO on both backends.
R3D_Frame_Uniforms :: struct {
    // NOTE: both Matrix4f32 members FIRST — Odin aligns matrices to 32 bytes,
    // std140 aligns mat4 to 16. Keeping matrices at offsets 0 and 64 makes the
    // Odin struct layout identical to the GLSL std140 block (736 bytes).
    view_proj:       linalg.Matrix4f32,
    light_view_proj: linalg.Matrix4f32,
    camera_pos:      linalg.Vector4f32, // xyz = position
    ambient:         linalg.Vector4f32, // rgb = ambient light
    light_pos:       [R3D_MAX_LIGHTS]linalg.Vector4f32,   // xyz = pos, w = radius
    light_color:     [R3D_MAX_LIGHTS]linalg.Vector4f32,   // rgb = HDR intensity
    meta:            linalg.Vector4f32, // x = num_lights
    sun_dir:         linalg.Vector4f32, // xyz = direction light travels
    sun_color:       linalg.Vector4f32, // rgb = HDR intensity
    shadow_params:   linalg.Vector4f32, // x = shadows on, y = bias, z = texel, w = 1 if NDC z needs remap (GL)
}

// Directional light (the "sun") with optional shadow casting.
R3D_Sun :: struct {
    direction:      linalg.Vector3f32, // direction light travels (from sun toward scene)
    color:          linalg.Vector3f32, // linear HDR intensity
    enabled:        bool,
    cast_shadows:   bool,
    shadow_radius:  f32,  // ortho half-extent of the shadow frustum
    shadow_bias:    f32,  // depth bias when sampling
    // computed each frame via r3d_sun_view_proj:
    light_view_proj: linalg.Matrix4f32,
    shadow_texel:    f32, // 1 / shadow map resolution
}

// Right-handed orthographic projection, OpenGL clip conventions (z in [-1,1]).
r3d_ortho_gl :: proc "contextless" (left, right, bottom, top, near_z, far_z: f32) -> (m: linalg.Matrix4f32) {
    m[0, 0] = 2 / (right - left)
    m[1, 1] = 2 / (top - bottom)
    m[2, 2] = -2 / (far_z - near_z)
    m[3, 0] = -(right + left) / (right - left)
    m[3, 1] = -(top + bottom) / (top - bottom)
    m[3, 2] = -(far_z + near_z) / (far_z - near_z)
    m[3, 3] = 1
    return
}

// Right-handed orthographic projection, Vulkan clip conventions (z in [0,1], Y flipped).
r3d_ortho_vk :: proc "contextless" (left, right, bottom, top, near_z, far_z: f32) -> (m: linalg.Matrix4f32) {
    m[0, 0] = 2 / (right - left)
    m[1, 1] = -2 / (top - bottom)
    m[2, 2] = -1 / (far_z - near_z)
    m[3, 0] = -(right + left) / (right - left)
    m[3, 1] = -(top + bottom) / (top - bottom)
    m[3, 2] = near_z / (far_z - near_z)
    m[3, 3] = 1
    return
}

// Build the sun's shadow view-projection: an ortho box of `shadow_radius`
// around `center`, looking along the sun direction. Result is also stored
// in sun.light_view_proj.
r3d_sun_view_proj :: proc "contextless" (sun: ^R3D_Sun, center: linalg.Vector3f32, vulkan: bool) -> linalg.Matrix4f32 {
    radius := max(sun.shadow_radius, 1.0)
    dir := linalg.normalize(sun.direction)
    eye := center - dir * (radius * 2)
    view := linalg.matrix4_look_at(eye, center, linalg.Vector3f32{0, 1, 0})
    near_z: f32 = 0.1
    far_z  := radius * 4
    proj := vulkan ? r3d_ortho_vk(-radius, radius, -radius, radius, near_z, far_z) :
                     r3d_ortho_gl(-radius, radius, -radius, radius, near_z, far_z)
    sun.light_view_proj = proj * view
    return sun.light_view_proj
}

// Camera basis vectors from yaw/pitch (no roll).
// yaw=0, pitch=0 -> right=(1,0,0), up=(0,1,0), forward=(0,0,-1)
r3d_camera_basis :: proc "contextless" (cam: ^R3D_Camera) -> (right, up, forward: linalg.Vector3f32) {
    cp := math.cos(cam.pitch)
    sp := math.sin(cam.pitch)
    cy := math.cos(cam.yaw)
    sy := math.sin(cam.yaw)
    forward = {cp * sy, sp, -cp * cy}
    right   = {cy, 0, sy}
    up      = linalg.normalize(linalg.cross(right, forward))
    return
}

// Resolve a sprite into a GPU instance: billboard orientation, in-plane
// rotation, and scale baked into the right/up basis vectors.
r3d_make_instance :: proc "contextless" (
    cam:  ^R3D_Camera,
    pos:  linalg.Vector3f32,
    size: linalg.Vector2f32,
    opts: R3D_Sprite_Options,
) -> (inst: R3D_Instance) {
    right, up: linalg.Vector3f32

    cam_right, cam_up, _ := r3d_camera_basis(cam)

    switch opts.billboard {
    case .Spherical:
        right = cam_right
        up    = cam_up
    case .Cylindrical:
        // Face the camera, but stay upright on the world Y axis.
        to_cam := cam.position - pos
        to_cam.y = 0
        len_xz := linalg.length(to_cam)
        facing: linalg.Vector3f32 = {0, 0, 1}
        if len_xz > 1e-5 {
            facing = to_cam / len_xz
        }
        right = linalg.normalize(linalg.cross(linalg.Vector3f32{0, 1, 0}, facing))
        up    = {0, 1, 0}
    case .FlatXZ:
        // up = -Z so that cross(right, up) = +Y (floor lit from above)
        right = {1, 0, 0}
        up    = {0, 0, -1}
    case .FlatXY:
        right = {1, 0, 0}
        up    = {0, 1, 0}
    }

    // In-plane rotation: rotate the basis within its own plane.
    c := math.cos(opts.rotation)
    s := math.sin(opts.rotation)
    r2 := right * c + up * s
    u2 := up * c - right * s

    inst.origin  = pos
    inst.right   = r2 * size.x
    inst.up      = u2 * size.y
    inst.normal  = linalg.normalize(linalg.cross(r2, u2))
    inst.uv_rect = opts.uv_rect
    inst.color   = opts.color
    inst.params  = {opts.spec_strength, opts.shininess, opts.emissive, 0}
    return
}

// Right-handed perspective projection, OpenGL clip conventions
// (camera looks down -Z, NDC z in [-1, 1]).
r3d_perspective_gl :: proc "contextless" (fov_y, aspect, near_z, far_z: f32) -> (m: linalg.Matrix4f32) {
    f := 1.0 / math.tan(0.5 * fov_y)
    m[0, 0] = f / aspect
    m[1, 1] = f
    m[2, 2] = (far_z + near_z) / (near_z - far_z)
    m[3, 2] = -1
    m[2, 3] = 2 * far_z * near_z / (near_z - far_z)
    return
}

// Right-handed perspective projection, Vulkan clip conventions
// (camera looks down -Z, NDC z in [0, 1], Y flipped to match GL orientation).
r3d_perspective_vk :: proc "contextless" (fov_y, aspect, near_z, far_z: f32) -> (m: linalg.Matrix4f32) {
    f := 1.0 / math.tan(0.5 * fov_y)
    m[0, 0] = f / aspect
    m[1, 1] = -f
    m[2, 2] = far_z / (near_z - far_z)
    m[3, 2] = -1
    m[2, 3] = far_z * near_z / (near_z - far_z)
    return
}

// View-projection matrix for the given camera and backend clip conventions.
r3d_camera_view_proj :: proc "contextless" (cam: ^R3D_Camera, aspect: f32, vulkan: bool) -> linalg.Matrix4f32 {
    _, _, forward := r3d_camera_basis(cam)
    view := linalg.matrix4_look_at(cam.position, cam.position + forward, linalg.Vector3f32{0, 1, 0})
    proj := vulkan ? r3d_perspective_vk(cam.fov_y, aspect, cam.near_z, cam.far_z) :
                     r3d_perspective_gl(cam.fov_y, aspect, cam.near_z, cam.far_z)
    return proj * view
}

// Fill a frame-uniform block from scene state.
r3d_make_frame_uniforms :: proc "contextless" (
    cam:       ^R3D_Camera,
    aspect:    f32,
    vulkan:    bool,
    ambient:   linalg.Vector3f32,
    lights:    []R3D_Light,
    sun:       ^R3D_Sun = nil,
) -> (u: R3D_Frame_Uniforms) {
    u.view_proj  = r3d_camera_view_proj(cam, aspect, vulkan)
    u.camera_pos = {cam.position.x, cam.position.y, cam.position.z, 0}
    u.ambient    = {ambient.x, ambient.y, ambient.z, 0}
    n := min(len(lights), R3D_MAX_LIGHTS)
    for i in 0 ..< n {
        u.light_pos[i]   = {lights[i].position.x, lights[i].position.y, lights[i].position.z, lights[i].radius}
        u.light_color[i] = {lights[i].color.x, lights[i].color.y, lights[i].color.z, 0}
    }
    u.meta = {f32(n), 0, 0, 0}
    if sun != nil && sun.enabled {
        u.light_view_proj = sun.light_view_proj
        dir := linalg.normalize(sun.direction)
        u.sun_dir   = {dir.x, dir.y, dir.z, 0}
        u.sun_color = {sun.color.x, sun.color.y, sun.color.z, 0}
        z_remap: f32 = vulkan ? 0 : 1
        on: f32 = sun.cast_shadows ? 1 : 0
        u.shadow_params = {on, sun.shadow_bias, sun.shadow_texel, z_remap}
    }
    return
}
