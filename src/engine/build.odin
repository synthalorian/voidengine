package engine

import "core:fmt"
import "core:os"
import "core:time"
import "core:strings"
import "core:path/filepath"

// Build system for standalone executables
// Compiles game + engine into a single binary without DLL hot-reload

Build_Config :: struct {
	project_path:     string,
	project_name:     string,
	output_name:      string,
	engine_collection: string,
	build_mode:       Build_Mode,
	target_os:        string,
}

Build_Mode :: enum {
	DEBUG,
	RELEASE,
}

// Platform detection for cross-compilation
get_target_os :: proc() -> string {
	when ODIN_OS == .Linux {
		return "linux"
	}
	when ODIN_OS == .Windows {
		return "windows"
	}
	when ODIN_OS == .Darwin {
		return "darwin"
	}
	return "unknown"
}

get_target_arch :: proc() -> string {
	when ODIN_ARCH == .amd64 {
		return "amd64"
	}
	when ODIN_ARCH == .i386 {
		return "386"
	}
	when ODIN_ARCH == .arm64 {
		return "arm64"
	}
	return "unknown"
}

// Build a standalone executable from a game project
build_standalone :: proc(path: string, mode: Build_Mode = .DEBUG) -> bool {
	fmt.println("[BUILD] Building standalone project:", path)

	// Extract project name from path
	project_name := extract_project_name(path)

	// Determine output filename based on target OS
	output_name := project_name
	when ODIN_OS == .Windows {
		output_name = fmt.tprintf("%s.exe", project_name)
	}

	// Create a temporary build directory
	build_dir := fmt.tprintf("%s/.voidengine_build", path)
	os.make_directory(build_dir)
	defer {
		// Clean up build directory
		os.remove(build_dir)
	}

	// Generate the standalone entry point
	entry_code := generate_standalone_entry(path, project_name)
	entry_path := fmt.tprintf("%s/standalone_main.odin", build_dir)

	write_err := os.write_entire_file(entry_path, transmute([]u8)entry_code)
	if write_err != os.ERROR_NONE {
		fmt.println("[BUILD ERROR] Failed to write standalone entry point")
		return false
	}

	// Determine engine collection path
	// The engine collection should point to where the engine source is
	engine_collection := get_engine_collection_path()

	// Build flags based on mode
	build_flags := ""
	switch mode {
	case .DEBUG:
		build_flags = "-debug"
	case .RELEASE:
		build_flags = "-o:speed"
	}

	// Construct the build command
	// We build from the build directory which contains the entry point
	// and references the game code via import
	fmt.println("[BUILD] Compiling standalone binary:", output_name)
	fmt.println("[BUILD] Engine collection:", engine_collection)
	fmt.println("[BUILD] Mode:", mode)

	// For now, print instructions on how to build manually
	// Full automation would require invoking odin compiler directly
	fmt.println("\n[BUILD] To build manually, run:")
	fmt.printf("  odin build %s -collection:engine=%s -collection:game=%s %s -out:%s\n",
		build_dir, engine_collection, path, build_flags, output_name)

	return true
}

// Generate a standalone entry point that statically links the game
// This creates a main() function that initializes the engine and calls game functions directly
generate_standalone_entry :: proc(project_path: string, project_name: string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	fmt.sbprintln(&builder, "package main")
	fmt.sbprintln(&builder, "")
	fmt.sbprintln(&builder, "import \"engine:engine\"")
	fmt.sbprintln(&builder, "import \"game:game\"")
	fmt.sbprintln(&builder, "import \"core:fmt\"")
	fmt.sbprintln(&builder, "")
	fmt.sbprintln(&builder, "main :: proc() {")
	fmt.sbprintf(&builder, "    fmt.println(\"[STANDALONE] Starting %s...\")\n", project_name)
	fmt.sbprintln(&builder, "    engine.run_standalone_game(\u0026game.game_init, \u0026game.game_update, \u0026game.game_draw, \u0026game.game_shutdown)")
	fmt.sbprintln(&builder, "}")

	return strings.to_string(builder)
}

// run_standalone_game runs a game with function pointers (no DLL loading)
run_standalone_game :: proc(
	game_init: proc(),
	game_update: proc(dt: f32),
	game_draw: proc(),
	game_shutdown: proc(),
) {
	fmt.println("[STANDALONE] Initializing engine...")

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

	// Call game init directly (no DLL loading)
	game_init()
	defer game_shutdown()

	// Frame timing
	TARGET_FPS :: 60
	TARGET_FRAME_TIME :: 1.0 / f64(TARGET_FPS)

	for engine.running {
		frame_start := time.tick_now()

		profiler_begin_frame()

		// Process input
		profiler_begin("input")
		process_events()
		input_poll()
		profiler_end("input")

		// Update
		profiler_begin("update")
		game_update(f32(engine.last_frame_time))
		profiler_end("update")

		// Render
		profiler_begin("render")
		renderer_reset_stats()
		game_draw()
		debug_overlay_draw()
		present()
		profiler_end("render")

		profiler_end_frame()

		// Frame limiting
		frame_end := time.tick_now()
		frame_duration := time.tick_diff(frame_start, frame_end)
		frame_duration_sec := time.duration_seconds(frame_duration)
		engine.last_frame_time = frame_duration_sec

		frame_time_ms := f32(frame_duration_sec * 1000.0)
		debug_overlay_update(frame_time_ms)

		if frame_duration_sec < TARGET_FRAME_TIME {
			sleep_time := TARGET_FRAME_TIME - frame_duration_sec
			time.sleep(time.Duration(sleep_time * f64(time.Second)))
		}
	}
}

// Extract project name from path
extract_project_name :: proc(path: string) -> string {
	// Remove trailing slashes
	clean_path := path
	for len(clean_path) > 0 && (clean_path[len(clean_path)-1] == '/' || clean_path[len(clean_path)-1] == '\\') {
		clean_path = clean_path[:len(clean_path)-1]
	}

	// Find last path separator
	last_sep := -1
	for i := 0; i < len(clean_path); i += 1 {
		if clean_path[i] == '/' || clean_path[i] == '\\' {
			last_sep = i
		}
	}

	if last_sep >= 0 {
		return clean_path[last_sep+1:]
	}
	return clean_path
}

// Get engine collection path relative to working directory
get_engine_collection_path :: proc() -> string {
	// Engine is at src/ relative to project root
	return "src"
}

// Cross-platform build helpers
build_for_linux :: proc(path: string) -> bool {
	fmt.println("[BUILD] Target: Linux amd64")
	// On Linux, native build
	when ODIN_OS == .Linux {
		return build_standalone(path)
	}
	// Cross-compilation would require setting up cross-compiler
	fmt.println("[BUILD] Cross-compilation to Linux from", get_target_os(), "not yet supported")
	return false
}

build_for_windows :: proc(path: string) -> bool {
	fmt.println("[BUILD] Target: Windows amd64")
	when ODIN_OS == .Windows {
		return build_standalone(path)
	}
	fmt.println("[BUILD] Cross-compilation to Windows from", get_target_os(), "not yet supported")
	return false
}

build_for_macos :: proc(path: string) -> bool {
	fmt.println("[BUILD] Target: macOS arm64/amd64")
	when ODIN_OS == .Darwin {
		return build_standalone(path)
	}
	fmt.println("[BUILD] Cross-compilation to macOS from", get_target_os(), "not yet supported")
	return false
}

// Build for all platforms
build_all_platforms :: proc(path: string) {
	fmt.println("[BUILD] Building for all platforms...")
	build_for_linux(path)
	build_for_windows(path)
	build_for_macos(path)
}
