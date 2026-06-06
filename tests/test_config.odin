package tests

import "core:fmt"
import "core:os"
import "engine:engine"

main :: proc() {
	fmt.println("=== Running Config Tests ===")

	// Test default config
	cfg := engine.default_config()
	assert(cfg.window.width == 800, "default width failed")
	assert(cfg.window.height == 600, "default height failed")
	assert(cfg.audio.master_volume == 1.0, "default master volume failed")
	assert(cfg.debug.log_level == "INFO", "default log level failed")

	// Test config generation
	config_json := engine.generate_default_config()
	assert(len(config_json) > 0, "generate_default_config failed")
	assert(config_json != "", "config should not be empty")

	// Test config save/load roundtrip
	test_path := "/tmp/voidengine_test_config.json"
	defer os.remove(test_path)

	// Save config
	ok := engine.config_save(test_path, &cfg)
	assert(ok, "config_save failed")
	assert(os.exists(test_path), "config file should exist after save")

	// Load config
	cfg2, ok2 := engine.config_load(test_path)
	assert(ok2, "config_load failed")
	assert(cfg2.window.width == 800, "loaded width mismatch")
	assert(cfg2.window.height == 600, "loaded height mismatch")

	// Test get_project_config_path
	path := engine.get_project_config_path("mygame")
	assert(path == "mygame/config.json", "get_project_config_path failed")

	fmt.println("✅ All config tests passed")
}
