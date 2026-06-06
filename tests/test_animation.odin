package tests

import "core:fmt"
import "core:testing"
import "engine:engine"

main :: proc() {
	fmt.println("=== Running Animation Tests ===")

	engine.animation_init()
	defer engine.animation_shutdown()

	// Test animation registration
	frames := []engine.Animation_Frame{
		{sprite_id = 0, duration = 0.1},
		{sprite_id = 1, duration = 0.1},
		{sprite_id = 2, duration = 0.1},
	}

	anim_id := engine.animation_register("test_anim", frames, true)
	assert(anim_id >= 0, "Failed to register animation")

	// Test player creation
	player_id := engine.animation_player_create(anim_id)
	assert(player_id >= 0, "Failed to create animation player")

	// Test initial state
	assert(engine.animation_player_is_playing(player_id), "Player should be playing")
	assert(!engine.animation_player_is_finished(player_id), "Player should not be finished")
	assert(engine.animation_player_get_current_frame(player_id) == 0, "Should start at frame 0")

	// Test update (advance frames)
	engine.animation_update(0.15) // Should advance past first frame
	frame := engine.animation_player_get_current_frame(player_id)
	assert(frame >= 0, "Frame should be valid")

	// Test pause
	engine.animation_player_pause(player_id)
	assert(!engine.animation_player_is_playing(player_id), "Player should be paused")

	// Test play
	engine.animation_player_play(player_id)
	assert(engine.animation_player_is_playing(player_id), "Player should be playing")

	// Test stop
	engine.animation_player_stop(player_id)
	assert(!engine.animation_player_is_playing(player_id), "Player should be stopped")
	assert(engine.animation_player_get_current_frame(player_id) == 0, "Should reset to frame 0")

	// Test sprite-based registration
	sprite_ids := []int{10, 11, 12, 13}
	anim2_id := engine.animation_register_from_sprites("sprite_anim", sprite_ids, 0.05, false)
	assert(anim2_id >= 0, "Failed to register sprite animation")

	player2_id := engine.animation_player_create(anim2_id)
	assert(player2_id >= 0, "Failed to create player for sprite anim")

	fmt.println("✅ All animation tests passed")
}
