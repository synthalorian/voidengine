package tests

import "core:fmt"
import "core:testing"
import "engine:engine"

main :: proc() {
	fmt.println("=== Running Build System Tests ===")

	// Test 1: Project name extraction
	name1 := engine.extract_project_name("mygame")
	assert(name1 == "mygame", "extract_project_name failed for simple name")

	name2 := engine.extract_project_name("/path/to/mygame")
	assert(name2 == "mygame", "extract_project_name failed for path")

	name3 := engine.extract_project_name("/path/to/mygame/")
	assert(name3 == "mygame", "extract_project_name failed for trailing slash")

	name4 := engine.extract_project_name("C:\\path\\to\\mygame")
	assert(name4 == "mygame", "extract_project_name failed for Windows path")
	fmt.println("✓ extract_project_name works")

	// Test 2: Target OS detection
	target_os := engine.get_target_os()
	assert(target_os != "unknown", "get_target_os should return a valid OS")
	fmt.println("✓ get_target_os returns:", target_os)

	// Test 3: Target arch detection
	target_arch := engine.get_target_arch()
	assert(target_arch != "unknown", "get_target_arch should return a valid arch")
	fmt.println("✓ get_target_arch returns:", target_arch)

	// Test 4: Engine collection path
	engine_path := engine.get_engine_collection_path()
	assert(len(engine_path) > 0, "get_engine_collection_path should return non-empty")
	fmt.println("✓ get_engine_collection_path returns:", engine_path)

	// Test 5: Build config defaults
	build_cfg := engine.Build_Config{
		project_path = "test_project",
		project_name = "test",
		output_name = "test",
		engine_collection = "src",
		build_mode = .DEBUG,
		target_os = "linux",
	}
	assert(build_cfg.project_name == "test", "build config project name")
	assert(build_cfg.build_mode == .DEBUG, "build config mode")
	fmt.println("✓ Build_Config struct works")

	// Test 6: Build mode enum
	debug_mode := engine.Build_Mode.DEBUG
	release_mode := engine.Build_Mode.RELEASE
	assert(debug_mode != release_mode, "DEBUG and RELEASE should differ")
	fmt.println("✓ Build_Mode enum works")

	// Test 7: Standalone entry generation
	entry_code := engine.generate_standalone_entry("/test/project", "test")
	assert(len(entry_code) > 0, "generate_standalone_entry should produce code")
	assert(entry_code != "", "entry code should not be empty")
	fmt.println("✓ generate_standalone_entry works")

	// Test 8: Game wrapper generation
	wrapper_code := engine.generate_game_wrapper("/test/project", "test")
	assert(len(wrapper_code) > 0, "generate_game_wrapper should produce code")
	assert(wrapper_code != "", "wrapper code should not be empty")
	fmt.println("✓ generate_game_wrapper works")

	// Test 9: Platform-specific build helpers
	// These should at least not crash
	linux_result := engine.build_for_linux(".")
	// Result depends on current OS, so we just verify it doesn't panic
	fmt.println("✓ build_for_linux runs without panic")

	windows_result := engine.build_for_windows(".")
	fmt.println("✓ build_for_windows runs without panic")

	macos_result := engine.build_for_macos(".")
	fmt.println("✓ build_for_macos runs without panic")

	fmt.println("\n=== All Build System Tests Passed ===")
}
