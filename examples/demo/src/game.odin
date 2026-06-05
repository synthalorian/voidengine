package game

import "engine:engine"

player_x: f32 = 368
player_y: f32 = 268
player_speed: f32 = 300

@(export)
game_init :: proc() {
	engine.print("Demo game initialized!")
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
}

@(export)
game_draw :: proc() {
	engine.clear(0.05, 0.05, 0.1)
	engine.draw_text(10, 10, "VoidEngine Demo v0.1.0")
	engine.draw_text(10, 30, "Arrow keys to move")
	engine.draw_rect(player_x, player_y, 64, 64, 0.0, 1.0, 0.5)
}

@(export)
game_shutdown :: proc() {
}
