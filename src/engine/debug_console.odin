package engine

import "core:fmt"
import "core:strings"
import "core:strconv"

// --- Debug Console ---

Debug_Console :: struct {
	visible:          bool,
	lines:            [dynamic]string,
	input_buffer:     strings.Builder,
	cursor_pos:       int,
	scroll_pos:       int,
	max_lines:        int,
	history:          [dynamic]string,
	history_pos:      int,
	font_id:          int,
}

debug_console: Debug_Console

// Console command callback
debug_console_init :: proc() {
	debug_console = Debug_Console{
		visible     = false,
		lines       = make([dynamic]string),
		input_buffer = strings.builder_make(),
		cursor_pos  = 0,
		scroll_pos  = 0,
		max_lines   = 100,
		history     = make([dynamic]string),
		history_pos = -1,
		font_id     = -1,
	}
	console_log("Debug console initialized. Type 'help' for commands.")
}

debug_console_shutdown :: proc() {
	for line in debug_console.lines {
		delete(line)
	}
	delete(debug_console.lines)
	strings.builder_destroy(&debug_console.input_buffer)
	for cmd in debug_console.history {
		delete(cmd)
	}
	delete(debug_console.history)
}

// --- Visibility ---

debug_console_toggle :: proc() {
	debug_console.visible = !debug_console.visible
	if debug_console.visible {
		// Clear input when opening
		strings.builder_reset(&debug_console.input_buffer)
		debug_console.cursor_pos = 0
	}
}

debug_console_is_visible :: proc() -> bool {
	return debug_console.visible
}

// --- Input Handling ---

debug_console_input_text :: proc(text: string) {
	if !debug_console.visible { return }
	strings.write_string(&debug_console.input_buffer, text)
	debug_console.cursor_pos += len(text)
}

debug_console_input_key :: proc(key: Key) {
	if !debug_console.visible { return }

	#partial switch key {
	case .A: // Enter (START is Return)
		debug_console_execute()
	case .B: // Backspace
		debug_console_backspace()
	case .UP:
		debug_console_history_prev()
	case .DOWN:
		debug_console_history_next()
	case .LEFT:
		if debug_console.cursor_pos > 0 {
			debug_console.cursor_pos -= 1
		}
	case .RIGHT:
		buf_len := len(strings.to_string(debug_console.input_buffer))
		if debug_console.cursor_pos < buf_len {
			debug_console.cursor_pos += 1
		}
	}
}

debug_console_backspace :: proc() {
	buf := strings.to_string(debug_console.input_buffer)
	if debug_console.cursor_pos > 0 && len(buf) > 0 {
		// Remove character before cursor
		new_buf := fmt.tprintf("%s%s", buf[:debug_console.cursor_pos-1], buf[debug_console.cursor_pos:])
		strings.builder_reset(&debug_console.input_buffer)
		strings.write_string(&debug_console.input_buffer, new_buf)
		debug_console.cursor_pos -= 1
	}
}

debug_console_execute :: proc() {
	cmd := strings.clone(strings.to_string(debug_console.input_buffer))
	if len(cmd) > 0 {
		console_log(fmt.tprintf("> %s", cmd))
		console_execute(cmd)

		// Add to history
		append(&debug_console.history, cmd)
		debug_console.history_pos = len(debug_console.history)
	} else {
		delete(cmd)
	}

	strings.builder_reset(&debug_console.input_buffer)
	debug_console.cursor_pos = 0
}

debug_console_history_prev :: proc() {
	if len(debug_console.history) == 0 { return }
	if debug_console.history_pos > 0 {
		debug_console.history_pos -= 1
		strings.builder_reset(&debug_console.input_buffer)
		strings.write_string(&debug_console.input_buffer, debug_console.history[debug_console.history_pos])
		debug_console.cursor_pos = len(strings.to_string(debug_console.input_buffer))
	}
}

debug_console_history_next :: proc() {
	if len(debug_console.history) == 0 { return }
	if debug_console.history_pos < len(debug_console.history) - 1 {
		debug_console.history_pos += 1
		strings.builder_reset(&debug_console.input_buffer)
		strings.write_string(&debug_console.input_buffer, debug_console.history[debug_console.history_pos])
		debug_console.cursor_pos = len(strings.to_string(debug_console.input_buffer))
	} else {
		debug_console.history_pos = len(debug_console.history)
		strings.builder_reset(&debug_console.input_buffer)
		debug_console.cursor_pos = 0
	}
}

// --- Logging ---

console_log :: proc(msg: string) {
	append(&debug_console.lines, strings.clone(msg))
	if len(debug_console.lines) > debug_console.max_lines {
		old := debug_console.lines[0]
		delete(old)
		ordered_remove(&debug_console.lines, 0)
	}
	// Auto-scroll to bottom
	debug_console.scroll_pos = len(debug_console.lines)
}

console_logf :: proc(format: string, args: ..any) {
	msg := fmt.tprintf(format, ..args)
	console_log(msg)
}

// --- Command Execution ---

console_execute :: proc(cmd: string) {
	parts := strings.split(cmd, " ")
	defer delete(parts)

	if len(parts) == 0 {
		return
	}

	switch parts[0] {
	case "help":
		console_log("Available commands:")
		console_log("  help              - Show this help")
		console_log("  clear             - Clear console")
		console_log("  fps               - Show FPS info")
		console_log("  mem               - Show memory stats")
		console_log("  states            - List registered states")
		console_log("  physics           - Show physics body count")
		console_log("  particles         - Show particle emitter count")
		console_log("  reload            - Reload game DLL")
		console_log("  quit              - Exit game")
		console_log("  echo <msg>        - Print message")
		console_log("  set_volume <ch> <v> - Set volume (master/music/sfx/ui)")
		console_log("  goto <state>      - Change to state by name")
		console_log("  save              - Save game state")
		console_log("  load              - Load game state")

	case "clear":
		for line in debug_console.lines {
			delete(line)
		}
		clear_dynamic_array(&debug_console.lines)
		debug_console.scroll_pos = 0

	case "fps":
		avg_ms := profiler_avg_frame_time(60)
		avg_fps := profiler_avg_fps(60)
		console_logf("FPS: %.1f (%.2f ms)", avg_fps, avg_ms)
		console_logf("Current: %.1f FPS", debug_overlay.current_fps)

	case "mem":
		console_logf("Active Allocs: %d", len(tracking_allocator.allocation_map))
		console_logf("Total Allocs: %d", tracking_allocator.total_allocation_count)
		console_logf("Total Frees: %d", tracking_allocator.total_free_count)
		console_logf("Current Memory: %d KB", tracking_allocator.current_memory_allocated / 1024)
		console_logf("Peak Memory: %d KB", tracking_allocator.peak_memory_allocated / 1024)

	case "states":
		console_logf("Registered states: %d", state_count())
		for i in 0..<state_count() {
			if i < len(state_machine.states) {
				state := state_machine.states[i]
				marker := ""
				if i == state_machine.current_state {
					marker = " [ACTIVE]"
				}
				console_logf("  %d: %s%s", i, state.name, marker)
			}
		}

	case "physics":
		console_logf("Physics bodies: %d", physics_body_count())
		console_logf("Gravity: (%.1f, %.1f)", physics_world.gravity.x, physics_world.gravity.y)

	case "particles":
		console_logf("Emitters: %d", len(emitters))
		total_particles := 0
		for emitter in emitters {
			total_particles += len(emitter.particles)
		}
		console_logf("Total particles: %d", total_particles)

	case "reload":
		console_log("Reloading game DLL...")
		reload_game_dll()
		console_log("DLL reloaded")

	case "quit", "exit":
		console_log("Quitting...")
		engine.running = false

	case "echo":
		if len(parts) > 1 {
			console_log(strings.join(parts[1:], " "))
		}

	case "set_volume":
		if len(parts) >= 3 {
			channel: Audio_Channel
			switch parts[1] {
			case "master": channel = .MASTER
			case "music":  channel = .MUSIC
			case "sfx":    channel = .SFX
			case "ui":     channel = .UI
			case:
				console_logf("Unknown channel: %s", parts[1])
				return
			}
			if vol, ok := strconv.parse_f32(parts[2]); ok {
				mixer_set_volume(channel, vol)
				console_logf("Set %s volume to %.2f", parts[1], vol)
			} else {
				console_log("Invalid volume value")
			}
		} else {
			console_log("Usage: set_volume <channel> <0.0-1.0>")
		}

	case "goto":
		if len(parts) >= 2 {
			state_name := parts[1]
			if state_change_by_name(state_name) {
				console_logf("Changed to state: %s", state_name)
			} else {
				console_logf("State not found: %s", state_name)
			}
		}

	case "save":
		path := save_get_path(engine.project_path)
		if save_to_file(path) {
			console_logf("Game saved to: %s", path)
		} else {
			console_log("Failed to save game")
		}

	case "load":
		path := save_get_path(engine.project_path)
		if save_from_file(path) {
			console_logf("Game loaded from: %s", path)
		} else {
			console_log("Failed to load game (no save file)")
		}

	case:
		console_logf("Unknown command: %s", parts[0])
	}
}

// --- Rendering ---

debug_console_draw :: proc() {
	if !debug_console.visible { return }
	if renderer == nil { return }

	console_w := f32(engine.window_width)
	console_h := f32(engine.window_height) * 0.4
	console_y := f32(engine.window_height) - console_h

	// Draw background
	draw_rect(0, console_y, console_w, console_h, 0.0, 0.0, 0.0)

	// Draw border line
	draw_rect(0, console_y, console_w, 2, 0.5, 0.5, 0.5)

	// Draw lines
	line_height: f32 = 16.0
	visible_lines := int(console_h / line_height) - 2
	start_line := max(len(debug_console.lines) - visible_lines, 0)

	for idx in start_line..<len(debug_console.lines) {
		y := console_y + f32(idx - start_line) * line_height + 5
		if y + line_height > console_y + console_h - 25 {
			break
		}
		draw_text(10, y, debug_console.lines[idx], debug_console.font_id, 1.0, 1.0, 1.0)
	}

	// Draw input prompt
	prompt_y := console_y + console_h - 20
	draw_rect(0, prompt_y - 2, console_w, 22, 0.1, 0.1, 0.1)
	input_text := fmt.tprintf("> %s", strings.to_string(debug_console.input_buffer))
	draw_text(10, prompt_y, input_text, debug_console.font_id, 0.0, 1.0, 0.0)
}
