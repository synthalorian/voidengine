# VoidEngine Studio

A Tauri v2 + React desktop GUI for building and testing games made with **VoidEngine**.

## What it does

- Automatically discovers VoidEngine projects (looks for `src/core`, `examples`, and `Makefile`)
- One-click **Check**, **Test**, **Build All**, **Clean**
- Per-example **Build Example** and **Run Example** buttons
- Live command output in a built-in terminal panel
- Add any VoidEngine project folder via file picker

## Tech stack

- **Tauri v2** (Rust backend)
- **React + TypeScript + Vite** frontend
- **tauri-plugin-shell** for running `make` / `odin` commands
- **tauri-plugin-dialog** for folder picking

## Development

```bash
cd studio
npm install
npm run tauri:dev
```

This opens the desktop window in dev mode.

## Build release

```bash
cd studio
npm run tauri:build
```

The built bundle will be in `src-tauri/target/release/bundle/`.

## Usage

1. Launch the app
2. It should auto-detect `~/projects/active/voidengine`
3. Select a project in the sidebar
4. Click **Check** / **Test** / **Build All** or pick an example and click **Build Example** / **Run Example**

## Adding a new project

Click **+ Add Project** and select the folder containing your VoidEngine `Makefile` and `src/core/`.

---

*Part of the VoidEngine project.* 🎹🦞🌆
