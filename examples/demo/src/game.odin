package game

import "engine:engine"
import "core:fmt"

// Player using new Vec2 math type
player_pos: engine.Vec2 = {368, 268}
player_speed: f32 = 300
player_rect: engine.Rect

// Audio test state
sound_id: int = -1
music_id: int = -1
sound_played: bool = false

// Font test
font_id: int = -1

// Atlas test
atlas_id: int = -1
frame_1: int = -1
frame_2: int = -1

// State machine IDs
state_menu: int = -1
state_play: int = -1
state_pause: int = -1

// Demo colors using Color struct
title_color: engine.Color = {1.0, 1.0, 0.0, 1.0}
info_color:  engine.Color = {0.8, 0.8, 0.8, 1.0}
player_color: engine.Color = {0.0, 1.0, 0.5, 1.0}

// Menu state
menu_selection: int = 0

@(export)
game_init :: proc() {
	engine.log_info("Demo game initialized! v0.4.0")

	// Initialize state machine
	engine.state_machine_init()

	// Register game states
	state_menu = engine.state_register("menu", menu_init, menu_update, menu_draw, menu_exit)
	state_play = engine.state_register("play", play_init, play_update, play_draw, play_exit)
	state_pause = engine.state_register("pause", pause_init, pause_update, pause_draw, pause_exit)

	// Start in menu state
	engine.state_change(state_menu)

	// Try to load assets (will fail gracefully if not present)
	sound_id = engine.load_sound("examples/demo/assets/sounds/jump.wav")
	music_id = engine.load_music("examples/demo/assets/music/loop.ogg")
	font_id  = engine.load_font("examples/demo/assets/fonts/default.ttf", 24)

	// Create a simple atlas with frames
	atlas_id = engine.load_atlas("examples/demo/assets/sprites/atlas.png")
	if atlas_id >= 0 {
		frame_1 = engine.add_atlas_frame(atlas_id, 0, 0, 32, 32)
		frame_2 = engine.add_atlas_frame(atlas_id, 32, 0, 32, 32)
	}
}

@(export)
game_update :: proc(dt: f32) {
	engine.state_machine_update(dt)
}

@(export)
game_draw :: proc() {
	engine.state_machine_draw()
}

@(export)
game_shutdown :: proc() {
	engine.stop_music()
	engine.state_machine_shutdown()
}

// --- Menu State ---

menu_init :: proc() {
	engine.log_info("Entering menu state")
	menu_selection = 0
}

menu_update :: proc(dt: f32) {
	if engine.is_key_pressed(.UP) {
		menu_selection -= 1
		if menu_selection < 0 { menu_selection = 1 }
	}
	if engine.is_key_pressed(.DOWN) {
		menu_selection += 1
		if menu_selection > 1 { menu_selection = 0 }
	}
	if engine.is_key_pressed(.START) || engine.is_key_pressed(.A) {
		switch menu_selection {
		case 0: engine.state_change(state_play)
		case 1: engine.log_info("Quit selected")
		}
	}
}

menu_draw :: proc() {
	engine.clear(0.05, 0.05, 0.1)

	if font_id >= 0 {
		engine.draw_text(300, 150, "VoidEngine Demo v0.4.0", font_id, title_color.r, title_color.g, title_color.b)
		engine.draw_text(320, 220, "New Features:", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(300, 250, "- Config system", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(300, 275, "- Structured logging", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(300, 300, "- Math utilities (Vec2, Rect)", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(300, 325, "- Game state machine", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(300, 375, "Press START or A to continue", font_id, info_color.r, info_color.g, info_color.b)
	}
}

menu_exit :: proc() {
	engine.log_info("Exiting menu state")
}

// --- Play State ---

play_init :: proc() {
	engine.log_info("Entering play state")
	player_pos = {368, 268}
	if music_id >= 0 {
		engine.play_music(music_id)
		engine.set_music_volume(0.5)
	}
}

play_update :: proc(dt: f32) {
	// Use Vec2 for movement
	move := engine.vec2_zero()
	if engine.is_key_down(.LEFT)  { move.x -= 1 }
	if engine.is_key_down(.RIGHT) { move.x += 1 }
	if engine.is_key_down(.UP)    { move.y -= 1 }
	if engine.is_key_down(.DOWN)  { move.y += 1 }

	// Normalize and scale by speed
	if engine.vec2_len_sq(move) > 0 {
		move = engine.vec2_normalize(move)
		move = engine.vec2_mul(move, player_speed * dt)
		player_pos = engine.vec2_add(player_pos, move)
	}

	// Clamp to screen using math utilities
	player_pos.x = engine.clamp(player_pos.x, 0, 736)
	player_pos.y = engine.clamp(player_pos.y, 0, 536)

	// Update player rect for collision
	player_rect = engine.rect(player_pos.x, player_pos.y, 64, 64)

	// Play sound on action press
	if !sound_played && (engine.is_key_pressed(.A) || engine.is_key_pressed(.B)) {
		if sound_id >= 0 {
			engine.play_sound(sound_id)
		}
		sound_played = true
	}
	if !engine.is_key_down(.A) && !engine.is_key_down(.B) {
		sound_played = false
	}

	// Pause with SELECT
	if engine.is_key_pressed(.SELECT) {
		engine.state_change(state_pause)
	}
}

play_draw :: proc() {
	engine.clear(0.05, 0.05, 0.1)

	if font_id >= 0 {
		engine.draw_text(10, 10, "VoidEngine Demo v0.4.0", font_id, title_color.r, title_color.g, title_color.b)
		engine.draw_text(10, 40, "Arrow keys to move", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(10, 70, "Z/A to play sound, SELECT to pause", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(10, 100, "ESC to quit", font_id, info_color.r, info_color.g, info_color.b)
	}

	// Draw atlas frames if loaded
	if atlas_id >= 0 && frame_1 >= 0 {
		engine.draw_atlas_frame(400, 100, atlas_id, frame_1)
	}
	if atlas_id >= 0 && frame_2 >= 0 {
		engine.draw_atlas_frame(440, 100, atlas_id, frame_2)
	}

	// Draw player using Color struct
	engine.draw_rect(player_pos.x, player_pos.y, 64, 64, player_color.r, player_color.g, player_color.b)
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
		engine.state_change(state_play)
	}
}

pause_draw :: proc() {
	// Draw the game behind
	play_draw()

	// Draw pause overlay
	engine.draw_rect(250, 200, 300, 200, 0.0, 0.0, 0.0)

	if font_id >= 0 {
		engine.draw_text(320, 280, "PAUSED", font_id, 1.0, 1.0, 1.0)
		engine.draw_text(280, 320, "Press START or A to resume", font_id, 0.8, 0.8, 0.8)
	}
}

pause_exit :: proc() {
	engine.log_info("Exiting pause state")
	engine.resume_music()
}
