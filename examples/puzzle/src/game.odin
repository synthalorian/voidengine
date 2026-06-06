package game

import "engine:engine"
import "core:fmt"
import "core:math"

// v1.0.0 — Puzzle Example Game
// Features: grid-based puzzle, save/load progress, state machine (menu/play/victory)

// Game constants
GRID_SIZE :: 4
CELL_SIZE :: 100
GRID_OFFSET_X :: 150
GRID_OFFSET_Y :: 100
ANIMATION_SPEED :: 10.0

// Game states
state_menu: int = -1
state_play: int = -1
state_victory: int = -1

// Tile data
Tile :: struct {
	value:     int,
	x, y:      int,     // Grid position
	target_x:  f32,     // For animation
	target_y:  f32,
	animating: bool,
}

// Game grid
grid: [GRID_SIZE][GRID_SIZE]Tile
score: int = 0
moves: int = 0
best_score: int = 0
best_moves: int = 0
level: int = 1

// Colors
tile_colors := []engine.Color{
	{0.9, 0.9, 0.9, 1.0},   // 0 - empty
	{0.93, 0.89, 0.85, 1.0}, // 1
	{0.93, 0.88, 0.78, 1.0}, // 2
	{0.95, 0.69, 0.48, 1.0}, // 3
	{0.96, 0.49, 0.35, 1.0}, // 4
	{0.97, 0.35, 0.22, 1.0}, // 5
	{0.98, 0.80, 0.18, 1.0}, // 6
	{0.98, 0.75, 0.15, 1.0}, // 7
	{0.98, 0.70, 0.12, 1.0}, // 8
}

// Font
font_id: int = -1

// Sound
sound_move: int = -1
sound_merge: int = -1
sound_win: int = -1

// Animation
animating_tiles: int = 0

@(export)
game_init :: proc() {
	engine.log_info("Puzzle game initialized! v1.0.0")

	// Initialize state machine
	engine.state_machine_init()

	state_menu = engine.state_register("menu", menu_init, menu_update, menu_draw, menu_exit)
	state_play = engine.state_register("play", play_init, play_update, play_draw, play_exit)
	state_victory = engine.state_register("victory", victory_init, victory_update, victory_draw, victory_exit)

	// Load assets
	font_id = engine.load_font("examples/demo/assets/fonts/default.ttf", 28)
	sound_move = engine.load_sound("examples/demo/assets/sounds/jump.wav")
	sound_merge = engine.load_sound("examples/demo/assets/sounds/land.wav")
	sound_win = engine.load_sound("examples/shmup/assets/sounds/shoot.wav")

	// Load best scores from save
	if engine.save_exists("examples/puzzle") {
		engine.save_from_file("examples/puzzle/save.json")
		best_score = engine.save_get_int("best_score", 0)
		best_moves = engine.save_get_int("best_moves", 0)
		level = engine.save_get_int("level", 1)
		engine.log_info("Loaded save - Best: %d pts, %d moves", best_score, best_moves)
	}

	// Start in menu
	engine.state_change(state_menu)
}

@(export)
game_update :: proc(dt: f32) {
	engine.state_machine_update(dt)
}

@(export)
game_draw :: proc() {
	engine.clear(0.98, 0.96, 0.94)
	engine.state_machine_draw()
}

@(export)
game_shutdown :: proc() {
	// Save progress
	engine.save_set_int("best_score", best_score)
	engine.save_set_int("best_moves", best_moves)
	engine.save_set_int("level", level)
	engine.save_to_file("examples/puzzle/save.json")
	engine.log_info("Saved puzzle game progress")
}

// --- Menu State ---

menu_init :: proc() {
	engine.log_info("Menu state initialized")
}

menu_update :: proc(dt: f32) {
	if engine.is_key_pressed(.START) || engine.is_key_pressed(.A) {
		engine.state_change(state_play)
	}
}

menu_draw :: proc() {
	// Title
	engine.draw_text(200, 120, "PUZZLE SHIFT", font_id, f32(0.47), f32(0.33), f32(0.28))

	// Instructions
	engine.draw_text(180, 220, "Arrow keys to move tiles", font_id, f32(0.5), f32(0.5), f32(0.5))
	engine.draw_text(180, 260, "Combine tiles to reach 2048!", font_id, f32(0.5), f32(0.5), f32(0.5))
	engine.draw_text(180, 320, fmt.tprintf("Best Score: %d", best_score), font_id, f32(0.5), f32(0.5), f32(0.5))
	engine.draw_text(180, 360, fmt.tprintf("Best Moves: %d", best_moves), font_id, f32(0.5), f32(0.5), f32(0.5))
	engine.draw_text(180, 440, "Press ENTER or Z to start", font_id, f32(0.5), f32(0.5), f32(0.5))

	// Draw a decorative grid preview
	draw_grid_preview()
}

menu_exit :: proc() {}

draw_grid_preview :: proc() {
	for y in 0..<GRID_SIZE {
		for x in 0..<GRID_SIZE {
			px := GRID_OFFSET_X + x * CELL_SIZE
			py := GRID_OFFSET_Y + y * CELL_SIZE + 50
			
			// Draw cell background
			color := engine.Color{0.85, 0.80, 0.75, 1.0}
			engine.draw_rect(f32(px), f32(py), CELL_SIZE - 4, CELL_SIZE - 4, color.r, color.g, color.b)
		}
	}
}

// --- Play State ---

play_init :: proc() {
	engine.log_info("Play state initialized")
	init_grid()
	score = 0
	moves = 0
	spawn_tile()
	spawn_tile()
}

play_update :: proc(dt: f32) {
	// Handle input
	dir_x, dir_y: int
	moved := false

	if engine.is_key_pressed(.UP) {
		dir_y = -1
		moved = true
	} else if engine.is_key_pressed(.DOWN) {
		dir_y = 1
		moved = true
	} else if engine.is_key_pressed(.LEFT) {
		dir_x = -1
		moved = true
	} else if engine.is_key_pressed(.RIGHT) {
		dir_x = 1
		moved = true
	}

	if moved && !is_animating() {
		if move_tiles(dir_x, dir_y) {
			moves += 1
			spawn_tile()
			engine.play_sound(sound_move)

			// Check for win condition
			if check_win_condition() {
				if score > best_score {
					best_score = score
				}
				if moves < best_moves || best_moves == 0 {
					best_moves = moves
				}
				engine.play_sound(sound_win)
				engine.state_change_with_transition(state_victory, .FADE, 1.0)
			}

			// Check for game over
			if is_game_over() {
				if score > best_score {
					best_score = score
				}
				engine.log_info("Game over! Score: %d", score)
			}
		}
	}

	// Update animations
	update_animations(dt)

	// Pause/menu
	if engine.is_key_pressed(.START) {
		engine.state_change_with_transition(state_menu, .FADE, 0.3)
	}
}

play_draw :: proc() {
	draw_grid()
	draw_ui()
}

play_exit :: proc() {
	// Save progress on exit
	engine.save_set_int("best_score", best_score)
	engine.save_set_int("best_moves", best_moves)
	engine.save_set_int("level", level)
	engine.save_to_file("examples/puzzle/save.json")
}

// --- Victory State ---

victory_init :: proc() {
	engine.log_info("Victory! Score: %d in %d moves", score, moves)
}

victory_update :: proc(dt: f32) {
	if engine.is_key_pressed(.START) || engine.is_key_pressed(.A) {
		level += 1
		engine.state_change(state_play)
	}
	if engine.is_key_pressed(.SELECT) {
		engine.state_change_with_transition(state_menu, .SLIDE_RIGHT, 0.5)
	}
}

victory_draw :: proc() {
	// Semi-transparent overlay
	engine.draw_rect(0, 0, 800, 600, 0.0, 0.0, 0.0)

	// Victory text
	engine.draw_text(250, 200, "YOU WIN!", font_id, 1.0, 0.84, 0.0)
	engine.draw_text(220, 280, fmt.tprintf("Score: %d", score), font_id, 1.0, 1.0, 1.0)
	engine.draw_text(220, 320, fmt.tprintf("Moves: %d", moves), font_id, 1.0, 1.0, 1.0)
	engine.draw_text(180, 400, "Press ENTER to continue", font_id, 0.8, 0.8, 0.8)
	engine.draw_text(180, 440, "Press TAB for menu", font_id, 0.8, 0.8, 0.8)
}

victory_exit :: proc() {}

// --- Grid Logic ---

init_grid :: proc() {
	for y in 0..<GRID_SIZE {
		for x in 0..<GRID_SIZE {
			grid[y][x] = Tile{
				value = 0,
				x = x,
				y = y,
				target_x = f32(x),
				target_y = f32(y),
				animating = false,
			}
		}
	}
}

spawn_tile :: proc() {
	// Find empty cells
	empty_cells: [dynamic][2]int
	defer delete(empty_cells)

	for y in 0..<GRID_SIZE {
		for x in 0..<GRID_SIZE {
			if grid[y][x].value == 0 {
				append(&empty_cells, [2]int{x, y})
			}
		}
	}

	if len(empty_cells) == 0 {
		return
	}

	// Pick random empty cell
	idx := int(engine.random_f32() * f32(len(empty_cells)))
	if idx >= len(empty_cells) {
		idx = len(empty_cells) - 1
	}

	cell := empty_cells[idx]
	x, y := cell[0], cell[1]

	// 90% chance of value 1, 10% chance of value 2
	value := 1
	if engine.random_f32() < 0.1 {
		value = 2
	}

	grid[y][x].value = value
}

move_tiles :: proc(dir_x, dir_y: int) -> bool {
	moved := false
	merged := make(map[[2]int]bool)
	defer delete(merged)

	// Determine iteration order based on direction
	start_x, end_x, step_x: int = 0, GRID_SIZE, 1
	start_y, end_y, step_y: int = 0, GRID_SIZE, 1

	if dir_x == 1 {
		start_x = GRID_SIZE - 1
		end_x = -1
		step_x = -1
	}
	if dir_y == 1 {
		start_y = GRID_SIZE - 1
		end_y = -1
		step_y = -1
	}

	for y := start_y; y != end_y; y += step_y {
		for x := start_x; x != end_x; x += step_x {
			if grid[y][x].value == 0 {
				continue
			}

			// Find the furthest position we can move to
			tx, ty := x, y
			for {
				nx := tx + dir_x
				ny := ty + dir_y

				if nx < 0 || nx >= GRID_SIZE || ny < 0 || ny >= GRID_SIZE {
					break
				}

				if grid[ny][nx].value == 0 {
					tx = nx
					ty = ny
				} else if grid[ny][nx].value == grid[y][x].value && !merged[{nx, ny}] {
					// Can merge
					tx = nx
					ty = ny
					break
				} else {
					break
				}
			}

			if tx != x || ty != y {
				// Move the tile
				if grid[ty][tx].value == grid[y][x].value && (tx != x || ty != y) {
					// Merge
					grid[ty][tx].value += 1
					score += int(math.pow(2.0, f64(grid[ty][tx].value)))
					merged[{tx, ty}] = true
					grid[y][x].value = 0
					moved = true
				} else if grid[ty][tx].value == 0 {
					// Move to empty
					grid[ty][tx].value = grid[y][x].value
					grid[y][x].value = 0
					moved = true
				}
			}
		}
	}

	return moved
}

check_win_condition :: proc() -> bool {
	for y in 0..<GRID_SIZE {
		for x in 0..<GRID_SIZE {
			if grid[y][x].value >= 11 { // 2^11 = 2048
				return true
			}
		}
	}
	return false
}

is_game_over :: proc() -> bool {
	// Check for empty cells
	for y in 0..<GRID_SIZE {
		for x in 0..<GRID_SIZE {
			if grid[y][x].value == 0 {
				return false
			}
		}
	}

	// Check for possible merges
	for y in 0..<GRID_SIZE {
		for x in 0..<GRID_SIZE {
			if x < GRID_SIZE - 1 && grid[y][x].value == grid[y][x + 1].value {
				return false
			}
			if y < GRID_SIZE - 1 && grid[y][x].value == grid[y + 1][x].value {
				return false
			}
		}
	}

	return true
}

is_animating :: proc() -> bool {
	return animating_tiles > 0
}

update_animations :: proc(dt: f32) {
	animating_tiles = 0
	for y in 0..<GRID_SIZE {
		for x in 0..<GRID_SIZE {
			tile := &grid[y][x]
			if tile.animating {
				animating_tiles += 1
				// Simple lerp animation
				tile.target_x = f32(x)
				tile.target_y = f32(y)
				// In a real implementation, we'd animate the visual position
				// For now, just mark as done immediately
				tile.animating = false
			}
		}
	}
}

// --- Drawing ---

draw_grid :: proc() {
	for y in 0..<GRID_SIZE {
		for x in 0..<GRID_SIZE {
			px := GRID_OFFSET_X + x * CELL_SIZE
			py := GRID_OFFSET_Y + y * CELL_SIZE
			
			value := grid[y][x].value
			
			// Draw cell background
			if value > 0 && value <= len(tile_colors) {
				color := tile_colors[value - 1]
				engine.draw_rect(f32(px + 2), f32(py + 2), CELL_SIZE - 4, CELL_SIZE - 4, color.r, color.g, color.b)
			} else if value > len(tile_colors) {
				// Super tiles
				color := engine.Color{0.2, 0.8, 0.2, 1.0}
				engine.draw_rect(f32(px + 2), f32(py + 2), CELL_SIZE - 4, CELL_SIZE - 4, color.r, color.g, color.b)
			} else {
				// Empty cell
				engine.draw_rect(f32(px + 2), f32(py + 2), CELL_SIZE - 4, CELL_SIZE - 4, 0.85, 0.80, 0.75)
			}
			
			// Draw value text
			if value > 0 {
				tr, tg, tb := f32(0.47), f32(0.33), f32(0.28)
				if value >= 3 {
					tr, tg, tb = f32(1.0), f32(1.0), f32(1.0)
				}
				val_str := fmt.tprintf("%d", int(math.pow(2.0, f64(value))))
				engine.draw_text(f32(px + CELL_SIZE / 2 - 15), f32(py + CELL_SIZE / 2 - 10), val_str, font_id, tr, tg, tb)
			}
		}
	}
	
	// Draw grid border
	engine.draw_rect(f32(GRID_OFFSET_X), f32(GRID_OFFSET_Y), f32(GRID_SIZE * CELL_SIZE), 2, 0.7, 0.6, 0.5)
	engine.draw_rect(f32(GRID_OFFSET_X), f32(GRID_OFFSET_Y + GRID_SIZE * CELL_SIZE - 2), f32(GRID_SIZE * CELL_SIZE), 2, 0.7, 0.6, 0.5)
	engine.draw_rect(f32(GRID_OFFSET_X), f32(GRID_OFFSET_Y), 2, f32(GRID_SIZE * CELL_SIZE), 0.7, 0.6, 0.5)
	engine.draw_rect(f32(GRID_OFFSET_X + GRID_SIZE * CELL_SIZE - 2), f32(GRID_OFFSET_Y), 2, f32(GRID_SIZE * CELL_SIZE), 0.7, 0.6, 0.5)
}

draw_ui :: proc() {
	// Score
	engine.draw_text(600, 120, fmt.tprintf("Score: %d", score))
	engine.draw_text(600, 160, fmt.tprintf("Moves: %d", moves))
	engine.draw_text(600, 220, fmt.tprintf("Best: %d", best_score))
	engine.draw_text(600, 260, fmt.tprintf("Level: %d", level))
	
	// Controls
	engine.draw_text(600, 380, "Controls:")
	engine.draw_text(600, 420, "Arrow Keys - Move")
	engine.draw_text(600, 460, "ENTER - Menu")
	
	// Game over message
	if is_game_over() {
		engine.draw_text(200, 520, "Game Over! Press ENTER for menu")
	}
}
