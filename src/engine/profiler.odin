package engine

import "core:fmt"
import "core:time"
import "core:strings"

// Profile section tracking
Profile_Section :: struct {
	name:      string,
	start_ns:  i64,
	elapsed_ns: i64,
}

Profile_Frame :: struct {
	sections:    [dynamic]Profile_Section,
	total_ns:    i64,
	frame_time:  f32,  // in milliseconds
}

Profiler :: struct {
	current_sections: [dynamic]Profile_Section,
	frame_history:    [dynamic]Profile_Frame,
	max_history:      int,
	current_frame:    Profile_Frame,
	frame_start_ns:   i64,
}

profiler: Profiler

profiler_init :: proc(max_history: int = 120) {
	profiler.max_history = max_history
	profiler.current_sections = make([dynamic]Profile_Section)
	profiler.frame_history = make([dynamic]Profile_Frame)
}

profiler_shutdown :: proc() {
	for frame in profiler.frame_history {
		delete(frame.sections)
	}
	delete(profiler.frame_history)
	delete(profiler.current_sections)
}

profiler_begin_frame :: proc() {
	profiler.frame_start_ns = time.tick_now()._nsec
	clear_dynamic_array(&profiler.current_sections)
}

profiler_end_frame :: proc() {
	frame_end_ns := time.tick_now()._nsec
	elapsed := frame_end_ns - profiler.frame_start_ns

	// Copy current sections into a new frame
	frame := Profile_Frame{
		sections   = make([dynamic]Profile_Section, len(profiler.current_sections)),
		total_ns   = elapsed,
		frame_time = f32(f64(elapsed) / 1_000_000.0), // ns -> ms
	}
	copy(frame.sections[:], profiler.current_sections[:])

	append(&profiler.frame_history, frame)

	// Keep history bounded
	if len(profiler.frame_history) > profiler.max_history {
		old_frame := profiler.frame_history[0]
		delete(old_frame.sections)
		ordered_remove(&profiler.frame_history, 0)
	}
}

profiler_begin :: proc(name: string) {
	section := Profile_Section{
		name     = name,
		start_ns = time.tick_now()._nsec,
	}
	append(&profiler.current_sections, section)
}

profiler_end :: proc(name: string) {
	end_ns := time.tick_now()._nsec
	for i := len(profiler.current_sections) - 1; i >= 0; i -= 1 {
		section := &profiler.current_sections[i]
		if section.name == name && section.elapsed_ns == 0 {
			section.elapsed_ns = end_ns - section.start_ns
			return
		}
	}
}

// Get average frame time over the last N frames
profiler_avg_frame_time :: proc(frames: int = 60) -> f32 {
	count := min(frames, len(profiler.frame_history))
	if count == 0 { return 0 }

	total: f32 = 0
	start_idx := len(profiler.frame_history) - count
	for i in start_idx..<len(profiler.frame_history) {
		total += profiler.frame_history[i].frame_time
	}
	return total / f32(count)
}

// Get average FPS over the last N frames
profiler_avg_fps :: proc(frames: int = 60) -> f32 {
	avg_ms := profiler_avg_frame_time(frames)
	if avg_ms <= 0 { return 0 }
	return 1000.0 / avg_ms
}

// Get the last frame's section data for display
profiler_get_last_frame_sections :: proc() -> []Profile_Section {
	if len(profiler.frame_history) == 0 {
		return nil
	}
	last := &profiler.frame_history[len(profiler.frame_history) - 1]
	return last.sections[:]
}

// Get frame history for graphing
profiler_get_frame_times :: proc() -> []f32 {
	if len(profiler.frame_history) == 0 {
		return nil
	}
	// Return a view into the frame times - caller should not modify
	return nil // We'll draw directly from history
}

// Format profiler data for debug display
profiler_format_stats :: proc(builder: ^strings.Builder) {
	avg_ms := profiler_avg_frame_time(60)
	avg_fps := profiler_avg_fps(60)

	fmt.sbprintf(builder, "FPS: %.1f (%.2f ms)\n", avg_fps, avg_ms)

	if len(profiler.frame_history) > 0 {
		last := &profiler.frame_history[len(profiler.frame_history) - 1]
		fmt.sbprintf(builder, "Frame Sections:\n")
		for section in last.sections {
			ms := f32(f64(section.elapsed_ns) / 1_000_000.0)
			pct := f32(0)
			if last.total_ns > 0 {
				pct = f32(f64(section.elapsed_ns) / f64(last.total_ns)) * 100
			}
			fmt.sbprintf(builder, "  %s: %.2f ms (%.1f%%)\n", section.name, ms, pct)
		}
	}
}

// Draw frame time graph
profiler_draw_graph :: proc(x, y, w, h: f32) {
	if renderer == nil { return }
	if len(profiler.frame_history) < 2 { return }

	// Background
	draw_rect(x, y, w, h, 0.1, 0.1, 0.1)

	// Draw grid lines (16.67ms = 60fps, 33.33ms = 30fps)
	fps60_y := y + h * 0.5
	fps30_y := y + h
	draw_rect(x, fps60_y, w, 1, 0.3, 0.3, 0.3)
	draw_rect(x, fps30_y - 1, w, 1, 0.5, 0.2, 0.2)

	// Draw frame time bars
	max_frames := min(len(profiler.frame_history), int(w))
	start_idx := len(profiler.frame_history) - max_frames
	bar_w := w / f32(max_frames)

	for i in 0..<max_frames {
		frame := &profiler.frame_history[start_idx + i]
		// Scale: 0ms at top, 33.33ms at bottom
		t := clamp(frame.frame_time / 33.33, 0.0, 1.0)
		bar_h := t * h
		bar_x := x + f32(i) * bar_w
		bar_y := y + h - bar_h

		// Color based on frame time: green < 16ms, yellow < 33ms, red > 33ms
		if frame.frame_time < 16.67 {
			draw_rect(bar_x, bar_y, bar_w - 0.5, bar_h, 0.0, 1.0, 0.0)
		} else if frame.frame_time < 33.33 {
			draw_rect(bar_x, bar_y, bar_w - 0.5, bar_h, 1.0, 1.0, 0.0)
		} else {
			draw_rect(bar_x, bar_y, bar_w - 0.5, bar_h, 1.0, 0.0, 0.0)
		}
	}
}

// Draw memory usage bar
profiler_draw_memory_bar :: proc(x, y, w, h: f32) {
	if renderer == nil { return }

	// Background
	draw_rect(x, y, w, h, 0.1, 0.1, 0.1)

	// Memory bar (scale arbitrarily to 10MB for visualization)
	max_mem := f32(10 * 1024 * 1024) // 10MB
	current := f32(tracking_allocator.current_memory_allocated)
	t := clamp(current / max_mem, 0.0, 1.0)

	bar_w := t * w
	if bar_w > 0 {
		// Color based on usage: green < 50%, yellow < 80%, red > 80%
		if t < 0.5 {
			draw_rect(x, y, bar_w, h, 0.0, 1.0, 0.0)
		} else if t < 0.8 {
			draw_rect(x, y, bar_w, h, 1.0, 1.0, 0.0)
		} else {
			draw_rect(x, y, bar_w, h, 1.0, 0.0, 0.0)
		}
	}

	// Border
	draw_rect(x, y, w, 1, 0.5, 0.5, 0.5)
	draw_rect(x, y + h - 1, w, 1, 0.5, 0.5, 0.5)
	draw_rect(x, y, 1, h, 0.5, 0.5, 0.5)
	draw_rect(x + w - 1, y, 1, h, 0.5, 0.5, 0.5)
}
