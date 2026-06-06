package game

import "engine:engine"
import "core:fmt"

// Game state IDs
state_menu: int = -1
state_play: int = -1
state_pause: int = -1

// v0.5.0 — Physics & Animation
player_body: int = -1
player_anim: int = -1
player_anim_idle: int = -1
player_anim_run: int = -1

// Ground bodies for physics
GROUND_COUNT :: 5
ground_bodies: [GROUND_COUNT]int

// v0.5.0 — Camera
camera_target: engine.Vec2

// v0.5.0 — Particles
jump_emitter: int = -1
land_emitter: int = -1

// v0.5.0 — Tilemap
tilemap: engine.Tilemap

// v0.6.0 — Audio
sound_jump: int = -1
sound_land: int = -1
music_bg: int = -1

// v0.6.0 — Save/Load
save_loaded: bool = false

// Font
font_id: int = -1

// Colors
title_color: engine.Color = {1.0, 1.0, 0.0, 1.0}
info_color: engine.Color = {0.8, 0.8, 0.8, 1.0}

@(export)
game_init :: proc() {
	engine.log_info("Demo game initialized! v1.0.0")

	// Initialize state machine
	engine.state_machine_init()

	// Register game states
	state_menu = engine.state_register("menu", menu_init, menu_update, menu_draw, menu_exit)
	state_play = engine.state_register("play", play_init, play_update, play_draw, play_exit)
	state_pause = engine.state_register("pause", pause_init, pause_update, pause_draw, pause_exit)

	// Start in menu state
	engine.state_change(state_menu)

	// Load assets
	sound_jump = engine.load_sound("examples/demo/assets/sounds/jump.wav")
	sound_land = engine.load_sound("examples/demo/assets/sounds/land.wav")
	music_bg = engine.load_music("examples/demo/assets/music/loop.ogg")
	font_id = engine.load_font("examples/demo/assets/fonts/default.ttf", 24)

	// v0.5.0: Setup animations (using sprite IDs as frames)
	// For demo, we'll use simple rect drawing if no sprites available
	engine.animation_init()

	// v0.5.0: Setup particles
	engine.particle_init()

	// v0.6.0: Load save if exists
	if engine.save_exists("examples/demo") {
		engine.save_from_file("examples/demo/save.json")
		save_loaded = true
		engine.log_info("Loaded save data")
	}
}

@(export)
game_update :: proc(dt: f32) {
	engine.state_machine_update(dt)
	engine.state_machine_update_transitions(dt)
}

@(export)
game_draw :: proc() {
	engine.state_machine_draw()
	engine.state_machine_draw_transition()
}

@(export)
game_shutdown :: proc() {
	engine.stop_music()
	engine.state_machine_shutdown()

	// v0.5.0: Cleanup
	engine.animation_shutdown()
	engine.particle_shutdown()

	// v0.6.0: Save game state
	engine.save_set_int("high_score", engine.save_get_int("high_score", 0))
	engine.save_to_file("examples/demo/save.json")
}

// --- Menu State ---

menu_selection: int = 0

menu_init :: proc() {
	engine.log_info("Entering menu state")
	menu_selection = 0
	engine.play_music(music_bg)
	engine.mixer_set_volume(.MUSIC, 0.6)
}

menu_update :: proc(dt: f32) {
	if engine.is_key_pressed(.UP) {
		menu_selection -= 1
		if menu_selection < 0 { menu_selection = 2 }
	}
	if engine.is_key_pressed(.DOWN) {
		menu_selection += 1
		if menu_selection > 2 { menu_selection = 0 }
	}
	if engine.is_key_pressed(.START) || engine.is_key_pressed(.A) {
		switch menu_selection {
		case 0:
			engine.state_change_with_transition(state_play, .FADE, 0.5)
		case 1:
			if save_loaded {
				engine.state_change_with_transition(state_play, .FADE, 0.5)
			}
		case 2:
			engine.log_info("Quit selected")
		}
	}
}

menu_draw :: proc() {
	engine.clear(0.05, 0.05, 0.15)

	if font_id >= 0 {
		engine.draw_text(250, 120, "VoidEngine Demo v1.0.0", font_id, title_color.r, title_color.g, title_color.b)

		// v0.5.0 features
		engine.draw_text(250, 180, "v0.5.0 Features:", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(270, 210, "- 2D Physics Engine", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(270, 235, "- Sprite Animation", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(270, 260, "- Camera System", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(270, 285, "- Particle System", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(270, 310, "- Tilemap Support", font_id, info_color.r, info_color.g, info_color.b)

		// v0.6.0 features
		engine.draw_text(250, 350, "v0.6.0 Features:", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(270, 380, "- Spatial Audio & Mixer", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(270, 405, "- Music Crossfade", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(270, 430, "- Save/Load System", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(270, 455, "- Debug Console (~)", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(270, 480, "- Performance Profiler", font_id, info_color.r, info_color.g, info_color.b)

		// Menu options
		y := 540
		options := [3]string{"New Game", "Continue", "Quit"}
		for i in 0..<3 {
			color := info_color
			if i == menu_selection {
				color = engine.COLOR_YELLOW
				engine.draw_text(230, f32(y), ">", font_id, color.r, color.g, color.b)
			}
			if i == 1 && !save_loaded {
				engine.draw_text(250, f32(y), options[i], font_id, 0.4, 0.4, 0.4)
			} else {
				engine.draw_text(250, f32(y), options[i], font_id, color.r, color.g, color.b)
			}
			y += 30
		}
	}
}

menu_exit :: proc() {
	engine.log_info("Exiting menu state")
}

// --- Play State (Platformer) ---

PLAYER_SPEED :: 300.0
JUMP_FORCE :: -500.0
PLAYER_W :: 32.0
PLAYER_H :: 48.0

play_init :: proc() {
	engine.log_info("Entering play state")

	// v0.5.0: Setup physics world
	engine.physics_clear_bodies()
	engine.physics_set_gravity({0, 1200})

	// Create player body
	player_body = engine.physics_add_body({400, 300}, {PLAYER_W, PLAYER_H}, .DYNAMIC)
	player := engine.physics_get_body(player_body)
	if player != nil {
		player.friction = 0.8
		player.restitution = 0.0
	}

	// Create ground platforms
	ground_bodies[0] = engine.physics_add_body({400, 550}, {800, 40}, .STATIC)
	ground_bodies[1] = engine.physics_add_body({200, 450}, {150, 20}, .STATIC)
	ground_bodies[2] = engine.physics_add_body({600, 400}, {150, 20}, .STATIC)
	ground_bodies[3] = engine.physics_add_body({400, 300}, {100, 20}, .STATIC)
	ground_bodies[4] = engine.physics_add_body({100, 350}, {80, 20}, .STATIC)

	// v0.5.0: Setup camera
	engine.camera_set_position({400, 300})
	engine.camera_set_target(&camera_target)
	engine.camera_set_smoothing(0.15)
	engine.camera_set_bounds({0, 0, 800, 600})

	// v0.5.0: Setup particles
	jump_emitter = engine.particle_preset_sparkle({0, 0})
	engine.particle_emitter_stop(jump_emitter)

	// v0.6.0: Setup audio listener
	engine.set_audio_listener({400, 300})
}

play_update :: proc(dt: f32) {
	player := engine.physics_get_body(player_body)
	if player == nil { return }

	// Horizontal movement
	move_x: f32 = 0
	if engine.is_key_down(.LEFT)  { move_x -= 1 }
	if engine.is_key_down(.RIGHT) { move_x += 1 }

	if move_x != 0 {
		engine.physics_add_velocity(player_body, {move_x * PLAYER_SPEED * dt, 0})
	}

	// Jump
	if engine.is_key_pressed(.A) && player.is_grounded {
		engine.physics_apply_impulse(player_body, {0, JUMP_FORCE})

		// v0.5.0: Particle effect at jump position
		engine.particle_emitter_set_position(jump_emitter, player.position)
		engine.particle_emitter_burst(jump_emitter, 10)

		// v0.6.0: Spatial audio
		engine.play_sound_spatial(sound_jump, player.position)
	}

	// Update camera target to follow player
	camera_target = player.position

	// v0.6.0: Update audio listener to follow player
	engine.set_audio_listener(player.position)

	// Pause
	if engine.is_key_pressed(.SELECT) {
		engine.state_change_with_transition(state_pause, .FADE, 0.3)
	}

	// v0.6.0: Quick save with F5
	if engine.is_scancode_down(engine.string_to_scancode("F5")) {
		engine.save_set_float("player_x", player.position.x)
		engine.save_set_float("player_y", player.position.y)
		engine.save_to_file("examples/demo/save.json")
		engine.log_info("Game saved!")
	}
}

play_draw :: proc() {
	engine.clear(0.1, 0.1, 0.2)

	// v0.5.0: Draw tilemap background (if loaded)
	// For demo, draw simple ground representation

	// Draw ground platforms
	for body_id in ground_bodies {
		body := engine.physics_get_body(body_id)
		if body == nil { continue }
		rect := engine.physics_body_get_rect(body_id)
		screen_rect := engine.camera_world_to_screen({rect.x, rect.y})
		engine.draw_rect(
			screen_rect.x,
			screen_rect.y,
			rect.w * engine.camera_get_zoom(),
			rect.h * engine.camera_get_zoom(),
			0.4, 0.3, 0.2,
		)
	}

	// Draw player
	player := engine.physics_get_body(player_body)
	if player != nil {
		screen_pos := engine.camera_world_to_screen(player.position)
		size_w := PLAYER_W * engine.camera_get_zoom()
		size_h := PLAYER_H * engine.camera_get_zoom()

		// Color based on grounded state
		if player.is_grounded {
			engine.draw_rect(screen_pos.x - size_w*0.5, screen_pos.y - size_h*0.5, size_w, size_h, 0.0, 1.0, 0.5)
		} else {
			engine.draw_rect(screen_pos.x - size_w*0.5, screen_pos.y - size_h*0.5, size_w, size_h, 0.0, 0.7, 1.0)
		}
	}

	// v0.5.0: Draw particles
	engine.particle_draw_all()

	// UI
	if font_id >= 0 {
		engine.draw_text(10, 10, "VoidEngine Demo v1.0.0", font_id, title_color.r, title_color.g, title_color.b)
		engine.draw_text(10, 40, "Arrow keys to move, Z/A to jump", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(10, 70, "SELECT to pause, ~ for console, F5 to save", font_id, info_color.r, info_color.g, info_color.b)

		// Physics debug info
		if player != nil {
			engine.draw_text(10, 100, fmt.tprintf("Pos: %.0f, %.0f | Grounded: %t", player.position.x, player.position.y, player.is_grounded), font_id, info_color.r, info_color.g, info_color.b)
		}
	}

	// v0.6.0: Draw profiler graph if enabled
	if engine.debug_overlay.show_profiler {
		engine.profiler_draw_graph(10, 150, 200, 60)
	}
}

play_exit :: proc() {
	engine.log_info("Exiting play state")
}

// --- Pause State ---

pause_init :: proc() {
	engine.log_info("Entering pause state")
	engine.pause_music()
}

pause_update :: proc(dt: f32) {
	if engine.is_key_pressed(.SELECT) || engine.is_key_pressed(.START) || engine.is_key_pressed(.A) {
		engine.state_change_with_transition(state_play, .FADE, 0.3)
	}
}

pause_draw :: proc() {
	// Draw game behind
	play_draw()

	// Draw pause overlay
	engine.draw_rect(0, 0, 800, 600, 0.0, 0.0, 0.0)

	if font_id >= 0 {
		engine.draw_text(320, 250, "PAUSED", font_id, 1.0, 1.0, 1.0)
		engine.draw_text(250, 300, "Press START or A to resume", font_id, 0.8, 0.8, 0.8)
		engine.draw_text(250, 330, "Press ~ for debug console", font_id, 0.6, 0.6, 0.6)
	}
}

pause_exit :: proc() {
	engine.log_info("Exiting pause state")
	engine.resume_music()
}
