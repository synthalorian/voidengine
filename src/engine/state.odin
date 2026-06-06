package engine

import "core:fmt"
import "core:strings"

// Game State Machine
// Manages transitions between game states (menu, gameplay, pause, etc.)

// State identifier
gameplay_state_id: int = 0

// State callback signatures
State_Init_Proc   :: proc()
State_Update_Proc :: proc(dt: f32)
State_Draw_Proc   :: proc()
State_Exit_Proc   :: proc()

// Game State definition
Game_State :: struct {
	name:    string,
	init:    State_Init_Proc,
	update:  State_Update_Proc,
	draw:    State_Draw_Proc,
	exit:    State_Exit_Proc,
	id:      int,
}

// State Machine
State_Machine :: struct {
	states:         [dynamic]Game_State,
	current_state:  int,
	previous_state: int,
	transitioning:  bool,
	next_state:     int,
}

state_machine: State_Machine

// Initialize the state machine
state_machine_init :: proc() {
	state_machine = State_Machine{
		states         = make([dynamic]Game_State),
		current_state  = -1,
		previous_state = -1,
		transitioning  = false,
		next_state     = -1,
	}
}

// Shutdown the state machine
state_machine_shutdown :: proc() {
	// Call exit on current state if active
	if state_machine.current_state >= 0 {
		state := &state_machine.states[state_machine.current_state]
		if state.exit != nil {
			state.exit()
		}
	}
	delete(state_machine.states)
}

// Register a new state with the machine
state_register :: proc(name: string, init: State_Init_Proc, update: State_Update_Proc, draw: State_Draw_Proc, exit: State_Exit_Proc) -> int {
	id := len(state_machine.states)
	append(&state_machine.states, Game_State{
		name   = name,
		init   = init,
		update = update,
		draw   = draw,
		exit   = exit,
		id     = id,
	})
	log_info("Registered state: %s (id: %d)", name, id)
	return id
}

// Change to a different state
state_change :: proc(state_id: int) -> bool {
	if state_id < 0 || state_id >= len(state_machine.states) {
		log_error("Invalid state ID: %d", state_id)
		return false
	}

	if state_machine.current_state >= 0 {
		old_state := &state_machine.states[state_machine.current_state]
		log_info("Exiting state: %s", old_state.name)
		if old_state.exit != nil {
			old_state.exit()
		}
	}

	state_machine.previous_state = state_machine.current_state
	state_machine.current_state = state_id

	new_state := &state_machine.states[state_machine.current_state]
	log_info("Entering state: %s", new_state.name)
	if new_state.init != nil {
		new_state.init()
	}

	return true
}

// Change to a state by name
state_change_by_name :: proc(name: string) -> bool {
	for state, i in state_machine.states {
		if state.name == name {
			return state_change(i)
		}
	}
	log_error("State not found: %s", name)
	return false
}

// Get the current state's name
state_get_current_name :: proc() -> string {
	if state_machine.current_state < 0 {
		return "none"
	}
	return state_machine.states[state_machine.current_state].name
}

// Update the current state
state_machine_update :: proc(dt: f32) {
	if state_machine.current_state < 0 {
		return
	}

	state := &state_machine.states[state_machine.current_state]
	if state.update != nil {
		state.update(dt)
	}
}

// Draw the current state
state_machine_draw :: proc() {
	if state_machine.current_state < 0 {
		return
	}

	state := &state_machine.states[state_machine.current_state]
	if state.draw != nil {
		state.draw()
	}
}

// Check if currently in a specific state
state_is_current :: proc(state_id: int) -> bool {
	return state_machine.current_state == state_id
}

// Check if currently in a state by name
state_is_current_name :: proc(name: string) -> bool {
	if state_machine.current_state < 0 {
		return false
	}
	return state_machine.states[state_machine.current_state].name == name
}

// Push a state onto a stack (for pause menus, overlays)
// Simple implementation: just track previous and current
state_push :: proc(state_id: int) -> bool {
	if state_id < 0 || state_id >= len(state_machine.states) {
		return false
	}

	state_machine.previous_state = state_machine.current_state
	return state_change(state_id)
}

// Pop back to previous state
state_pop :: proc() -> bool {
	if state_machine.previous_state < 0 {
		return false
	}
	return state_change(state_machine.previous_state)
}

// Common built-in state helpers

// Empty state callbacks for simple states
state_empty_init   :: proc() {}
state_empty_update :: proc(dt: f32) {}
state_empty_draw   :: proc() {}
state_empty_exit   :: proc() {}

// Get number of registered states
state_count :: proc() -> int {
	return len(state_machine.states)
}
