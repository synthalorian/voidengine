package voidengine

// ============================================================================
// ray3d — CPU raycasting for 3D picking and queries (backend-agnostic)
//
// Rays are world-space with normalized direction. Intersection procs return
// the parametric t along the ray (world units, since dir is normalized) and
// a hit flag. t is always the NEAREST positive intersection.
// ============================================================================

import "core:math"
import "core:math/linalg"

Ray3D :: struct {
    origin: linalg.Vector3f32,
    dir:    linalg.Vector3f32, // normalized
}

ray3d_at :: proc "contextless" (ray: Ray3D, t: f32) -> linalg.Vector3f32 {
    return ray.origin + ray.dir * t
}

// Build a world-space ray from screen pixel coordinates (y-down, SDL mouse
// convention) through the camera. Unprojects via the inverse view-projection,
// so GL/VK clip conventions are handled by passing the same `vulkan` flag
// used when rendering.
ray3d_from_screen :: proc "contextless" (
    cam: ^R3D_Camera,
    sx, sy, width, height: f32,
    vulkan: bool,
) -> Ray3D {
    aspect := width / max(height, 1)
    vp := r3d_camera_view_proj(cam, aspect, vulkan)
    inv := linalg.inverse(vp)

    ndc_x := 2 * sx / max(width, 1) - 1
    ndc_y := 1 - 2 * sy / max(height, 1) // screen y-down -> NDC y-up

    z_near: f32 = vulkan ? 0 : -1
    p_near := inv * linalg.Vector4f32{ndc_x, ndc_y, z_near, 1}
    p_far  := inv * linalg.Vector4f32{ndc_x, ndc_y, 1, 1}
    near3 := p_near.xyz / p_near.w
    far3  := p_far.xyz / p_far.w

    return Ray3D{
        origin = near3,
        dir    = linalg.normalize(far3 - near3),
    }
}

// Ray vs sphere. Returns nearest positive t.
ray3d_sphere :: proc "contextless" (ray: Ray3D, center: linalg.Vector3f32, radius: f32) -> (t: f32, hit: bool) {
    oc := ray.origin - center
    b := linalg.dot(oc, ray.dir)
    c := linalg.dot(oc, oc) - radius * radius
    disc := b * b - c
    if disc < 0 { return 0, false }
    sq := math.sqrt(disc)
    t = -b - sq
    if t < 0 { t = -b + sq } // origin inside sphere
    if t < 0 { return 0, false }
    return t, true
}

// Ray vs axis-aligned box (slab method). Returns nearest positive t.
ray3d_aabb :: proc "contextless" (ray: Ray3D, bmin, bmax: linalg.Vector3f32) -> (t: f32, hit: bool) {
    tmin: f32 = -1e30
    tmax: f32 = 1e30
    for axis in 0 ..< 3 {
        o := ray.origin[axis]
        d := ray.dir[axis]
        lo := bmin[axis]
        hi := bmax[axis]
        if abs(d) < 1e-8 {
            if o < lo || o > hi { return 0, false }
        } else {
            inv := 1 / d
            t1 := (lo - o) * inv
            t2 := (hi - o) * inv
            if t1 > t2 { t1, t2 = t2, t1 }
            tmin = max(tmin, t1)
            tmax = min(tmax, t2)
            if tmin > tmax { return 0, false }
        }
    }
    if tmax < 0 { return 0, false }
    t = tmin > 0 ? tmin : tmax
    return t, true
}

// Ray vs plane (point + normal). Returns positive t.
ray3d_plane :: proc "contextless" (ray: Ray3D, point, normal: linalg.Vector3f32) -> (t: f32, hit: bool) {
    denom := linalg.dot(normal, ray.dir)
    if abs(denom) < 1e-8 { return 0, false }
    t = linalg.dot(normal, point - ray.origin) / denom
    if t < 0 { return 0, false }
    return t, true
}

// Ray vs mesh (Möller–Trumbore over all triangles). The ray is transformed
// into model space via the inverse model matrix; the returned t is in WORLD
// units along the original ray. Works with non-uniform scale.
ray3d_mesh :: proc "contextless" (
    ray:   Ray3D,
    mesh:  ^R3D_Mesh_Data,
    model: linalg.Matrix4f32,
) -> (t: f32, hit: bool) {
    inv := linalg.inverse(model)
    o4 := inv * linalg.Vector4f32{ray.origin.x, ray.origin.y, ray.origin.z, 1}
    d4 := inv * linalg.Vector4f32{ray.dir.x, ray.dir.y, ray.dir.z, 0}
    mo := o4.xyz
    md := d4.xyz // NOT normalized; t values below are in model-ray units

    best := linalg.Vector3f32{0, 0, 0}
    best_found := false

    n := len(mesh.indices)
    for i := 0; i + 2 < n; i += 3 {
        a := mesh.vertices[mesh.indices[i]].pos
        b := mesh.vertices[mesh.indices[i + 1]].pos
        c := mesh.vertices[mesh.indices[i + 2]].pos

        e1 := b - a
        e2 := c - a
        p := linalg.cross(md, e2)
        det := linalg.dot(e1, p)
        if abs(det) < 1e-8 { continue }
        inv_det := 1 / det
        tv := mo - a
        u := linalg.dot(tv, p) * inv_det
        if u < 0 || u > 1 { continue }
        q := linalg.cross(tv, e1)
        v := linalg.dot(md, q) * inv_det
        if v < 0 || u + v > 1 { continue }
        tt := linalg.dot(e2, q) * inv_det
        if tt < 0 { continue }

        cand := mo + md * tt
        if !best_found || linalg.length2(cand - mo) < linalg.length2(best - mo) {
            best = cand
            best_found = true
        }
    }
    if !best_found { return 0, false }

    // back to world space; t along the normalized world ray
    w4 := model * linalg.Vector4f32{best.x, best.y, best.z, 1}
    world_hit := w4.xyz
    t = linalg.length(world_hit - ray.origin)
    // guard: hit must be in front of the ray
    if linalg.dot(world_hit - ray.origin, ray.dir) < 0 { return 0, false }
    return t, true
}
