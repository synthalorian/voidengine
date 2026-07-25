#!/usr/bin/env python3
"""Generate synthwave sprite sheets for the shmup example.

Outputs (relative to this script's parent dir):
  ../assets/ship_sheet.png   - 64x32, two 32x32 frames (engine flame flicker)
  ../assets/enemy_sheet.png  - 64x32, two 32x32 frames (core pulse)

Palette: synthwave '84 - deep purple bg (transparent), electric cyan ship,
magenta/hot-pink enemy, neon accents.

Run: python3 gen_sprites.py
Requires: pillow
"""

from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets")
os.makedirs(OUT, exist_ok=True)

TRANSPARENT = (0, 0, 0, 0)
CYAN = (0, 220, 255, 255)
CYAN_DARK = (0, 120, 180, 255)
WHITE = (240, 250, 255, 255)
FLAME_A = (255, 200, 60, 255)
FLAME_B = (255, 120, 220, 255)
MAGENTA = (255, 60, 200, 255)
MAGENTA_DARK = (150, 20, 120, 255)
RED_CORE = (255, 80, 80, 255)


def draw_player_ship(draw: ImageDraw.Draw, ox: int, flame: bool) -> None:
    """32x32 player ship, nose pointing up. ox = frame x offset."""
    # Main fuselage (triangle)
    draw.polygon([
        (ox + 16, 2),    # nose
        (ox + 6, 26),    # left wing root
        (ox + 26, 26),   # right wing root
    ], fill=CYAN, outline=WHITE)
    # Wings
    draw.polygon([(ox + 6, 26), (ox + 2, 30), (ox + 10, 22)], fill=CYAN_DARK)
    draw.polygon([(ox + 26, 26), (ox + 30, 30), (ox + 22, 22)], fill=CYAN_DARK)
    # Cockpit
    draw.ellipse([ox + 13, 8, ox + 19, 16], fill=WHITE)
    # Engine flame (frame variant)
    if flame:
        draw.polygon([(ox + 12, 27), (ox + 16, 31), (ox + 20, 27)], fill=FLAME_A)
    else:
        draw.polygon([(ox + 13, 27), (ox + 16, 30), (ox + 19, 27)], fill=FLAME_B)


def draw_enemy_ship(draw: ImageDraw.Draw, ox: int, pulse: bool) -> None:
    """32x32 enemy ship, pointing down. ox = frame x offset."""
    # Inverted fuselage
    draw.polygon([
        (ox + 16, 29),   # nose (down)
        (ox + 4, 6),     # left wing
        (ox + 28, 6),    # right wing
    ], fill=MAGENTA, outline=MAGENTA_DARK)
    # Wing tips
    draw.polygon([(ox + 4, 6), (ox + 2, 2), (ox + 9, 8)], fill=MAGENTA_DARK)
    draw.polygon([(ox + 28, 6), (ox + 30, 2), (ox + 23, 8)], fill=MAGENTA_DARK)
    # Core (pulses between frames)
    core = RED_CORE if pulse else (255, 160, 60, 255)
    r = 5 if pulse else 4
    draw.ellipse([ox + 16 - r, 12 - r + 4, ox + 16 + r, 12 + r + 4], fill=core)


def main() -> None:
    # Player sheet: 2 frames side by side
    ship = Image.new("RGBA", (64, 32), TRANSPARENT)
    d = ImageDraw.Draw(ship)
    draw_player_ship(d, 0, flame=True)
    draw_player_ship(d, 32, flame=False)
    ship_path = os.path.join(OUT, "ship_sheet.png")
    ship.save(ship_path)
    print("wrote", ship_path)

    # Enemy sheet: 2 frames side by side
    enemy = Image.new("RGBA", (64, 32), TRANSPARENT)
    d = ImageDraw.Draw(enemy)
    draw_enemy_ship(d, 0, pulse=True)
    draw_enemy_ship(d, 32, pulse=False)
    enemy_path = os.path.join(OUT, "enemy_sheet.png")
    enemy.save(enemy_path)
    print("wrote", enemy_path)


if __name__ == "__main__":
    main()
