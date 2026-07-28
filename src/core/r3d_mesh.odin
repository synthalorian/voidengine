package voidengine

// ============================================================================
// r3d_mesh — backend-agnostic 3D mesh data: vertex layout, procedural mesh
// builders, and a Wavefront OBJ loader. Pure CPU code (unit-testable); the
// gl3d/vk3d backends upload R3D_Mesh_Data to GPU buffers.
// ============================================================================

import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strconv"
import "core:strings"

// Interleaved mesh vertex: position, normal, uv (32 bytes).
R3D_Vertex :: struct {
    pos:    linalg.Vector3f32,
    normal: linalg.Vector3f32,
    uv:     linalg.Vector2f32,
}

R3D_VERTEX_STRIDE :: size_of(R3D_Vertex) // 32

R3D_Mesh_Data :: struct {
    vertices: [dynamic]R3D_Vertex,
    indices:  [dynamic]u32,
}

r3d_mesh_data_destroy :: proc(m: ^R3D_Mesh_Data) {
    delete(m.vertices)
    delete(m.indices)
}

R3D_Mesh_Options :: struct {
    color:         linalg.Vector4f32,
    uv_tiling:     linalg.Vector2f32, // multiply uvs (e.g. {4,4} for tiled floors)
    spec_strength: f32,
    shininess:     f32,
    emissive:      f32,
}

r3d_default_mesh_options :: proc "contextless" () -> R3D_Mesh_Options {
    return R3D_Mesh_Options{
        color         = {1, 1, 1, 1},
        uv_tiling     = {1, 1},
        spec_strength = 0.5,
        shininess     = 32,
        emissive      = 0,
    }
}

@(private)
r3d_add_tri :: proc(m: ^R3D_Mesh_Data, a, b, c: linalg.Vector3f32, ua, ub, uc: linalg.Vector2f32) {
    // flat shading: face normal, duplicated verts
    n := linalg.normalize(linalg.cross(b - a, c - a))
    base := u32(len(m.vertices))
    append(&m.vertices, R3D_Vertex{pos = a, normal = n, uv = ua})
    append(&m.vertices, R3D_Vertex{pos = b, normal = n, uv = ub})
    append(&m.vertices, R3D_Vertex{pos = c, normal = n, uv = uc})
    append(&m.indices, base, base + 1, base + 2)
}

// Unit cube centered at origin, side length 1, flat normals.
r3d_mesh_cube :: proc() -> (m: R3D_Mesh_Data) {
    m.vertices = make([dynamic]R3D_Vertex)
    m.indices  = make([dynamic]u32)
    h :: f32(0.5)
    faces := [?]struct{n: linalg.Vector3f32, a, b, c, d: linalg.Vector3f32}{
        {{0, 0, 1},  {-h, -h, h}, {h, -h, h}, {h, h, h}, {-h, h, h}},   // +Z
        {{0, 0, -1}, {h, -h, -h}, {-h, -h, -h}, {-h, h, -h}, {h, h, -h}}, // -Z
        {{1, 0, 0},  {h, -h, h}, {h, -h, -h}, {h, h, -h}, {h, h, h}},   // +X
        {{-1, 0, 0}, {-h, -h, -h}, {-h, -h, h}, {-h, h, h}, {-h, h, -h}}, // -X
        {{0, 1, 0},  {-h, h, h}, {h, h, h}, {h, h, -h}, {-h, h, -h}},   // +Y
        {{0, -1, 0}, {-h, -h, -h}, {h, -h, -h}, {h, -h, h}, {-h, -h, h}}, // -Y
    }
    for f in faces {
        base := u32(len(m.vertices))
        append(&m.vertices,
            R3D_Vertex{pos = f.a, normal = f.n, uv = {0, 1}},
            R3D_Vertex{pos = f.b, normal = f.n, uv = {1, 1}},
            R3D_Vertex{pos = f.c, normal = f.n, uv = {1, 0}},
            R3D_Vertex{pos = f.d, normal = f.n, uv = {0, 0}},
        )
        append(&m.indices, base, base + 1, base + 2, base + 2, base + 3, base)
    }
    return
}

// Faceted crystal gem: two N-sided pyramids joined at a shared ring.
// radius = ring radius, top_h/bot_h = pyramid heights from the ring plane.
// Flat-shaded facets — the low-poly gem look.
r3d_mesh_crystal :: proc(sides := 6, radius: f32 = 0.5, top_h: f32 = 1.0, bot_h: f32 = 0.8) -> (m: R3D_Mesh_Data) {
    m.vertices = make([dynamic]R3D_Vertex)
    m.indices  = make([dynamic]u32)
    top := linalg.Vector3f32{0, top_h, 0}
    bot := linalg.Vector3f32{0, -bot_h, 0}
    ring := make([dynamic]linalg.Vector3f32, 0, sides, context.temp_allocator)
    for i in 0 ..< sides {
        a := f32(i) * math.TAU / f32(sides)
        append(&ring, linalg.Vector3f32{radius * math.cos(a), 0, radius * math.sin(a)})
    }
    for i in 0 ..< sides {
        j := (i + 1) % sides
        // facet uvs: strip across the gem
        ui  := f32(i) / f32(sides)
        uj  := f32(j) / f32(sides)
        r3d_add_tri(&m, top, ring[j], ring[i], {uj, 0}, {uj, 1}, {ui, 1})
        r3d_add_tri(&m, bot, ring[i], ring[j], {ui, 0}, {ui, 1}, {uj, 1})
    }
    return
}

// Flat grid plane on the XZ axis (subdivided quads), normals +Y.
r3d_mesh_plane :: proc(size: f32 = 1, subdivisions := 1) -> (m: R3D_Mesh_Data) {
    m.vertices = make([dynamic]R3D_Vertex)
    m.indices  = make([dynamic]u32)
    n := max(subdivisions, 1)
    step := size / f32(n)
    half := size / 2
    for gz in 0 ..< n {
        for gx in 0 ..< n {
            x0 := -half + f32(gx) * step
            z0 := -half + f32(gz) * step
            x1 := x0 + step
            z1 := z0 + step
            u0 := f32(gx) / f32(n)
            v0 := f32(gz) / f32(n)
            u1 := f32(gx + 1) / f32(n)
            v1 := f32(gz + 1) / f32(n)
            base := u32(len(m.vertices))
            yn := linalg.Vector3f32{0, 1, 0}
            append(&m.vertices,
                R3D_Vertex{pos = {x0, 0, z0}, normal = yn, uv = {u0, v1}},
                R3D_Vertex{pos = {x1, 0, z0}, normal = yn, uv = {u1, v1}},
                R3D_Vertex{pos = {x1, 0, z1}, normal = yn, uv = {u1, v0}},
                R3D_Vertex{pos = {x0, 0, z1}, normal = yn, uv = {u0, v0}},
            )
            append(&m.indices, base, base + 1, base + 2, base + 2, base + 3, base)
        }
    }
    return
}

// ----------------------------------------------------------------------------
// Wavefront OBJ loader (v / vn / vt / f, fan-triangulated)
// ----------------------------------------------------------------------------

r3d_load_obj :: proc(source: string) -> (m: R3D_Mesh_Data, ok: bool) {
    m.vertices = make([dynamic]R3D_Vertex)
    m.indices  = make([dynamic]u32)

    positions := make([dynamic]linalg.Vector3f32, 0, 64, context.temp_allocator)
    normals   := make([dynamic]linalg.Vector3f32, 0, 64, context.temp_allocator)
    uvs       := make([dynamic]linalg.Vector2f32, 0, 64, context.temp_allocator)

    // resolved (deduplicated) vertex soup
    key_to_index := make(map[u64]u32, 256, context.temp_allocator)

    src := source
    for line in strings.split_lines_iterator(&src) {
        trimmed := strings.trim_space(line)
        if len(trimmed) == 0 || trimmed[0] == '#' { continue }

        fields := strings.fields(trimmed, context.temp_allocator)
        if len(fields) == 0 { continue }

        switch fields[0] {
        case "v":
            if len(fields) < 4 { continue }
            x, _ := strconv.parse_f32(fields[1])
            y, _ := strconv.parse_f32(fields[2])
            z, _ := strconv.parse_f32(fields[3])
            append(&positions, linalg.Vector3f32{x, y, z})
        case "vn":
            if len(fields) < 4 { continue }
            x, _ := strconv.parse_f32(fields[1])
            y, _ := strconv.parse_f32(fields[2])
            z, _ := strconv.parse_f32(fields[3])
            append(&normals, linalg.normalize(linalg.Vector3f32{x, y, z}))
        case "vt":
            if len(fields) < 3 { continue }
            u, _ := strconv.parse_f32(fields[1])
            v, _ := strconv.parse_f32(fields[2])
            append(&uvs, linalg.Vector2f32{u, v})
        case "f":
            if len(fields) < 4 { continue }
            // resolve each corner; fan-triangulate polygons
            corner_idx := make([dynamic]u32, 0, len(fields) - 1, context.temp_allocator)
            for corner in fields[1:] {
                pi, ti, ni := 0, 0, 0 // OBJ indices are 1-based; 0 = absent
                parts := strings.split(corner, "/", context.temp_allocator)
                if len(parts) >= 1 && len(parts[0]) > 0 { pi, _ = strconv.parse_int(parts[0]) }
                if len(parts) >= 2 && len(parts[1]) > 0 { ti, _ = strconv.parse_int(parts[1]) }
                if len(parts) >= 3 && len(parts[2]) > 0 { ni, _ = strconv.parse_int(parts[2]) }
                if pi <= 0 || pi > len(positions) { continue }

                key := u64(u32(pi)) << 40 | u64(u32(ti)) << 20 | u64(u32(ni))
                if existing, found := key_to_index[key]; found {
                    append(&corner_idx, existing)
                    continue
                }
                v := R3D_Vertex{pos = positions[pi - 1]}
                if ti > 0 && ti <= len(uvs) { v.uv = uvs[ti - 1] }
                if ni > 0 && ni <= len(normals) { v.normal = normals[ni - 1] }
                idx := u32(len(m.vertices))
                append(&m.vertices, v)
                key_to_index[key] = idx
                append(&corner_idx, idx)
            }
            for k in 1 ..< max(len(corner_idx) - 1, 0) {
                append(&m.indices, corner_idx[0], corner_idx[k], corner_idx[k + 1])
            }
        }
    }

    // synthesize normals when the file had none
    has_normals := false
    for v in m.vertices {
        if v.normal != {} { has_normals = true; break }
    }
    if !has_normals {
        for i in 0 ..< len(m.indices) / 3 {
            a := &m.vertices[m.indices[i * 3 + 0]]
            b := &m.vertices[m.indices[i * 3 + 1]]
            c := &m.vertices[m.indices[i * 3 + 2]]
            n := linalg.normalize(linalg.cross(b.pos - a.pos, c.pos - a.pos))
            a.normal = n
            b.normal = n
            c.normal = n
        }
    }

    ok = len(m.vertices) > 0 && len(m.indices) > 0
    return
}

r3d_load_obj_file :: proc(path: string) -> (R3D_Mesh_Data, bool) {
    data, err := os_read_entire_file(path)
    if err { return {}, false }
    defer delete(data)
    return r3d_load_obj(string(data))
}

@(private)
os_read_entire_file :: proc(path: string) -> ([]u8, bool) {
    // thin wrapper so the loader's error path stays one-liners
    data, ferr := os.read_entire_file_from_path(path, context.allocator)
    return data, ferr == nil
}
