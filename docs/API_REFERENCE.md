# VoidEngine Documentation

## Getting Started Guide

### Installation

VoidEngine is a single binary with zero dependencies. Just download and run:

```bash
# Clone the repository
git clone https://github.com/voidengine/voidengine.git
cd voidengine

# Build the engine
make build

# Verify everything works
make check
make test
```

### Creating Your First Game

```bash
# Create a new game project
./voidengine new mygame
cd mygame

# Run it (hot-reload enabled)
./voidengine run .

# Edit src/game.odin, save, and see changes instantly
```

### Project Structure

```
mygame/
├── src/
│   └── game.odin      # Your game code
├── assets/
│   ├── sprites/       # PNG/JPG images
│   ├── sounds/        # WAV audio files
│   ├── music/         # OGG music files
│   └── fonts/         # TTF font files
├── config.json        # Game configuration
└── game.dll           # Compiled game (auto-generated)
```

## Game API Reference

### Lifecycle Functions (Required Exports)

```odin
@(export)
game_init :: proc() {
    // Called once when the game starts
    // Load assets, initialize state, etc.
}

@(export)
game_update :: proc(dt: f32) {
    // Called every frame (60 FPS)
    // dt = delta time in seconds
    // Update game logic, handle input, etc.
}

@(export)
game_draw :: proc() {
    // Called every frame after update
    // All rendering happens here
}

@(export)
game_shutdown :: proc() {
    // Called when the game exits
    // Save progress, clean up, etc.
}
```

### Drawing

```odin
// Clear the screen with RGB color (0.0 - 1.0)
engine.clear(r, g, b: f32)

// Draw a filled rectangle
engine.draw_rect(x, y, w, h: f32, r, g, b: f32)

// Load and draw a sprite (returns sprite_id)
sprite_id := engine.load_sprite(path: string)
engine.draw_sprite(x, y: f32, sprite_id: int)

// Load and draw text (returns font_id)
font_id := engine.load_font(path: string, size: i32)
engine.draw_text(x, y: f32, text: string, font_id: int = 0, r, g, b: f32 = 1.0)
```

### Input

```odin
// Check if a key was just pressed this frame
engine.is_key_pressed(.A)      // Returns true for one frame
engine.is_key_pressed(.START)

// Check if a key is currently held down
engine.is_key_down(.LEFT)
engine.is_key_down(.RIGHT)

// Check any SDL scancode directly
engine.is_scancode_down(SDL.Scancode.F5)

// Get mouse position
mx, my := engine.get_mouse_pos()

// Check mouse buttons (1=left, 2=middle, 3=right)
if engine.is_mouse_button_down(1) { }
```

### Audio

```odin
// Load and play sounds
sound_id := engine.load_sound(path: string)
engine.play_sound(sound_id: int)

// Load and play music (loops automatically)
music_id := engine.load_music(path: string)
engine.play_music(music_id: int)
engine.stop_music()
engine.pause_music()
engine.resume_music()

// Volume control (0.0 - 1.0)
engine.set_music_volume(0.8)
engine.set_sound_volume(sound_id, 0.5)
```

### State Machine

```odin
// Initialize the state machine
engine.state_machine_init()

// Register states (returns state_id)
state_menu := engine.state_register("menu", menu_init, menu_update, menu_draw, menu_exit)
state_play := engine.state_register("play", play_init, play_update, play_draw, play_exit)

// Change state instantly
engine.state_change(state_play)

// Change state with transition effect
engine.state_change_with_transition(state_play, .FADE, 0.5)
// Transition types: .NONE, .FADE, .SLIDE_LEFT, .SLIDE_RIGHT, .SLIDE_UP, .SLIDE_DOWN

// Update and draw current state (called in game_update/game_draw)
engine.state_machine_update(dt)
engine.state_machine_draw()
```

### Save/Load System

```odin
// Set values (persisted in memory)
engine.save_set_int("score", 1000)
engine.save_set_float("player_x", 150.5)
engine.save_set_string("player_name", "Hero")
engine.save_set_bool("unlocked_level_2", true)

// Get values with defaults
score := engine.save_get_int("score", 0)
x := engine.save_get_float("player_x", 0.0)
name := engine.save_get_string("player_name", "Unknown")
unlocked := engine.save_get_bool("unlocked_level_2", false)

// Save to file
engine.save_to_file("save.json")

// Load from file
engine.save_from_file("save.json")

// Check if save exists
if engine.save_exists(".") { }
```

### Physics (v0.5.0+)

```odin
// Initialize physics
engine.physics_init()

// Create a rigid body (returns body_id)
body_id := engine.physics_create_body(x, y: f32, mass: f32)

// Apply forces
engine.physics_apply_force(body_id, fx, fy: f32)
engine.physics_set_velocity(body_id, vx, vy: f32)

// Get body state
pos := engine.physics_get_position(body_id)
vel := engine.physics_get_velocity(body_id)

// Collision detection
if engine.physics_check_collision(body_a, body_b) { }

// Step physics (called automatically by engine)
engine.physics_step(dt)
```

### Camera (v0.5.0+)

```odin
// Initialize camera
engine.camera_init(screen_width, screen_height: f32)

// Set camera target (smooth follow)
engine.camera_set_target(x, y: f32)
engine.camera_set_damping(damping: f32)  // 0.0 = instant, 1.0 = very smooth

// Set camera bounds
engine.camera_set_bounds(min_x, min_y, max_x, max_y: f32)

// Get camera offset for drawing
offset := engine.camera_get_offset()

// Convert world to screen and back
screen_pos := engine.camera_world_to_screen(world_pos)
world_pos := engine.camera_screen_to_world(screen_pos)
```

### Particles (v0.5.0+)

```odin
// Initialize particle system
engine.particle_init()

// Create an emitter (returns emitter_id)
emitter_id := engine.particle_create_emitter(x, y: f32)

// Configure emitter
engine.particle_set_rate(emitter_id, particles_per_second: f32)
engine.particle_set_lifetime(emitter_id, min_life, max_life: f32)
engine.particle_set_velocity(emitter_id, min_vx, min_vy, max_vx, max_vy: f32)
engine.particle_set_color(emitter_id, r, g, b: f32)

// Update and draw particles (called automatically by engine)
engine.particle_update(dt)
engine.particle_draw()
```

### Math Utilities

```odin
// Vec2
v1 := engine.vec2(3, 4)
v2 := engine.vec2_add(v1, engine.vec2(1, 2))
len := engine.vec2_len(v1)
dot := engine.vec2_dot(v1, v2)
lerped := engine.vec2_lerp(v1, v2, 0.5)

// Rect
r1 := engine.rect(0, 0, 100, 100)
r2 := engine.rect(50, 50, 100, 100)
if engine.rect_intersects(r1, r2) { }
if engine.rect_contains_point(r1, engine.vec2(50, 50)) { }

// General math
result := engine.lerp(0.0, 100.0, 0.5)     // 50.0
clamped := engine.clamp(value, 0.0, 1.0)   // 0.0-1.0
```

### Logging

```odin
engine.log_debug("Debug message: %d", value)
engine.log_info("Info message: %s", name)
engine.log_warn("Warning: something might be wrong")
engine.log_error("Error: something went wrong!")
```

### Configuration

```json
{
    "window": {
        "title": "My Game",
        "width": 800,
        "height": 600,
        "vsync": true
    },
    "audio": {
        "enabled": true,
        "master_volume": 1.0,
        "music_volume": 0.8,
        "sfx_volume": 1.0
    },
    "input": {
        "keybindings": {
            "left": "LEFT",
            "right": "RIGHT",
            "up": "UP",
            "down": "DOWN",
            "action_a": "Z",
            "action_b": "X",
            "start": "RETURN",
            "select": "TAB"
        }
    },
    "debug": {
        "show_overlay": false,
        "log_level": "INFO"
    }
}
```

## Asset Pipeline (v0.7.0+)

### Texture Atlas Packing

```odin
// Scan directory for images
images := engine.scan_images("assets/sprites")

// Pack into atlas
result := engine.atlas_pack("game_atlas", images)
if result.success {
    atlas_idx := len(engine.atlases) - 1
    
    // Draw sprite from atlas
    engine.atlas_draw_sprite(atlas_idx, "player", 100, 100)
    
    // Save metadata for runtime
    engine.atlas_save_metadata(atlas_idx, "atlas.json")
}
```

### Audio Bank Bundling

```odin
// Scan directory for audio
sounds := engine.scan_audio("assets/sounds")

// Create audio bank
bank_idx := engine.audio_bank_create("sfx_bank", sounds)

// Play sound from bank
engine.audio_bank_play(bank_idx, "jump")
engine.audio_bank_play(bank_idx, "explosion")
```

## Error Handling (v0.7.0+)

```odin
// Set error context
engine.error_set(.FILE_NOT_FOUND, "Could not load player.png", #file, #line)

// Check for errors
if engine.error_occurred() {
    msg := engine.error_get_user_message()
    engine.log_error("Error: %s", msg)
    engine.error_print_report()
}

// Try operations with automatic error handling
data, ok := engine.try_read_file("save.json")
if ok {
    // Use data
    delete(data)
}
```

## Hot-Reload (v0.7.0+)

During development, press **F5** to hot-reload the game DLL without restarting the engine:

1. Make changes to `src/game.odin`
2. Save the file
3. Rebuild the game DLL: `make build-demo` (or your project's build command)
4. Press **F5** in the running game window
5. The engine will:
   - Save current game state
   - Unload the old DLL
   - Load the new DLL
   - Restore game state
   - Resume gameplay

The hot-reload system prevents memory leaks and state corruption by properly cleaning up resources.

## Standalone Build

To build a standalone executable (no DLL required):

```bash
./voidengine build mygame/
```

This produces a single binary that can be distributed without the engine source code.

## Package Manager

```bash
# Install a package from the registry
./voidengine get math

# Install from a Git repository
./voidengine get https://github.com/user/package-name

# List installed packages
./voidengine packages
```

## Example Games

Three example games are included:

1. **Demo** (`examples/demo/`) - Platformer with physics, tilemap, animations
2. **Shmup** (`examples/shmup/`) - Shoot 'em up with particles and spatial audio
3. **Puzzle** (`examples/puzzle/`) - Grid-based puzzle showcasing save/load and state machine

Run an example:
```bash
make build-demo
make run-demo
```

## CLI Commands

```bash
voidengine new <name>       # Create a new game project
voidengine run <dir>        # Run a game project (with hot-reload)
voidengine build <dir>      # Build standalone executable
voidengine get <pkg>        # Install a package
voidengine packages         # List installed packages
voidengine help             # Show help message
```

---

*Built with VoidEngine v0.7.0* 🌌
