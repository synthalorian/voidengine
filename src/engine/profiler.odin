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
