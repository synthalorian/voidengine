package voidengine_test

// Tests for gltf.odin: builds a minimal binary glTF (.glb) fixture in memory,
// writes it to a temp file, and verifies the loader decodes positions,
// normals, uvs, indices, mesh name, and material baseColorFactor.

import "core:os"
import "core:testing"
import "core:math/linalg"
import engine "../src/core"

@(private)
glb_u32 :: proc(buf: ^[dynamic]u8, v: u32) {
    append(buf, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))
}

@(private)
glb_f32 :: proc(buf: ^[dynamic]u8, v: f32) {
    glb_u32(buf, transmute(u32)v)
}

@(private)
glb_u16 :: proc(buf: ^[dynamic]u8, v: u16) {
    append(buf, u8(v), u8(v >> 8))
}

@(private)
glb_bytes :: proc(buf: ^[dynamic]u8, s: string) {
    for i in 0 ..< len(s) { append(buf, s[i]) }
}

@(private)
pad4 :: proc(buf: ^[dynamic]u8, pad: u8) {
    for len(buf) % 4 != 0 { append(buf, pad) }
}

// Build a one-triangle glb: positions/normals/uvs + u16 indices + pink material.
@(private)
build_triangle_glb :: proc() -> []u8 {
    json := `{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"TriNode","mesh":0,"translation":[10,5,-2]}],` +
        `"meshes":[{"name":"Tri","primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"indices":3,"material":0}]}],` +
        `"materials":[{"pbrMetallicRoughness":{"baseColorFactor":[1.0,0.2,0.8,1.0]}}],` +
        `"accessors":[` +
        `{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},` +
        `{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},` +
        `{"bufferView":2,"componentType":5126,"count":3,"type":"VEC2"},` +
        `{"bufferView":3,"componentType":5123,"count":3,"type":"SCALAR"}],` +
        `"bufferViews":[` +
        `{"buffer":0,"byteOffset":0,"byteLength":36},` +
        `{"buffer":0,"byteOffset":36,"byteLength":36},` +
        `{"buffer":0,"byteOffset":72,"byteLength":24},` +
        `{"buffer":0,"byteOffset":96,"byteLength":6}],` +
        `"buffers":[{"byteLength":104}]}`

    bin: [dynamic]u8
    // positions: (0,0,0) (1,0,0) (0,1,0)
    glb_f32(&bin, 0); glb_f32(&bin, 0); glb_f32(&bin, 0)
    glb_f32(&bin, 1); glb_f32(&bin, 0); glb_f32(&bin, 0)
    glb_f32(&bin, 0); glb_f32(&bin, 1); glb_f32(&bin, 0)
    // normals: all (0,0,1)
    for _ in 0 ..< 3 { glb_f32(&bin, 0); glb_f32(&bin, 0); glb_f32(&bin, 1) }
    // uvs: (0,0) (1,0) (0,1)
    glb_f32(&bin, 0); glb_f32(&bin, 0)
    glb_f32(&bin, 1); glb_f32(&bin, 0)
    glb_f32(&bin, 0); glb_f32(&bin, 1)
    // indices u16: 0,1,2 + pad
    glb_u16(&bin, 0); glb_u16(&bin, 1); glb_u16(&bin, 2); glb_u16(&bin, 0)

    out: [dynamic]u8
    // header (length patched after chunks)
    glb_u32(&out, 0x46546C67) // "glTF"
    glb_u32(&out, 2)
    glb_u32(&out, 0)
    // JSON chunk
    json_start := len(out)
    glb_u32(&out, 0)
    glb_u32(&out, 0x4E4F534A) // "JSON"
    glb_bytes(&out, json)
    pad4(&out, ' ')
    json_len := u32(len(out) - json_start - 8)
    // BIN chunk
    bin_start := len(out)
    glb_u32(&out, u32(len(bin)))
    glb_u32(&out, 0x004E4942) // "BIN\0"
    for b in bin { append(&out, b) }
    pad4(&out, 0)
    bin_len := u32(len(out) - bin_start - 8)
    // patch lengths
    total := u32(len(out))
    out[8] = u8(total); out[9] = u8(total >> 8); out[10] = u8(total >> 16); out[11] = u8(total >> 24)
    out[json_start] = u8(json_len); out[json_start + 1] = u8(json_len >> 8)
    out[json_start + 2] = u8(json_len >> 16); out[json_start + 3] = u8(json_len >> 24)
    out[bin_start] = u8(bin_len); out[bin_start + 1] = u8(bin_len >> 8)
    out[bin_start + 2] = u8(bin_len >> 16); out[bin_start + 3] = u8(bin_len >> 24)

    delete(bin)
    return out[:]
}

@(test)
gltf_loads_triangle :: proc(t: ^testing.T) {
    glb := build_triangle_glb()
    defer delete(glb)
    path := "/tmp/voidengine_test_tri.glb"
    testing.expect(t, os.write_entire_file(path, glb) == nil, "write fixture")

    model, ok := engine.r3d_gltf_load(path)
    defer engine.r3d_gltf_destroy(&model)
    testing.expect(t, ok, "load must succeed")
    if !ok { return }
    testing.expect_value(t, len(model.meshes), 1)
    if len(model.meshes) == 0 { return }

    m := model.meshes[0]
    testing.expect_value(t, m.name, "TriNode")
    testing.expect_value(t, len(m.data.vertices), 3)
    testing.expect_value(t, len(m.data.indices), 3)

    // node translation [10,5,-2] must be flattened into vertex positions
    v0 := m.data.vertices[0]
    testing.expect(t, abs(v0.pos.x - 10) < 1e-4 && abs(v0.pos.y - 5) < 1e-4 && abs(v0.pos.z + 2) < 1e-4,
        "v0 translated by node")
    v1 := m.data.vertices[1]
    testing.expect(t, abs(v1.pos.x - 11) < 1e-4 && abs(v1.pos.y - 5) < 1e-4, "pos1.x == 11 after node transform")
    v2 := m.data.vertices[2]
    testing.expect(t, abs(v2.pos.y - 6) < 1e-4, "pos2.y == 6 after node transform")
    testing.expect(t, abs(m.data.vertices[0].normal.z - 1) < 1e-6, "normal (0,0,1)")
    testing.expect(t, abs(v1.uv.x - 1) < 1e-6, "uv1.x == 1")

    testing.expect_value(t, m.data.indices[2], u32(2))
    want_tint := linalg.Vector4f32{1, 0.2, 0.8, 1}
    for i in 0 ..< 4 {
        testing.expect(t, abs(m.tint[i] - want_tint[i]) < 1e-4, "baseColorFactor tint")
    }
}
