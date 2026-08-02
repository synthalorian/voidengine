package voidengine

// ============================================================================
// gltf.odin — static glTF mesh loading (v1) via vendor:cgltf.
//
// Scope: .gltf/.glb, triangle primitives, POSITION/NORMAL/TEXCOORD_0 +
// indices. Materials reduce to baseColorFactor tints. Node transforms ARE
// flattened into world space (Blender exports every object as a node with
// TRS — without this, parts collapse onto the origin). Texture paths and
// skins/animations come later. glTF is right-handed Y-up like the engine.
// ============================================================================

import "core:strings"
import "core:math/linalg"
import "vendor:cgltf"

R3D_Gltf_Mesh :: struct {
    name: string,
    data: R3D_Mesh_Data,
    tint: linalg.Vector4f32, // material baseColorFactor (white if absent)
}

R3D_Gltf_Model :: struct {
    meshes: [dynamic]R3D_Gltf_Mesh,
}

// Load a glTF file into engine mesh data. Caller destroys with
// r3d_gltf_destroy (and uploads via gl3d/vk3d_upload_mesh first if desired).
r3d_gltf_load :: proc(path: string, allocator := context.allocator) -> (model: R3D_Gltf_Model, ok: bool) {
    context.allocator = allocator
    model.meshes = make([dynamic]R3D_Gltf_Mesh)

    opts: cgltf.options
    data, res := cgltf.parse_file(opts, strings.clone_to_cstring(path, context.temp_allocator))
    if res != .success { return model, false }
    defer cgltf.free(data)

    if cgltf.load_buffers(opts, data, strings.clone_to_cstring(path, context.temp_allocator)) != .success {
        return model, false
    }
    if cgltf.validate(data) != .success { return model, false }

    if data.scene != nil {
        for n in data.scene.nodes {
            gltf_walk_node(&model, n, linalg.MATRIX4F32_IDENTITY)
        }
    } else if len(data.scenes) > 0 {
        for n in data.scenes[0].nodes {
            gltf_walk_node(&model, n, linalg.MATRIX4F32_IDENTITY)
        }
    } else {
        // no scene graph: every mesh at identity
        for m in data.meshes {
            for &p in m.primitives {
                if p.type != .triangles { continue }
                name := m.name != nil ? string(m.name) : ""
                gm := gltf_load_primitive(name, &p)
                if len(gm.data.vertices) == 0 { continue }
                append(&model.meshes, gm)
            }
        }
    }
    if len(model.meshes) == 0 { return model, false }
    return model, true
}

r3d_gltf_destroy :: proc(model: ^R3D_Gltf_Model) {
    for &m in model.meshes {
        r3d_mesh_data_destroy(&m.data)
        delete(m.name)
    }
    delete(model.meshes)
    model.meshes = nil
}

@(private)
gltf_walk_node :: proc(model: ^R3D_Gltf_Model, n: ^cgltf.node, parent: linalg.Matrix4f32) {
    local16: [16]f32
    cgltf.node_transform_local(n, raw_data(local16[:]))
    local := transmute(linalg.Matrix4f32)local16
    world := parent * local

    if n.mesh != nil {
        for &p in n.mesh.primitives {
            if p.type != .triangles { continue }
            name: string
            if n.name != nil {
                name = string(n.name)
            } else if n.mesh.name != nil {
                name = string(n.mesh.name)
            }
            gm := gltf_load_primitive(name, &p)
            if len(gm.data.vertices) == 0 { continue }
            gltf_apply_transform(&gm.data, world)
            append(&model.meshes, gm)
        }
    }
    for c in n.children {
        gltf_walk_node(model, c, world)
    }
}

@(private)
gltf_apply_transform :: proc(d: ^R3D_Mesh_Data, m: linalg.Matrix4f32) {
    for &v in d.vertices {
        p := m * linalg.Vector4f32{v.pos.x, v.pos.y, v.pos.z, 1}
        v.pos = p.xyz / p.w
        n4 := m * linalg.Vector4f32{v.normal.x, v.normal.y, v.normal.z, 0}
        v.normal = linalg.normalize(n4.xyz)
    }
}

@(private)
gltf_load_primitive :: proc(mesh_name: string, p: ^cgltf.primitive) -> (gm: R3D_Gltf_Mesh) {
    gm.name = strings.clone(mesh_name)
    gm.tint = {1, 1, 1, 1}
    if p.material != nil && p.material.has_pbr_metallic_roughness {
        c := p.material.pbr_metallic_roughness.base_color_factor
        gm.tint = {c[0], c[1], c[2], c[3]}
    }

    // locate attribute accessors
    pos_acc, nrm_acc, uv_acc: ^cgltf.accessor
    for a in p.attributes {
        #partial switch a.type {
        case .position: pos_acc = a.data
        case .normal:   nrm_acc = a.data
        case .texcoord: if a.index == 0 { uv_acc = a.data }
        }
    }
    if pos_acc == nil { return }
    n := int(pos_acc.count)

    positions := make([]f32, n * 3)
    defer delete(positions)
    if cgltf.accessor_unpack_floats(pos_acc, raw_data(positions), uint(n * 3)) == 0 { return }

    normals: []f32
    if nrm_acc != nil {
        normals = make([]f32, n * 3)
        _ = cgltf.accessor_unpack_floats(nrm_acc, raw_data(normals), uint(n * 3))
    }
    defer if normals != nil { delete(normals) }

    uvs: []f32
    if uv_acc != nil {
        uvs = make([]f32, n * 2)
        _ = cgltf.accessor_unpack_floats(uv_acc, raw_data(uvs), uint(n * 2))
    }
    defer if uvs != nil { delete(uvs) }

    gm.data.vertices = make([dynamic]R3D_Vertex, 0, n)
    for i in 0 ..< n {
        v := R3D_Vertex{
            pos    = {positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]},
            normal = {0, 1, 0},
            uv     = {0, 0},
        }
        if normals != nil {
            v.normal = {normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2]}
        }
        if uvs != nil {
            // glTF uv origin is top-left; engine textures (stb) are top-left too,
            // so v passes through unflipped.
            v.uv = {uvs[i * 2], uvs[i * 2 + 1]}
        }
        append(&gm.data.vertices, v)
    }

    // indices (unpack to u32 regardless of source component size)
    if p.indices != nil {
        count := int(p.indices.count)
        gm.data.indices = make([dynamic]u32, 0, count)
        raw := make([]u32, count)
        defer delete(raw)
        got := cgltf.accessor_unpack_indices(p.indices, raw_data(raw), 4, uint(count))
        for i in 0 ..< int(got) { append(&gm.data.indices, raw[i]) }
    } else {
        // non-indexed: sequential
        gm.data.indices = make([dynamic]u32, 0, n)
        for i in 0 ..< n { append(&gm.data.indices, u32(i)) }
    }

    // fallback: flat-shade compute normals when the file ships none
    if normals == nil {
        gltf_compute_flat_normals(&gm.data)
    }
    return
}

@(private)
gltf_compute_flat_normals :: proc(d: ^R3D_Mesh_Data) {
    // accumulate face normals onto vertices (smooth where indices are shared)
    for i := 0; i + 2 < len(d.indices); i += 3 {
        i0 := d.indices[i]
        i1 := d.indices[i + 1]
        i2 := d.indices[i + 2]
        a := d.vertices[i0].pos
        b := d.vertices[i1].pos
        c := d.vertices[i2].pos
        n := linalg.normalize(linalg.cross(b - a, c - a))
        d.vertices[i0].normal += n
        d.vertices[i1].normal += n
        d.vertices[i2].normal += n
    }
    for &v in d.vertices {
        v.normal = linalg.normalize(v.normal)
    }
}
