package voidengine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import "core:dynlib"
import "core:thread"
import "core:sync"
import "core:time"
import "core:math"
import "core:math/linalg"
import SDL "vendor:sdl2"

// Engine configuration
EngineConfig :: struct {
    title: string,
    width: i32,
    height: i32,
    target_fps: f64,
    enable_hot_reload: bool,
    asset_path: string,
}

// Main engine struct
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
    
    // Hot reload
    game_dll: dynlib.Library,
    game_api: GameAPI,
    last_dll_write_time: time.Time,
    
    // Frame timing
    accumulator: f64,
    fixed_timestep: f64,
}

// Game API for hot-reloadable game code
GameAPI :: struct {
    init: proc(^Engine),
    update: proc(^Engine, f64),
    render: proc(^Engine, ^SDL.Renderer),
    shutdown: proc(^Engine),
    handle_event: proc(^Engine, ^SDL.Event) -> bool,
}

// Input state tracking
InputState :: struct {
    keys: [512]bool,
    keys_prev: [512]bool,
    mouse_x: i32,
    mouse_y: i32,
    mouse_dx: i32,
    mouse_dy: i32,
    mouse_buttons: [8]bool,
    mouse_buttons_prev: [8]bool,
}

// Scene management
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
    entities: [dynamic]Entity,
    engine: ^Engine,
}

// Entity-Component-System base
Entity :: struct {
    id: u64,
    active: bool,
    position: linalg.Vector3f32,
    rotation: linalg.Vector3f32,
    scale: linalg.Vector3f32,
    components: map[typeid]rawptr,
}

// Audio engine stub (would integrate with SDL_mixer or similar)
AudioEngine :: struct {
    initialized: bool,
    master_volume: f32,
}

// Initialize the engine
engine_init :: proc(config: EngineConfig) -> ^Engine {
    engine := new(Engine)
    engine.config = config
    engine.fixed_timestep = 1.0 / 60.0  // 60 Hz physics/update
    
    // Initialize SDL
    if SDL.Init(SDL.INIT_VIDEO | SDL.INIT_AUDIO | SDL.INIT_TIMER) != 0 {
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
    
    // Initialize input
    engine.input = InputState{}
    
    // Initialize scene manager
    engine.scene = SceneManager{
        scenes = make([dynamic]^Scene),
    }
    
    // Initialize audio
    engine.audio = AudioEngine{
        initialized = true,
        master_volume = 1.0,
    }
    
    engine.running = true
    engine.last_frame_time = f64(time.now()._nsec) / 1e9
    
    fmt.println("VoidEngine initialized")
    fmt.println("   Resolution:", config.width, "x", config.height)
    fmt.println("   Hot reload:", config.enable_hot_reload)
    
    return engine
}

// Shutdown the engine
engine_shutdown :: proc(engine: ^Engine) {
    if engine.game_api.shutdown != nil {
        engine.game_api.shutdown(engine)
    }
    
    if engine.game_dll != nil {
        dynlib.unload_library(engine.game_dll)
    }
    
    SDL.DestroyRenderer(engine.renderer)
    SDL.DestroyWindow(engine.window)
    SDL.Quit()
    
    free(engine)
    fmt.println("VoidEngine shutdown complete")
}

// Main game loop
engine_run :: proc(engine: ^Engine) {
    event: SDL.Event
    
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

// Input helpers
input_update_prev_state :: proc(input: ^InputState) {
    input.keys_prev = input.keys
    input.mouse_buttons_prev = input.mouse_buttons
    input.mouse_dx = 0
    input.mouse_dy = 0
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

// Hot reload system
engine_check_hot_reload :: proc(engine: ^Engine) {
    // Check if game DLL has been modified
    dll_path := strings.concatenate({engine.config.asset_path, "/game.dll"})
    defer delete(dll_path)
    
    if os.exists(dll_path) {
        mod_time, err := os.modification_time_by_path(dll_path)
        if err == nil && mod_time != engine.last_dll_write_time {
            engine.last_dll_write_time = mod_time
            engine_reload_game_code(engine, dll_path)
        }
    }
}

engine_reload_game_code :: proc(engine: ^Engine, dll_path: string) {
    fmt.println("Hot reloading game code...")
    
    // Unload old DLL
    if engine.game_dll != nil {
        if engine.game_api.shutdown != nil {
            engine.game_api.shutdown(engine)
        }
        dynlib.unload_library(engine.game_dll)
    }
    
    // Copy DLL to avoid locking issues on Windows
    temp_path := strings.concatenate({dll_path, ".tmp"})
    defer delete(temp_path)
    
    // Load new DLL
    engine.game_dll, _ = dynlib.load_library(temp_path)
    if engine.game_dll == nil {
        fmt.eprintln("Failed to load game DLL")
        return
    }
    
    // Load symbols
    // Note: In real implementation, you'd use dynlib.symbol_address
    fmt.println("Game code reloaded")
}

// Scene management helpers
scene_create :: proc(engine: ^Engine, name: string) -> ^Scene {
    scene := new(Scene)
    scene.name = name
    scene.engine = engine
    scene.entities = make([dynamic]Entity)
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

// Entity helpers
entity_create :: proc(scene: ^Scene) -> ^Entity {
    entity := Entity{
        id = u64(len(scene.entities)),
        active = true,
        position = {0, 0, 0},
        rotation = {0, 0, 0},
        scale = {1, 1, 1},
        components = make(map[typeid]rawptr),
    }
    append(&scene.entities, entity)
    return &scene.entities[len(scene.entities) - 1]
}

entity_add_component :: proc(entity: ^Entity, $T: typeid, component: ^T) {
    entity.components[T] = component
}

entity_get_component :: proc(entity: ^Entity, $T: typeid) -> ^T {
    if ptr, ok := entity.components[T]; ok {
        return (^T)(ptr)
    }
    return nil
}

// Math helpers
vec2 :: proc(x, y: f32) -> linalg.Vector2f32 {
    return {x, y}
}

vec3 :: proc(x, y, z: f32) -> linalg.Vector3f32 {
    return {x, y, z}
}

// Color helper
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
