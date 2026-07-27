#!/usr/bin/env bash
# Install VoidEngine Studio (Tauri editor GUI) as a freedesktop app.
# Idempotent — re-run after each rebuild (npm run tauri:build -- --no-bundle).
set -euo pipefail

APP_ID="voidengine-studio"
APP_NAME="VoidEngine Studio"
REPO="$HOME/Projects/active/voidengine"
BINARY="$REPO/studio/src-tauri/target/release/voidengine-studio"
ICON_SRC="$REPO/studio/src-tauri/icons/icon.png"
PREFIX="$HOME/.local/share/$APP_ID"

[[ -x "$BINARY" ]] || { echo "error: $BINARY not found — run 'npm run tauri:build -- --no-bundle' in studio/ first" >&2; exit 1; }

echo "Installing $APP_NAME to $PREFIX ..."
mkdir -p "$PREFIX"
cp -f "$BINARY" "$PREFIX/voidengine-studio"

install -Dm644 "$ICON_SRC" \
    "$HOME/.local/share/icons/hicolor/512x512/apps/$APP_ID.png"

mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=VoidEngine editor — build, test, and run engine projects
Exec="$PREFIX/voidengine-studio"
Icon=$APP_ID
Terminal=false
Categories=Development;
Keywords=game;engine;editor;voidengine;
EOF

desktop-file-validate "$HOME/.local/share/applications/$APP_ID.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental 2>/dev/null || true

echo "Done. '$APP_NAME' should appear in the Application Launcher under Development."
