package voidengine_test

// Tests for r3d_mesh: procedural builders and the OBJ loader.

import "core:testing"
import "core:math/linalg"
import engine "../src/core"

@(test)
mesh_cube_geometry :: proc(t: ^testing.T) {
    m := engine.r3d_mesh_cube()
    defer engine.r3d_mesh_data_destroy(&m)
    testing.expect(t, len(m.vertices) == 24, "cube has 24 flat-shaded verts")
    testing.expect(t, len(m.indices) == 36, "cube has 36 indices")
    // all normals unit length and axis-aligned
    for v in m.vertices {
        l := linalg.length(v.normal)
        testing.expect(t, l > 0.99 && l < 1.01, "cube normals unit length")
    }
    // indices in range
    for idx in m.indices {
        testing.expect(t, int(idx) < len(m.vertices), "cube indices in range")
    }
}

@(test)
mesh_crystal_geometry :: proc(t: ^testing.T) {
    sides := 6
    m := engine.r3d_mesh_crystal(sides, 0.5, 1.0, 0.8)
    defer engine.r3d_mesh_data_destroy(&m)
    // 2 triangles per side, 3 verts each (flat shaded)
    testing.expect(t, len(m.vertices) == sides * 2 * 3, "crystal vert count")
    testing.expect(t, len(m.indices) == sides * 2 * 3, "crystal index count")
    // apex present
    found_top := false
    for v in m.vertices {
        if v.pos.y > 0.99 && v.pos.x == 0 && v.pos.z == 0 {
            found_top = true
        }
    }
    testing.expect(t, found_top, "crystal has a top apex")
    // flat normals point outward-ish: top facets must have +Y component
    for i in 0 ..< len(m.indices) / 3 {
        v := m.vertices[m.indices[i * 3]]
        if v.pos.y > 0.5 {
            testing.expect(t, v.normal.y > 0.05, "top facet normal points up")
        }
    }
}

@(test)
mesh_plane_subdivision :: proc(t: ^testing.T) {
    m := engine.r3d_mesh_plane(4, 2)
    defer engine.r3d_mesh_data_destroy(&m)
    testing.expect(t, len(m.vertices) == 2 * 2 * 4, "plane 2x2 quads = 16 verts")
    testing.expect(t, len(m.indices) == 2 * 2 * 6, "plane 2x2 quads = 24 indices")
    for v in m.vertices {
        testing.expect(t, v.normal == linalg.Vector3f32{0, 1, 0}, "plane normals +Y")
        testing.expect(t, v.pos.y == 0, "plane flat on XZ")
    }
}

@(test)
obj_loader_triangle :: proc(t: ^testing.T) {
    src := `# comment
v 0 0 0
v 1 0 0
v 0 1 0
vt 0 0
vt 1 0
vt 0 1
vn 0 0 1
f 1/1/1 2/2/1 3/3/1
`
    m, ok := engine.r3d_load_obj(src)
    defer engine.r3d_mesh_data_destroy(&m)
    testing.expect(t, ok, "obj parses")
    testing.expect(t, len(m.vertices) == 3, "obj dedups 3 corners")
    testing.expect(t, len(m.indices) == 3, "obj one triangle")
    testing.expect(t, m.vertices[0].normal == linalg.Vector3f32{0, 0, 1}, "obj normal bound")
    testing.expect(t, m.vertices[1].uv == linalg.Vector2f32{1, 0}, "obj uv bound")
}

@(test)
obj_loader_quad_fan_and_synth_normals :: proc(t: ^testing.T) {
    // quad without vn: fan-triangulated, normals synthesized
    src := `v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
f 1 2 3 4
`
    m, ok := engine.r3d_load_obj(src)
    defer engine.r3d_mesh_data_destroy(&m)
    testing.expect(t, ok, "obj quad parses")
    testing.expect(t, len(m.indices) == 6, "quad fan = 2 triangles")
    for v in m.vertices {
        testing.expect(t, v.normal.z == 1, "synthesized +Z normals")
    }
}

@(test)
obj_loader_shared_corner_dedup :: proc(t: ^testing.T) {
    src := `v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
f 1/1 2/1 3/1
f 1/1 3/1 4/1
`
    m, ok := engine.r3d_load_obj(src)
    defer engine.r3d_mesh_data_destroy(&m)
    testing.expect(t, ok, "parses")
    testing.expect(t, len(m.vertices) == 4, "shared (pos,uv,normal) corners dedup")
    testing.expect(t, len(m.indices) == 6, "two triangles")
}
