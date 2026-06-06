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
| `src/engine/audio.odin` | Sound/music playback |
| `src/engine/input.odin` | Keyboard, mouse, gamepad |
| `src/engine/config.odin` | JSON configuration loading |
| `src/engine/log.odin` | Structured logging |
| `src/engine/math.odin` | Vec2, Rect, Color, utilities |
| `src/engine/state.odin` | Game state machine |

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
