# VoidEngine 🎮

Game engine with hot-reload and data-driven design. Built with Odin + SDL2.

## Features

- **Hot reload**: Reload game code without restarting the engine
- **Entity-Component-System**: Flexible architecture for game objects
- **Fixed timestep**: Deterministic 60Hz physics/update loop
- **Scene management**: Easy scene transitions and management
- **Input handling**: Keyboard, mouse, and gamepad support
- **Audio system**: Integrated audio engine (placeholder for SDL_mixer)

## Building

```bash
# Install dependencies (Arch)
sudo pacman -S sdl2 sdl2_image sdl2_mixer sdl2_ttf

# Build engine library
odin build src/core -build-mode:shared -out:voidengine.dll

# Build demo
cd examples/demo
odin build . -out:demo

# Run
./demo
```

## Architecture

```
voidengine/
├── src/
│   └── core/
│       └── engine.odin      # Core engine (hot reload, ECS, scenes)
├── examples/
│   ├── demo/                # Basic demo showing engine features
│   ├── shmup/               # Vertical scrolling shooter
│   └── puzzle/              # Match-3 puzzle game
└── assets/
    ├── shaders/
    ├── textures/
    └── sounds/
```

## Hot Reload

The engine supports hot-reloading of game code:

1. Build your game as a shared library (`game.dll`)
2. The engine monitors the file for changes
3. When modified, the engine reloads the game code seamlessly
4. Game state is preserved across reloads

## API

```odin
// Initialize engine
config := engine.EngineConfig{
    title = "My Game",
    width = 1280,
    height = 720,
    target_fps = 60.0,
    enable_hot_reload = true,
}
e := engine.engine_init(config)

// Define game callbacks
e.game_api = engine.GameAPI{
    init = my_init,
    update = my_update,
    render = my_render,
    shutdown = my_shutdown,
}

// Run
engine.engine_run(e)
```

## License

MIT
