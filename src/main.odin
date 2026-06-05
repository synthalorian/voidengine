package main

import "core:fmt"
import "core:os"
import "core:mem"
import "engine"

main :: proc() {
    fmt.println("🎹 GridTracker v0.1.0")
    fmt.println("Usage: void run mygame/")

    if len(os.args) < 3 {
        fmt.println("\nCommands:")
        fmt.println("  run <dir>     Run a game project")
        fmt.println("  new <name>    Create a new game project")
        fmt.println("  build <dir>   Build standalone executable")
        return
    }

    cmd := os.args[1]
    path := os.args[2]

    switch cmd {
    case "run":
        engine.run_project(path)
    case "new":
        engine.create_project(path)
    case "build":
        engine.build_project(path)
    case:
        fmt.println("Unknown command:", cmd)
    }
}
