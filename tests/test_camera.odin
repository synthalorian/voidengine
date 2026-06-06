package tests

import "core:fmt"
import "core:testing"
import "engine:engine"

main :: proc() {
	fmt.println("=== Running Camera Tests ===")

	engine.camera_init(800, 600)
	defer engine.camera_shutdown()

	// Test initial state
	pos := engine.camera_get_position()
	assert(pos.x == 400 && pos.y == 300, "Initial camera position should be center of viewport")
	assert(engine.camera_get_zoom() == 1.0, "Initial zoom should be 1.0")

	// Test position setting
	engine.camera_set_position({100, 200})
	pos = engine.camera_get_position()
	assert(pos.x == 100 && pos.y == 200, "Camera position should be set")

	// Test zoom
	engine.camera_set_zoom(2.0)
	assert(engine.camera_get_zoom() == 2.0, "Zoom should be 2.0")

	// Test zoom clamping
	engine.camera_set_zoom(15.0)
	assert(engine.camera_get_zoom() == 10.0, "Zoom should be clamped to max 10.0")

	engine.camera_set_zoom(0.05)
	assert(engine.camera_get_zoom() == 0.1, "Zoom should be clamped to min 0.1")

	// Test world to screen conversion
	engine.camera_set_position({0, 0})
	engine.camera_set_zoom(1.0)
	screen := engine.camera_world_to_screen({100, 100})
	// At position (0,0), world (100,100) should be at screen center + 100
	assert(screen.x > 0, "Screen X should be positive")
	assert(screen.y > 0, "Screen Y should be positive")

	// Test screen to world conversion
	world := engine.camera_screen_to_world({400, 300})
	assert(world.x >= -1 && world.x <= 1, "World X should be near 0")
	assert(world.y >= -1 && world.y <= 1, "World Y should be near 0")

	// Test bounds
	engine.camera_set_bounds({0, 0, 1000, 1000})
	engine.camera_set_position({5000, 5000})
	engine.camera_update(0.016)
	pos = engine.camera_get_position()
	// Should be clamped to bounds
	assert(pos.x < 5000, "Camera X should be clamped")
	assert(pos.y < 5000, "Camera Y should be clamped")

	// Test viewport
	viewport := engine.camera_get_viewport()
	assert(viewport.w > 0, "Viewport width should be positive")
	assert(viewport.h > 0, "Viewport height should be positive")

	fmt.println("✅ All camera tests passed")
}
