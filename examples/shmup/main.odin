package main

import "core:fmt"
import SDL "vendor:sdl2"
import MIX "vendor:sdl2/mixer"
import engine "../../src/core"
import "core:math/rand"
import "core:math"

// Shmup example — vertical scrolling shooter with full gameplay

// Game state (stored in engine.user_data to survive hot reload)
shmup_game :: struct {
    ship: Ship,
    bullets: [dynamic]Bullet,
    enemies: [dynamic]Enemy_ship,
    particles: [dynamic]Particle,
    stars: [dynamic]Star,
    score: i32,
    wave: i32,
    lives: i32,
    game_over: bool,
    spawn_timer: f32,
    wave_timer: f32,
    screen_shake: f32,
    invuln_flash: f32,
    high_score: i32,
}

Ship :: struct {
    transform: ^engine.Transform,
    sprite: ^engine.Sprite,
    velocity: ^engine.Velocity,
    collider: ^engine.Collider,
    speed: f32,
    weapon_level: i32,
    invulnerable: f32,
    fire_cooldown: f32,
}

Bullet :: struct {
    transform: ^engine.Transform,
    sprite: ^engine.Sprite,
    velocity: ^engine.Velocity,
    collider: ^engine.Collider,
    active: bool,
    lifetime: f32,
    is_player: bool,
}

Enemy_ship :: struct {
    transform: ^engine.Transform,
    sprite: ^engine.Sprite,
    velocity: ^engine.Velocity,
    collider: ^engine.Collider,
    active: bool,
    health: i32,
    pattern: EnemyPattern,
    pattern_timer: f32,
    pattern_data: f32, // extra data per pattern (e.g. sine phase)
    fire_cooldown: f32,
    score_value: i32,
}

EnemyPattern :: enum {
    straight,
    sine_wave,
    dive,
    zigzag,
    boss,
}

Particle :: struct {
    x, y: f32,
    vx, vy: f32,
    life: f32,
    max_life: f32,
    size: f32,
    color: SDL.Color,
}

Star :: struct {
    x: f32,
    y: f32,
    speed: f32,
    brightness: u8,
    size: u8,
}

// Game API functions exported for hot reload
@(export)
game_init :: proc(e: ^engine.Engine) {
    fmt.println("🚀 Shmup example initialized")
    
    game := new(shmup_game)
    e.user_data = game
    
    config := e.config
    
    // Create player ship
    ship_entity := engine.entity_create(&e.scene.scenes[0])
    ship_transform := new(engine.Transform)
    ship_transform^ = engine.make_transform(f32(config.width) / 2, f32(config.height) - 60)
    ship_sprite := new(engine.Sprite)
    ship_sprite^ = engine.make_sprite(32, 32, engine.color(0, 200, 255, 255))
    ship_velocity := new(engine.Velocity)
    ship_velocity^ = engine.make_velocity(0, 0)
    ship_collider := new(engine.Collider)
    ship_collider^ = engine.make_collider(24, 24, engine.CollisionLayer.Player, 
        engine.CollisionMask{engine.CollisionLayer.Enemy, engine.CollisionLayer.EnemyBullet})
    
    engine.entity_add_component(ship_entity, engine.Transform, ship_transform)
    engine.entity_add_component(ship_entity, engine.Sprite, ship_sprite)
    engine.entity_add_component(ship_entity, engine.Velocity, ship_velocity)
    engine.entity_add_component(ship_entity, engine.Collider, ship_collider)
    
    game.ship = Ship{
        transform = ship_transform,
        sprite = ship_sprite,
        velocity = ship_velocity,
        collider = ship_collider,
        speed = 400.0,
        weapon_level = 1,
        invulnerable = 2.0,
        fire_cooldown = 0,
    }
    
    game.bullets = make([dynamic]Bullet)
    game.enemies = make([dynamic]Enemy_ship)
    game.particles = make([dynamic]Particle)
    game.stars = make([dynamic]Star)
    game.lives = 3
    game.score = 0
    game.wave = 1
    game.spawn_timer = 1.0
    game.wave_timer = 0
    game.screen_shake = 0
    game.invuln_flash = 0
    game.high_score = 0
    game.game_over = false
    
    // Initialize starfield
    for i in 0..<150 {
        star := Star{
            x = rand.float32() * f32(config.width),
            y = rand.float32() * f32(config.height),
            speed = 30.0 + rand.float32() * 200.0,
            brightness = u8(80 + rand.int_max(175)),
            size = u8(1 + rand.int_max(3)),
        }
        append(&game.stars, star)
    }
    
    // Create scene for ECS
    scene := engine.scene_create(e, "shmup")
    engine.scene_switch(e, scene)
    
    // Load placeholder sounds (will work if assets exist, silently fail otherwise)
    engine.audio_load_sound(&e.audio, "shoot", "assets/shoot.wav")
    engine.audio_load_sound(&e.audio, "explosion", "assets/explosion.wav")
    engine.audio_load_sound(&e.audio, "hit", "assets/hit.wav")
    
    fmt.println("Controls: WASD/Arrows to move, Space to shoot, R to restart")
}

@(export)
game_update :: proc(e: ^engine.Engine, dt: f64) {
    game := cast(^shmup_game)e.user_data
    if game == nil {
        return
    }
    
    dt_f32 := f32(dt)
    config := e.config
    
    if game.game_over {
        if engine.input_is_key_pressed(&e.input, SDL.Scancode.R) {
            restart_game(e, game)
        }
        return
    }
    
    // Update invulnerability
    if game.ship.invulnerable > 0 {
        game.ship.invulnerable -= dt_f32
        game.invuln_flash += dt_f32 * 10
    }
    
    // Player movement
    move_x: f32 = 0
    move_y: f32 = 0
    if engine.input_is_key_held(&e.input, SDL.Scancode.A) || engine.input_is_key_held(&e.input, SDL.Scancode.LEFT) {
        move_x -= 1
    }
    if engine.input_is_key_held(&e.input, SDL.Scancode.D) || engine.input_is_key_held(&e.input, SDL.Scancode.RIGHT) {
        move_x += 1
    }
    if engine.input_is_key_held(&e.input, SDL.Scancode.W) || engine.input_is_key_held(&e.input, SDL.Scancode.UP) {
        move_y -= 1
    }
    if engine.input_is_key_held(&e.input, SDL.Scancode.S) || engine.input_is_key_held(&e.input, SDL.Scancode.DOWN) {
        move_y += 1
    }
    
    // Normalize diagonal movement
    if move_x != 0 && move_y != 0 {
        move_x *= 0.707
        move_y *= 0.707
    }
    
    game.ship.velocity.linear.x = move_x * game.ship.speed
    game.ship.velocity.linear.y = move_y * game.ship.speed
    
    // Clamp to screen
    ship_entity := &e.scene.current_scene.entities[0]
    engine.clamp_to_screen(ship_entity, config.width, config.height)
    
    // Shooting
    game.ship.fire_cooldown -= dt_f32
    if engine.input_is_key_held(&e.input, SDL.Scancode.SPACE) && game.ship.fire_cooldown <= 0 {
        spawn_bullet(e, game, game.ship.transform.position.x, game.ship.transform.position.y - 20, true)
        if game.ship.weapon_level >= 2 {
            spawn_bullet(e, game, game.ship.transform.position.x - 12, game.ship.transform.position.y - 10, true)
            spawn_bullet(e, game, game.ship.transform.position.x + 12, game.ship.transform.position.y - 10, true)
        }
        if game.ship.weapon_level >= 3 {
            spawn_bullet(e, game, game.ship.transform.position.x - 20, game.ship.transform.position.y, true)
            spawn_bullet(e, game, game.ship.transform.position.x + 20, game.ship.transform.position.y, true)
        }
        game.ship.fire_cooldown = 0.12
        engine.audio_play_sound(&e.audio, "shoot", -1)
    }
    
    // Spawn enemies
    game.spawn_timer -= dt_f32
    if game.spawn_timer <= 0 {
        spawn_enemy(e, game)
        game.spawn_timer = math.max(0.3, 1.5 - f32(game.wave) * 0.1)
    }
    
    // Wave progression
    game.wave_timer += dt_f32
    if game.wave_timer > 15.0 {
        game.wave += 1
        game.wave_timer = 0
        fmt.println("Wave", game.wave, "!")
    }
    
    // Update physics
    engine.physics_update(e.scene.current_scene, dt)
    
    // Update bullets
    for i := len(game.bullets) - 1; i >= 0; i -= 1 {
        bullet := &game.bullets[i]
        bullet.lifetime -= dt_f32
        if bullet.lifetime <= 0 || bullet.transform.position.y < -20 || bullet.transform.position.y > f32(config.height) + 20 {
            bullet.active = false
        }
    }
    
    // Update enemies
    for i := len(game.enemies) - 1; i >= 0; i -= 1 {
        enemy := &game.enemies[i]
        if !enemy.active {
            continue
        }
        
        // Pattern movement
        enemy.pattern_timer += dt_f32
        switch enemy.pattern {
        case .sine_wave:
            enemy.velocity.linear.x = math.sin(enemy.pattern_timer * 3) * 80
        case .dive:
            if enemy.pattern_timer > 1.0 {
                enemy.velocity.linear.y += 100 * dt_f32
            }
        case .zigzag:
            enemy.velocity.linear.x = math.sin(enemy.pattern_timer * 5) * 120
        case .boss:
            enemy.velocity.linear.x = math.sin(enemy.pattern_timer) * 60
            enemy.velocity.linear.y = math.sin(enemy.pattern_timer * 0.5) * 30
            enemy.fire_cooldown -= dt_f32
            if enemy.fire_cooldown <= 0 {
                spawn_bullet(e, game, enemy.transform.position.x, enemy.transform.position.y + 30, false)
                enemy.fire_cooldown = 0.8
            }
        case .straight:
            // No extra movement
        }
        
        // Remove off-screen enemies
        if enemy.transform.position.y > f32(config.height) + 50 {
            enemy.active = false
        }
    }
    
    // Update stars
    for &star in game.stars {
        star.y += star.speed * dt_f32
        if star.y > f32(config.height) {
            star.y = 0
            star.x = rand.float32() * f32(config.width)
        }
    }
    
    // Update particles
    for i := len(game.particles) - 1; i >= 0; i -= 1 {
        particle := &game.particles[i]
        particle.x += particle.vx * dt_f32
        particle.y += particle.vy * dt_f32
        particle.life -= dt_f32
        if particle.life <= 0 {
            unordered_remove(&game.particles, i)
        }
    }
    
    // Collision detection
    check_collisions(e, game)
    
    // Screen shake decay
    if game.screen_shake > 0 {
        game.screen_shake -= dt_f32 * 5
        if game.screen_shake < 0 {
            game.screen_shake = 0
        }
    }
    
    // Cleanup inactive entities
    cleanup_entities(e, game)
}

@(export)
game_render :: proc(e: ^engine.Engine, renderer: ^SDL.Renderer) {
    game := cast(^shmup_game)e.user_data
    if game == nil {
        return
    }
    
    config := e.config
    
    // Screen shake offset
    shake_x: i32 = 0
    shake_y: i32 = 0
    if game.screen_shake > 0 {
        shake_x = i32(rand.float32() * game.screen_shake * 4 - game.screen_shake * 2)
        shake_y = i32(rand.float32() * game.screen_shake * 4 - game.screen_shake * 2)
    }
    
    // Draw starfield
    for star in game.stars {
        brightness := star.brightness
        if star.size > 1 {
            engine.draw_rect(renderer, i32(star.x) + shake_x, i32(star.y) + shake_y, i32(star.size), i32(star.size), 
                engine.color(brightness, brightness, brightness + 20, 255))
        } else {
            SDL.SetRenderDrawColor(renderer, brightness, brightness, brightness + 20, 255)
            SDL.RenderDrawPoint(renderer, i32(star.x) + shake_x, i32(star.y) + shake_y)
        }
    }
    
    // Draw player ship (with invulnerability flash)
    if game.ship.invulnerable <= 0 || int(game.invuln_flash) % 2 == 0 {
        draw_ship(renderer, game.ship.transform.position.x, game.ship.transform.position.y, 
            game.ship.sprite.color, shake_x, shake_y)
    }
    
    // Draw bullets
    for bullet in game.bullets {
        if !bullet.active {
            continue
        }
        col := bullet.sprite.color
        if bullet.is_player {
            engine.draw_rect(renderer, i32(bullet.transform.position.x - 3) + shake_x, 
                i32(bullet.transform.position.y - 8) + shake_y, 6, 16, col)
        } else {
            engine.draw_rect(renderer, i32(bullet.transform.position.x - 3) + shake_x, 
                i32(bullet.transform.position.y) + shake_y, 6, 12, col)
        }
    }
    
    // Draw enemies
    for enemy in game.enemies {
        if !enemy.active {
            continue
        }
        draw_enemy(renderer, enemy.transform.position.x, enemy.transform.position.y, 
            enemy.sprite.color, enemy.pattern, shake_x, shake_y)
    }
    
    // Draw particles
    for particle in game.particles {
        alpha := u8(255 * (particle.life / particle.max_life))
        col := particle.color
        col.a = alpha
        size := i32(particle.size * (particle.life / particle.max_life))
        if size < 1 {
            size = 1
        }
        engine.draw_rect(renderer, i32(particle.x - f32(size)/2) + shake_x, 
            i32(particle.y - f32(size)/2) + shake_y, size, size, col)
    }
    
    // HUD
    draw_hud(renderer, game, config.width, config.height)
    
    // Game over screen
    if game.game_over {
        draw_game_over(renderer, game, config.width, config.height)
    }
}

@(export)
game_shutdown :: proc(e: ^engine.Engine) {
    game := cast(^shmup_game)e.user_data
    if game == nil {
        return
    }
    
    delete(game.bullets)
    delete(game.enemies)
    delete(game.particles)
    delete(game.stars)
    free(game)
    
    fmt.println("Shmup example shutdown")
}

@(export)
game_handle_event :: proc(e: ^engine.Engine, event: ^SDL.Event) -> bool {
    if event.type == SDL.EventType.KEYDOWN {
        if event.key.keysym.scancode == SDL.Scancode.ESCAPE {
            return false // Quit
        }
    }
    return true // Continue running
}

// ============================================================================
// Spawning
// ============================================================================

spawn_bullet :: proc(e: ^engine.Engine, game: ^shmup_game, x, y: f32, is_player: bool) {
    if len(game.bullets) >= 100 {
        return
    }
    
    bullet := Bullet{
        transform = new(engine.Transform),
        sprite = new(engine.Sprite),
        velocity = new(engine.Velocity),
        collider = new(engine.Collider),
        active = true,
        lifetime = 3.0,
        is_player = is_player,
    }
    
    bullet.transform^ = engine.make_transform(x, y)
    if is_player {
        bullet.sprite^ = engine.make_sprite(6, 16, engine.color(100, 255, 100, 255))
        bullet.velocity^ = engine.make_velocity(0, -600)
        bullet.collider^ = engine.make_collider(6, 16, engine.CollisionLayer.PlayerBullet, 
            engine.CollisionMask{engine.CollisionLayer.Enemy})
    } else {
        bullet.sprite^ = engine.make_sprite(6, 12, engine.color(255, 100, 100, 255))
        bullet.velocity^ = engine.make_velocity(0, 250)
        bullet.collider^ = engine.make_collider(6, 12, engine.CollisionLayer.EnemyBullet, 
            engine.CollisionMask{engine.CollisionLayer.Player})
    }
    
    append(&game.bullets, bullet)
}

spawn_enemy :: proc(e: ^engine.Engine, game: ^shmup_game) {
    if len(game.enemies) >= 30 {
        return
    }
    
    config := e.config
    
    // Choose pattern based on wave
    pattern: EnemyPattern
    if game.wave >= 5 && rand.float32() < 0.05 {
        pattern = .boss
    } else if game.wave >= 3 && rand.float32() < 0.3 {
        pattern = .dive
    } else if game.wave >= 2 && rand.float32() < 0.4 {
        pattern = .zigzag
    } else if rand.float32() < 0.5 {
        pattern = .sine_wave
    } else {
        pattern = .straight
    }
    
    enemy := Enemy_ship{
        transform = new(engine.Transform),
        sprite = new(engine.Sprite),
        velocity = new(engine.Velocity),
        collider = new(engine.Collider),
        active = true,
        health = 1,
        pattern = pattern,
        pattern_timer = 0,
        pattern_data = rand.float32() * 6.28,
        fire_cooldown = 1.0 + rand.float32() * 2.0,
        score_value = 100,
    }
    
    x := rand.float32() * f32(config.width - 40) + 20
    y: f32 = -30
    speed: f32 = 80 + f32(game.wave) * 10 + rand.float32() * 50
    
    switch pattern {
    case .straight:
        enemy.sprite^ = engine.make_sprite(28, 28, engine.color(255, 80, 80, 255))
        enemy.velocity^ = engine.make_velocity(0, speed)
        enemy.collider^ = engine.make_collider(24, 24, engine.CollisionLayer.Enemy, 
            engine.CollisionMask{engine.CollisionLayer.Player, engine.CollisionLayer.PlayerBullet})
    case .sine_wave:
        enemy.sprite^ = engine.make_sprite(24, 24, engine.color(255, 150, 50, 255))
        enemy.velocity^ = engine.make_velocity(0, speed * 0.8)
        enemy.collider^ = engine.make_collider(20, 20, engine.CollisionLayer.Enemy, 
            engine.CollisionMask{engine.CollisionLayer.Player, engine.CollisionLayer.PlayerBullet})
    case .dive:
        enemy.sprite^ = engine.make_sprite(26, 26, engine.color(200, 50, 200, 255))
        enemy.velocity^ = engine.make_velocity(0, speed * 0.5)
        enemy.collider^ = engine.make_collider(22, 22, engine.CollisionLayer.Enemy, 
            engine.CollisionMask{engine.CollisionLayer.Player, engine.CollisionLayer.PlayerBullet})
    case .zigzag:
        enemy.sprite^ = engine.make_sprite(22, 22, engine.color(50, 255, 150, 255))
        enemy.velocity^ = engine.make_velocity(0, speed * 0.9)
        enemy.collider^ = engine.make_collider(18, 18, engine.CollisionLayer.Enemy, 
            engine.CollisionMask{engine.CollisionLayer.Player, engine.CollisionLayer.PlayerBullet})
    case .boss:
        enemy.health = 10
        enemy.score_value = 1000
        enemy.sprite^ = engine.make_sprite(60, 60, engine.color(255, 50, 50, 255))
        enemy.velocity^ = engine.make_velocity(0, speed * 0.3)
        enemy.collider^ = engine.make_collider(50, 50, engine.CollisionLayer.Enemy, 
            engine.CollisionMask{engine.CollisionLayer.Player, engine.CollisionLayer.PlayerBullet})
    }
    
    enemy.transform^ = engine.make_transform(x, y)
    append(&game.enemies, enemy)
}

spawn_explosion :: proc(game: ^shmup_game, x, y: f32, color: SDL.Color, count: int) {
    for i in 0..<count {
        angle := rand.float32() * 6.28
        speed := 50 + rand.float32() * 150
        particle := Particle{
            x = x,
            y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = 0.3 + rand.float32() * 0.5,
            max_life = 0.3 + rand.float32() * 0.5,
            size = 2 + rand.float32() * 4,
            color = color,
        }
        append(&game.particles, particle)
    }
}

// ============================================================================
// Collision
// ============================================================================

check_collisions :: proc(e: ^engine.Engine, game: ^shmup_game) {
    // Bullet vs Enemy
    for i := len(game.bullets) - 1; i >= 0; i -= 1 {
        bullet := &game.bullets[i]
        if !bullet.active || !bullet.is_player {
            continue
        }
        
        for j := len(game.enemies) - 1; j >= 0; j -= 1 {
            enemy := &game.enemies[j]
            if !enemy.active {
                continue
            }
            
            if bullet_enemy_collide(bullet, enemy) {
                bullet.active = false
                enemy.health -= 1
                if enemy.health <= 0 {
                    enemy.active = false
                    game.score += enemy.score_value
                    game.screen_shake = 0.5
                    spawn_explosion(game, enemy.transform.position.x, enemy.transform.position.y, 
                        enemy.sprite.color, 15)
                    engine.audio_play_sound(&e.audio, "explosion", -1)
                    
                    // Powerup drop chance
                    if rand.float32() < 0.1 {
                        game.ship.weapon_level = math.min(3, game.ship.weapon_level + 1)
                    }
                } else {
                    spawn_explosion(game, bullet.transform.position.x, bullet.transform.position.y, 
                        engine.color(255, 255, 100, 255), 3)
                    engine.audio_play_sound(&e.audio, "hit", -1)
                }
                break
            }
        }
    }
    
    // Enemy bullet vs Player
    for i := len(game.bullets) - 1; i >= 0; i -= 1 {
        bullet := &game.bullets[i]
        if !bullet.active || bullet.is_player {
            continue
        }
        
        if bullet_player_collide(bullet, &game.ship) {
            bullet.active = false
            if game.ship.invulnerable <= 0 {
                player_hit(e, game)
            }
        }
    }
    
    // Enemy vs Player (collision)
    for i := len(game.enemies) - 1; i >= 0; i -= 1 {
        enemy := &game.enemies[i]
        if !enemy.active {
            continue
        }
        
        if enemy_player_collide(enemy, &game.ship) {
            enemy.active = false
            spawn_explosion(game, enemy.transform.position.x, enemy.transform.position.y, 
                enemy.sprite.color, 10)
            if game.ship.invulnerable <= 0 {
                player_hit(e, game)
            }
        }
    }
}

bullet_enemy_collide :: proc(bullet: ^Bullet, enemy: ^Enemy_ship) -> bool {
    dx := bullet.transform.position.x - enemy.transform.position.x
    dy := bullet.transform.position.y - enemy.transform.position.y
    dist := math.sqrt(dx*dx + dy*dy)
    return dist < (f32(bullet.sprite.width) + f32(enemy.sprite.width)) / 2
}

bullet_player_collide :: proc(bullet: ^Bullet, ship: ^Ship) -> bool {
    dx := bullet.transform.position.x - ship.transform.position.x
    dy := bullet.transform.position.y - ship.transform.position.y
    dist := math.sqrt(dx*dx + dy*dy)
    return dist < (f32(bullet.sprite.width) + f32(ship.sprite.width)) / 2
}

enemy_player_collide :: proc(enemy: ^Enemy_ship, ship: ^Ship) -> bool {
    dx := enemy.transform.position.x - ship.transform.position.x
    dy := enemy.transform.position.y - ship.transform.position.y
    dist := math.sqrt(dx*dx + dy*dy)
    return dist < (f32(enemy.sprite.width) + f32(ship.sprite.width)) / 2
}

player_hit :: proc(e: ^engine.Engine, game: ^shmup_game) {
    game.lives -= 1
    game.screen_shake = 1.0
    spawn_explosion(game, game.ship.transform.position.x, game.ship.transform.position.y, 
        engine.color(0, 200, 255, 255), 20)
    engine.audio_play_sound(&e.audio, "explosion", -1)
    
    if game.lives <= 0 {
        game.game_over = true
        if game.score > game.high_score {
            game.high_score = game.score
        }
    } else {
        game.ship.invulnerable = 2.0
        game.ship.transform.position.x = f32(e.config.width) / 2
        game.ship.transform.position.y = f32(e.config.height) - 60
        game.ship.weapon_level = math.max(1, game.ship.weapon_level - 1)
    }
}

// ============================================================================
// Cleanup
// ============================================================================

cleanup_entities :: proc(e: ^engine.Engine, game: ^shmup_game) {
    // Remove inactive bullets
    for i := len(game.bullets) - 1; i >= 0; i -= 1 {
        if !game.bullets[i].active {
            unordered_remove(&game.bullets, i)
        }
    }
    
    // Remove inactive enemies
    for i := len(game.enemies) - 1; i >= 0; i -= 1 {
        if !game.enemies[i].active {
            unordered_remove(&game.enemies, i)
        }
    }
}

restart_game :: proc(e: ^engine.Engine, game: ^shmup_game) {
    game.score = 0
    game.wave = 1
    game.lives = 3
    game.game_over = false
    game.spawn_timer = 1.0
    game.wave_timer = 0
    game.screen_shake = 0
    game.ship.weapon_level = 1
    game.ship.invulnerable = 2.0
    game.ship.fire_cooldown = 0
    
    game.ship.transform.position.x = f32(e.config.width) / 2
    game.ship.transform.position.y = f32(e.config.height) - 60
    
    clear(&game.bullets)
    clear(&game.enemies)
    clear(&game.particles)
}

// ============================================================================
// Drawing
// ============================================================================

draw_ship :: proc(renderer: ^SDL.Renderer, x, y: f32, color: SDL.Color, shake_x, shake_y: i32) {
    cx := i32(x) + shake_x
    cy := i32(y) + shake_y
    
    // Main body (triangle)
    SDL.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
    SDL.RenderDrawLine(renderer, cx, cy - 16, cx - 12, cy + 12)
    SDL.RenderDrawLine(renderer, cx - 12, cy + 12, cx, cy + 8)
    SDL.RenderDrawLine(renderer, cx, cy + 8, cx + 12, cy + 12)
    SDL.RenderDrawLine(renderer, cx + 12, cy + 12, cx, cy - 16)
    
    // Engine glow
    engine_color := engine.color(100, 200, 255, 200)
    SDL.SetRenderDrawColor(renderer, engine_color.r, engine_color.g, engine_color.b, engine_color.a)
    SDL.RenderDrawLine(renderer, cx - 4, cy + 12, cx - 6, cy + 18 + rand.int_max(4))
    SDL.RenderDrawLine(renderer, cx + 4, cy + 12, cx + 6, cy + 18 + rand.int_max(4))
}

draw_enemy :: proc(renderer: ^SDL.Renderer, x, y: f32, color: SDL.Color, pattern: EnemyPattern, shake_x, shake_y: i32) {
    cx := i32(x) + shake_x
    cy := i32(y) + shake_y
    
    SDL.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
    
    switch pattern {
    case .straight:
        // Inverted triangle
        SDL.RenderDrawLine(renderer, cx - 14, cy - 14, cx + 14, cy - 14)
        SDL.RenderDrawLine(renderer, cx + 14, cy - 14, cx, cy + 14)
        SDL.RenderDrawLine(renderer, cx, cy + 14, cx - 14, cy - 14)
    case .sine_wave:
        // Diamond
        SDL.RenderDrawLine(renderer, cx, cy - 12, cx + 12, cy)
        SDL.RenderDrawLine(renderer, cx + 12, cy, cx, cy + 12)
        SDL.RenderDrawLine(renderer, cx, cy + 12, cx - 12, cy)
        SDL.RenderDrawLine(renderer, cx - 12, cy, cx, cy - 12)
    case .dive:
        // Arrow pointing down
        SDL.RenderDrawLine(renderer, cx - 10, cy - 10, cx + 10, cy - 10)
        SDL.RenderDrawLine(renderer, cx + 10, cy - 10, cx + 10, cy + 5)
        SDL.RenderDrawLine(renderer, cx + 10, cy + 5, cx, cy + 15)
        SDL.RenderDrawLine(renderer, cx, cy + 15, cx - 10, cy + 5)
        SDL.RenderDrawLine(renderer, cx - 10, cy + 5, cx - 10, cy - 10)
    case .zigzag:
        // Zigzag shape
        SDL.RenderDrawLine(renderer, cx - 10, cy - 10, cx, cy)
        SDL.RenderDrawLine(renderer, cx, cy, cx + 10, cy - 10)
        SDL.RenderDrawLine(renderer, cx + 10, cy - 10, cx + 10, cy + 10)
        SDL.RenderDrawLine(renderer, cx + 10, cy + 10, cx, cy)
        SDL.RenderDrawLine(renderer, cx, cy, cx - 10, cy + 10)
        SDL.RenderDrawLine(renderer, cx - 10, cy + 10, cx - 10, cy - 10)
    case .boss:
        // Large hexagon
        for i in 0..<6 {
            angle1 := f32(i) * 1.047
            angle2 := f32(i + 1) * 1.047
            x1 := cx + i32(math.cos(angle1) * 28)
            y1 := cy + i32(math.sin(angle1) * 28)
            x2 := cx + i32(math.cos(angle2) * 28)
            y2 := cy + i32(math.sin(angle2) * 28)
            SDL.RenderDrawLine(renderer, x1, y1, x2, y2)
        }
        // Boss health indicator
        SDL.SetRenderDrawColor(renderer, 255, 0, 0, 255)
        SDL.RenderDrawLine(renderer, cx - 20, cy - 35, cx + 20, cy - 35)
    }
}

draw_hud :: proc(renderer: ^SDL.Renderer, game: ^shmup_game, screen_w, screen_h: i32) {
    // Score
    score_str := fmt.tprintf("SCORE: %d", game.score)
    // Simple text rendering via SDL (would use TTF in production)
    // For now, draw a simple bar
    
    // Lives
    for i in 0..<game.lives {
        draw_ship(renderer, f32(20 + i * 25), f32(screen_h - 30), 
            engine.color(0, 200, 255, 255), 0, 0)
    }
    
    // Wave indicator
    wave_y := i32(20)
    SDL.SetRenderDrawColor(renderer, 255, 255, 255, 200)
    SDL.RenderDrawLine(renderer, 10, wave_y, 10 + game.wave * 8, wave_y)
    
    // Weapon level indicator
    if game.ship.weapon_level > 1 {
        SDL.SetRenderDrawColor(renderer, 100, 255, 100, 200)
        for i in 0..<game.ship.weapon_level {
            rect := SDL.Rect{screen_w - 30 - i * 12, screen_h - 20, 8, 8}
            SDL.RenderFillRect(renderer, &rect)
        }
    }
}

draw_game_over :: proc(renderer: ^SDL.Renderer, game: ^shmup_game, screen_w, screen_h: i32) {
    // Dark overlay
    SDL.SetRenderDrawColor(renderer, 0, 0, 0, 180)
    SDL.RenderFillRect(renderer, &SDL.Rect{0, 0, screen_w, screen_h})
    
    // Game over text (represented as lines for now)
    cx := screen_w / 2
    cy := screen_h / 2 - 40
    
    SDL.SetRenderDrawColor(renderer, 255, 50, 50, 255)
    // G
    SDL.RenderDrawLine(renderer, cx - 60, cy - 10, cx - 50, cy - 10)
    SDL.RenderDrawLine(renderer, cx - 60, cy - 10, cx - 60, cy + 10)
    SDL.RenderDrawLine(renderer, cx - 60, cy + 10, cx - 50, cy + 10)
    SDL.RenderDrawLine(renderer, cx - 50, cy, cx - 50, cy + 10)
    SDL.RenderDrawLine(renderer, cx - 55, cy, cx - 50, cy)
    
    // A
    SDL.RenderDrawLine(renderer, cx - 40, cy + 10, cx - 35, cy - 10)
    SDL.RenderDrawLine(renderer, cx - 35, cy - 10, cx - 30, cy + 10)
    SDL.RenderDrawLine(renderer, cx - 38, cy, cx - 32, cy)
    
    // M
    SDL.RenderDrawLine(renderer, cx - 20, cy + 10, cx - 20, cy - 10)
    SDL.RenderDrawLine(renderer, cx - 20, cy - 10, cx - 15, cy)
    SDL.RenderDrawLine(renderer, cx - 15, cy, cx - 10, cy - 10)
    SDL.RenderDrawLine(renderer, cx - 10, cy - 10, cx - 10, cy + 10)
    
    // E
    SDL.RenderDrawLine(renderer, cx, cy - 10, cx, cy + 10)
    SDL.RenderDrawLine(renderer, cx, cy - 10, cx + 10, cy - 10)
    SDL.RenderDrawLine(renderer, cx, cy, cx + 8, cy)
    SDL.RenderDrawLine(renderer, cx, cy + 10, cx + 10, cy + 10)
    
    // Score display
    SDL.SetRenderDrawColor(renderer, 255, 255, 255, 255)
    SDL.RenderDrawLine(renderer, cx - 40, cy + 30, cx + 40, cy + 30)
    
    // Restart prompt
    SDL.SetRenderDrawColor(renderer, 200, 200, 200, 255)
    SDL.RenderDrawLine(renderer, cx - 30, cy + 50, cx + 30, cy + 50)
}

// ============================================================================
// Entry Point
// ============================================================================

main :: proc() {
    config := engine.EngineConfig{
        title = "VoidEngine — Shmup",
        width = 800,
        height = 600,
        target_fps = 60.0,
        enable_hot_reload = true,
        asset_path = "assets",
        game_so_path = "",
    }
    
    e := engine.engine_init(config)
    defer engine.engine_shutdown(e)
    
    // Set up game API for hot reload
    e.game_api = engine.GameAPI{
        init = game_init,
        update = game_update,
        render = game_render,
        shutdown = game_shutdown,
        handle_event = game_handle_event,
    }
    
    // Initialize game
    game_init(e)
    
    // Run engine
    engine.engine_run(e)
}
