package engine

import "core:fmt"
import "core:strings"
import "core:mem"

// Debug overlay state
Debug_Overlay :: struct {
	enabled:           bool,
	show_profiler:     bool,
	show_memory:       bool,
	font_id:           int,
	overlay_x:         f32,
	overlay_y:         f32,
	line_height:       f32,
	bg_width:          f32,
	bg_height:         f32,
	frame_counter:     int,
	fps_update_interval: int,
	current_fps:       f32,
	current_frame_ms:  f32,
}

debug_overlay: Debug_Overlay

// Tracking allocator for memory stats
tracking_allocator: mem.Tracking_Allocator

debug_overlay_init :: proc() {
	debug_overlay = Debug_Overlay{
		enabled             = false,
		show_profiler       = true,
		show_memory         = true,
		font_id             = -1,
		overlay_x           = 10,
		overlay_y           = 10,
		line_height         = 18,
		bg_width            = 280,
		bg_height           = 200,
		frame_counter       = 0,
		fps_update_interval = 30,
		current_fps         = 0,
		current_frame_ms    = 0,
	}

	// Initialize tracking allocator on top of default allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	// Note: We don't swap context.allocator here to avoid interfering with SDL
	// Instead we just use tracking_allocator for explicit queries
}

debug_overlay_shutdown :: proc() {
	mem.tracking_allocator_destroy(&tracking_allocator)
}

// Toggle overlay on/off
debug_overlay_toggle :: proc() {
	debug_overlay.enabled = !debug_overlay.enabled
}

// Check if a specific key should toggle the overlay (call from engine event loop)
debug_overlay_check_toggle :: proc(key: Key) -> bool {
	if key == .START { // Use START (RETURN) as toggle, or we can use F1 via scancode
		return true
	}
	return false
}

// Update FPS counter (call once per frame)
debug_overlay_update :: proc(frame_time_ms: f32) {
	debug_overlay.frame_counter += 1
	debug_overlay.current_frame_ms = frame_time_ms

	if debug_overlay.frame_counter >= debug_overlay.fps_update_interval {
		debug_overlay.current_fps = 1000.0 / frame_time_ms
		debug_overlay.frame_counter = 0
	}
}

// Set the font to use for the overlay (call after fonts are loaded)
debug_overlay_set_font :: proc(font_id: int) {
	debug_overlay.font_id = font_id
}

// Main draw function for the overlay
debug_overlay_draw :: proc() {
	if !debug_overlay.enabled { return }
	if renderer == nil { return }

	// Use default font if available, otherwise try to create/use a built-in
	font_id := debug_overlay.font_id

	// Build the display text
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	// FPS Section
	fmt.sbprintf(&builder, "=== DEBUG OVERLAY ===\n")
	fmt.sbprintf(&builder, "FPS: %.1f (%.2f ms)\n", debug_overlay.current_fps, debug_overlay.current_frame_ms)

	// Draw calls
	fmt.sbprintf(&builder, "Draw Calls: %d\n", renderer_stats.draw_calls)

	// Memory section
	if debug_overlay.show_memory {
		fmt.sbprintf(&builder, "\n--- Memory ---\n")
		debug_overlay_format_memory(&builder)
	}

	// Profiler section
	if debug_overlay.show_profiler {
		fmt.sbprintf(&builder, "\n--- Profiler ---\n")
		profiler_format_stats(&builder)
	}

	text := strings.to_string(builder)

	// Draw background panel
	bg_r := debug_overlay.overlay_x - 5
	bg_y := debug_overlay.overlay_y - 5
	draw_rect(bg_r, bg_y, debug_overlay.bg_width, debug_overlay.bg_height, 0.0, 0.0, 0.0)

	// Draw text lines
	if font_id >= 0 && font_initialized {
		lines := strings.split(text, "\n")
		defer delete(lines)
		for line, i in lines {
			y := debug_overlay.overlay_y + f32(i) * debug_overlay.line_height
			draw_text(debug_overlay.overlay_x, y, line, font_id, 0.0, 1.0, 0.0)
		}
	} else {
		// Fallback: draw simple colored bars/rects as visual indicator
		// when no font is available
		draw_rect(debug_overlay.overlay_x, debug_overlay.overlay_y, 4, 4, 0.0, 1.0, 0.0)
		draw_rect(debug_overlay.overlay_x, debug_overlay.overlay_y + 10, 4, 4, 0.0, 1.0, 0.0)
	}
}

// Format memory statistics
debug_overlay_format_memory :: proc(builder: ^strings.Builder) {
	// Get memory statistics from the tracking allocator
	fmt.sbprintf(builder, "Active Allocs: %d\n", len(tracking_allocator.allocation_map))
	fmt.sbprintf(builder, "Total Allocs: %d\n", tracking_allocator.total_allocation_count)
	fmt.sbprintf(builder, "Total Frees: %d\n", tracking_allocator.total_free_count)
	fmt.sbprintf(builder, "Current Memory: %d KB\n", tracking_allocator.current_memory_allocated / 1024)
	fmt.sbprintf(builder, "Peak Memory: %d KB\n", tracking_allocator.peak_memory_allocated / 1024)
}

// Renderer statistics for draw call tracking
Renderer_Stats :: struct {
	draw_calls: int,
}

renderer_stats: Renderer_Stats

renderer_reset_stats :: proc() {
	renderer_stats.draw_calls = 0
}

renderer_increment_draw_calls :: proc(count: int = 1) {
	renderer_stats.draw_calls += count
}
