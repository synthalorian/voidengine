# 🌌 VoidEngine

A game engine where `void run mygame/` just works. No install, no dependencies, no 20-step setup.

Born from the void. Built for immediacy. Hot-reload everything and watch your game come alive in real-time.

## Philosophy

- **Single binary** — The engine is one executable
- **Hot-reload everything** — Edit code, see changes instantly
- **PICO-8 immediacy** — For "real" games
- **Zero ceremony** — No project wizards, no boilerplate mountains

## Quick Start

```bash
# Create a new game
grid-engine new mygame
cd mygame

# Run it (hot-reload enabled)
grid-engine run .

# Edit src/game.odin, save, see changes instantly
```

## Project Structure

```
mygame/
├── src/
│   └── game.odin      # Your game code
├── assets/
│   ├── sprites/
│   ├── sounds/
│   └── music/
└── game.dll           # Compiled game (auto-generated)
```

## API

```odin
// Lifecycle (required exports)
game_init :: proc() { }
game_update :: proc(dt: f32) { }
game_draw :: proc() { }
game_shutdown :: proc() { }

// Drawing
engine.clear(r, g, b: f32)
engine.draw_rect(x, y, w, h, r, g, b: f32)
engine.draw_sprite(x, y: f32, sprite_id: int)
engine.draw_text(x, y: f32, text: string)

// Input
engine.is_key_pressed(.A)
engine.is_key_down(.LEFT)

// Audio
engine.play_sound(id: int)
engine.play_music(id: int)
```

## Building Standalone

```bash
grid-engine build mygame/
# Produces: mygame-standalone (single binary)
```

## Architecture

```
┌─────────────────────────────────────┐
│           Grid Engine               │
│  ┌─────────┐  ┌─────────┐          │
│  │ Hot     │  │ Game    │          │
│  │ Reload  │  │ DLL     │          │
│  └────┬────┘  └────┬────┘          │
│       └─────────────┘               │
│  ┌─────────┐  ┌─────────┐          │
│  │ Renderer│  │ Audio   │          │
│  │ (GL/VK) │  │ (minia.)│          │
│  └─────────┘  └─────────┘          │
└─────────────────────────────────────┘
```

## License

MIT — Build the future. 🎹🦈
