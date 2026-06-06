# VoidEngine Tutorial — Building Your First Game

## Introduction

Welcome to VoidEngine! This tutorial will walk you through creating a complete game from scratch. By the end, you'll have a working platformer with physics, sound, and save/load functionality.

## Prerequisites

- VoidEngine built and ready (`make build`)
- Basic familiarity with Odin or C-like syntax
- A text editor you enjoy

## Part 1: Creating a New Project

```bash
# Create a new game project
./voidengine new myplatformer
cd myplatformer

# Project structure:
# myplatformer/
# ├── src/
# │   └── game.odin
# ├── assets/
# │   ├── sprites/
# │   ├── sounds/
# │   ├── music/
# │   └── fonts/
# └── config.json
```

## Part 2: Basic Game Loop

Open `src/game.odin` and let's build a simple game:

```odin
package game

import "engine:engine"

// Player position
player_x: f32 = 400
player_y: f32 = 300
player_speed: f32 = 200

@(export)
game_init :: proc() {
    engine.log_info("Game initialized!")
}

@(export)
game_update :: proc(dt: f32) {
    // Move player with arrow keys
    if engine.is_key_down(.LEFT)  { player_x -= player_speed * dt }
    if engine.is_key_down(.RIGHT) { player_x += player_speed * dt }
    if engine.is_key_down(.UP)    { player_y -= player_speed * dt }
    if engine.is_key_down(.DOWN)  { player_y += player_speed * dt }
    
    // Keep player on screen
    player_x = engine.clamp(player_x, 0, 750)
    player_y = engine.clamp(player_y, 0, 550)
}

@(export)
game_draw :: proc() {
    // Clear screen (dark blue)
    engine.clear(0.05, 0.05, 0.15)
    
    // Draw player (green rectangle)
    engine.draw_rect(player_x, player_y, 50, 50, 0.0, 1.0, 0.5)
}

@(export)
game_shutdown :: proc() {
    engine.log_info("Game shutdown!")
}
```

Run it:
```bash
../voidengine run .
```

Use arrow keys to move the green rectangle around!

## Part 3: Adding Physics

Let's make the player jump and fall with gravity:

```odin
package game

import "engine:engine"

// Physics body ID
player_body: int = -1

// Ground
GROUND_Y :: 500

@(export)
game_init :: proc() {
    engine.log_info("Game initialized!")
    
    // Initialize physics
    engine.physics_init()
    
    // Create player body (dynamic, affected by gravity)
    player_body = engine.physics_add_body({400, 300}, {32, 32}, .DYNAMIC)
    
    // Create ground (static, doesn't move)
    ground := engine.physics_add_body({400, GROUND_Y}, {800, 20}, .STATIC)
}

@(export)
game_update :: proc(dt: f32) {
    // Get player body
    body := engine.physics_get_body(player_body)
    if body == nil { return }
    
    // Horizontal movement
    move_x: f32 = 0
    if engine.is_key_down(.LEFT)  { move_x -= 1 }
    if engine.is_key_down(.RIGHT) { move_x += 1 }
    
    body.velocity.x = move_x * 200
    
    // Jump
    if engine.is_key_pressed(.A) && body.position.y >= GROUND_Y - 50 {
        body.velocity.y = -400
    }
    
    // Apply gravity
    body.velocity.y += 800 * dt
    
    // Update physics
    engine.physics_step(dt)
}

@(export)
game_draw :: proc() {
    engine.clear(0.05, 0.05, 0.15)
    
    // Draw ground
    engine.draw_rect(0, GROUND_Y, 800, 20, 0.4, 0.3, 0.2)
    
    // Draw player
    body := engine.physics_get_body(player_body)
    if body != nil {
        engine.draw_rect(
            body.position.x - 16, 
            body.position.y - 16, 
            32, 32, 
            0.0, 1.0, 0.5
        )
    }
}

@(export)
game_shutdown :: proc() {
    engine.physics_shutdown()
}
```

## Part 4: Adding Sound

Add sound effects to your game:

```odin
@(export)
game_init :: proc() {
    engine.log_info("Game initialized!")
    engine.physics_init()
    
    // Load sounds
    sound_jump = engine.load_sound("assets/sounds/jump.wav")
    sound_land = engine.load_sound("assets/sounds/land.wav")
    
    // ... rest of init
}

@(export)
game_update :: proc(dt: f32) {
    // ... movement code ...
    
    // Jump with sound
    if engine.is_key_pressed(.A) && on_ground {
        body.velocity.y = -400
        engine.play_sound(sound_jump)  // Play jump sound!
    }
    
    // ... rest of update
}
```

## Part 5: Game States

Add a menu and game over screen:

```odin
package game

import "engine:engine"

state_menu: int = -1
state_play: int = -1
state_gameover: int = -1

@(export)
game_init :: proc() {
    engine.state_machine_init()
    
    state_menu = engine.state_register("menu", menu_init, menu_update, menu_draw, menu_exit)
    state_play = engine.state_register("play", play_init, play_update, play_draw, play_exit)
    state_gameover = engine.state_register("gameover", gameover_init, gameover_update, gameover_draw, gameover_exit)
    
    engine.state_change(state_menu)
}

@(export)
game_update :: proc(dt: f32) {
    engine.state_machine_update(dt)
}

@(export)
game_draw :: proc() {
    engine.state_machine_draw()
}

// Menu state
menu_init :: proc() { }
menu_update :: proc(dt: f32) {
    if engine.is_key_pressed(.START) {
        engine.state_change(state_play)
    }
}
menu_draw :: proc() {
    engine.clear(0.05, 0.05, 0.15)
    engine.draw_text(300, 250, "MY PLATFORMER", 0, 1.0, 1.0, 1.0)
    engine.draw_text(250, 320, "Press ENTER to start", 0, 0.8, 0.8, 0.8)
}
menu_exit :: proc() { }

// Play state
play_init :: proc() {
    // Reset player position
    player_body = engine.physics_add_body({400, 300}, {32, 32}, .DYNAMIC)
}
play_update :: proc(dt: f32) {
    // ... game logic ...
    
    // Check game over condition
    body := engine.physics_get_body(player_body)
    if body != nil && body.position.y > 600 {
        engine.state_change(state_gameover)
    }
}
play_draw :: proc() {
    engine.clear(0.05, 0.05, 0.15)
    // ... draw game ...
}
play_exit :: proc() { }

// Game over state
gameover_init :: proc() { }
gameover_update :: proc(dt: f32) {
    if engine.is_key_pressed(.START) {
        engine.state_change(state_play)
    }
}
gameover_draw :: proc() {
    engine.clear(0.2, 0.05, 0.05)
    engine.draw_text(300, 250, "GAME OVER", 0, 1.0, 0.0, 0.0)
    engine.draw_text(250, 320, "Press ENTER to retry", 0, 0.8, 0.8, 0.8)
}
gameover_exit :: proc() { }

@(export)
game_shutdown :: proc() {
    engine.state_machine_shutdown()
}
```

## Part 6: Save/Load Progress

Save the player's high score:

```odin
high_score: int = 0

@(export)
game_init :: proc() {
    // Load save if it exists
    if engine.save_exists(".") {
        engine.save_from_file("save.json")
        high_score = engine.save_get_int("high_score", 0)
    }
}

// When game ends, save high score
play_exit :: proc() {
    if current_score > high_score {
        high_score = current_score
        engine.save_set_int("high_score", high_score)
        engine.save_to_file("save.json")
    }
}
```

## Part 7: Hot-Reload Development

One of VoidEngine's best features is hot-reload:

1. Run your game: `./voidengine run .`
2. Edit `src/game.odin` in your editor
3. Save the file
4. Rebuild the DLL: `make build-demo` (or your build command)
5. Press **F5** in the game window
6. See your changes instantly!

The engine automatically saves and restores game state across reloads.

## Part 8: Building a Standalone Executable

When your game is ready to ship:

```bash
./voidengine build .
```

This produces a single executable with no DLL dependency.

## Tips and Best Practices

### Performance
- Keep `game_update` fast (under 16ms for 60fps)
- Do heavy work in `game_init`, not every frame
- Use the debug overlay (F1) to monitor performance

### Asset Management
- Keep sprites small (under 512x512)
- Use WAV for short sounds, OGG for music
- Place fonts in `assets/fonts/`

### Debugging
- Press **F1** to toggle the debug overlay (FPS, memory, draw calls)
- Press **~** (grave) to open the debug console
- Use `engine.log_info()` for debugging

### Common Issues

**Game DLL not found:**
- Make sure you built the game DLL: `make build-demo`
- Check that `game.dll` exists in your project directory

**Assets not loading:**
- Use relative paths from the project root
- Check that files exist in `assets/`

**Hot-reload not working:**
- Make sure you rebuilt the DLL after changes
- Check that the DLL compiled successfully
- Press F5 to trigger reload

## Next Steps

- Study the example games in `examples/` directory
- Read the full API reference in `docs/API_REFERENCE.md`
- Join the community and share your creations!

---

*Happy game development with VoidEngine v1.0.0!* 🎮🌌
