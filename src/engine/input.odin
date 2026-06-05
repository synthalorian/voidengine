package engine

import SDL "vendor:sdl2"

// Engine key enum (stable API)
Key :: enum {
	LEFT, RIGHT, UP, DOWN,
	A, B, X, Y,
	START, SELECT,
}

// Internal mapping to SDL scancodes
key_to_scancode :: proc(key: Key) -> SDL.Scancode {
	switch key {
	case .LEFT:   return SDL.Scancode.LEFT
	case .RIGHT:  return SDL.Scancode.RIGHT
	case .UP:     return SDL.Scancode.UP
	case .DOWN:   return SDL.Scancode.DOWN
	case .A:      return SDL.Scancode.Z
	case .B:      return SDL.Scancode.X
	case .X:      return SDL.Scancode.A
	case .Y:      return SDL.Scancode.S
	case .START:  return SDL.Scancode.RETURN
	case .SELECT: return SDL.Scancode.TAB
	}
	return SDL.Scancode.UNKNOWN
}

// Keyboard state tracking
MAX_KEYS :: 512
keys_current:  [MAX_KEYS]bool
keys_previous: [MAX_KEYS]bool

// Mouse state
mouse_x: f32
mouse_y: f32
mouse_buttons: u32

// --- Input polling (called once per frame from engine.odin) ---

input_poll :: proc() {
	// Save previous state
	keys_previous = keys_current

	// Poll current SDL keyboard state
	numkeys: i32
	sdl_keys := SDL.GetKeyboardState(&numkeys)
	count := min(int(numkeys), MAX_KEYS)
	for i in 0..<count {
		keys_current[i] = sdl_keys[i] != 0
	}

	// Poll mouse
	mx, my: i32
	mouse_buttons = SDL.GetMouseState(&mx, &my)
	mouse_x = f32(mx)
	mouse_y = f32(my)
}

// --- Public input API ---

is_key_pressed :: proc(key: Key) -> bool {
	sc := key_to_scancode(key)
	idx := int(sc)
	if idx < 0 || idx >= MAX_KEYS { return false }
	return keys_current[idx] && !keys_previous[idx]
}

is_key_down :: proc(key: Key) -> bool {
	sc := key_to_scancode(key)
	idx := int(sc)
	if idx < 0 || idx >= MAX_KEYS { return false }
	return keys_current[idx]
}

// Also expose raw SDL scancode check for games that need more keys
is_scancode_down :: proc(sc: SDL.Scancode) -> bool {
	idx := int(sc)
	if idx < 0 || idx >= MAX_KEYS { return false }
	return keys_current[idx]
}

get_mouse_pos :: proc() -> (f32, f32) {
	return mouse_x, mouse_y
}

is_mouse_button_down :: proc(button: int) -> bool {
	switch button {
	case 1: return (mouse_buttons & SDL.BUTTON_LMASK) != 0
	case 2: return (mouse_buttons & SDL.BUTTON_MMASK) != 0
	case 3: return (mouse_buttons & SDL.BUTTON_RMASK) != 0
	}
	return false
}
