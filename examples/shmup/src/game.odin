package game

import "engine:engine"
import "core:fmt"
import "core:math"

// v0.6.0 — Shmup Example Game
// Features: particles, spatial audio, physics, save/load, camera

// Game states
state_menu: int = -1
state_game: int = -1
state_gameover: int = -1

// Player
player_body: int = -1
player_speed: f32 = 400.0
player_shoot_timer: f32 = 0.0
PLAYER_SHOOT_DELAY :: 0.15

// Bullets (using physics bodies)
MAX_BULLETS :: 20
bullets: [MAX_BULLETS]int
bullet_active: [MAX_BULLETS]bool

// Enemies
MAX_ENEMIES :: 10
enemies: [MAX_ENEMIES]int
enemy_active: [MAX_ENEMIES]bool
enemy_spawn_timer: f32 = 0.0
ENEMY_SPAWN_DELAY :: 2.0

// Score
score: int = 0
high_score: int = 0

// Particles
explosion_emitters: [dynamic]int
thruster_emitter: int = -1

// Audio
sound_shoot: int = -1
sound_explosion: int = -1
sound_hit: int = -1
music_battle: int = -1

// Camera
camera_target: engine.Vec2

// Font
font_id: int = -1

// Colors
title_color: engine.Color = {1.0, 1.0, 0.0, 1.0}
info_color: engine.Color = {0.8, 0.8, 0.8, 1.0}

@(export)
game_init :: proc() {
	engine.log_info("Shmup game initialized! v0.6.0")

	// Initialize state machine
	engine.state_machine_init()

	state_menu = engine.state_register("menu", menu_init, menu_update, menu_draw, menu_exit)
	state_game = engine.state_register("game", game_state_init, game_state_update, game_state_draw, game_state_exit)
	state_gameover = engine.state_register("gameover", gameover_init, gameover_update, gameover_draw, gameover_exit)

	engine.state_change(state_menu)

	// Load assets
	sound_shoot = engine.load_sound("examples/shmup/assets/sounds/shoot.wav")
	sound_explosion = engine.load_sound("examples/shmup/assets/sounds/explosion.wav")
	sound_hit = engine.load_sound("examples/shmup/assets/sounds/hit.wav")
	music_battle = engine.load_music("examples/shmup/assets/music/battle.ogg")
	font_id = engine.load_font("examples/demo/assets/fonts/default.ttf", 24)

	// Initialize systems
	engine.animation_init()
	engine.particle_init()

	// Load high score
	if engine.save_exists("examples/shmup") {
		engine.save_from_file("examples/shmup/save.json")
		high_score = engine.save_get_int("high_score", 0)
	}

	explosion_emitters = make([dynamic]int)
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
	engine.animation_shutdown()
	engine.particle_shutdown()
	delete(explosion_emitters)

	// Save high score
	engine.save_set_int("high_score", high_score)
	engine.save_to_file("examples/shmup/save.json")
}

// --- Menu State ---

menu_init :: proc() {
	engine.log_info("Entering menu")
	engine.play_music(music_battle)
	engine.mixer_set_volume(.MUSIC, 0.5)
}

menu_update :: proc(dt: f32) {
	if engine.is_key_pressed(.START) || engine.is_key_pressed(.A) {
		engine.state_change_with_transition(state_game, .SLIDE_LEFT, 0.5)
	}
}

menu_draw :: proc() {
	engine.clear(0.02, 0.02, 0.08)

	if font_id >= 0 {
		engine.draw_text(280, 200, "VOID SHMUP", font_id, title_color.r, title_color.g, title_color.b)
		engine.draw_text(260, 260, "v0.6.0 Demo", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(220, 320, "Arrow keys to move, Z to shoot", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(260, 360, "Press START or A to play", font_id, info_color.r, info_color.g, info_color.b)

		if high_score > 0 {
			engine.draw_text(280, 420, fmt.tprintf("High Score: %d", high_score), font_id, 1.0, 0.8, 0.0)
		}
	}
}

menu_exit :: proc() {
	engine.log_info("Exiting menu")
}

// --- Game State ---

game_state_init :: proc() {
	engine.log_info("Entering game state")

	// Reset score
	score = 0

	// Setup physics
	engine.physics_clear_bodies()
	engine.physics_set_gravity({0, 0})

	// Create player
	player_body = engine.physics_add_body({400, 500}, {32, 32}, .DYNAMIC)
	player := engine.physics_get_body(player_body)
	if player != nil {
		player.friction = 0.9
	}

	// Clear bullets
	for i in 0..<MAX_BULLETS {
		bullets[i] = -1
		bullet_active[i] = false
	}

	// Clear enemies
	for i in 0..<MAX_ENEMIES {
		enemies[i] = -1
		enemy_active[i] = false
	}

	// Setup camera
	engine.camera_init(800, 600)
	engine.camera_set_position({400, 300})
	engine.camera_set_smoothing(0.2)

	// Setup particles
	engine.particle_shutdown()
	engine.particle_init()
	thruster_emitter = engine.particle_preset_smoke({0, 0})
	engine.particle_emitter_stop(thruster_emitter)

	// Setup audio listener
	engine.set_audio_listener({400, 300})
	engine.set_audio_listener_max_dist(800)

	// Clear old explosion emitters
	clear_dynamic_array(&explosion_emitters)
}

spawn_bullet :: proc(pos: engine.Vec2) {
	for i in 0..<MAX_BULLETS {
		if !bullet_active[i] {
			bullets[i] = engine.physics_add_body(pos, {6, 12}, .DYNAMIC)
			bullet_active[i] = true
			body := engine.physics_get_body(bullets[i])
			if body != nil {
				body.velocity = {0, -600}
				body.gravity_scale = 0
			}
			break
		}
	}
}

spawn_enemy :: proc() {
	for i in 0..<MAX_ENEMIES {
		if !enemy_active[i] {
			x := 100.0 + engine.random_range(0, 600)
			enemies[i] = engine.physics_add_body({x, -30}, {28, 28}, .DYNAMIC)
			enemy_active[i] = true
			body := engine.physics_get_body(enemies[i])
			if body != nil {
				body.velocity = {0, 150 + engine.random_range(0, 100)}
				body.gravity_scale = 0
			}
			break
		}
	}
}

game_state_update :: proc(dt: f32) {
	player := engine.physics_get_body(player_body)
	if player == nil { return }

	// Player movement
	move := engine.vec2_zero()
	if engine.is_key_down(.LEFT)  { move.x -= 1 }
	if engine.is_key_down(.RIGHT) { move.x += 1 }
	if engine.is_key_down(.UP)    { move.y -= 1 }
	if engine.is_key_down(.DOWN)  { move.y += 1 }

	if engine.vec2_len_sq(move) > 0 {
		move = engine.vec2_normalize(move)
		player.velocity = engine.vec2_mul(move, player_speed)
	} else {
		player.velocity = engine.vec2_mul(player.velocity, 0.9)
	}

	// Clamp player to screen
	player.position.x = engine.clamp(player.position.x, 20, 780)
	player.position.y = engine.clamp(player.position.y, 50, 550)

	// Shoot
	player_shoot_timer -= dt
	if engine.is_key_down(.A) && player_shoot_timer <= 0 {
		spawn_bullet({player.position.x, player.position.y - 20})
		player_shoot_timer = PLAYER_SHOOT_DELAY

		// v0.6.0: Spatial audio
		engine.play_sound_spatial(sound_shoot, player.position)
	}

	// Update thruster particles
	engine.particle_emitter_set_position(thruster_emitter, {player.position.x, player.position.y + 20})
	engine.particle_emitter_start(thruster_emitter)

	// Spawn enemies
	enemy_spawn_timer -= dt
	if enemy_spawn_timer <= 0 {
		spawn_enemy()
		enemy_spawn_timer = ENEMY_SPAWN_DELAY
	}

	// Update bullets (despawn off-screen)
	for i in 0..<MAX_BULLETS {
		if !bullet_active[i] { continue }
		body := engine.physics_get_body(bullets[i])
		if body == nil || body.position.y < -50 {
			if body != nil {
				engine.physics_remove_body(bullets[i])
			}
			bullets[i] = -1
			bullet_active[i] = false
		}
	}

	// Update enemies (despawn off-screen)
	for i in 0..<MAX_ENEMIES {
		if !enemy_active[i] { continue }
		body := engine.physics_get_body(enemies[i])
		if body == nil || body.position.y > 650 {
			if body != nil {
				engine.physics_remove_body(enemies[i])
			}
			enemies[i] = -1
			enemy_active[i] = false
		}
	}

	// Check bullet-enemy collisions
	for b in 0..<MAX_BULLETS {
		if !bullet_active[b] { continue }
		bullet_body := engine.physics_get_body(bullets[b])
		if bullet_body == nil { continue }

		for e in 0..<MAX_ENEMIES {
			if !enemy_active[e] { continue }
			enemy_body := engine.physics_get_body(enemies[e])
			if enemy_body == nil { continue }

			if engine.circle_circle_collision(bullet_body.position, 3, enemy_body.position, 14) {
				// Hit!
				score += 100

				// v0.5.0: Explosion particles
				explosion_id := engine.particle_preset_explosion(enemy_body.position)
				append(&explosion_emitters, explosion_id)

				// v0.6.0: Spatial audio
				engine.play_sound_spatial(sound_explosion, enemy_body.position)

				// Remove bullet and enemy
				engine.physics_remove_body(bullets[b])
				bullets[b] = -1
				bullet_active[b] = false

				engine.physics_remove_body(enemies[e])
				enemies[e] = -1
				enemy_active[e] = false
				break
			}
		}
	}

	// Check player-enemy collisions
	for e in 0..<MAX_ENEMIES {
		if !enemy_active[e] { continue }
		enemy_body := engine.physics_get_body(enemies[e])
		if enemy_body == nil { continue }

		if engine.circle_circle_collision(player.position, 16, enemy_body.position, 14) {
			// Player hit!
			engine.play_sound_spatial(sound_hit, player.position)

			// Update high score
			if score > high_score {
				high_score = score
			}

			engine.state_change_with_transition(state_gameover, .FADE, 1.0)
			return
		}
	}

	// Update camera to follow player
	camera_target = player.position
	engine.camera_update(dt)

	// Update audio listener
	engine.set_audio_listener(player.position)

	// Pause
	if engine.is_key_pressed(.SELECT) {
		engine.state_change(state_menu)
	}
}

game_state_draw :: proc() {
	engine.clear(0.02, 0.02, 0.08)

	// Draw stars background (simple dots)
	for i in 0..<50 {
		sx := f32((i * 137) % 800)
		sy := f32((i * 93) % 600)
		engine.draw_rect(sx, sy, 2, 2, 0.8, 0.8, 1.0)
	}

	// Draw player
	player := engine.physics_get_body(player_body)
	if player != nil {
		screen_pos := engine.camera_world_to_screen(player.position)
		size := 32.0 * engine.camera_get_zoom()
		engine.draw_rect(screen_pos.x - size*0.5, screen_pos.y - size*0.5, size, size, 0.0, 1.0, 0.5)
	}

	// Draw bullets
	for i in 0..<MAX_BULLETS {
		if !bullet_active[i] { continue }
		body := engine.physics_get_body(bullets[i])
		if body == nil { continue }
		screen_pos := engine.camera_world_to_screen(body.position)
		engine.draw_rect(screen_pos.x - 3, screen_pos.y - 6, 6, 12, 1.0, 1.0, 0.0)
	}

	// Draw enemies
	for i in 0..<MAX_ENEMIES {
		if !enemy_active[i] { continue }
		body := engine.physics_get_body(enemies[i])
		if body == nil { continue }
		screen_pos := engine.camera_world_to_screen(body.position)
		size := 28.0 * engine.camera_get_zoom()
		engine.draw_rect(screen_pos.x - size*0.5, screen_pos.y - size*0.5, size, size, 1.0, 0.2, 0.2)
	}

	// v0.5.0: Draw particles
	engine.particle_draw_all()

	// UI
	if font_id >= 0 {
		engine.draw_text(10, 10, fmt.tprintf("Score: %d", score), font_id, 1.0, 1.0, 1.0)
		engine.draw_text(10, 40, fmt.tprintf("High: %d", high_score), font_id, 1.0, 0.8, 0.0)
		engine.draw_text(10, 70, "Arrow keys: move | Z: shoot", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(10, 100, "SELECT: menu | ~: console", font_id, info_color.r, info_color.g, info_color.b)
	}

	// v0.6.0: Profiler graph
	if engine.debug_overlay.show_profiler {
		engine.profiler_draw_graph(600, 10, 190, 60)
	}
}

game_state_exit :: proc() {
	engine.log_info("Exiting game state")
	engine.particle_shutdown()
	engine.particle_init()
}

// --- Game Over State ---

gameover_init :: proc() {
	engine.log_info("Game Over!")
	engine.pause_music()
}

gameover_update :: proc(dt: f32) {
	if engine.is_key_pressed(.START) || engine.is_key_pressed(.A) {
		engine.state_change_with_transition(state_game, .SLIDE_UP, 0.5)
	}
	if engine.is_key_pressed(.SELECT) {
		engine.state_change_with_transition(state_menu, .FADE, 0.5)
	}
}

gameover_draw :: proc() {
	engine.clear(0.1, 0.02, 0.02)

	if font_id >= 0 {
		engine.draw_text(280, 200, "GAME OVER", font_id, 1.0, 0.0, 0.0)
		engine.draw_text(300, 260, fmt.tprintf("Score: %d", score), font_id, 1.0, 1.0, 1.0)
		if score >= high_score && score > 0 {
			engine.draw_text(260, 300, "NEW HIGH SCORE!", font_id, 1.0, 0.8, 0.0)
		}
		engine.draw_text(250, 360, "Press START to retry", font_id, info_color.r, info_color.g, info_color.b)
		engine.draw_text(250, 390, "Press SELECT for menu", font_id, info_color.r, info_color.g, info_color.b)
	}
}

gameover_exit :: proc() {
	engine.log_info("Exiting game over state")
	engine.resume_music()
}
