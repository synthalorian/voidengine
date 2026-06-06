# VoidEngine — Development Plan

Game engine where `void run mygame/` just works. Odin. Zero dependencies. Hot-reload everything.

---

## v0.1.0 — Draw (Now) ✅

- [x] Add SDL2 dependency to build system
- [x] Implement `renderer.odin` with real SDL2 draw calls
- [x] Clear screen, draw rects, draw sprites from PNG
- [x] Implement `input.odin` with SDL2 keyboard + mouse polling
- [x] Game loop: process input → update → render at 60fps
- [x] Demo game: move a rectangle with arrow keys

## v0.2.0 — Sound + Assets ✅

- [x] Add miniaudio or SDL2_mixer for audio
- [x] Load and play WAV/OGG sounds
- [x] Stream music
- [x] Sprite atlas support
- [x] Font rendering (TTF or bitmap)
- [x] Asset hot-reload (edit PNG, see changes instantly)

## v0.3.0 — Ship ✅

- [x] Implement `build_project()` — compile game + engine to single binary
- [x] Cross-platform: Linux, Windows, macOS
- [x] Package manager: `void get <package>`
- [x] Debug overlay (FPS, memory, draw calls)
- [x] Profiling hooks

## v0.4.0 — Engine Core ✅

- [x] Configuration system — JSON-based game settings (window, audio, keybinds)
- [x] Structured logging — log levels (DEBUG, INFO, WARN, ERROR)
- [x] Math utilities — Vec2, Rect, Color, lerp, clamp, collision detection
- [x] Game state machine — menu, gameplay, pause states
- [x] Configurable keybindings via config file
- [x] Engine reads window title/size from game config
- [x] Tests for config, math, logging, and state modules
- [x] Demo updated to showcase v0.4.0 features

## v0.5.0 — Physics & Animation ✅

- [x] 2D physics engine — rigid bodies, velocity, acceleration, gravity
- [x] AABB and circle collision resolution (response, not just detection)
- [x] Sprite animation system — frame-based with timing and looping
- [x] Tilemap support — load and render Tiled JSON maps
- [x] Camera system — follow target, smooth damping, bounds clamping
- [x] Particle system — emitters, lifetime, velocity, color over life
- [x] Demo: platformer with physics, tilemap, animated sprites

## v0.6.0 — Audio & Polish ✅

- [x] Spatial audio — pan and volume based on listener position
- [x] Audio mixer with channels (music, SFX, UI) and per-channel volume
- [x] Music transition system — crossfade between tracks
- [x] Save/load game state to JSON
- [x] Screen transitions (fade, slide) via state machine
- [x] Debug console — in-game command line for inspecting state
- [x] Performance profiler — frame time graph, memory usage display
- [x] Second example game: shmup with particles and spatial audio

## v0.7.0 — Pre-Release Polish ✅

- [x] Hot-reload fix — reload game DLL without memory leaks or state corruption
- [x] Standalone build — `void build` produces single executable (no DLL)
- [x] Third example game: puzzle game showcasing save/load and state machine
- [x] Documentation — engine API reference, getting started guide, tutorial
- [x] Asset pipeline — texture atlas packing, audio bank bundling
- [x] Error handling — graceful failures with clear messages
- [x] Cross-platform build verification (Linux, Windows via Wine, macOS notes)
- [x] Package manager — `void get` fetches from git repos

## v1.0.0 — Ship It

- [ ] Complete 2D game engine
- [ ] Hot-reload works flawlessly
- [ ] Standalone build produces single executable
- [ ] Documentation + tutorial
- [ ] Example games: platformer, shmup, puzzle

---

## Architecture

```
Game DLL (user code)
    ↓ calls
Engine (renderer, audio, input, hot-reload, config, logging, math, state)
    ↓ calls
SDL2 / miniaudio / OS
```

## Key Files

| File | Responsibility |
|------|---------------|
| `src/main.odin` | CLI: run, new, build commands |
| `src/engine/engine.odin` | Hot-reload, game loop, DLL management |
| `src/engine/renderer.odin` | SDL2 graphics |
| `src/engine/audio.odin` | Sound/music playback, spatial audio, mixer |
| `src/engine/input.odin` | Keyboard, mouse, gamepad |
| `src/engine/config.odin` | JSON configuration loading |
| `src/engine/log.odin` | Structured logging |
| `src/engine/math.odin` | Vec2, Rect, Color, utilities |
| `src/engine/state.odin` | Game state machine, screen transitions |
| `src/engine/physics.odin` | 2D physics, rigid bodies, collision |
| `src/engine/animation.odin` | Sprite animation system |
| `src/engine/tilemap.odin` | Tiled JSON map loading/rendering |
| `src/engine/camera.odin` | Camera follow, damping, bounds |
| `src/engine/particle.odin` | Particle emitters and effects |
| `src/engine/save.odin` | Save/load game state to JSON |
| `src/engine/debug_console.odin` | In-game debug command console |
| `src/engine/profiler.odin` | Frame timing, performance graphs |

## Local Dev

```bash
make check    # Verify all packages compile
make build    # Build engine executable
make build-demo  # Build demo game DLL
make run-demo    # Run demo with hot-reload
make test        # Run tests
```

## Project Structure

```
mygame/
├── src/
│   └── game.odin      # game_init, game_update, game_draw, game_shutdown
├── assets/
│   ├── sprites/
│   ├── sounds/
│   └── music/
├── config.json        # Game configuration
└── game.dll           # Auto-generated on build
```

## Game API

```odin
@(export) game_init :: proc() { }
@(export) game_update :: proc(dt: f32) { }
@(export) game_draw :: proc() { }
@(export) game_shutdown :: proc() { }
```

---

*Born from the void.* 🌌
