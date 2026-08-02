package voidengine_test

// Tests for the backend-agnostic 3D sprite core (r3d.odin): camera basis,
// billboard orientation, in-plane rotation, projection clip mapping, and
// frame uniform packing. No GL/Vulkan context required.

import "core:testing"
import "core:math"
import "core:math/linalg"
import engine "../src/core"

expect_vec3_close :: proc(t: ^testing.T, got, want: linalg.Vector3f32, msg: string, eps: f32 = 1e-5) {
    for i in 0 ..< 3 {
        if abs(got[i] - want[i]) > eps {
            testing.fail(t)
            return
        }
    }
}

@(test)
r3d_camera_basis_identity :: proc(t: ^testing.T) {
    cam := engine.R3D_Camera{yaw = 0, pitch = 0}
    right, up, forward := engine.r3d_camera_basis(&cam)
    expect_vec3_close(t, right, {1, 0, 0}, "right")
    expect_vec3_close(t, up, {0, 1, 0}, "up")
    expect_vec3_close(t, forward, {0, 0, -1}, "forward")
}

@(test)
r3d_camera_basis_yaw_90 :: proc(t: ^testing.T) {
    // yaw = +90deg: camera faces +X, right hand points +Z
    cam := engine.R3D_Camera{yaw = math.PI / 2, pitch = 0}
    right, _, forward := engine.r3d_camera_basis(&cam)
    expect_vec3_close(t, forward, {1, 0, 0}, "forward")
    expect_vec3_close(t, right, {0, 0, 1}, "right")
}

@(test)
r3d_camera_basis_pitch_up :: proc(t: ^testing.T) {
    cam := engine.R3D_Camera{yaw = 0, pitch = math.PI / 2}
    _, _, forward := engine.r3d_camera_basis(&cam)
    expect_vec3_close(t, forward, {0, 1, 0}, "forward should look straight up")
}

@(test)
r3d_spherical_billboard_faces_camera :: proc(t: ^testing.T) {
    cam := engine.R3D_Camera{position = {0, 0, 5}, yaw = 0, pitch = 0}
    opts := engine.r3d_default_sprite_options()
    inst := engine.r3d_make_instance(&cam, {0, 0, 0}, {2, 4}, opts)

    // camera at +Z looking -Z: right=+X, up=+Y, normal=+Z (toward camera)
    expect_vec3_close(t, inst.right, {2, 0, 0}, "right scaled by width")
    expect_vec3_close(t, inst.up, {0, 4, 0}, "up scaled by height")
    expect_vec3_close(t, inst.normal, {0, 0, 1}, "normal faces camera")
    expect_vec3_close(t, inst.origin, {0, 0, 0}, "origin")
}

@(test)
r3d_flat_xz_floor :: proc(t: ^testing.T) {
    cam := engine.R3D_Camera{position = {0, 5, 5}, yaw = 0.3, pitch = -0.4}
    opts := engine.r3d_default_sprite_options()
    opts.billboard = .FlatXZ
    inst := engine.r3d_make_instance(&cam, {1, 0, 2}, {10, 10}, opts)
    expect_vec3_close(t, inst.right, {10, 0, 0}, "floor right")
    expect_vec3_close(t, inst.up, {0, 0, -10}, "floor up is -Z (keeps normal +Y)")
    expect_vec3_close(t, inst.normal, {0, 1, 0}, "floor normal +Y")
}

@(test)
r3d_cylindrical_stays_upright :: proc(t: ^testing.T) {
    // camera above the sprite: cylindrical billboard must keep up = +Y
    cam := engine.R3D_Camera{position = {0, 8, 8}, yaw = 0, pitch = -0.7}
    opts := engine.r3d_default_sprite_options()
    opts.billboard = .Cylindrical
    inst := engine.r3d_make_instance(&cam, {0, 0, 0}, {1, 2}, opts)
    expect_vec3_close(t, inst.up, {0, 2, 0}, "cylindrical up stays world Y")
    // right must be horizontal (y == 0)
    testing.expect(t, abs(inst.right.y) < 1e-5, "cylindrical right is horizontal")
    // normal must point at the camera's XZ position
    testing.expect(t, inst.normal.y < 1e-5, "cylindrical normal is horizontal")
    testing.expect(t, inst.normal.z > 0.9, "normal faces camera XZ")
}

@(test)
r3d_in_plane_rotation :: proc(t: ^testing.T) {
    cam := engine.R3D_Camera{position = {0, 0, 5}, yaw = 0, pitch = 0}
    opts := engine.r3d_default_sprite_options()
    opts.rotation = math.PI / 2  // 90deg CCW in screen plane
    inst := engine.r3d_make_instance(&cam, {0, 0, 0}, {2, 4}, opts)
    // rotating basis by +90deg: right' = c*r + s*u = +up, up' = c*u - s*r = -right
    expect_vec3_close(t, inst.right, {0, 2, 0}, "rotated right")
    expect_vec3_close(t, inst.up, {-4, 0, 0}, "rotated up")
    // normal must be unchanged by in-plane rotation
    expect_vec3_close(t, inst.normal, {0, 0, 1}, "normal stable under rotation")
}

@(test)
r3d_perspective_gl_clip_range :: proc(t: ^testing.T) {
    near_z, far_z: f32 = 0.5, 50
    m := engine.r3d_perspective_gl(math.PI / 3, 16.0 / 9.0, near_z, far_z)
    // point on -Z at near -> NDC z = -1; at far -> NDC z = +1
    p_near := linalg.matrix_mul_vector(m, linalg.Vector4f32{0, 0, -near_z, 1})
    p_far  := linalg.matrix_mul_vector(m, linalg.Vector4f32{0, 0, -far_z, 1})
    testing.expect(t, abs(p_near.z / p_near.w - (-1)) < 1e-4, "GL near maps to -1")
    testing.expect(t, abs(p_far.z / p_far.w - 1) < 1e-4, "GL far maps to +1")
}

@(test)
r3d_perspective_vk_clip_range :: proc(t: ^testing.T) {
    near_z, far_z: f32 = 0.5, 50
    m := engine.r3d_perspective_vk(math.PI / 3, 16.0 / 9.0, near_z, far_z)
    p_near := linalg.matrix_mul_vector(m, linalg.Vector4f32{0, 0, -near_z, 1})
    p_far  := linalg.matrix_mul_vector(m, linalg.Vector4f32{0, 0, -far_z, 1})
    testing.expect(t, abs(p_near.z / p_near.w - 0) < 1e-4, "VK near maps to 0")
    testing.expect(t, abs(p_far.z / p_far.w - 1) < 1e-4, "VK far maps to 1")
    // Y flip: a point above the camera axis must get negative NDC y (Vulkan y-down)
    p_up := linalg.matrix_mul_vector(m, linalg.Vector4f32{0, 1, -2, 1})
    testing.expect(t, p_up.y / p_up.w < 0, "VK projection flips Y")
}

@(test)
r3d_frame_uniforms_packing :: proc(t: ^testing.T) {
    cam := engine.R3D_Camera{position = {1, 2, 3}, yaw = 0, pitch = 0, fov_y = 1, near_z = 0.1, far_z = 10}
    lights := [?]engine.R3D_Light{
        {position = {4, 5, 6}, color = {1, 0.5, 0.25}, radius = 8},
    }
    u := engine.r3d_make_frame_uniforms(&cam, 1.5, false, {0.1, 0.2, 0.3}, lights[:])
    testing.expect(t, u.camera_pos.x == 1 && u.camera_pos.y == 2 && u.camera_pos.z == 3, "camera pos packed")
    testing.expect(t, u.light_pos[0].x == 4 && u.light_pos[0].w == 8, "light pos+radius packed")
    testing.expect(t, u.light_color[0].y == 0.5, "light color packed")
    testing.expect(t, u.meta.x == 1, "light count packed")
    testing.expect(t, u.ambient.z == 0.3, "ambient packed")
}

@(test)
r3d_frame_uniforms_lights_capped :: proc(t: ^testing.T) {
    cam := engine.R3D_Camera{fov_y = 1, near_z = 0.1, far_z = 10}
    lights := make([dynamic]engine.R3D_Light, 0, 64)
    defer delete(lights)
    for i in 0 ..< 64 {
        append(&lights, engine.R3D_Light{})
    }
    u := engine.r3d_make_frame_uniforms(&cam, 1, false, {}, lights[:])
    testing.expect(t, u.meta.x == f32(engine.R3D_MAX_LIGHTS), "lights capped at R3D_MAX_LIGHTS")
}

@test
r3d_ortho_gl_mapping :: proc(t: ^testing.T) {
    // Ortho must be a pure affine camera matrix: w stays 1 for every point,
    // x/y map [l,r]x[b,t] -> [-1,1], z maps [near,far] -> [-1,1] (GL).
    m := engine.r3d_ortho_gl(-10, 10, -5, 5, 1, 101)

    // w-row must be {0,0,0,1} — regression: translation terms previously
    // landed in the w-row (m[3,0..2] under Odin's m[row,col] indexing),
    // which broke shadow-map depth comparisons.
    for p in ([?]linalg.Vector4f32{{0, 0, -1, 1}, {7, -3, -51, 1}, {-10, 5, -101, 1}}) {
        r := m * p
        testing.expect(t, abs(r.w - 1) < 1e-5, "ortho must preserve w=1")
    }

    center := m * linalg.Vector4f32{0, 0, -51, 1}
    testing.expect(t, abs(center.x) < 1e-5 && abs(center.y) < 1e-5, "box center maps to NDC origin")
    testing.expect(t, abs(center.z) < 1e-3, "mid-depth maps near 0")

    near_pt := m * linalg.Vector4f32{0, 0, -1, 1}
    far_pt  := m * linalg.Vector4f32{0, 0, -101, 1}
    testing.expect(t, abs(near_pt.z - (-1)) < 1e-4, "near plane -> z=-1")
    testing.expect(t, abs(far_pt.z - 1) < 1e-4, "far plane -> z=+1")

    // closer-to-camera geometry must get SMALLER depth (shadow correctness)
    closer := m * linalg.Vector4f32{0, 0, -30, 1}
    farther := m * linalg.Vector4f32{0, 0, -60, 1}
    testing.expect(t, closer.z < farther.z, "closer points must map to smaller z")
}

@test
r3d_ortho_vk_mapping :: proc(t: ^testing.T) {
    m := engine.r3d_ortho_vk(-10, 10, -5, 5, 1, 101)
    for p in ([?]linalg.Vector4f32{{0, 0, -1, 1}, {7, -3, -51, 1}, {-10, 5, -101, 1}}) {
        r := m * p
        testing.expect(t, abs(r.w - 1) < 1e-5, "vk ortho must preserve w=1")
    }
    near_pt := m * linalg.Vector4f32{0, 0, -1, 1}
    far_pt  := m * linalg.Vector4f32{0, 0, -101, 1}
    testing.expect(t, abs(near_pt.z) < 1e-3, "vk near plane -> z=0")
    testing.expect(t, abs(far_pt.z - 1) < 1e-3, "vk far plane -> z=1")
    // y flipped vs GL
    top_pt := m * linalg.Vector4f32{0, 5, -51, 1}
    testing.expect(t, top_pt.y < -0.99, "vk ortho flips y")
}

@test
r3d_sun_view_proj_depth_order :: proc(t: ^testing.T) {
    // A point closer to the sun must land at smaller shadow depth than one
    // farther away, at the same lateral position — the invariant shadow
    // comparison depends on.
    for vulkan in ([2]bool{false, true}) {
        sun := engine.R3D_Sun{
            direction = {-0.4, -0.8, 0.3},
            shadow_radius = 20,
        }
        vp := engine.r3d_sun_view_proj(&sun, {0, 0, 0}, vulkan)
        low  := vp * linalg.Vector4f32{0, 0, 0, 1}
        high := vp * linalg.Vector4f32{0, 5, 0, 1} // 5 units closer to the sun
        low_z  := low.z / low.w
        high_z := high.z / high.w
        testing.expect(t, abs(low.w - 1) < 1e-4 && abs(high.w - 1) < 1e-4, "sun ortho preserves w")
        testing.expect(t, high_z < low_z, "sun-facing points must be at smaller depth")
    }
}
