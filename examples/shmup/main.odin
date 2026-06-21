package main
import "core:fmt"
import SDL "vendor:sdl2"
import engine "../../src/core"
import "core:os"
import "core:math/rand"

// Shmup example — vertical scrolling shooter
shmup_game :: struct {
    ship: Ship,
    enemies: [dynamic]Enemy_ship,
    stars: [dynamic]Star,
    score: i32,
    wave: i32,
    lives: i32,
}

Ship :: struct {
    x: f32,
    y: f32,
    speed: f32,
    weapon_level: i32,
    invulnerable: f32,
}

Enemy_ship :: struct {
    x: f32,
    y: f32,
    pattern: EnemyPattern,
    health: i32,
    active: bool,
}

EnemyPattern :: enum {
    straight,
    sine_wave,
    dive,
    boss,
}

Star :: struct {
    x: f32,
    y: f32,
    speed: f32,
    brightness: u8,
}

main :: proc() {
    config := engine.EngineConfig{
        title = "VoidEngine — Shmup",
        width = 800,
        height = 600,
        target_fps = 60.0,
        enable_hot_reload = true,
        asset_path = "assets",
    }
    
    e := engine.engine_init(config)
    defer engine.engine_shutdown(e)
    
    game := new(shmup_game)
    game.ship = Ship{
        x = f32(config.width) / 2.0,
        y = f32(config.height) - 60.0,
        speed = 350.0,
        weapon_level = 1,
        invulnerable = 0.0,
    }
    game.enemies = make([dynamic]Enemy_ship)
    game.stars = make([dynamic]Star)
    game.lives = 3
    
    // Initialize starfield
    for i in 0..<100 {
        star := Star{
            x = rand.float32() * f32(config.width),
            y = rand.float32() * f32(config.height),
            speed = 50.0 + rand.float32() * 150.0,
            brightness = u8(100 + rand.int_max(155)),
        }
        append(&game.stars, star)
    }
    
    fmt.println("🚀 Shmup example loaded")
    fmt.println("Controls: WASD to move, Space to shoot")
    
    engine.engine_run(e)
}
