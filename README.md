# VoidEngine 🎮🌌

A lightweight 2D game engine with hot-reload, ECS, physics, and audio. Built with **Odin** + **SDL2**.

> **Version:** v0.3.0  
> **Status:** playable demos, test suite passing, ship-ready

---

## Features

- **Hot Reload** — reload game logic as a shared library without restarting the engine
- **Entity-Component-System (ECS)** — scene-based entities with components and helpers
- **2D Physics & Collision** — velocity-based movement, AABB collision, layer/mask filtering
- **Audio System** — SDL_mixer integration for WAV sound effects and music
- **Scene Management** — switch scenes with init/update/render/shutdown lifecycle
- **Fixed Timestep** — deterministic 60 Hz update loop
- **Input Handling** — keyboard, mouse, and gamepad support
- **Math Helpers** — `vec2`, `vec3`, `color`, `lerp`, `clamp`, `rand_range`

---

## Dependencies

```bash
# Arch Linux
sudo pacman -S sdl2 sdl2_mixer
```

Other distros: install `libsdl2` and `SDL2_mixer` development packages.

---

## Building

```bash
# Clone / cd into the project
cd voidengine

# Build all examples
make

# Or build individually
make shmup
make demo
make puzzle

# Build the engine as a shared library (for hot-reload games)
make shared

# Type-check everything without compiling
make check

# Run the test suite
make test

# Clean build artifacts
make clean
```

### Running Examples

```bash
make run          # vertical scrolling shooter
make run-demo     # simple demo
make run-puzzle   # match-3 puzzle
```

---

## Project Layout

```
voidengine/
├── src/
│   └── core/
│       └── engine.odin      # Core engine, ECS, physics, audio, hot-reload
├── tests/
│   └── test_engine.odin     # Unit tests for ECS, collision, helpers
├── examples/
│   ├── demo/                # Basic input + shooting demo
│   ├── shmup/               # Full vertical scrolling shooter
│   └── puzzle/              # Match-3 puzzle with mouse input
├── studio/                  # VoidEngine Studio (Tauri GUI)
│   ├── src-tauri/           # Rust backend
│   ├── src/                 # React frontend
│   └── README.md
├── assets/                  # Sound effects (not included)
├── Makefile
└── README.md
```

---

## VoidEngine Studio

Want a GUI instead of the terminal? Use **VoidEngine Studio** — a Tauri + React desktop app for building and testing your games.

```bash
cd studio
npm install
npm run tauri:dev
```

Studio auto-detects VoidEngine projects, lets you run **Check / Test / Build All**, and gives you per-example **Build Example** / **Run Example** buttons with live output. See [`studio/README.md`](studio/README.md) for details.

---

## Quick Start

```odin
package main

import SDL "vendor:sdl2"
import engine "../src/core"

main :: proc() {
    e := engine.engine_init(engine.EngineConfig{
        title = "My Game",
        width = 1280,
        height = 720,
        target_fps = 60.0,
        asset_path = "assets",
    })
    defer engine.engine_shutdown(e)

    // Create a scene
    scene := engine.scene_create(e, "gameplay")
    engine.scene_switch(e, scene)

    // Create an entity
    entity := engine.entity_create(scene)
    transform := new(engine.Transform)
    transform^ = engine.make_transform(100, 100)
    engine.entity_add_component(entity, engine.Transform, transform)

    engine.engine_run(e)
}
```

### Hot Reload

Build your game as a shared library with exported symbols:

```odin
@(export)
game_init :: proc(e: ^engine.Engine) { }

@(export)
game_update :: proc(e: ^engine.Engine, dt: f64) { }

@(export)
game_render :: proc(e: ^engine.Engine, renderer: ^SDL.Renderer) { }

@(export)
game_shutdown :: proc(e: ^engine.Engine) { }
```

Set `enable_hot_reload = true` and `game_so_path = "path/to/game.so"`. The engine will watch the file and reload it on change.

---

## Examples

| Example | What it Shows | Controls |
|---------|-------------|----------|
| **demo** | Basic movement, shooting, collision | WASD / Arrows + Space |
| **shmup** | Full game with waves, particles, screen shake | WASD / Arrows + Space + R |
| **puzzle** | Match-3 with mouse, swapping, cascades | Mouse click + Space |

---

## Architecture

### ECS

Entities live in scenes. Components are plain structs (e.g., `Transform`, `Sprite`, `Velocity`, `Collider`). Use `entity_add_component` and `entity_get_component` to attach and retrieve data.

### Physics

`physics_update(scene, dt)` applies velocity to transforms. `entities_collide(a, b)` does AABB checks with layer/mask filtering.

### Audio

```odin
engine.audio_load_sound(&e.audio, "shoot", "assets/shoot.wav")
engine.audio_play_sound(&e.audio, "shoot")
engine.audio_play_music(&e.audio, "bgm")
engine.audio_set_master_volume(&e.audio, 0.8)
```

---

## Testing

```bash
make test
```

The test suite covers config creation, component helpers, entity creation, collision detection, and math utilities.

---

## Roadmap

- [x] Core engine + game loop
- [x] ECS + components
- [x] 2D physics + collision
- [x] Audio system (SDL_mixer)
- [x] Hot reload on Linux
- [x] Working examples (demo, shmup, puzzle)
- [x] Unit tests
- [ ] Texture / sprite batch rendering
- [ ] Tilemap / level loader
- [ ] Gamepad support
- [ ] Windows / macOS hot reload

---

## License

MIT

---

*Built on the neon grid. The tape never stops rolling.* 🎹🦞
