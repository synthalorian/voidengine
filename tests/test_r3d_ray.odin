package voidengine_test

// Tests for ray3d: screen-ray unprojection and intersection queries.

import "core:math"
import "core:testing"
import "core:math/linalg"
import engine "../src/core"

approx :: proc(a, b: f32, eps := f32(1e-4)) -> bool {
    return abs(a - b) < eps
}

@test
ray_sphere_hit :: proc(t: ^testing.T) {
    ray := engine.Ray3D{origin = {0, 0, 5}, dir = {0, 0, -1}}
    dist, hit := engine.ray3d_sphere(ray, {0, 0, 0}, 1)
    testing.expect(t, hit, "ray straight at sphere should hit")
    testing.expect(t, approx(dist, 4), "t should be 4 (near face)")
}

@test
ray_sphere_miss :: proc(t: ^testing.T) {
    ray := engine.Ray3D{origin = {0, 5, 5}, dir = {0, 0, -1}}
    _, hit := engine.ray3d_sphere(ray, {0, 0, 0}, 1)
    testing.expect(t, !hit, "ray passing 5 above sphere should miss")
}

@test
ray_sphere_inside :: proc(t: ^testing.T) {
    ray := engine.Ray3D{origin = {0, 0, 0}, dir = {1, 0, 0}}
    dist, hit := engine.ray3d_sphere(ray, {0, 0, 0}, 2)
    testing.expect(t, hit, "origin inside sphere should hit")
    testing.expect(t, approx(dist, 2), "t should be exit point at 2")
}

@test
ray_aabb_hit :: proc(t: ^testing.T) {
    ray := engine.Ray3D{origin = {-5, 0, 0}, dir = {1, 0, 0}}
    dist, hit := engine.ray3d_aabb(ray, {-1, -1, -1}, {1, 1, 1})
    testing.expect(t, hit, "ray at unit box should hit")
    testing.expect(t, approx(dist, 4), "t should be 4 (near face)")
}

@test
ray_aabb_parallel_miss :: proc(t: ^testing.T) {
    ray := engine.Ray3D{origin = {-5, 3, 0}, dir = {1, 0, 0}}
    _, hit := engine.ray3d_aabb(ray, {-1, -1, -1}, {1, 1, 1})
    testing.expect(t, !hit, "ray parallel but offset should miss")
}

@test
ray_plane_ground :: proc(t: ^testing.T) {
    dir := linalg.normalize(linalg.Vector3f32{0, -1, 1})
    ray := engine.Ray3D{origin = {0, 2, 0}, dir = dir}
    dist, hit := engine.ray3d_plane(ray, {0, 0, 0}, {0, 1, 0})
    testing.expect(t, hit, "downward ray should hit ground plane")
    testing.expect(t, approx(dist, 2 * math.sqrt(f32(2)), 1e-3), "t should be 2*sqrt(2)")
    p := engine.ray3d_at(ray, dist)
    testing.expect(t, approx(p.y, 0, 1e-3), "hit point should be on plane")
}

@test
ray_from_screen_center :: proc(t: ^testing.T) {
    // camera at origin looking down -Z; screen center ray must go to -Z
    cam := engine.R3D_Camera{
        position = {0, 0, 0},
        yaw      = 0,
        pitch    = 0,
        fov_y    = math.PI / 3,
        near_z   = 0.1,
        far_z    = 100,
    }
    for vk in ([2]bool{false, true}) {
        ray := engine.ray3d_from_screen(&cam, 640, 360, 1280, 720, vk)
        testing.expect(t, approx(ray.dir.x, 0, 1e-3), "center ray x ~ 0")
        testing.expect(t, approx(ray.dir.y, 0, 1e-3), "center ray y ~ 0")
        testing.expect(t, approx(ray.dir.z, -1, 1e-3), "center ray z ~ -1")
    }
}

@test
ray_from_screen_offsets :: proc(t: ^testing.T) {
    cam := engine.R3D_Camera{
        position = {0, 0, 0},
        yaw      = 0,
        pitch    = 0,
        fov_y    = math.PI / 2,
        near_z   = 0.1,
        far_z    = 100,
    }
    // left edge of screen -> negative x; top of screen -> positive y
    left := engine.ray3d_from_screen(&cam, 0, 360, 1280, 720, false)
    top  := engine.ray3d_from_screen(&cam, 640, 0, 1280, 720, false)
    testing.expect(t, left.dir.x < -0.5, "left edge ray should point -x")
    testing.expect(t, top.dir.y > 0.5, "top edge ray should point +y")
}

@test
ray_mesh_cube :: proc(t: ^testing.T) {
    m := engine.r3d_mesh_cube()
    defer engine.r3d_mesh_data_destroy(&m)

    // cube is unit-sized centered at origin; shoot at it from +z
    model := linalg.matrix4_translate(linalg.Vector3f32{0, 0, -5})
    ray := engine.Ray3D{origin = {0, 0, 0}, dir = {0, 0, -1}}
    dist, hit := engine.ray3d_mesh(ray, &m, model)
    testing.expect(t, hit, "ray at translated cube should hit")
    // cube half-extent 0.5 -> near face at z=-4.5 -> t=4.5
    testing.expect(t, approx(dist, 4.5, 1e-3), "t should be 4.5")

    // scaled 2x: near face at z=-4
    big := linalg.matrix4_translate(linalg.Vector3f32{0, 0, -5}) * linalg.matrix4_scale(linalg.Vector3f32{2, 2, 2})
    dist2, hit2 := engine.ray3d_mesh(ray, &m, big)
    testing.expect(t, hit2, "ray at scaled cube should hit")
    testing.expect(t, approx(dist2, 4, 1e-3), "scaled cube near face at t=4")

    // miss: ray offset beyond the cube
    ray_off := engine.Ray3D{origin = {5, 0, 0}, dir = {0, 0, -1}}
    _, hit3 := engine.ray3d_mesh(ray_off, &m, model)
    testing.expect(t, !hit3, "offset ray should miss cube")
}
