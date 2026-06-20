package main

import "core:fmt"
import SDL "vendor:sdl2"
import engine "../src/core"

// Puzzle example — match-3 style game
puzzle_game :: struct {
    grid: [8][8]Gem,
    selected: Maybe(Vec2i),
    score: i32,
    combo: i32,
    animating: bool,
    particles: [dynamic]Particle,
}

Gem :: struct {
    color: GemColor,
    x: f32,  // Animated position
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
    color: SDL.Color,
}

main :: proc() {
    config := engine.EngineConfig{
        title = "VoidEngine — Puzzle",
        width = 640,
        height = 720,
        target_fps = 60.0,
        enable_hot_reload = false,
        asset_path = "assets",
    }
    
    e := engine.engine_init(config)
    defer engine.engine_shutdown(e)
    
    game := new(puzzle_game)
    game.particles = make([dynamic]Particle)
    
    // Initialize grid with random gems
    for y in 0..<8 {
        for x in 0..<8 {
            game.grid[y][x] = Gem{
                color = GemColor(os.random() % 6),
                x = f32(x * 64 + 32),
                y = f32(y * 64 + 100),
                target_x = x,
                target_y = y,
            }
        }
    }
    
    fmt.println("🧩 Puzzle example loaded")
    fmt.println("Click gems to swap and match 3+")
    
    engine.engine_run(e)
}
