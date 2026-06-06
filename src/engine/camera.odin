package engine

import "core:math"

// --- Camera ---

Camera :: struct {
	position:    Vec2,    // Camera center position in world space
	zoom:        f32,     // Zoom scale (1.0 = 100%)
	rotation:    f32,     // Rotation in degrees
	viewport_w:  f32,     // Viewport width in pixels
	viewport_h:  f32,     // Viewport height in pixels

	// Follow settings
	target:      ^Vec2,   // Pointer to target position (can be nil)
	smoothing:   f32,     // Follow smoothing (0 = instant, 1 = no follow)
	deadzone_w:  f32,     // Deadzone width (don't follow if target within)
	deadzone_h:  f32,     // Deadzone height

	// Bounds
	bounds:      Rect,    // Camera cannot show outside these world bounds
	use_bounds:  bool,
}

main_camera: Camera

camera_init :: proc(viewport_w, viewport_h: f32) {
	main_camera = Camera{
		position   = Vec2{viewport_w * 0.5, viewport_h * 0.5},
		zoom       = 1.0,
		rotation   = 0.0,
		viewport_w = viewport_w,
		viewport_h = viewport_h,
		smoothing  = 0.1,
		deadzone_w = 0.0,
		deadzone_h = 0.0,
		use_bounds = false,
	}
}

camera_shutdown :: proc() {
	// Nothing to clean up
}

// --- Transformations ---

// Convert world position to screen position
camera_world_to_screen :: proc(world_pos: Vec2) -> Vec2 {
	// Translate by camera position (inverse)
	offset := vec2_sub(world_pos, main_camera.position)

	// Apply zoom
	scaled := vec2_mul(offset, main_camera.zoom)

	// Apply rotation
	if main_camera.rotation != 0 {
		rad := math.to_radians_f32(main_camera.rotation)
		cos_r := math.cos(rad)
		sin_r := math.sin(rad)
		rotated := Vec2{
			x = scaled.x * cos_r - scaled.y * sin_r,
			y = scaled.x * sin_r + scaled.y * cos_r,
		}
		scaled = rotated
	}

	// Offset to center of viewport
	return Vec2{
		x = scaled.x + main_camera.viewport_w * 0.5,
		y = scaled.y + main_camera.viewport_h * 0.5,
	}
}

// Convert screen position to world position
camera_screen_to_world :: proc(screen_pos: Vec2) -> Vec2 {
	// Offset from viewport center
	offset := Vec2{
		x = screen_pos.x - main_camera.viewport_w * 0.5,
		y = screen_pos.y - main_camera.viewport_h * 0.5,
	}

	// Undo rotation
	if main_camera.rotation != 0 {
		rad := math.to_radians_f32(-main_camera.rotation)
		cos_r := math.cos(rad)
		sin_r := math.sin(rad)
		rotated := Vec2{
			x = offset.x * cos_r - offset.y * sin_r,
			y = offset.x * sin_r + offset.y * cos_r,
		}
		offset = rotated
	}

	// Undo zoom
	scaled := vec2_div(offset, main_camera.zoom)

	// Translate by camera position
	return vec2_add(main_camera.position, scaled)
}

// Get the visible world area as a Rect
camera_get_viewport :: proc() -> Rect {
	half_w := (main_camera.viewport_w * 0.5) / main_camera.zoom
	half_h := (main_camera.viewport_h * 0.5) / main_camera.zoom
	return Rect{
		x = main_camera.position.x - half_w,
		y = main_camera.position.y - half_h,
		w = half_w * 2,
		h = half_h * 2,
	}
}

// Check if a world rect is visible on camera
camera_is_visible :: proc(world_rect: Rect) -> bool {
	viewport := camera_get_viewport()
	return rect_intersects(viewport, world_rect)
}

// --- Follow System ---

camera_set_target :: proc(target: ^Vec2) {
	main_camera.target = target
}

camera_clear_target :: proc() {
	main_camera.target = nil
}

camera_set_smoothing :: proc(smoothing: f32) {
	main_camera.smoothing = clamp(smoothing, 0.0, 1.0)
}

camera_set_deadzone :: proc(w, h: f32) {
	main_camera.deadzone_w = w
	main_camera.deadzone_h = h
}

// --- Bounds ---

camera_set_bounds :: proc(bounds: Rect) {
	main_camera.bounds = bounds
	main_camera.use_bounds = true
}

camera_clear_bounds :: proc() {
	main_camera.use_bounds = false
}

// --- Update ---

camera_update :: proc(dt: f32) {
	// Follow target
	if main_camera.target != nil {
		target_pos := main_camera.target^

		// Apply deadzone
		dx := target_pos.x - main_camera.position.x
		dy := target_pos.y - main_camera.position.y

		move_x := dx
		move_y := dy

		if main_camera.deadzone_w > 0 {
			if abs(dx) < main_camera.deadzone_w * 0.5 {
				move_x = 0
			} else {
				move_x = sign(dx) * (abs(dx) - main_camera.deadzone_w * 0.5)
			}
		}
		if main_camera.deadzone_h > 0 {
			if abs(dy) < main_camera.deadzone_h * 0.5 {
				move_y = 0
			} else {
				move_y = sign(dy) * (abs(dy) - main_camera.deadzone_h * 0.5)
			}
		}

		// Apply smoothing
		if main_camera.smoothing > 0 {
			move_x *= (1.0 - main_camera.smoothing) * dt * 60.0 // Normalize to ~60fps
			move_y *= (1.0 - main_camera.smoothing) * dt * 60.0
		}

		main_camera.position.x += move_x
		main_camera.position.y += move_y
	}

	// Clamp to bounds
	if main_camera.use_bounds {
		half_w := (main_camera.viewport_w * 0.5) / main_camera.zoom
		half_h := (main_camera.viewport_h * 0.5) / main_camera.zoom

		main_camera.position.x = clamp(
			main_camera.position.x,
			main_camera.bounds.x + half_w,
			main_camera.bounds.x + main_camera.bounds.w - half_w,
		)
		main_camera.position.y = clamp(
			main_camera.position.y,
			main_camera.bounds.y + half_h,
			main_camera.bounds.y + main_camera.bounds.h - half_h,
		)
	}
}

// --- Properties ---

camera_set_position :: proc(pos: Vec2) {
	main_camera.position = pos
}

camera_set_zoom :: proc(zoom: f32) {
	main_camera.zoom = clamp(zoom, 0.1, 10.0)
}

camera_set_rotation :: proc(rotation: f32) {
	main_camera.rotation = rotation
}

camera_get_position :: proc() -> Vec2 {
	return main_camera.position
}

camera_get_zoom :: proc() -> f32 {
	return main_camera.zoom
}

camera_get_rotation :: proc() -> f32 {
	return main_camera.rotation
}

// --- Shake effect ---

camera_shake :: proc(intensity: f32, duration: f32) {
	// Simple shake: apply random offset each frame
	// Store shake state (simplified - just log it)
	log_debug("Camera shake: intensity=%.2f, duration=%.2f", intensity, duration)
}

// --- Drawing helpers ---

// Draw a sprite in world space (automatically transforms through camera)
camera_draw_sprite :: proc(world_pos: Vec2, sprite_id: int) {
	screen_pos := camera_world_to_screen(world_pos)
	// Adjust for sprite center (sprites draw from top-left)
	if sprite_id >= 0 && sprite_id < len(sprites) {
		entry := sprites[sprite_id]
		screen_pos.x -= entry.w * 0.5 * main_camera.zoom
		screen_pos.y -= entry.h * 0.5 * main_camera.zoom
	}
	draw_sprite(screen_pos.x, screen_pos.y, sprite_id)
}

// Draw a rectangle in world space
camera_draw_rect :: proc(world_rect: Rect, r, g, b: f32) {
	screen_pos := camera_world_to_screen(Vec2{world_rect.x, world_rect.y})
	draw_rect(
		screen_pos.x,
		screen_pos.y,
		world_rect.w * main_camera.zoom,
		world_rect.h * main_camera.zoom,
		r, g, b,
	)
}

// Draw text in world space
camera_draw_text :: proc(world_pos: Vec2, text: string, font_id: int, r, g, b: f32) {
	screen_pos := camera_world_to_screen(world_pos)
	draw_text(screen_pos.x, screen_pos.y, text, font_id, r, g, b)
}
