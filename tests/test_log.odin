package tests

import "core:fmt"
import "engine:engine"

main :: proc() {
	fmt.println("=== Running Log Tests ===")

	// Test log init
	engine.log_init(.DEBUG, false, false)
	assert(engine.logger.min_level == .DEBUG, "log_init min_level failed")
	assert(!engine.logger.use_colors, "log_init use_colors failed")
	assert(!engine.logger.show_timestamp, "log_init show_timestamp failed")

	// Test log level change
	engine.log_set_level(.WARN)
	assert(engine.logger.min_level == .WARN, "log_set_level failed")

	// Test that log functions don't crash
	engine.log_debug("Test debug message: %d", 42)
	engine.log_info("Test info message: %s", "hello")
	engine.log_warn("Test warn message")
	engine.log_error("Test error message")

	// Test print wrapper (backward compatibility)
	engine.print("Test print message")

	// Test log level filtering
	engine.log_set_level(.ERROR)
	engine.log_info("This should be filtered")
	engine.log_warn("This should be filtered too")
	engine.log_error("This should appear")

	fmt.println("✅ All log tests passed")
}
