package tests

import "core:fmt"
import "core:testing"
import "engine:engine"

main :: proc() {
	fmt.println("=== Running Particle Tests ===")

	engine.particle_init()
	defer engine.particle_shutdown()

	// Test emitter creation
	emitter_id := engine.particle_emitter_create()
	assert(emitter_id >= 0, "Failed to create emitter")
	assert(len(engine.emitters) == 1, "Should have 1 emitter")

	// Test position setting
	engine.particle_emitter_set_position(emitter_id, {100, 200})

	// Test burst
	engine.particle_emitter_burst(emitter_id, 10)
	assert(len(engine.emitters[emitter_id].particles) == 10, "Should have 10 particles")

	// Test update (particles should age and die)
	engine.particle_update(2.0) // Advance 2 seconds
	assert(len(engine.emitters[emitter_id].particles) == 0, "All particles should have died")

	// Test preset explosion
	explosion := engine.particle_preset_explosion({400, 300})
	assert(explosion >= 0, "Failed to create explosion")
	assert(len(engine.emitters) == 2, "Should have 2 emitters")

	// Test preset smoke
	engine.particle_preset_smoke({100, 100})
	assert(len(engine.emitters) == 3, "Should have 3 emitters")

	// Test preset sparkle
	engine.particle_preset_sparkle({200, 200})
	assert(len(engine.emitters) == 4, "Should have 4 emitters")

	// Test emitter destruction
	engine.particle_emitter_destroy(emitter_id)
	assert(len(engine.emitters) == 3, "Should have 3 emitters after destroy")

	fmt.println("✅ All particle tests passed")
}
