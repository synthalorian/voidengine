package engine

import "core:fmt"
import "core:os"
import "core:dynlib"
import "core:time"
import SDL "vendor:sdl2"

print :: proc(msg: string) {
	fmt.println(msg)
}

Game_API :: struct {
	init:     proc(),
	update:   proc(dt: f32),
	draw:     proc(),
	shutdown: proc(),
}

Engine :: struct {
	running:       bool,
	game_dll:      dynlib.Library,
	api:           Game_API,
	last_reload:   time.Time,
	project_path:  string,
	window_width:  i32,
	window_height: i32,
}

engine: Engine

run_project :: proc(path: string) {
	fmt.println("[ENGINE] Loading project:", path)

	engine.project_path = path
	engine.window_width = 800
	engine.window_height = 600
	engine.running = true

	if !renderer_init(engine.window_width, engine.window_height, "VoidEngine") {
		fmt.println("[ERROR] Failed to initialize renderer")
		return
	}
	defer renderer_shutdown()

	if !audio_init() {
		fmt.println("[WARNING] Failed to initialize audio")
	}
	defer audio_shutdown()

	if !font_init() {
		fmt.println("[WARNING] Failed to initialize font system")
	}

	if !load_game_dll() {
		fmt.println("[ERROR] Failed to load game.dll")
		return
	}

	engine.api.init()
	defer engine.api.shutdown()

	// 60 FPS timing
	TARGET_FPS :: 60
	FRAME_TIME_MS :: 1000 / TARGET_FPS
	FRAME_TIME_S :: f32(1.0 / f64(TARGET_FPS))

	for engine.running {
		frame_start := SDL.GetTicks()

		// --- Process Input ---
		process_events()
		input_poll()

		// --- Check hot-reload ---
		check_sprite_reload()

		// --- Update ---
		engine.api.update(FRAME_TIME_S)

		// --- Render ---
		engine.api.draw()
		present()

		// --- Frame limiting ---
		frame_time := SDL.GetTicks() - frame_start
		if frame_time < u32(FRAME_TIME_MS) {
			SDL.Delay(u32(FRAME_TIME_MS) - frame_time)
		}
	}
}

process_events :: proc() {
	event: SDL.Event
	for SDL.PollEvent(&event) {
		#partial switch event.type {
		case SDL.EventType.QUIT:
			engine.running = false
		case SDL.EventType.KEYDOWN:
			if event.key.keysym.sym == SDL.Keycode.ESCAPE {
				engine.running = false
			}
		}
	}
}

load_game_dll :: proc() -> bool {
	dll_path := fmt.tprintf("%s/game.dll", engine.project_path)

	lib, ok := dynlib.load_library(dll_path)
	if !ok {
		return false
	}

	engine.game_dll = lib

	init_ptr,     init_ok     := dynlib.symbol_address(lib, "game_init")
	update_ptr,   update_ok   := dynlib.symbol_address(lib, "game_update")
	draw_ptr,     draw_ok     := dynlib.symbol_address(lib, "game_draw")
	shutdown_ptr, shutdown_ok := dynlib.symbol_address(lib, "game_shutdown")

	if !init_ok || !update_ok || !draw_ok || !shutdown_ok {
		dynlib.unload_library(lib)
		return false
	}

	engine.api = Game_API{
		init     = cast(proc())init_ptr,
		update   = cast(proc(dt: f32))update_ptr,
		draw     = cast(proc())draw_ptr,
		shutdown = cast(proc())shutdown_ptr,
	}

	return true
}

reload_game_dll :: proc() {
	if engine.game_dll != nil {
		dynlib.unload_library(engine.game_dll)
	}
	load_game_dll()
}

should_reload :: proc() -> bool {
	// TODO: Implement file watcher for hot-reload
	return false
}

create_project :: proc(name: string) {
	fmt.println("[ENGINE] Creating project:", name)

	os.make_directory(name)
	os.make_directory(fmt.tprintf("%s/assets", name))
	os.make_directory(fmt.tprintf("%s/assets/sprites", name))
	os.make_directory(fmt.tprintf("%s/assets/sounds", name))
	os.make_directory(fmt.tprintf("%s/assets/music", name))
	os.make_directory(fmt.tprintf("%s/assets/fonts", name))
	os.make_directory(fmt.tprintf("%s/src", name))

	// Write boilerplate
	main_code := `package game

import "engine:engine"

@(export)
game_init :: proc() {
	engine.print("Hello from the void!")
}

@(export)
game_update :: proc(dt: f32) {
	// Update logic here
}

@(export)
game_draw :: proc() {
	engine.clear(0.05, 0.05, 0.1)
	engine.draw_rect(100, 100, 50, 50, 1.0, 0.0, 0.0)
}

@(export)
game_shutdown :: proc() {
}
`
	_ = os.write_entire_file(fmt.tprintf("%s/src/game.odin", name), transmute([]u8)main_code)

	fmt.println("[ENGINE] Project created at ./", name)
}

build_project :: proc(path: string) {
	fmt.println("[ENGINE] Building standalone:", path)
	// TODO: Compile game + engine into single binary
}
