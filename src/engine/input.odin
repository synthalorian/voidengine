package engine

import SDL "vendor:sdl2"

// Engine key enum (stable API)
Key :: enum {
	LEFT, RIGHT, UP, DOWN,
	A, B, X, Y,
	START, SELECT,
}

// Configurable keybindings — maps engine Key to SDL scancode
// Can be overridden by loading a config file
key_bindings: [Key]SDL.Scancode

// Default keybindings
init_default_keybindings :: proc() {
	key_bindings[.LEFT]   = SDL.Scancode.LEFT
	key_bindings[.RIGHT]  = SDL.Scancode.RIGHT
	key_bindings[.UP]     = SDL.Scancode.UP
	key_bindings[.DOWN]   = SDL.Scancode.DOWN
	key_bindings[.A]      = SDL.Scancode.Z
	key_bindings[.B]      = SDL.Scancode.X
	key_bindings[.X]      = SDL.Scancode.A
	key_bindings[.Y]      = SDL.Scancode.S
	key_bindings[.START]  = SDL.Scancode.RETURN
	key_bindings[.SELECT] = SDL.Scancode.TAB
}

// Map a string key name to SDL scancode
string_to_scancode :: proc(name: string) -> SDL.Scancode {
	switch name {
	case "A":          return SDL.Scancode.A
	case "B":          return SDL.Scancode.B
	case "C":          return SDL.Scancode.C
	case "D":          return SDL.Scancode.D
	case "E":          return SDL.Scancode.E
	case "F":          return SDL.Scancode.F
	case "G":          return SDL.Scancode.G
	case "H":          return SDL.Scancode.H
	case "I":          return SDL.Scancode.I
	case "J":          return SDL.Scancode.J
	case "K":          return SDL.Scancode.K
	case "L":          return SDL.Scancode.L
	case "M":          return SDL.Scancode.M
	case "N":          return SDL.Scancode.N
	case "O":          return SDL.Scancode.O
	case "P":          return SDL.Scancode.P
	case "Q":          return SDL.Scancode.Q
	case "R":          return SDL.Scancode.R
	case "S":          return SDL.Scancode.S
	case "T":          return SDL.Scancode.T
	case "U":          return SDL.Scancode.U
	case "V":          return SDL.Scancode.V
	case "W":          return SDL.Scancode.W
	case "X":          return SDL.Scancode.X
	case "Y":          return SDL.Scancode.Y
	case "Z":          return SDL.Scancode.Z
	case "LEFT":       return SDL.Scancode.LEFT
	case "RIGHT":      return SDL.Scancode.RIGHT
	case "UP":         return SDL.Scancode.UP
	case "DOWN":       return SDL.Scancode.DOWN
	case "RETURN":     return SDL.Scancode.RETURN
	case "TAB":        return SDL.Scancode.TAB
	case "SPACE":      return SDL.Scancode.SPACE
	case "ESCAPE":     return SDL.Scancode.ESCAPE
	case "LCTRL":      return SDL.Scancode.LCTRL
	case "RCTRL":      return SDL.Scancode.RCTRL
	case "LSHIFT":     return SDL.Scancode.LSHIFT
	case "RSHIFT":     return SDL.Scancode.RSHIFT
	case "LALT":       return SDL.Scancode.LALT
	case "RALT":       return SDL.Scancode.RALT
	case "BACKSPACE":  return SDL.Scancode.BACKSPACE
	case "DELETE":     return SDL.Scancode.DELETE
	case "HOME":       return SDL.Scancode.HOME
	case "END":        return SDL.Scancode.END
	case "PAGEUP":     return SDL.Scancode.PAGEUP
	case "PAGEDOWN":   return SDL.Scancode.PAGEDOWN
	case "F1":         return SDL.Scancode.F1
	case "F2":         return SDL.Scancode.F2
	case "F3":         return SDL.Scancode.F3
	case "F4":         return SDL.Scancode.F4
	case "F5":         return SDL.Scancode.F5
	case "F6":         return SDL.Scancode.F6
	case "F7":         return SDL.Scancode.F7
	case "F8":         return SDL.Scancode.F8
	case "F9":         return SDL.Scancode.F9
	case "F10":        return SDL.Scancode.F10
	case "F11":        return SDL.Scancode.F11
	case "F12":        return SDL.Scancode.F12
	}
	return SDL.Scancode.UNKNOWN
}

// Set a keybinding from config strings
set_keybinding :: proc(action: string, key_name: string) {
	sc := string_to_scancode(key_name)
	if sc == SDL.Scancode.UNKNOWN {
		log_warn("Unknown key name in config: %s", key_name)
		return
	}

	switch action {
	case "left":   key_bindings[.LEFT]   = sc
	case "right":  key_bindings[.RIGHT]  = sc
	case "up":     key_bindings[.UP]     = sc
	case "down":   key_bindings[.DOWN]   = sc
	case "action_a": key_bindings[.A]    = sc
	case "action_b": key_bindings[.B]    = sc
	case "action_x": key_bindings[.X]    = sc
	case "action_y": key_bindings[.Y]    = sc
	case "start":  key_bindings[.START]  = sc
	case "select": key_bindings[.SELECT] = sc
	case:
		log_warn("Unknown action in keybinding config: %s", action)
	}
}

// Load keybindings from a Game_Config
load_keybindings_from_config :: proc(cfg: ^Game_Config) {
	init_default_keybindings()
	for action, key_name in cfg.input.keybindings {
		set_keybinding(action, key_name)
	}
	log_info("Loaded keybindings from config")
}

// Internal mapping to SDL scancodes (uses configurable bindings)
key_to_scancode :: proc(key: Key) -> SDL.Scancode {
	return key_bindings[key]
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
