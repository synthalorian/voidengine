package main

// ============================================================================
// void3d — VoidEngine 3D sprite rendering showcase
//
// Pushes the engine's gl3d (OpenGL 3.3) and vk3d (Vulkan) backends:
//   - lit, normal-mapped billboard sprites (spherical + cylindrical)
//   - HDR point lights with distance attenuation
//   - bloom / tonemap / vignette post chain
//   - tiled 3D floor, animated sprite-sheet billboard, rotating rune ring
//
// Controls:
//   Left/Right  orbit camera      Up/Down  camera height
//   B           toggle bloom      +/-      exposure
//   Esc         quit
//
// Flags:
//   --backend gl|vk   renderer backend (default gl)
//   --bench N         run N frames, print FPS stats, exit
//   --shot <path>     dump a PPM screenshot ~1s in (GL backend only)
// ============================================================================

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:math/linalg"
import SDL "vendor:sdl2"
import ve "../../src/core"

Backend :: enum { GL, VK }

// Texture handle that works for either backend.
TexHandle :: struct {
    gl: u32,
    vk: ve.VK3D_Texture,
}

Renderer :: struct {
    backend: Backend,
    gl:      ^ve.GL3D_Renderer,
    vk:      ^ve.VK3D_Renderer,
}

// ----------------------------------------------------------------------------
// Backend wrapper
// ----------------------------------------------------------------------------

r_load_texture :: proc(r: ^Renderer, path: string, repeat := false) -> (TexHandle, bool) {
    h: TexHandle
    switch r.backend {
    case .GL:
        tex, _, _, ok := ve.gl3d_load_texture(path, repeat)
        if !ok { return h, false }
        h.gl = tex
    case .VK:
        tex, _, _, ok := ve.vk3d_load_texture(r.vk, path, repeat)
        if !ok { return h, false }
        h.vk = tex
    }
    return h, true
}

r_set_camera :: proc(r: ^Renderer, cam: ^ve.R3D_Camera) {
    switch r.backend {
    case .GL: ve.gl3d_set_camera(r.gl, cam)
    case .VK: ve.vk3d_set_camera(r.vk, cam)
    }
}

r_set_ambient :: proc(r: ^Renderer, ambient: linalg.Vector3f32) {
    switch r.backend {
    case .GL: ve.gl3d_set_ambient(r.gl, ambient)
    case .VK: ve.vk3d_set_ambient(r.vk, ambient)
    }
}

r_clear_lights :: proc(r: ^Renderer) {
    switch r.backend {
    case .GL: ve.gl3d_clear_lights(r.gl)
    case .VK: ve.vk3d_clear_lights(r.vk)
    }
}

r_add_light :: proc(r: ^Renderer, light: ve.R3D_Light) {
    switch r.backend {
    case .GL: ve.gl3d_add_light(r.gl, light)
    case .VK: ve.vk3d_add_light(r.vk, light)
    }
}

r_begin_frame :: proc(r: ^Renderer) -> bool {
    switch r.backend {
    case .GL: ve.gl3d_begin_frame(r.gl)
    case .VK: if !ve.vk3d_begin_frame(r.vk) { return false }
    }
    return true
}

r_end_frame :: proc(r: ^Renderer) {
    switch r.backend {
    case .GL: ve.gl3d_end_frame(r.gl)
    case .VK: ve.vk3d_end_frame(r.vk)
    }
}

r_set_post :: proc(r: ^Renderer, bloom: bool, exposure: f32) {
    switch r.backend {
    case .GL:
        r.gl.bloom = bloom
        r.gl.exposure = exposure
    case .VK:
        r.vk.bloom = bloom
        r.vk.exposure = exposure
    }
}

r_resize :: proc(r: ^Renderer, w, h: i32) {
    switch r.backend {
    case .GL: ve.gl3d_resize(r.gl, w, h)
    case .VK: ve.vk3d_resize(r.vk, w, h)
    }
}

// ----------------------------------------------------------------------------
// Game state
// ----------------------------------------------------------------------------

Game :: struct {
    e:           ^ve.Engine,
    r:           Renderer,

    // textures
    crystal:     TexPair,
    orb:         TexPair,
    rune:        TexPair,
    grid:        TexPair,
    ship:        TexPair,

    // scene
    cam:         ve.R3D_Camera,
    time:        f64,
    orbit_angle: f64,
    orbit_height: f32,
    bloom:       bool,
    exposure:    f32,

    // bench / screenshot
    bench_frames: int,
    frame_count:  int,
    fps_accum:    f64,
    fps_min_dt:   f64,
    fps_max_dt:   f64,
    shot_path:    string,

    assets:      string,
}

TexPair :: struct {
    diffuse: TexHandle,
    normal:  TexHandle, // zero = flat
    has_normal: bool,
}

// draw a TexPair through the wrapper
rp_draw :: proc(g: ^Game, tp: ^TexPair, pos: linalg.Vector3f32, size: linalg.Vector2f32, opts: ve.R3D_Sprite_Options) {
    switch g.r.backend {
    case .GL: ve.gl3d_draw_sprite_opts(g.r.gl, tp.diffuse.gl, tp.normal.gl, pos, size, opts)
    case .VK: ve.vk3d_draw_sprite_opts(g.r.vk, tp.diffuse.vk, tp.normal.vk, pos, size, opts)
    }
}

// ----------------------------------------------------------------------------
// Init
// ----------------------------------------------------------------------------

load_pair :: proc(g: ^Game, name: string, repeat := false) -> TexPair {
    tp: TexPair
    path := fmt.tprintf("%s/%s.png", g.assets, name)
    diff, ok := r_load_texture(&g.r, path, repeat)
    if !ok {
        fmt.eprintln("void3d: failed to load", path)
        return tp
    }
    tp.diffuse = diff

    npath := fmt.tprintf("%s/%s_n.png", g.assets, name)
    if os.exists(npath) {
        norm, nok := r_load_texture(&g.r, npath, repeat)
        if nok {
            tp.normal = norm
            tp.has_normal = true
        }
    }
    return tp
}

game_init :: proc(e: ^ve.Engine) {
    g := cast(^Game)e.user_data

    // init renderer backend
    if g.r.backend == .GL {
        g.r.gl = ve.gl3d_init(e.config.width, e.config.height)
        if g.r.gl == nil {
            fmt.eprintln("void3d: gl3d_init failed")
            e.running = false
            return
        }
    } else {
        shader_dir := fmt.tprintf("%s/shaders", g.assets)
        g.r.vk = ve.vk3d_init(e.window, e.config.width, e.config.height, shader_dir)
        if g.r.vk == nil {
            fmt.eprintln("void3d: vk3d_init failed")
            e.running = false
            return
        }
    }

    // resolve assets dir (run from repo root or from example dir)
    if !os.exists(g.assets) {
        if os.exists("examples/void3d/assets") {
            g.assets = "examples/void3d/assets"
        } else {
            g.assets = "assets"
        }
    }

    g.grid    = load_pair(g, "grid", repeat = true)
    g.crystal = load_pair(g, "crystal")
    g.orb     = load_pair(g, "orb")
    g.rune    = load_pair(g, "rune")
    g.ship    = load_pair(g, "ship_sheet")

    g.cam = ve.R3D_Camera{
        position = {9, 3.2, 0},
        fov_y    = math.to_radians(60.0),
        near_z   = 0.1,
        far_z    = 100.0,
    }
    g.orbit_angle = 0.6
    g.orbit_height = 3.2
    g.bloom = true
    g.exposure = 1.1

    r_set_ambient(&g.r, {0.10, 0.07, 0.16})
    fmt.println("void3d ready — backend:", g.r.backend)
}

// ----------------------------------------------------------------------------
// Update
// ----------------------------------------------------------------------------

game_update :: proc(e: ^ve.Engine, dt: f64) {
    g := cast(^Game)e.user_data
    g.time += dt

    input := &e.input

    if ve.input_is_key_pressed(input, .ESCAPE) {
        e.running = false
    }
    if ve.input_is_key_pressed(input, .B) {
        g.bloom = !g.bloom
    }
    if ve.input_is_key_held(input, .LEFT) {
        g.orbit_angle -= dt * 1.5
    }
    if ve.input_is_key_held(input, .RIGHT) {
        g.orbit_angle += dt * 1.5
    }
    if ve.input_is_key_held(input, .UP) {
        g.orbit_height = min(g.orbit_height + f32(dt * 3), 12)
    }
    if ve.input_is_key_held(input, .DOWN) {
        g.orbit_height = max(g.orbit_height - f32(dt * 3), 0.5)
    }
    if ve.input_is_key_pressed(input, .EQUALS) {
        g.exposure = min(g.exposure + 0.1, 3.0)
    }
    if ve.input_is_key_pressed(input, .MINUS) {
        g.exposure = max(g.exposure - 0.1, 0.2)
    }
}

// ----------------------------------------------------------------------------
// Render
// ----------------------------------------------------------------------------

game_render :: proc(e: ^ve.Engine, _: ^SDL.Renderer) {
    g := cast(^Game)e.user_data
    t := f32(g.time)
    bench := g.bench_frames > 0
    if bench {
        t = 1.0  // deterministic scene for benchmarking
    }

    // --- camera orbit ---
    angle := g.orbit_angle + (bench ? 0.0 : f64(t) * 0.25)
    radius: f32 = 9.0
    cam_pos := linalg.Vector3f32{
        radius * f32(math.cos(angle)),
        g.orbit_height,
        radius * f32(math.sin(angle)),
    }
    target := linalg.Vector3f32{0, 1.2, 0}
    dir := target - cam_pos
    dir_len := linalg.length(dir)
    g.cam.position = cam_pos
    g.cam.yaw   = f32(math.atan2(dir.x, -dir.z))
    g.cam.pitch = f32(math.asin(dir.y / dir_len))

    if !r_begin_frame(&g.r) {
        return  // vk swapchain out of date; skip
    }

    r_set_camera(&g.r, &g.cam)
    r_clear_lights(&g.r)

    // --- 3 orbiting HDR point lights (cyan / magenta / orange) ---
    light_colors := [?]linalg.Vector3f32{
        {0.0, 3.6, 4.0},   // cyan
        {4.0, 0.9, 3.2},   // magenta
        {4.0, 2.4, 0.9},   // orange
    }
    for i in 0 ..< 3 {
        a := t * (0.5 + 0.2 * f32(i)) + f32(i) * 2.1
        r_add_light(&g.r, ve.R3D_Light{
            position = {4.0 * math.cos(a), 1.4 + f32(i) * 0.9, 4.0 * math.sin(a)},
            color    = light_colors[i],
            radius   = 9.0,
        })
    }

    // --- floor: one big tiled quad ---
    floor_opts := ve.r3d_default_sprite_options()
    floor_opts.billboard = .FlatXZ
    floor_opts.uv_rect = {0, 0, 20, 20}
    floor_opts.spec_strength = 0.9
    floor_opts.shininess = 48
    rp_draw(g, &g.grid, {0, 0, 0}, {40, 40}, floor_opts)

    // --- ring of crystals (spherical billboards, normal-mapped, pulsing) ---
    for i in 0 ..< 12 {
        a := f32(i) * math.TAU / 12
        pulse := 0.5 + 0.5 * math.sin(t * 2.0 + f32(i) * 1.3)
        opts := ve.r3d_default_sprite_options()
        opts.emissive = 0.25 + 0.55 * pulse
        opts.rotation = t * 0.4 + f32(i)
        opts.spec_strength = 1.0
        opts.shininess = 64
        // hue variation: cyan -> violet tint
        tint_t := 0.5 + 0.5 * math.sin(f32(i) * 2.7)
        opts.color = {1.0, 1.0 - 0.25 * tint_t, 1.0, 1.0}
        pos := linalg.Vector3f32{6.0 * math.cos(a), 1.0 + 0.3 * pulse, 6.0 * math.sin(a)}
        rp_draw(g, &g.crystal, pos, {1.2, 1.8}, opts)
    }

    // --- floating orbs (bright emissive -> bloom) ---
    for i in 0 ..< 8 {
        a := f32(i) * math.TAU / 8 + t * 0.3
        bob := 0.4 * math.sin(t * 1.7 + f32(i) * 2.0)
        opts := ve.r3d_default_sprite_options()
        opts.emissive = 1.8
        opts.spec_strength = 0.3
        pos := linalg.Vector3f32{3.5 * math.cos(a), 2.2 + bob, 3.5 * math.sin(a)}
        rp_draw(g, &g.orb, pos, {0.55, 0.55}, opts)
    }

    // --- center: spinning rune ring ---
    rune_opts := ve.r3d_default_sprite_options()
    rune_opts.rotation = t * 0.5
    rune_opts.emissive = 0.9
    rune_opts.spec_strength = 1.2
    rune_opts.shininess = 96
    rp_draw(g, &g.rune, {0, 1.8, 0}, {3.2, 3.2}, rune_opts)

    // --- animated ship circling the scene (cylindrical billboard, 2 frames) ---
    ship_a := t * 0.8
    frame := f32(int(t * 8) % 2)
    ship_opts := ve.r3d_default_sprite_options()
    ship_opts.billboard = .Cylindrical
    ship_opts.uv_rect = {frame * 0.5, 0, 0.5, 1}
    ship_opts.emissive = 0.4
    ship_opts.spec_strength = 0.8
    ship_pos := linalg.Vector3f32{4.5 * math.cos(ship_a), 2.6 + 0.5 * math.sin(t * 2.3), 4.5 * math.sin(ship_a)}
    rp_draw(g, &g.ship, ship_pos, {1.4, 1.4}, ship_opts)

    r_set_post(&g.r, g.bloom, g.exposure)
    r_end_frame(&g.r)

    // --- stats / bench / screenshot ---
    g.frame_count += 1
    dt := e.delta_time
    if dt > 0 {
        g.fps_accum += dt
        if g.fps_min_dt == 0 || dt < g.fps_min_dt { g.fps_min_dt = dt }
        if dt > g.fps_max_dt { g.fps_max_dt = dt }
    }

    if g.frame_count == 60 && len(g.shot_path) > 0 && g.r.backend == .GL {
        save_screenshot_ppm(g, g.shot_path)
    }

    if bench && g.frame_count >= g.bench_frames {
        avg := f64(g.frame_count) / g.fps_accum
        fmt.printfln("BENCH backend=%v frames=%d avg_fps=%.1f worst_fps=%.1f best_fps=%.1f",
            g.r.backend, g.frame_count, avg, 1.0 / g.fps_max_dt, 1.0 / g.fps_min_dt)
        e.running = false
    } else if g.frame_count % 120 == 0 {
        fps := 120.0 / g.fps_accum
        g.fps_accum = 0
        title := fmt.aprintf("void3d [%v] — %.0f fps | arrows: orbit | B: bloom | +/-: exposure", g.r.backend, fps)
        ctitle := strings.clone_to_cstring(title)
        SDL.SetWindowTitle(e.window, ctitle)
        delete(ctitle)
        delete(title)
    }
}

// ----------------------------------------------------------------------------
// Screenshot (GL only): back buffer -> PPM
// ----------------------------------------------------------------------------

save_screenshot_ppm :: proc(g: ^Game, path: string) {
    w := int(g.r.gl.width)
    h := int(g.r.gl.height)
    pixels := make([]u8, w * h * 4)
    defer delete(pixels)
    ve.gl3d_read_screen(g.r.gl, pixels)

    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
    fmt.sbprintf(&sb, "P6\n%d %d\n255\n", w, h)
    header := strings.to_string(sb)

    f, err := os.open(path, {.Write, .Create, .Trunc})
    if err != nil {
        fmt.eprintln("void3d: cannot write screenshot:", path)
        return
    }
    defer os.close(f)
    os.write_string(f, header)
    row := make([]u8, w * 3)
    defer delete(row)
    // GL rows are bottom-first; flip, and drop alpha
    for y in 0 ..< h {
        src_y := h - 1 - y
        for x in 0 ..< w {
            row[x * 3 + 0] = pixels[(src_y * w + x) * 4 + 0]
            row[x * 3 + 1] = pixels[(src_y * w + x) * 4 + 1]
            row[x * 3 + 2] = pixels[(src_y * w + x) * 4 + 2]
        }
        os.write(f, row)
    }
    fmt.println("void3d: screenshot ->", path)
}

// ----------------------------------------------------------------------------
// Events / shutdown
// ----------------------------------------------------------------------------

game_handle_event :: proc(e: ^ve.Engine, event: ^SDL.Event) -> bool {
    g := cast(^Game)e.user_data
    if event.type == .WINDOWEVENT && event.window.event == .RESIZED {
        w, h := event.window.data1, event.window.data2
        if w > 0 && h > 0 {
            r_resize(&g.r, w, h)
        }
    }
    return true
}

game_shutdown :: proc(e: ^ve.Engine) {
    g := cast(^Game)e.user_data
    switch g.r.backend {
    case .GL: ve.gl3d_shutdown(g.r.gl)
    case .VK: ve.vk3d_shutdown(g.r.vk)
    }
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------

main :: proc() {
    backend := Backend.GL
    bench := 0
    shot := ""

    args := os.args
    for i in 1 ..< len(args) {
        arg := args[i]
        switch {
        case arg == "--backend" && i + 1 < len(args):
            i += 1
            if args[i] == "vk" || args[i] == "vulkan" {
                backend = .VK
            }
        case arg == "--bench" && i + 1 < len(args):
            i += 1
            fmt.sscanf(args[i], "%d", &bench)
        case arg == "--shot" && i + 1 < len(args):
            i += 1
            shot = args[i]
        }
    }

    config := ve.EngineConfig{
        title = "void3d — VoidEngine 3D sprite showcase",
        width = 1280,
        height = 720,
        target_fps = 240.0,   // let the backends breathe
        enable_hot_reload = false,
        asset_path = "assets",
        app_id = "voidengine-void3d",
        use_opengl = backend == .GL,
        gl_vsync = 1,
        use_vulkan = backend == .VK,
    }

    e := ve.engine_init(config)
    defer ve.engine_shutdown(e)

    g := new(Game)
    g.e = e
    g.r.backend = backend
    g.bench_frames = bench
    g.shot_path = shot
    g.assets = "examples/void3d/assets"
    e.user_data = g

    e.game_api = ve.GameAPI{
        init = game_init,
        update = game_update,
        render = game_render,
        shutdown = game_shutdown,
        handle_event = game_handle_event,
    }

    ve.engine_run(e)
}
