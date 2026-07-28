package main

// Temporary smoke test for the gl3d backend (deleted after verification).

import "core:fmt"
import "core:os"
import "core:math/linalg"
import SDL "vendor:sdl2"
import ve "../../src/core"

G: struct {
    e:      ^ve.Engine,
    r:      ^ve.GL3D_Renderer,
    floor:  u32,
    floor_n: u32,
    crystal: u32,
    crystal_n: u32,
    frames: int,
}

init :: proc(e: ^ve.Engine) {
    G.e = e
    G.r = ve.gl3d_init(e.config.width, e.config.height)
    base :: "examples/void3d/assets"
    ok: bool
    G.floor, _, _, ok = ve.gl3d_load_texture(base + "/grid.png", true)
    if !ok { fmt.eprintln("grid load failed") }
    G.floor_n, _, _, _ = ve.gl3d_load_texture(base + "/grid_n.png", true)
    G.crystal, _, _, _ = ve.gl3d_load_texture(base + "/crystal.png")
    G.crystal_n, _, _, _ = ve.gl3d_load_texture(base + "/crystal_n.png")
}

render :: proc(e: ^ve.Engine, _: ^SDL.Renderer) {
    G.frames += 1
    cam := ve.R3D_Camera{
        position = {0, 2.5, 7},
        yaw      = 0,
        pitch    = -0.3,
        fov_y    = 1.05,
        near_z   = 0.1,
        far_z    = 100,
    }
    ve.gl3d_begin_frame(G.r)
    ve.gl3d_set_camera(G.r, &cam)
    ve.gl3d_clear_lights(G.r)
    ve.gl3d_add_light(G.r, ve.R3D_Light{position = {2, 3, 4}, color = {0, 3.6, 4}, radius = 10})
    ve.gl3d_add_light(G.r, ve.R3D_Light{position = {-3, 2, 2}, color = {4, 0.9, 3.2}, radius = 10})

    fo := ve.r3d_default_sprite_options()
    fo.billboard = .FlatXZ
    fo.uv_rect = {0, 0, 8, 8}
    ve.gl3d_draw_sprite_opts(G.r, G.floor, G.floor_n, {0, 0, 0}, {16, 16}, fo)

    co := ve.r3d_default_sprite_options()
    co.emissive = 0.4
    ve.gl3d_draw_sprite_opts(G.r, G.crystal, G.crystal_n, {0, 1, 0}, {1.2, 1.8}, co)

    ve.gl3d_end_frame(G.r)

    if G.frames == 30 {
        w := int(G.r.width)
        h := int(G.r.height)
        px := make([]u8, w * h * 4)
        ve.gl3d_read_screen(G.r, px)
        // quick sanity: count non-background pixels
        lit := 0
        for i in 0 ..< w * h {
            r := px[i * 4]
            g := px[i * 4 + 1]
            b := px[i * 4 + 2]
            if int(r) + int(g) + int(b) > 40 {
                lit += 1
            }
        }
        fmt.printfln("SMOKE: frame=%d lit_pixels=%d/%d (%.1f%%)", G.frames, lit, w * h, 100.0 * f64(lit) / f64(w * h))
        // dump PPM for visual check
        f, ferr := os.open("/tmp/gl3dsmoke.ppm", {.Write, .Create, .Trunc})
        if ferr == nil {
            hdr := fmt.aprintf("P6\n%d %d\n255\n", w, h)
            os.write_string(f, hdr)
            row := make([]u8, w * 3)
            for y in 0 ..< h {
                sy := h - 1 - y
                for x in 0 ..< w {
                    row[x*3+0] = px[(sy*w+x)*4+0]
                    row[x*3+1] = px[(sy*w+x)*4+1]
                    row[x*3+2] = px[(sy*w+x)*4+2]
                }
                os.write(f, row)
            }
            os.close(f)
            fmt.println("SMOKE: wrote /tmp/gl3dsmoke.ppm")
        }
        e.running = false
    }
}

main :: proc() {
    e := ve.engine_init(ve.EngineConfig{
        title = "gl3d smoke",
        width = 640,
        height = 360,
        target_fps = 120,
        use_opengl = true,
        gl_vsync = 0,
    })
    defer ve.engine_shutdown(e)
    e.game_api = ve.GameAPI{init = init, render = render}
    ve.engine_run(e)
}
