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
	last_frame_time: f64,  // Actual frame time in seconds
}

engine: Engine

run_project :: proc(path: string) {
	fmt.println("[ENGINE] Loading project:", path)

	engine.project_path = path
	engine.window_width = 800
	engine.window_height = 600
	engine.running = true
	engine.last_frame_time = 0.0

	// Initialize profiler and debug overlay
	profiler_init()
	defer profiler_shutdown()

	debug_overlay_init()
	defer debug_overlay_shutdown()

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

	// Frame timing variables
	TARGET_FPS :: 60
	TARGET_FRAME_TIME :: 1.0 / f64(TARGET_FPS)

	for engine.running {
		frame_start := time.tick_now()

		profiler_begin_frame()

		// --- Process Input ---
		profiler_begin("input")
		process_events()
		input_poll()
		profiler_end("input")

		// --- Check hot-reload ---
		profiler_begin("hot_reload")
		check_sprite_reload()
		profiler_end("hot_reload")

		// --- Update ---
		profiler_begin("update")
		engine.api.update(f32(engine.last_frame_time))
		profiler_end("update")

		// --- Render ---
		profiler_begin("render")
		renderer_reset_stats()
		engine.api.draw()

		// Draw debug overlay on top
		profiler_begin("debug_overlay")
		debug_overlay_draw()
		profiler_end("debug_overlay")

		present()
		profiler_end("render")

		profiler_end_frame()

		// --- Frame limiting ---
		frame_end := time.tick_now()
		frame_duration := time.tick_diff(frame_start, frame_end)
		frame_duration_sec := time.duration_seconds(frame_duration)
		engine.last_frame_time = frame_duration_sec

		// Update debug overlay with actual frame time
		frame_time_ms := f32(frame_duration_sec * 1000.0)
		debug_overlay_update(frame_time_ms)

		if frame_duration_sec < TARGET_FRAME_TIME {
			sleep_time := TARGET_FRAME_TIME - frame_duration_sec
			time.sleep(time.Duration(sleep_time * f64(time.Second)))
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
			// F1 toggles debug overlay
			if event.key.keysym.scancode == SDL.Scancode.F1 {
				debug_overlay_toggle()
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

	// Determine project name from path
	project_name := path
	for i := len(path) - 1; i >= 0; i -= 1 {
		if path[i] == '/' || path[i] == '\\' {
			project_name = path[i+1:]
			break
		}
	}
	if project_name == "" {
		project_name = "game"
	}

	// Get current executable directory to find engine collection
	exe_dir := get_executable_directory()
	engine_collection := fmt.tprintf("-collection:engine=%s", exe_dir)

	// Determine output name based on platform
	output_name := project_name
	when ODIN_OS == .Windows {
		output_name = fmt.tprintf("%s.exe", project_name)
	}
	when ODIN_OS == .Darwin {
		output_name = project_name  // macOS has no extension
	}

	// For standalone build, we compile the game source together with the engine
	// We create a temporary wrapper that statically links the game
	wrapper_code := generate_standalone_wrapper(path)
	wrapper_path := fmt.tprintf("%s/.voidengine_build_wrapper.odin", path)

	write_err := os.write_entire_file(wrapper_path, transmute([]u8)wrapper_code)
	if write_err != os.ERROR_NONE {
		fmt.println("[ERROR] Failed to write standalone wrapper")
		return
	}
	defer os.remove(wrapper_path)

	// Build command: compile game src + wrapper as executable
	build_cmd := fmt.tprintf(
		"odin build %s %s -out:%s",
		path,
		engine_collection,
		output_name,
	)

	fmt.println("[BUILD] Command:", build_cmd)
	fmt.println("[BUILD] This feature requires the game to be compiled as a static binary.")
	fmt.println("[BUILD] For now, use: odin build", path, engine_collection, "-out:", output_name)
}

// Helper to get the directory containing the engine executable
get_executable_directory :: proc() -> string {
	// Return the path to the engine collection (relative to working directory)
	// In practice, this should be resolved from the executable location
	return "src"
}

// Generate a wrapper file that includes game code for static compilation
generate_standalone_wrapper :: proc(project_path: string) -> string {
	return fmt.tprintf(`package main

import "engine:engine"
import "core:fmt"

// Standalone wrapper - game code is compiled directly into the binary
// The game package should be imported here

main :: proc() {
	fmt.println("[STANDALONE] Starting %s...")
	engine.run_standalone("%s")
}
`, project_path, project_path)
}

// run_standalone runs a game without DLL hot-reloading (for built executables)
run_standalone :: proc(path: string) {
	fmt.println("[STANDALONE] Running:", path)
	// TODO: Implement static game loading (no DLL)
	// This would require the game to be compiled as a static library
}

// get_package fetches and installs an external package
get_package :: proc(package_name: string) -> bool {
	fmt.println("[PACKAGE] Fetching:", package_name)
	return package_manager_fetch(package_name)
}
