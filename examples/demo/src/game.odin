package game

import "engine:engine"
import "core:fmt"

player_x: f32 = 368
player_y: f32 = 268
player_speed: f32 = 300

// Audio test state
sound_id: int = -1
music_id: int = -1
sound_played: bool = false

// Font test
font_id: int = -1

// Atlas test (simulated with rects for demo)
atlas_id: int = -1
frame_1: int = -1
frame_2: int = -1

@(export)
game_init :: proc() {
	engine.print("Demo game initialized! v0.2.0")

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

	// Start music if loaded
	if music_id >= 0 {
		engine.play_music(music_id)
		engine.set_music_volume(0.5)
	}
}

@(export)
game_update :: proc(dt: f32) {
	if engine.is_key_down(.LEFT)  { player_x -= player_speed * dt }
	if engine.is_key_down(.RIGHT) { player_x += player_speed * dt }
	if engine.is_key_down(.UP)    { player_y -= player_speed * dt }
	if engine.is_key_down(.DOWN)  { player_y += player_speed * dt }

	// Keep player on screen
	if player_x < 0 { player_x = 0 }
	if player_y < 0 { player_y = 0 }
	if player_x > 736 { player_x = 736 }
	if player_y > 536 { player_y = 536 }

	// Play sound on first key press (demo audio)
	if !sound_played && (engine.is_key_pressed(.A) || engine.is_key_pressed(.B)) {
		if sound_id >= 0 {
			engine.play_sound(sound_id)
		}
		sound_played = true
	}

	// Reset sound flag when no action keys pressed
	if !engine.is_key_down(.A) && !engine.is_key_down(.B) {
		sound_played = false
	}
}

@(export)
game_draw :: proc() {
	engine.clear(0.05, 0.05, 0.1)

	// Draw title with real font if available
	if font_id >= 0 {
		engine.draw_text(10, 10, "VoidEngine Demo v0.2.0", font_id, 1.0, 1.0, 0.0)
		engine.draw_text(10, 40, "Arrow keys to move", font_id, 0.8, 0.8, 0.8)
		engine.draw_text(10, 70, "Z/A to play sound, ESC to quit", font_id, 0.8, 0.8, 0.8)
	} else {
		// Fallback to placeholder rects if no font loaded
		engine.draw_rect(10, 10, 4, 4, 1.0, 1.0, 0.0)
		engine.draw_rect(10, 30, 4, 4, 1.0, 1.0, 1.0)
	}

	// Draw atlas frames if loaded
	if atlas_id >= 0 && frame_1 >= 0 {
		engine.draw_atlas_frame(400, 100, atlas_id, frame_1)
	}
	if atlas_id >= 0 && frame_2 >= 0 {
		engine.draw_atlas_frame(440, 100, atlas_id, frame_2)
	}

	// Draw player
	engine.draw_rect(player_x, player_y, 64, 64, 0.0, 1.0, 0.5)
}

@(export)
game_shutdown :: proc() {
	engine.stop_music()
}
