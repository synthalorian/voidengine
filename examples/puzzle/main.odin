package main

import "core:fmt"
import "core:os"
import "core:math"
import SDL "vendor:sdl2"
import engine "../../src/core"

// Puzzle example — match-3 style game
puzzle_game :: struct {
    grid: [8][8]Gem,
    selected: Maybe(Vec2i),
    score: i32,
    combo: i32,
    animating: bool,
    particles: [dynamic]Particle,
    pending_clears: [dynamic]Vec2i,
    swap_a: Maybe(Vec2i),
    swap_b: Maybe(Vec2i),
    swap_progress: f32,
    clear_flash: f32,
}

Gem :: struct {
    color: GemColor,
    x: f32,  // Animated pixel position
    y: f32,
    target_x: i32,
    target_y: i32,
    matched: bool,
    falling: bool,
}

GemColor :: enum {
    red,
    green,
    blue,
    yellow,
    purple,
    orange,
    empty,
}

Vec2i :: struct {
    x: i32,
    y: i32,
}

Particle :: struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: f32,
    max_life: f32,
    color: SDL.Color,
    size: f32,
}

GRID_SIZE :: 8
CELL_SIZE :: 64
GRID_OFFSET_X :: 32
GRID_OFFSET_Y :: 100

GEM_COLORS := [GemColor]SDL.Color{
    .red     = {230, 80, 80, 255},
    .green   = {80, 230, 120, 255},
    .blue    = {80, 150, 230, 255},
    .yellow  = {230, 210, 80, 255},
    .purple  = {180, 80, 230, 255},
    .orange  = {230, 150, 60, 255},
    .empty   = {0, 0, 0, 0},
}

main :: proc() {
    config := engine.EngineConfig{
        title = "VoidEngine — Puzzle",
        width = 600,
        height = 720,
        target_fps = 60.0,
        enable_hot_reload = false,
        asset_path = "assets",
    }

    e := engine.engine_init(config)
    defer engine.engine_shutdown(e)

    game := new(puzzle_game)
    game.particles = make([dynamic]Particle)
    game.pending_clears = make([dynamic]Vec2i)
    init_grid(game)

    // Avoid initial matches
    for find_matches(game) > 0 {
        clear_matches(game, false)
        fill_grid(game)
    }

    e.user_data = game

    e.game_api = engine.GameAPI{
        init = proc(e: ^engine.Engine) {
            fmt.println("🧩 Puzzle example initialized")
            fmt.println("Click adjacent gems to swap and match 3+")
        },
        update = proc(e: ^engine.Engine, dt: f64) {
            game := cast(^puzzle_game)e.user_data
            puzzle_update(game, e, dt)
        },
        render = proc(e: ^engine.Engine, renderer: ^SDL.Renderer) {
            game := cast(^puzzle_game)e.user_data
            puzzle_render(game, e, renderer)
        },
        shutdown = proc(e: ^engine.Engine) {
            fmt.println("🧩 Puzzle example shutdown")
        },
        handle_event = proc(e: ^engine.Engine, event: ^SDL.Event) -> bool {
            return true
        },
    }

    engine.engine_run(e)
}

init_grid :: proc(game: ^puzzle_game) {
    for y in 0..<GRID_SIZE {
        for x in 0..<GRID_SIZE {
            game.grid[y][x] = Gem{
                color = GemColor(engine.rand_int_range(0, 6)),
                x = f32(x * CELL_SIZE + GRID_OFFSET_X),
                y = f32(y * CELL_SIZE + GRID_OFFSET_Y),
                target_x = i32(x),
                target_y = i32(y),
            }
        }
    }
}

fill_grid :: proc(game: ^puzzle_game) {
    for y in 0..<GRID_SIZE {
        for x in 0..<GRID_SIZE {
            if game.grid[y][x].color == .empty {
                game.grid[y][x].color = GemColor(engine.rand_int_range(0, 6))
                game.grid[y][x].matched = false
                game.grid[y][x].falling = false
            }
        }
    }
}

puzzle_update :: proc(game: ^puzzle_game, e: ^engine.Engine, dt: f64) {
    dt_f32 := f32(dt)

    // Handle input
    if engine.input_is_mouse_pressed(&e.input, 1) && !game.animating {
        mx := e.input.mouse_x - GRID_OFFSET_X
        my := e.input.mouse_y - GRID_OFFSET_Y
        if mx >= 0 && my >= 0 {
            gx := mx / CELL_SIZE
            gy := my / CELL_SIZE
            if gx >= 0 && gx < GRID_SIZE && gy >= 0 && gy < GRID_SIZE {
                pos := Vec2i{x = gx, y = gy}
                if sel, ok := game.selected.?; ok {
                    if sel.x == pos.x && sel.y == pos.y {
                        game.selected = nil
                    } else if is_adjacent(sel, pos) {
                        game.swap_a = sel
                        game.swap_b = pos
                        game.animating = true
                        game.swap_progress = 0.0
                        game.selected = nil
                    } else {
                        game.selected = pos
                    }
                } else {
                    game.selected = pos
                }
            }
        }
    }

    // Process swap animation
    if game.animating && game.swap_a != nil && game.swap_b != nil {
        game.swap_progress += dt_f32 * 12.0
        if game.swap_progress >= 1.0 {
            a := game.swap_a.?
            b := game.swap_b.?
            swap_gems(game, a, b)
            matches := find_matches(game)
            if matches == 0 {
                // Revert invalid swap
                swap_gems(game, a, b)
            } else {
                game.combo = 1
                game.clear_flash = 0.3
            }
            game.swap_a = nil
            game.swap_b = nil
            game.animating = false
            game.swap_progress = 0.0
        }
    }

    // Clear matches and cascade
    if !game.animating && game.swap_a == nil {
        matches := find_matches(game)
        if matches > 0 {
            game.clear_flash = max(game.clear_flash, 0.2)
            game.score += matches * 10 * game.combo
            game.combo += 1
            clear_matches(game, true)
            apply_gravity(game)
            fill_grid(game)
            // Keep cascading if new matches formed
        } else {
            game.combo = 1
        }
    }

    // Animate gem positions toward targets
    speed := 10.0 * dt_f32
    for y in 0..<GRID_SIZE {
        for x in 0..<GRID_SIZE {
            gem := &game.grid[y][x]
            target_px := f32(x * CELL_SIZE + GRID_OFFSET_X)
            target_py := f32(y * CELL_SIZE + GRID_OFFSET_Y)
            gem.x = engine.lerp(gem.x, target_px, speed)
            gem.y = engine.lerp(gem.y, target_py, speed)
        }
    }

    // Flash decay
    if game.clear_flash > 0 {
        game.clear_flash -= dt_f32
        if game.clear_flash < 0 {
            game.clear_flash = 0
        }
    }

    // Update particles
    for i := len(game.particles) - 1; i >= 0; i -= 1 {
        p := &game.particles[i]
        p.x += p.vx * dt_f32
        p.y += p.vy * dt_f32
        p.life -= dt_f32
        if p.life <= 0 {
            unordered_remove(&game.particles, i)
        }
    }
}

is_adjacent :: proc(a, b: Vec2i) -> bool {
    dx := abs(a.x - b.x)
    dy := abs(a.y - b.y)
    return (dx == 1 && dy == 0) || (dx == 0 && dy == 1)
}

swap_gems :: proc(game: ^puzzle_game, a, b: Vec2i) {
    temp := game.grid[a.y][a.x]
    game.grid[a.y][a.x] = game.grid[b.y][b.x]
    game.grid[b.y][b.x] = temp

    // Update target positions
    game.grid[a.y][a.x].target_x = a.x
    game.grid[a.y][a.x].target_y = a.y
    game.grid[b.y][b.x].target_x = b.x
    game.grid[b.y][b.x].target_y = b.y
}

find_matches :: proc(game: ^puzzle_game) -> i32 {
    count: i32 = 0

    // Horizontal
    for y in 0..<GRID_SIZE {
        x := 0
        for x < GRID_SIZE {
            color := game.grid[y][x].color
            if color == .empty {
                x += 1
                continue
            }
            run := 1
            for x + run < GRID_SIZE && game.grid[y][x + run].color == color {
                run += 1
            }
            if run >= 3 {
                for i in 0..<run {
                    game.grid[y][x + i].matched = true
                }
                count += i32(run)
            }
            x += run
        }
    }

    // Vertical
    for x in 0..<GRID_SIZE {
        y := 0
        for y < GRID_SIZE {
            color := game.grid[y][x].color
            if color == .empty {
                y += 1
                continue
            }
            run := 1
            for y + run < GRID_SIZE && game.grid[y + run][x].color == color {
                run += 1
            }
            if run >= 3 {
                for i in 0..<run {
                    game.grid[y + i][x].matched = true
                }
                count += i32(run)
            }
            y += run
        }
    }

    return count
}

clear_matches :: proc(game: ^puzzle_game, spawn_particles: bool) {
    for y in 0..<GRID_SIZE {
        for x in 0..<GRID_SIZE {
            if game.grid[y][x].matched {
                if spawn_particles {
                    spawn_gem_particles(game, i32(x), i32(y), game.grid[y][x].color)
                }
                game.grid[y][x].color = .empty
                game.grid[y][x].matched = false
            }
        }
    }
}

apply_gravity :: proc(game: ^puzzle_game) {
    for x in 0..<GRID_SIZE {
        write_y := GRID_SIZE - 1
        for y := GRID_SIZE - 1; y >= 0; y -= 1 {
            if game.grid[y][x].color != .empty {
                if write_y != y {
                    game.grid[write_y][x] = game.grid[y][x]
                    game.grid[write_y][x].target_x = i32(x)
                    game.grid[write_y][x].target_y = i32(write_y)
                    game.grid[y][x].color = .empty
                }
                write_y -= 1
            }
        }
    }
}

spawn_gem_particles :: proc(game: ^puzzle_game, x, y: i32, color: GemColor) {
    px := f32(x * CELL_SIZE + GRID_OFFSET_X + CELL_SIZE / 2)
    py := f32(y * CELL_SIZE + GRID_OFFSET_Y + CELL_SIZE / 2)
    col := GEM_COLORS[color]
    for i in 0..<8 {
        angle := f32(i) * 0.785
        speed := 80.0 + f32(engine.rand_int_range(0, 80))
        p := Particle{
            x = px,
            y = py,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = 0.4 + f32(engine.rand_int_range(0, 40)) / 100.0,
            max_life = 0.8,
            color = col,
            size = 2.0 + f32(engine.rand_int_range(0, 5)),
        }
        append(&game.particles, p)
    }
}

puzzle_render :: proc(game: ^puzzle_game, e: ^engine.Engine, renderer: ^SDL.Renderer) {
    // Background
    engine.draw_rect(renderer, 0, 0, e.config.width, e.config.height, engine.color(30, 20, 40, 255))

    // Grid background
    engine.draw_rect(renderer, GRID_OFFSET_X - 4, GRID_OFFSET_Y - 4,
        GRID_SIZE * CELL_SIZE + 8, GRID_SIZE * CELL_SIZE + 8, engine.color(20, 15, 30, 255))

    // Selection flash
    if game.clear_flash > 0 {
        flash := u8(50 + i32(game.clear_flash * 400.0))
        engine.draw_rect(renderer, 0, 0, e.config.width, e.config.height, engine.color(flash, flash, flash, 30))
    }

    // Draw grid cells
    for y in 0..<GRID_SIZE {
        for x in 0..<GRID_SIZE {
            gem := game.grid[y][x]
            if gem.color == .empty {
                continue
            }
            draw_gem(renderer, gem, i32(x), i32(y))
        }
    }

    // Selection highlight
    if sel, ok := game.selected.?; ok {
        sx := sel.x * CELL_SIZE + GRID_OFFSET_X - 4
        sy := sel.y * CELL_SIZE + GRID_OFFSET_Y - 4
        engine.draw_rect_outline(renderer, sx, sy, CELL_SIZE + 8, CELL_SIZE + 8, engine.color(255, 255, 255, 200))
    }

    // Draw particles
    for p in game.particles {
        alpha := u8(255 * (p.life / p.max_life))
        c := p.color
        c.a = alpha
        engine.draw_rect(renderer, i32(p.x), i32(p.y), i32(p.size), i32(p.size), c)
    }

    // HUD
    draw_puzzle_hud(renderer, game, e.config.width)
}

draw_gem :: proc(renderer: ^SDL.Renderer, gem: Gem, x, y: i32) {
    pad: i32 = 4
    size := i32(CELL_SIZE - pad * 2)
    col := GEM_COLORS[gem.color]

    // Shadow
    engine.draw_rect(renderer, i32(gem.x) + pad + 2, i32(gem.y) + pad + 2, size, size, engine.color(0, 0, 0, 80))
    // Gem
    engine.draw_rect(renderer, i32(gem.x) + pad, i32(gem.y) + pad, size, size, col)
    // Highlight
    engine.draw_rect(renderer, i32(gem.x) + pad + 4, i32(gem.y) + pad + 4, size / 3, size / 6, engine.color(255, 255, 255, 60))
}

draw_puzzle_hud :: proc(renderer: ^SDL.Renderer, game: ^puzzle_game, screen_w: i32) {
    // Score bar
    engine.draw_rect(renderer, 20, 20, screen_w - 40, 50, engine.color(20, 15, 30, 255))

    // Combo indicator
    if game.combo > 1 {
        for i in 0..<min(game.combo, 10) {
            engine.draw_rect(renderer, screen_w - 30 - i * 12, 80, 8, 16, engine.color(255, 200, 80, 255))
        }
    }
}

abs :: proc(x: i32) -> i32 {
    if x < 0 {
        return -x
    }
    return x
}

min :: proc(a, b: i32) -> i32 {
    if a < b {
        return a
    }
    return b
}

max :: proc(a, b: f32) -> f32 {
    if a > b {
        return a
    }
    return b
}
