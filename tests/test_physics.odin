package tests

import "core:fmt"
import "core:testing"
import "engine:engine"

main :: proc() {
	fmt.println("=== Running Physics Tests ===")

	// Initialize physics
	engine.physics_init({0, 980})
	defer engine.physics_shutdown()

	// Test body creation
	body1 := engine.physics_add_body({100, 100}, {32, 32}, .DYNAMIC)
	assert(body1 >= 0, "Failed to create body")
	assert(engine.physics_body_count() == 1, "Body count should be 1")

	// Test body retrieval
	body := engine.physics_get_body(body1)
	assert(body != nil, "Body should not be nil")
	assert(body.position.x == 100 && body.position.y == 100, "Body position incorrect")
	assert(body.body_type == .DYNAMIC, "Body type should be DYNAMIC")

	// Test static body
	body2 := engine.physics_add_body({200, 200}, {64, 32}, .STATIC)
	assert(body2 >= 0, "Failed to create static body")
	assert(engine.physics_body_count() == 2, "Body count should be 2")

	static_body := engine.physics_get_body(body2)
	assert(static_body.inv_mass == 0, "Static body should have zero inverse mass")

	// Test velocity
	engine.physics_set_velocity(body1, {100, 0})
	body = engine.physics_get_body(body1)
	assert(body.velocity.x == 100, "Velocity should be set")

	// Test position update through physics step
	engine.physics_step(0.016) // ~1 frame at 60fps
	body = engine.physics_get_body(body1)
	assert(body.position.x > 100, "Body should have moved")

	// Test gravity
	start_y := body.position.y
	engine.physics_step(0.016)
	body = engine.physics_get_body(body1)
	assert(body.position.y > start_y, "Body should have fallen due to gravity")

	// Test circle body
	circle_body := engine.physics_add_circle_body({300, 300}, 16, .DYNAMIC)
	assert(circle_body >= 0, "Failed to create circle body")
	circle := engine.physics_get_body(circle_body)
	assert(circle.use_circle, "Body should use circle collider")
	assert(circle.radius == 16, "Radius should be 16")

	// Test collision detection - AABB vs AABB
	// Create two overlapping bodies
	col_a := engine.physics_add_body({0, 0}, {50, 50}, .DYNAMIC)
	col_b := engine.physics_add_body({30, 30}, {50, 50}, .STATIC)
	engine.physics_step(0.016)
	// After collision resolution, they should be separated
	a := engine.physics_get_body(col_a)
	b := engine.physics_get_body(col_b)
	// They should not be at exactly the same position anymore
	assert(a.position.x != 0 || a.position.y != 0, "Body should have been pushed by collision")

	// Test body removal
	engine.physics_remove_body(body2)
	assert(engine.physics_body_count() == 4, "Body count should be 4 after removal")

	// Test clear
	engine.physics_clear_bodies()
	assert(engine.physics_body_count() == 0, "Body count should be 0 after clear")

	fmt.println("✅ All physics tests passed")
}
