package main

import "core:fmt"
import "core:os"
import SDL "vendor:sdl2"
import engine "../src/core"

// Demo game showcasing VoidEngine features
demo_game :: struct {
    player_x: f32,
    player_y: f32,
    player_speed: f32,
    player_color: SDL.Color,
    
    // Game state
    score: i32,
    enemies: [dynamic]Enemy,
    bullets: [dynamic]Bullet,
    
    // Timing
    spawn_timer: f64,
    spawn_interval: f64,
}

Enemy :: struct {
    x: f32,
    y: f32,
    width: i32,
    height: i32,
    speed: f32,
    health: i32,
    color: SDL.Color,
}

Bullet :: struct {
    x: f32,
    y: f32,
    speed: f32,
    active: bool,
}

main :: proc() {
    config := engine.EngineConfig{
        title = "VoidEngine Demo — Shmup",
        width = 1280,
        height = 720,
        target_fps = 60.0,
        enable_hot_reload = true,
        asset_path = "assets",
    }
    
    e := engine.engine_init(config)
    defer engine.engine_shutdown(e)
    
    // Initialize game state
    game := new(demo_game)
    game.player_x = f32(config.width) / 2.0
    game.player_y = f32(config.height) - 100.0
    game.player_speed = 400.0
    game.player_color = engine.color(0, 255, 128, 255)
    game.enemies = make([dynamic]Enemy)
    game.bullets = make([dynamic]Bullet)
    game.spawn_interval = 2.0
    
    // Set up game API for hot reload
    e.game_api = engine.GameAPI{
        init = proc(e: ^engine.Engine) {
            fmt.println("🎮 Demo game initialized")
        },
        update = proc(e: ^engine.Engine, dt: f64) {
            game := (^demo_game)(e)
            demo_update(game, e, dt)
        },
        render = proc(e: ^engine.Engine, renderer: ^SDL.Renderer) {
            game := (^demo_game)(e)
            demo_render(game, e, renderer)
        },
        shutdown = proc(e: ^engine.Engine) {
            fmt.println("🎮 Demo game shutdown")
        },
        handle_event = proc(e: ^engine.Engine, event: ^SDL.Event) -> bool {
            return true
        },
    }
    
    // Store game pointer in engine for access
    // In real implementation, you'd use a proper userdata system
    
    fmt.println("\n🎮 VoidEngine Demo")
    fmt.println("Controls:")
    fmt.println("  [WASD / Arrows] — Move player")
    fmt.println("  [Space] — Shoot")
    fmt.println("  [ESC] — Quit")
    fmt.println()
    
    engine.engine_run(e)
}

demo_update :: proc(game: ^demo_game, e: ^engine.Engine, dt: f64) {
    dt_f32 := f32(dt)
    
    // Player movement
    if engine.input_is_key_held(&e.input, SDL.Scancode.W) || engine.input_is_key_held(&e.input, SDL.Scancode.UP) {
        game.player_y -= game.player_speed * dt_f32
    }
    if engine.input_is_key_held(&e.input, SDL.Scancode.S) || engine.input_is_key_held(&e.input, SDL.Scancode.DOWN) {
        game.player_y += game.player_speed * dt_f32
    }
    if engine.input_is_key_held(&e.input, SDL.Scancode.A) || engine.input_is_key_held(&e.input, SDL.Scancode.LEFT) {
        game.player_x -= game.player_speed * dt_f32
    }
    if engine.input_is_key_held(&e.input, SDL.Scancode.D) || engine.input_is_key_held(&e.input, SDL.Scancode.RIGHT) {
        game.player_x += game.player_speed * dt_f32
    }
    
    // Clamp player to screen
    game.player_x = clamp(game.player_x, 20.0, f32(e.config.width) - 20.0)
    game.player_y = clamp(game.player_y, 20.0, f32(e.config.height) - 20.0)
    
    // Shooting
    if engine.input_is_key_pressed(&e.input, SDL.Scancode.SPACE) {
        bullet := Bullet{
            x = game.player_x,
            y = game.player_y - 20.0,
            speed = 600.0,
            active = true,
        }
        append(&game.bullets, bullet)
    }
    
    // Update bullets
    for &bullet in game.bullets {
        if bullet.active {
            bullet.y -= bullet.speed * dt_f32
            if bullet.y < -10.0 {
                bullet.active = false
            }
        }
    }
    
    // Remove inactive bullets
    // Note: In real implementation, use a pool or mark-and-sweep
    
    // Spawn enemies
    game.spawn_timer += dt
    if game.spawn_timer >= game.spawn_interval {
        game.spawn_timer = 0.0
        enemy := Enemy{
            x = f32(os.random()) % f32(e.config.width - 40) + 20.0,
            y = -30.0,
            width = 30,
            height = 30,
            speed = 100.0 + f32(os.random()) % 100.0,
            health = 3,
            color = engine.color(255, 64, 64, 255),
        }
        append(&game.enemies, enemy)
    }
    
    // Update enemies
    for &enemy in game.enemies {
        enemy.y += enemy.speed * dt_f32
    }
    
    // Collision detection (simple AABB)
    player_rect := SDL.Rect{
        i32(game.player_x) - 15,
        i32(game.player_y) - 15,
        30,
        30,
    }
    
    for &enemy in game.enemies {
        enemy_rect := SDL.Rect{
            i32(enemy.x) - enemy.width / 2,
            i32(enemy.y) - enemy.height / 2,
            enemy.width,
            enemy.height,
        }
        
        if SDL.HasIntersection(&player_rect, &enemy_rect) {
            // Player hit - flash red
            game.player_color = engine.color(255, 0, 0, 255)
        }
    }
    
    // Reset player color
    if game.player_color.r == 255 {
        game.player_color.r = u8(lerp(f32(game.player_color.r), 0.0, dt_f32 * 5.0))
    }
}

demo_render :: proc(game: ^demo_game, e: ^engine.Engine, renderer: ^SDL.Renderer) {
    // Draw player (triangle shape)
    px := i32(game.player_x)
    py := i32(game.player_y)
    
    engine.draw_rect(renderer, px - 15, py - 15, 30, 30, game.player_color)
    
    // Draw bullets
    for bullet in game.bullets {
        if bullet.active {
            engine.draw_rect(renderer, i32(bullet.x) - 2, i32(bullet.y) - 5, 4, 10, engine.color(255, 255, 0, 255))
        }
    }
    
    // Draw enemies
    for enemy in game.enemies {
        engine.draw_rect(
            renderer,
            i32(enemy.x) - enemy.width / 2,
            i32(enemy.y) - enemy.height / 2,
            enemy.width,
            enemy.height,
            enemy.color,
        )
    }
    
    // Draw HUD
    // Note: In real implementation, use a text rendering system
    engine.draw_rect(renderer, 10, 10, 200, 30, engine.color(0, 0, 0, 128))
}

lerp :: proc(a, b, t: f32) -> f32 {
    return a + (b - a) * t
}

clamp :: proc(value, min, max: f32) -> f32 {
    if value < min {
        return min
    }
    if value > max {
        return max
    }
    return value
}
