#!/usr/bin/env bash
# Install VoidEngine examples as freedesktop apps on KDE Plasma / CachyOS.
# Idempotent — re-run after each rebuild.
set -euo pipefail

REPO="$HOME/Projects/active/voidengine"
ICON_SRC="$REPO/studio/src-tauri/icons/icon.png"

install_app() {
    local app_id="$1" app_name="$2" comment="$3" binary="$REPO/$4"
    local prefix="$HOME/.local/share/$app_id"

    [[ -x "$binary" ]] || { echo "error: $binary not found — run 'make $4' first" >&2; return 1; }

    echo "Installing $app_name to $prefix ..."
    mkdir -p "$prefix"
    cp -f "$binary" "$prefix/$4"
    rm -rf "$prefix/assets"
    cp -r "$REPO/assets" "$prefix/"

    install -Dm644 "$ICON_SRC" \
        "$HOME/.local/share/icons/hicolor/512x512/apps/$app_id.png"

    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/$app_id.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$app_name
Comment=$comment
Exec="$prefix/$4"
Path=$prefix
Icon=$app_id
Terminal=false
Categories=Game;
Keywords=game;engine;voidengine;
EOF

    desktop-file-validate "$HOME/.local/share/applications/$app_id.desktop"
}

install_app "voidengine-shmup" "VoidEngine Shmup" \
    "VoidEngine 2D space shooter (Odin + SDL2)" "shmup"
install_app "voidengine-demo" "VoidEngine Demo" \
    "VoidEngine 2D engine sandbox demo (Odin + SDL2)" "demo"

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental 2>/dev/null || true

echo "Done. Both entries should appear in the Application Launcher under Games."
