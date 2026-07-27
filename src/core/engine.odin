package voidengine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import "core:dynlib"
import "core:time"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import SDL "vendor:sdl2"
import MIX "vendor:sdl2/mixer"

// ============================================================================
// Engine Configuration
// ============================================================================
EngineConfig :: struct {
    title: string,
    width: i32,
    height: i32,
    target_fps: f64,
    enable_hot_reload: bool,
    asset_path: string,
    // Wayland app_id / desktop-file id (for taskbar icon association); may be empty
    app_id: string,
    // Linux shared library path for hot reload
    game_so_path: string,
}

// ============================================================================
// Main Engine Struct
// ============================================================================
Engine :: struct {
    config: EngineConfig,
    window: ^SDL.Window,
    renderer: ^SDL.Renderer,
    running: bool,
    delta_time: f64,
    last_frame_time: f64,
    
    // Subsystems
    input: InputState,
    scene: SceneManager,
    audio: AudioEngine,
    textures: TextureManager,
    
    // Hot reload
    game_dll: dynlib.Library,
    game_api: GameAPI,
    last_dll_write_time: time.Time,
    
    // Frame timing
    accumulator: f64,
    fixed_timestep: f64,
    
    // User data pointer for game state (avoids global state)
    user_data: rawptr,
}

// ============================================================================
// Game API for Hot-Reloadable Game Code
// ============================================================================
GameAPI :: struct {
    init: proc(^Engine),
    update: proc(^Engine, f64),
    render: proc(^Engine, ^SDL.Renderer),
    shutdown: proc(^Engine),
    handle_event: proc(^Engine, ^SDL.Event) -> bool,
}

// ============================================================================
// Input State Tracking
// ============================================================================
InputState :: struct {
    keys: [512]bool,
    keys_prev: [512]bool,
    mouse_x: i32,
    mouse_y: i32,
    mouse_dx: i32,
    mouse_dy: i32,
    mouse_buttons: [8]bool,
    mouse_buttons_prev: [8]bool,
    // gamepad (first connected controller, hot-polled each frame)
    pad: ^SDL.GameController,
    pad_buttons: [15]bool,
    pad_prev: [15]bool,
    pad_lx: f32,
    pad_ly: f32,
}

// ============================================================================
// Scene Management
// ============================================================================
SceneManager :: struct {
    current_scene: ^Scene,
    scenes: [dynamic]^Scene,
    transition_active: bool,
    transition_time: f64,
}

Scene :: struct {
    name: string,
    init: proc(^Scene),
    update: proc(^Scene, f64),
    render: proc(^Scene, ^SDL.Renderer),
    shutdown: proc(^Scene),
    entities: [dynamic]^Entity,
    engine: ^Engine,
}

// ============================================================================
// Entity-Component-System (ECS)
// ============================================================================
Entity :: struct {
    id: u64,
    active: bool,
    components: map[typeid]rawptr,
}

// --- Common Components ---

// 2D position, rotation, and scale
Transform :: struct {
    position: linalg.Vector2f32,
    rotation: f32,       // radians
    scale: linalg.Vector2f32,
}

// Sprite rendering info.
// If texture is nil the sprite renders as a filled colored rect.
// color doubles as RGBA modulation for textured sprites.
Sprite :: struct {
    color: SDL.Color,
    width: i32,
    height: i32,
    texture: ^SDL.Texture,
    flip: SDL.RendererFlip,
}

// 2D linear velocity
Velocity :: struct {
    linear: linalg.Vector2f32,
    angular: f32,
}

// Axis-aligned bounding box collider
Collider :: struct {
    width: f32,
    height: f32,
    offset: linalg.Vector2f32,  // offset from transform position
    layer: CollisionLayer,
    mask: CollisionMask,
}

CollisionLayer :: enum {
    None,
    Player,
    PlayerBullet,
    Enemy,
    EnemyBullet,
    PowerUp,
    Wall,
}

CollisionMask :: bit_set[CollisionLayer]

// ============================================================================
// Audio Engine (SDL_mixer)
// ============================================================================
AudioEngine :: struct {
    initialized: bool,
    master_volume: f32,
    // Loaded sounds and music
    sounds: map[string]^MIX.Chunk,
    music: map[string]^MIX.Music,
    // Current music track
    current_music: ^MIX.Music,
}

// ============================================================================
// Engine Initialization
// ============================================================================
engine_init :: proc(config: EngineConfig) -> ^Engine {
    engine := new(Engine)
    engine.config = config
    engine.fixed_timestep = 1.0 / 60.0
    
    // Set the app id (Wayland app_id via sdl2-compat -> SDL3) so the window
    // associates with its .desktop entry on Linux. Must be set before SDL.Init.
    if config.app_id != "" {
        SDL.SetHint("SDL_APP_ID", strings.clone_to_cstring(config.app_id))
    }

    // Initialize SDL
    if SDL.Init(SDL.INIT_VIDEO | SDL.INIT_AUDIO | SDL.INIT_TIMER | SDL.INIT_GAMECONTROLLER) != 0 {
        fmt.eprintln("SDL_Init failed:", SDL.GetError())
        os.exit(1)
    }
    
    // Create window
    engine.window = SDL.CreateWindow(
        strings.clone_to_cstring(config.title),
        SDL.WINDOWPOS_CENTERED,
        SDL.WINDOWPOS_CENTERED,
        config.width,
        config.height,
        SDL.WINDOW_SHOWN | SDL.WINDOW_RESIZABLE,
    )
    if engine.window == nil {
        fmt.eprintln("SDL_CreateWindow failed:", SDL.GetError())
        os.exit(1)
    }
    
    // Create renderer
    engine.renderer = SDL.CreateRenderer(
        engine.window,
        -1,
        SDL.RENDERER_ACCELERATED | SDL.RENDERER_PRESENTVSYNC,
    )
    if engine.renderer == nil {
        fmt.eprintln("SDL_CreateRenderer failed:", SDL.GetError())
        os.exit(1)
    }

    // Enable alpha blending so draw_rect alpha (HUD panels, overlays,
    // particles) actually blends instead of rendering opaque.
    SDL.SetRenderDrawBlendMode(engine.renderer, .BLEND)
    
    // Initialize input
    engine.input = InputState{}

    // first connected gamepad, if any
    for i in 0 ..< SDL.NumJoysticks() {
        if SDL.IsGameController(i) {
            engine.input.pad = SDL.GameControllerOpen(i)
            if engine.input.pad != nil {
                fmt.println("Gamepad connected:", SDL.GameControllerName(engine.input.pad))
            }
            break
        }
    }
    
    // Initialize scene manager
    engine.scene = SceneManager{
        scenes = make([dynamic]^Scene),
    }
    
    // Initialize audio
    audio_init(&engine.audio)
    
    // Initialize texture manager
    texture_manager_init(&engine.textures, engine.renderer)
    
    engine.running = true
    engine.last_frame_time = f64(time.now()._nsec) / 1e9
    
    fmt.println("VoidEngine initialized")
    fmt.println("   Resolution:", config.width, "x", config.height)
    fmt.println("   Hot reload:", config.enable_hot_reload)
    
    return engine
}

// ============================================================================
// Engine Shutdown
// ============================================================================
engine_shutdown :: proc(engine: ^Engine) {
    if engine.game_api.shutdown != nil {
        engine.game_api.shutdown(engine)
    }
    
    if engine.game_dll != nil {
        dynlib.unload_library(engine.game_dll)
    }
    
    audio_shutdown(&engine.audio)
    
    // Tear down all scenes (frees entities, components, scene structs)
    for len(engine.scene.scenes) > 0 {
        scene_destroy(engine.scene.scenes[len(engine.scene.scenes) - 1])
    }
    delete(engine.scene.scenes)
    
    texture_manager_shutdown(&engine.textures)
    
    SDL.DestroyRenderer(engine.renderer)
    SDL.DestroyWindow(engine.window)
    SDL.Quit()
    
    free(engine)
    fmt.println("VoidEngine shutdown complete")
}

// ============================================================================
// Main Game Loop
// ============================================================================
engine_run :: proc(engine: ^Engine) {
    event: SDL.Event

    if engine.game_api.init != nil {
        engine.game_api.init(engine)
    }

    for engine.running {
        // Calculate delta time
        current_time := f64(time.now()._nsec) / 1e9
        engine.delta_time = current_time - engine.last_frame_time
        engine.last_frame_time = current_time
        
        // Cap delta time to prevent spiral of death
        if engine.delta_time > 0.25 {
            engine.delta_time = 0.25
        }
        
        // Process input
        input_update_prev_state(&engine.input)
        input_poll_pad(&engine.input)
        
        for SDL.PollEvent(&event) {
            if event.type == SDL.EventType.QUIT {
                engine.running = false
            }
            
            input_process_event(&engine.input, &event)
            
            // Pass to game code
            if engine.game_api.handle_event != nil {
                if !engine.game_api.handle_event(engine, &event) {
                    engine.running = false
                }
            }
        }
        
        // Hot reload check
        if engine.config.enable_hot_reload {
            engine_check_hot_reload(engine)
        }
        
        // Fixed timestep update
        engine.accumulator += engine.delta_time
        for engine.accumulator >= engine.fixed_timestep {
            if engine.game_api.update != nil {
                engine.game_api.update(engine, engine.fixed_timestep)
            }
            
            if engine.scene.current_scene != nil && engine.scene.current_scene.update != nil {
                engine.scene.current_scene.update(engine.scene.current_scene, engine.fixed_timestep)
            }
            
            engine.accumulator -= engine.fixed_timestep
        }
        
        // Render
        SDL.SetRenderDrawColor(engine.renderer, 20, 20, 30, 255)
        SDL.RenderClear(engine.renderer)
        
        if engine.game_api.render != nil {
            engine.game_api.render(engine, engine.renderer)
        }
        
        if engine.scene.current_scene != nil && engine.scene.current_scene.render != nil {
            engine.scene.current_scene.render(engine.scene.current_scene, engine.renderer)
        }
        
        SDL.RenderPresent(engine.renderer)
        
        // Frame rate limiting
        frame_time := f64(time.now()._nsec) / 1e9 - current_time
        target_frame_time := 1.0 / engine.config.target_fps
        if frame_time < target_frame_time {
            sleep_time := target_frame_time - frame_time
            time.sleep(time.Duration(sleep_time * 1e9))
        }
    }
}

// ============================================================================
// Input Helpers
// ============================================================================
input_update_prev_state :: proc(input: ^InputState) {
    input.keys_prev = input.keys
    input.mouse_buttons_prev = input.mouse_buttons
    input.mouse_dx = 0
    input.mouse_dy = 0
    input.pad_prev = input.pad_buttons
}

PAD_DEADZONE :: 0.25

// hot-poll the pad once per frame (call after input_update_prev_state)
input_poll_pad :: proc(input: ^InputState) {
    if input.pad == nil do return
    for b in 0 ..< 15 {
        input.pad_buttons[b] = SDL.GameControllerGetButton(input.pad, SDL.GameControllerButton(b)) != 0
    }
    DEAD :: 8000
    ax := SDL.GameControllerGetAxis(input.pad, .LEFTX)
    ay := SDL.GameControllerGetAxis(input.pad, .LEFTY)
    input.pad_lx = abs(i32(ax)) > DEAD ? f32(ax) / 32767 : 0
    input.pad_ly = abs(i32(ay)) > DEAD ? f32(ay) / 32767 : 0
}

input_pad_held :: proc(input: ^InputState, button: SDL.GameControllerButton) -> bool {
    idx := int(button)
    if idx < 0 || idx >= 15 do return false
    return input.pad_buttons[idx]
}

input_pad_pressed :: proc(input: ^InputState, button: SDL.GameControllerButton) -> bool {
    idx := int(button)
    if idx < 0 || idx >= 15 do return false
    return input.pad_buttons[idx] && !input.pad_prev[idx]
}

input_pad_move :: proc(input: ^InputState) -> (x, y: f32) {
    return input.pad_lx, input.pad_ly
}

input_process_event :: proc(input: ^InputState, event: ^SDL.Event) {
    #partial switch event.type {
    case SDL.EventType.KEYDOWN:
        if u32(event.key.keysym.scancode) < u32(SDL.NUM_SCANCODES) {
            input.keys[event.key.keysym.scancode] = true
        }
    case SDL.EventType.KEYUP:
        if u32(event.key.keysym.scancode) < u32(SDL.NUM_SCANCODES) {
            input.keys[event.key.keysym.scancode] = false
        }
    case SDL.EventType.MOUSEMOTION:
        input.mouse_dx = event.motion.xrel
        input.mouse_dy = event.motion.yrel
        input.mouse_x = event.motion.x
        input.mouse_y = event.motion.y
    case SDL.EventType.MOUSEBUTTONDOWN:
        if event.button.button < 8 {
            input.mouse_buttons[event.button.button] = true
        }
    case SDL.EventType.MOUSEBUTTONUP:
        if event.button.button < 8 {
            input.mouse_buttons[event.button.button] = false
        }
    }
}

input_is_key_pressed :: proc(input: ^InputState, scancode: SDL.Scancode) -> bool {
    idx := int(scancode)
    if idx < 0 || idx >= 512 {
        return false
    }
    return input.keys[idx] && !input.keys_prev[idx]
}

input_is_key_held :: proc(input: ^InputState, scancode: SDL.Scancode) -> bool {
    idx := int(scancode)
    if idx < 0 || idx >= 512 {
        return false
    }
    return input.keys[idx]
}

input_is_mouse_pressed :: proc(input: ^InputState, button: u8) -> bool {
    if button >= 8 {
        return false
    }
    return input.mouse_buttons[button] && !input.mouse_buttons_prev[button]
}

// ============================================================================
// Hot Reload System (Linux .so)
// ============================================================================
engine_check_hot_reload :: proc(engine: ^Engine) {
    so_path := engine.config.game_so_path
    if so_path == "" {
        so_path = strings.concatenate({engine.config.asset_path, "/game.so"})
    }
    defer if engine.config.game_so_path == "" { delete(so_path) }
    
    if os.exists(so_path) {
        mod_time, err := os.modification_time_by_path(so_path)
        if err == nil && mod_time != engine.last_dll_write_time {
            engine.last_dll_write_time = mod_time
            engine_reload_game_code(engine, so_path)
        }
    }
}

engine_reload_game_code :: proc(engine: ^Engine, so_path: string) {
    fmt.println("[Hot Reload] Reloading game code...")
    
    // Unload old shared library
    if engine.game_dll != nil {
        if engine.game_api.shutdown != nil {
            engine.game_api.shutdown(engine)
        }
        dynlib.unload_library(engine.game_dll)
        engine.game_dll = nil
    }
    
    // Copy .so to a temp file to avoid locking the original on Linux
    temp_path := strings.concatenate({so_path, ".tmp"})
    defer delete(temp_path)
    
    copy_ok := copy_file(so_path, temp_path)
    if !copy_ok {
        fmt.eprintln("[Hot Reload] Failed to copy .so to temp path")
        return
    }
    
    // Load new shared library
    lib, ok := dynlib.load_library(temp_path)
    if !ok {
        fmt.eprintln("[Hot Reload] Failed to load game .so:", dynlib.last_error())
        return
    }
    engine.game_dll = lib
    
    // Load symbols individually via dynlib.symbol_address
    api := GameAPI{}
    
    if sym, found := dynlib.symbol_address(lib, "game_init"); found {
        api.init = (proc(^Engine))(sym)
    }
    if sym, found := dynlib.symbol_address(lib, "game_update"); found {
        api.update = (proc(^Engine, f64))(sym)
    }
    if sym, found := dynlib.symbol_address(lib, "game_render"); found {
        api.render = (proc(^Engine, ^SDL.Renderer))(sym)
    }
    if sym, found := dynlib.symbol_address(lib, "game_shutdown"); found {
        api.shutdown = (proc(^Engine))(sym)
    }
    if sym, found := dynlib.symbol_address(lib, "game_handle_event"); found {
        api.handle_event = (proc(^Engine, ^SDL.Event) -> bool)(sym)
    }
    
    engine.game_api = api
    
    // Call init if present
    if api.init != nil {
        api.init(engine)
    }
    
    fmt.println("[Hot Reload] Game code reloaded successfully")
}

// Simple file copy helper for Linux
@(private)
copy_file :: proc(src, dst: string) -> bool {
    data, err_read := os.read_entire_file_from_path(src, context.temp_allocator)
    if err_read != nil {
        return false
    }
    
    err_write := os.write_entire_file_from_bytes(dst, data)
    return err_write == nil
}

// ============================================================================
// Scene Management Helpers
// ============================================================================
scene_create :: proc(engine: ^Engine, name: string) -> ^Scene {
    scene := new(Scene)
    scene.name = name
    scene.engine = engine
    scene.entities = make([dynamic]^Entity)
    append(&engine.scene.scenes, scene)
    return scene
}

scene_switch :: proc(engine: ^Engine, scene: ^Scene) {
    if engine.scene.current_scene != nil && engine.scene.current_scene.shutdown != nil {
        engine.scene.current_scene.shutdown(engine.scene.current_scene)
    }
    
    engine.scene.current_scene = scene
    
    if scene.init != nil {
        scene.init(scene)
    }
    
    fmt.println("Switched to scene:", scene.name)
}

// ============================================================================
// Entity Helpers
// ============================================================================
entity_create :: proc(scene: ^Scene) -> ^Entity {
    // Heap-allocated so the returned pointer stays valid forever —
    // appending more entities can never realloc-move existing ones.
    entity := new(Entity)
    entity.id = u64(len(scene.entities))
    entity.active = true
    entity.components = make(map[typeid]rawptr)
    append(&scene.entities, entity)
    return entity
}

// entity_add_component attaches a component to an entity.
// OWNERSHIP: the engine takes ownership of `component` — it must be
// heap-allocated (e.g. via `new(T)`) and will be freed by entity_destroy
// or scene_destroy. Do not free it yourself after adding.
entity_add_component :: proc(entity: ^Entity, $T: typeid, component: ^T) {
    entity.components[T] = component
}

entity_get_component :: proc(entity: ^Entity, $T: typeid) -> ^T {
    if ptr, ok := entity.components[T]; ok {
        return (^T)(ptr)
    }
    return nil
}

// entity_destroy frees all components owned by the entity, deletes the
// component map, and marks the entity inactive. The entity slot stays in
// scene.entities so existing pointers into the array remain stable.
// Safe to call multiple times.
entity_destroy :: proc(scene: ^Scene, entity: ^Entity) {
    if entity == nil || !entity.active {
        return
    }
    for _, component in entity.components {
        free(component)
    }
    delete(entity.components)
    entity.components = nil
    entity.active = false
}

// scene_cleanup destroys every entity and frees the entities array.
// Works for stack-allocated scenes (e.g. tests) — does NOT free the
// Scene struct itself or unregister it from the engine.
scene_cleanup :: proc(scene: ^Scene) {
    if scene == nil {
        return
    }
    for entity in scene.entities {
        entity_destroy(scene, entity)
        free(entity)
    }
    delete(scene.entities)
    scene.entities = nil
}

// scene_destroy fully tears down a scene created by scene_create:
// cleans up entities, unregisters from the engine, frees the Scene.
scene_destroy :: proc(scene: ^Scene) {
    if scene == nil {
        return
    }
    scene_cleanup(scene)
    if scene.engine != nil {
        for s, i in scene.engine.scene.scenes {
            if s == scene {
                unordered_remove(&scene.engine.scene.scenes, i)
                break
            }
        }
    }
    free(scene)
}

// ============================================================================
// Component Helpers
// ============================================================================
make_transform :: proc(x, y: f32) -> Transform {
    return Transform{
        position = {x, y},
        rotation = 0,
        scale = {1, 1},
    }
}

make_sprite :: proc(width, height: i32, color: SDL.Color) -> Sprite {
    return Sprite{
        width = width,
        height = height,
        color = color,
    }
}

make_velocity :: proc(vx, vy: f32) -> Velocity {
    return Velocity{
        linear = {vx, vy},
        angular = 0,
    }
}

make_collider :: proc(width, height: f32, layer: CollisionLayer, mask: CollisionMask) -> Collider {
    return Collider{
        width = width,
        height = height,
        offset = {0, 0},
        layer = layer,
        mask = mask,
    }
}

// ============================================================================
// 2D Physics / Collision System
// ============================================================================

// Update positions based on velocity
physics_update :: proc(scene: ^Scene, dt: f64) {
    dt_f32 := f32(dt)
    for entity in scene.entities {
        if !entity.active {
            continue
        }
        transform := entity_get_component(entity, Transform)
        velocity := entity_get_component(entity, Velocity)
        if transform != nil && velocity != nil {
            transform.position.x += velocity.linear.x * dt_f32
            transform.position.y += velocity.linear.y * dt_f32
            transform.rotation += velocity.angular * dt_f32
        }
    }
}

// Simple AABB collision check between two entities
entities_collide :: proc(a, b: ^Entity) -> bool {
    ta := entity_get_component(a, Transform)
    ca := entity_get_component(a, Collider)
    tb := entity_get_component(b, Transform)
    cb := entity_get_component(b, Collider)
    
    if ta == nil || ca == nil || tb == nil || cb == nil {
        return false
    }
    
    // Check layer mask
    if ca.layer not_in cb.mask && cb.layer not_in ca.mask {
        return false
    }
    
    ax := ta.position.x + ca.offset.x - ca.width / 2
    ay := ta.position.y + ca.offset.y - ca.height / 2
    aw := ca.width
    ah := ca.height
    
    bx := tb.position.x + cb.offset.x - cb.width / 2
    by := tb.position.y + cb.offset.y - cb.height / 2
    bw := cb.width
    bh := cb.height
    
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by
}

// Get all colliding pairs in a scene
find_collisions :: proc(scene: ^Scene, allocator := context.allocator) -> [][2]^Entity {
    pairs := make([dynamic][2]^Entity, allocator)
    
    count := len(scene.entities)
    for i in 0..<count {
        a := scene.entities[i]
        if !a.active {
            continue
        }
        for j in i + 1..<count {
            b := scene.entities[j]
            if !b.active {
                continue
            }
            if entities_collide(a, b) {
                append(&pairs, [2]^Entity{a, b})
            }
        }
    }
    
    return pairs[:]
}

// Clamp an entity to screen bounds
clamp_to_screen :: proc(entity: ^Entity, screen_w, screen_h: i32) {
    transform := entity_get_component(entity, Transform)
    collider := entity_get_component(entity, Collider)
    if transform == nil {
        return
    }
    
    half_w: f32 = 0
    half_h: f32 = 0
    if collider != nil {
        half_w = collider.width / 2
        half_h = collider.height / 2
    }
    
    transform.position.x = clamp(transform.position.x, half_w, f32(screen_w) - half_w)
    transform.position.y = clamp(transform.position.y, half_h, f32(screen_h) - half_h)
}

// ============================================================================
// Audio Engine (SDL_mixer)
// ============================================================================

audio_init :: proc(audio: ^AudioEngine) {
    // Initialize SDL_mixer with standard frequency, stereo, 16-bit, 4096 chunk size
    if MIX.Init(MIX.INIT_MP3 | MIX.INIT_OGG) == 0 {
        fmt.println("MIX.Init warning:", MIX.GetError())
        // Non-fatal; we can still use WAV
    }
    
    if MIX.OpenAudio(44100, MIX.DEFAULT_FORMAT, 2, 4096) != 0 {
        fmt.eprintln("MIX.OpenAudio failed:", MIX.GetError())
        audio.initialized = false
        return
    }
    
    audio.initialized = true
    audio.master_volume = 1.0
    audio.sounds = make(map[string]^MIX.Chunk)
    audio.music = make(map[string]^MIX.Music)
    
    fmt.println("Audio engine initialized")
}

audio_shutdown :: proc(audio: ^AudioEngine) {
    if !audio.initialized {
        return
    }
    
    // Free all sounds
    for _, chunk in audio.sounds {
        MIX.FreeChunk(chunk)
    }
    delete(audio.sounds)
    
    // Free all music
    for _, music in audio.music {
        MIX.FreeMusic(music)
    }
    delete(audio.music)
    
    MIX.CloseAudio()
    MIX.Quit()
    audio.initialized = false
    fmt.println("Audio engine shutdown")
}

audio_load_sound :: proc(audio: ^AudioEngine, name, path: string) -> bool {
    if !audio.initialized {
        return false
    }
    
    cpath := strings.clone_to_cstring(path)
    defer delete(cpath)
    
    chunk := MIX.LoadWAV(cpath)
    if chunk == nil {
        fmt.eprintln("Failed to load sound:", path, "-", MIX.GetError())
        return false
    }
    
    audio.sounds[name] = chunk
    return true
}

audio_load_music :: proc(audio: ^AudioEngine, name, path: string) -> bool {
    if !audio.initialized {
        return false
    }
    
    cpath := strings.clone_to_cstring(path)
    defer delete(cpath)
    
    music := MIX.LoadMUS(cpath)
    if music == nil {
        fmt.eprintln("Failed to load music:", path, "-", MIX.GetError())
        return false
    }
    
    audio.music[name] = music
    return true
}

audio_play_sound :: proc(audio: ^AudioEngine, name: string, channel: i32 = -1) {
    if !audio.initialized {
        return
    }
    
    if chunk, ok := audio.sounds[name]; ok {
        MIX.PlayChannel(channel, chunk, 0)
    }
}

audio_play_music :: proc(audio: ^AudioEngine, name: string, loops: i32 = -1) {
    if !audio.initialized {
        return
    }
    
    if music, ok := audio.music[name]; ok {
        MIX.PlayMusic(music, loops)
        audio.current_music = music
    }
}

audio_stop_music :: proc(audio: ^AudioEngine) {
    if audio.initialized {
        MIX.HaltMusic()
    }
}

audio_set_master_volume :: proc(audio: ^AudioEngine, volume: f32) {
    audio.master_volume = clamp(volume, 0.0, 1.0)
    if audio.initialized {
        MIX.VolumeMusic(i32(audio.master_volume * 128))
    }
}

// ============================================================================
// Math & Drawing Helpers
// ============================================================================
vec2 :: proc(x, y: f32) -> linalg.Vector2f32 {
    return {x, y}
}

vec3 :: proc(x, y, z: f32) -> linalg.Vector3f32 {
    return {x, y, z}
}

color :: proc(r, g, b, a: u8) -> SDL.Color {
    return SDL.Color{r, g, b, a}
}

draw_rect :: proc(renderer: ^SDL.Renderer, x, y, w, h: i32, col: SDL.Color) {
    SDL.SetRenderDrawColor(renderer, col.r, col.g, col.b, col.a)
    rect := SDL.Rect{x, y, w, h}
    SDL.RenderFillRect(renderer, &rect)
}

draw_line :: proc(renderer: ^SDL.Renderer, x1, y1, x2, y2: i32, col: SDL.Color) {
    SDL.SetRenderDrawColor(renderer, col.r, col.g, col.b, col.a)
    SDL.RenderDrawLine(renderer, x1, y1, x2, y2)
}

draw_rect_outline :: proc(renderer: ^SDL.Renderer, x, y, w, h: i32, col: SDL.Color) {
    SDL.SetRenderDrawColor(renderer, col.r, col.g, col.b, col.a)
    rect := SDL.Rect{x, y, w, h}
    SDL.RenderDrawRect(renderer, &rect)
}

lerp :: proc(a, b, t: f32) -> f32 {
    return a + (b - a) * t
}

clamp :: proc(value, min, max: f32) -> f32 {
	if value < min {
		return min
	}
	if value > max {
		return max
	}
	return value
}

// ============================================================================
// Random Helpers
// ============================================================================
rand_range :: proc(min, max: f32) -> f32 {
    return min + (f32(rand.uint32()) / 4294967295.0) * (max - min)
}

rand_int_range :: proc(min, max: int) -> int {
    if max <= min {
        return min
    }
    return min + rand.int_max(max - min)
}
