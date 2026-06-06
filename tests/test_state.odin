package tests

import "core:fmt"
import "engine:engine"

menu_entered: bool = false
menu_exited: bool = false
play_entered: bool = false

menu_init :: proc() { menu_entered = true }
menu_update :: proc(dt: f32) {}
menu_draw :: proc() {}
menu_exit :: proc() { menu_exited = true }

play_init :: proc() { play_entered = true }
play_update :: proc(dt: f32) {}
play_draw :: proc() {}
play_exit :: proc() {}

main :: proc() {
	fmt.println("=== Running State Machine Tests ===")

	// Initialize state machine
	engine.state_machine_init()
	defer engine.state_machine_shutdown()

	// Register states
	menu_id := engine.state_register("menu", menu_init, menu_update, menu_draw, menu_exit)
	play_id := engine.state_register("play", play_init, play_update, play_draw, play_exit)

	assert(menu_id == 0, "first state should have id 0")
	assert(play_id == 1, "second state should have id 1")
	assert(engine.state_count() == 2, "state_count failed")

	// Change to menu state
	ok := engine.state_change(menu_id)
	assert(ok, "state_change to menu failed")
	assert(menu_entered, "menu init should have been called")
	assert(engine.state_is_current(menu_id), "state_is_current failed")
	assert(engine.state_get_current_name() == "menu", "state_get_current_name failed")

	// Change to play state (should trigger menu exit)
	ok = engine.state_change(play_id)
	assert(ok, "state_change to play failed")
	assert(menu_exited, "menu exit should have been called")
	assert(play_entered, "play init should have been called")
	assert(engine.state_is_current_name("play"), "state_is_current_name failed")

	// Test push/pop
	ok = engine.state_push(menu_id)
	assert(ok, "state_push failed")
	assert(engine.state_is_current(menu_id), "after push, menu should be current")

	ok = engine.state_pop()
	assert(ok, "state_pop failed")
	assert(engine.state_is_current(play_id), "after pop, play should be current")

	// Test invalid state
	ok = engine.state_change(999)
	assert(!ok, "state_change to invalid id should fail")

	ok = engine.state_change_by_name("nonexistent")
	assert(!ok, "state_change_by_name to nonexistent should fail")

	// Test update/draw don't crash
	engine.state_machine_update(0.016)
	engine.state_machine_draw()

	fmt.println("✅ All state machine tests passed")
}
