# VoidEngine — Development Plan

Game engine where `void run mygame/` just works. Odin. Zero dependencies. Hot-reload everything.

---

## v0.1.0 — Draw (Now)

- [ ] Add SDL2 dependency to build system
- [ ] Implement `renderer.odin` with real SDL2 draw calls
- [ ] Clear screen, draw rects, draw sprites from PNG
- [ ] Implement `input.odin` with SDL2 keyboard + mouse polling
- [ ] Game loop: process input → update → render at 60fps
- [ ] Demo game: move a rectangle with arrow keys

## v0.2.0 — Sound + Assets

- [ ] Add miniaudio or SDL2_mixer for audio
- [ ] Load and play WAV/OGG sounds
- [ ] Stream music
- [ ] Sprite atlas support
- [ ] Font rendering (TTF or bitmap)
- [ ] Asset hot-reload (edit PNG, see changes instantly)

## v0.3.0 — Ship

- [ ] Implement `build_project()` — compile game + engine to single binary
- [ ] Cross-platform: Linux, Windows, macOS
- [ ] Package manager: `void get <package>`
- [ ] Debug overlay (FPS, memory, draw calls)
- [ ] Profiling hooks

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
Engine (renderer, audio, input, hot-reload)
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

## Local Dev

```bash
make check    # Verify all packages compile
make build    # Build engine executable
make build-demo  # Build demo game DLL
make run-demo    # Run demo with hot-reload
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
