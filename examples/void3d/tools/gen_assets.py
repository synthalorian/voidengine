#!/usr/bin/env python3
"""Generate void3d demo assets: polished sprites + tangent-space normal maps.

Outputs (relative to this script):
  ../assets/crystal.png,  crystal_n.png   - faceted neon crystal (64x64)
  ../assets/orb.png,      orb_n.png       - glowing energy orb (48x48)
  ../assets/rune.png,     rune_n.png      - synthwave rune ring (96x96)
  ../assets/grid.png,     grid_n.png      - neon grid floor tile (64x64)
  ../assets/ship_sheet.png                - copied from the shmup example

Normal map convention: RGB = tangent-space normal (x=right, y=UP in world,
z=out of surface), matching voidengine's gl3d/vk3d TBN frame. Height-derived
normals use: n = normalize(-dh/dx*s, -dh/dy*s, 1) with y increasing DOWN the
image, so a bump's upper slope gets +y (up).

Run: python3 gen_assets.py
Requires: pillow
"""

import math
import os
import shutil

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets")
os.makedirs(OUT, exist_ok=True)

TRANSPARENT = (0, 0, 0, 0)

# synthwave '84 palette
CYAN = (0, 220, 255)
CYAN_HI = (180, 245, 255)
CYAN_LO = (0, 90, 160)
MAGENTA = (255, 60, 200)
MAGENTA_HI = (255, 180, 235)
MAGENTA_LO = (120, 10, 90)
PURPLE = (140, 60, 255)
GRID_LINE = (200, 80, 255)
GRID_BG = (16, 6, 36)
ORANGE = (255, 170, 60)


# ----------------------------------------------------------------------------
# height -> tangent-space normal map
# ----------------------------------------------------------------------------

def normals_from_height(height: list, w: int, h: int, strength: float = 2.0) -> Image.Image:
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        ym = max(y - 1, 0)
        yp = min(y + 1, h - 1)
        for x in range(w):
            xm = max(x - 1, 0)
            xp = min(x + 1, w - 1)
            dhx = (height[y * w + xp] - height[y * w + xm]) * strength
            dhy = (height[yp * w + x] - height[ym * w + x]) * strength
            nx, ny, nz = -dhx, -dhy, 1.0
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            r = int((nx / length * 0.5 + 0.5) * 255)
            g = int((ny / length * 0.5 + 0.5) * 255)
            b = int((nz / length * 0.5 + 0.5) * 255)
            px[x, y] = (r, g, b)
    return img


def save(diffuse: Image.Image, normal: Image.Image, name: str) -> None:
    diffuse.save(os.path.join(OUT, f"{name}.png"))
    normal.save(os.path.join(OUT, f"{name}_n.png"))
    print(f"  {name}.png + {name}_n.png")


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_rgb(a, b, t):
    return tuple(int(lerp(a[i], b[i], t)) for i in range(3))


# ----------------------------------------------------------------------------
# crystal: faceted gem, vertical, pointed top/bottom
# ----------------------------------------------------------------------------

def gen_crystal() -> None:
    w = h = 64
    img = Image.new("RGBA", (w, h), TRANSPARENT)
    draw = ImageDraw.Draw(img)

    # silhouette: hexagonal crystal point-up
    cx = 32
    top, bot = 3, 61
    shoulder = 22   # y where crystal is widest
    half_w = 14

    left_top = (cx - half_w, shoulder)
    right_top = (cx + half_w, shoulder)
    left_bot = (cx - half_w + 4, 44)
    right_bot = (cx + half_w - 4, 44)

    # facets: (polygon, shade 0..1) — brighter toward upper-left light
    facets = [
        ([(cx, top), left_top, (cx, shoulder)], 0.95),              # top-left face
        ([(cx, top), (cx, shoulder), right_top], 0.70),             # top-right face
        ([left_top, (cx - 6, 42), (cx, shoulder)], 0.80),           # mid-left
        ([right_top, (cx, shoulder), (cx + 6, 42)], 0.55),          # mid-right
        ([(cx - 6, 42), (cx + 6, 42), (cx, shoulder)], 0.88),       # center band
        ([(cx - 6, 42), left_bot, (cx, bot), (cx + 4, 46)], 0.62),  # lower-left
        ([(cx + 6, 42), (cx + 4, 46), (cx, bot), right_bot], 0.42), # lower-right
    ]
    for poly, shade in facets:
        draw.polygon(poly, fill=lerp_rgb(CYAN_LO, CYAN_HI, shade) + (255,))

    # edge highlights
    draw.line([(cx, top), left_top, left_bot, (cx, bot), right_bot, right_top, (cx, top)],
              fill=CYAN_HI + (255,), width=1)
    draw.line([(cx, top), (cx, shoulder)], fill=CYAN_HI + (200,), width=1)

    # sparkle
    draw.point([(cx - 4, 18), (cx - 3, 18), (cx - 4, 17), (cx - 4, 19)], fill=(255, 255, 255, 255))

    # height: pyramid-ish falloff from silhouette center + per-facet bevel
    height = [0.0] * (w * h)
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    md.polygon([(cx, top), right_top, right_bot, (cx, bot), left_bot, left_top], fill=255)
    mask_blur = mask.filter(ImageFilter.GaussianBlur(3))
    mpx = mask_blur.load()
    for y in range(h):
        for x in range(w):
            height[y * w + x] = mpx[x, y] / 255.0
    save(img, normals_from_height(height, w, h, 3.0), "crystal")


# ----------------------------------------------------------------------------
# orb: glowing energy sphere — true hemisphere normals
# ----------------------------------------------------------------------------

def gen_orb() -> None:
    w = h = 48
    img = Image.new("RGBA", (w, h), TRANSPARENT)
    px = img.load()
    height = [0.0] * (w * h)
    cx = cy = 23.5
    r_out = 22.0
    for y in range(h):
        for x in range(w):
            dx, dy = x - cx, y - cy
            d = math.sqrt(dx * dx + dy * dy)
            if d > r_out:
                continue
            t = d / r_out
            # hot core -> rim
            if t < 0.35:
                col = lerp_rgb((255, 255, 255), MAGENTA_HI, t / 0.35)
            elif t < 0.8:
                col = lerp_rgb(MAGENTA_HI, MAGENTA, (t - 0.35) / 0.45)
            else:
                col = lerp_rgb(MAGENTA, MAGENTA_LO, (t - 0.8) / 0.2)
            # rim darkening for sphere shading
            shade = 1.0 - 0.35 * t * t
            col = tuple(int(c * shade) for c in col)
            alpha = 255 if t < 0.97 else int(255 * (1.0 - (t - 0.97) / 0.03))
            px[x, y] = col + (alpha,)
            # hemisphere height (z of unit sphere)
            height[y * w + x] = math.sqrt(max(0.0, 1.0 - t * t))
    save(img, normals_from_height(height, w, h, 2.0), "orb")


# ----------------------------------------------------------------------------
# rune: neon ring with glyphs — embossed normals from blurred mask
# ----------------------------------------------------------------------------

def gen_rune() -> None:
    w = h = 96
    img = Image.new("RGBA", (w, h), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    c = 47.5

    # outer + inner rings
    draw.ellipse([6, 6, 89, 89], outline=MAGENTA + (255,), width=3)
    draw.ellipse([12, 12, 83, 83], outline=PURPLE + (220,), width=1)
    draw.ellipse([30, 30, 65, 65], outline=CYAN + (255,), width=2)

    # radial ticks
    for i in range(12):
        a = i * math.tau / 12
        r1, r2 = 34, 40
        x1, y1 = c + r1 * math.cos(a), c + r1 * math.sin(a)
        x2, y2 = c + r2 * math.cos(a), c + r2 * math.sin(a)
        col = CYAN_HI if i % 3 == 0 else CYAN
        draw.line([(x1, y1), (x2, y2)], fill=col + (255,), width=2)

    # rune glyphs: angular strokes on the ring (8 glyphs)
    for i in range(8):
        a = (i + 0.5) * math.tau / 8
        gx, gy = c + 26 * math.cos(a), c + 26 * math.sin(a)
        # tiny angular glyph (zig-zag) oriented radially
        ux, uy = math.cos(a), math.sin(a)      # radial
        vx, vy = -uy, ux                        # tangential
        p0 = (gx - 3 * vx - 2 * ux, gy - 3 * vy - 2 * uy)
        p1 = (gx + 3 * vx, gy + 3 * vy)
        p2 = (gx - 3 * vx + 2 * ux, gy - 3 * vy + 2 * uy)
        draw.line([p0, p1, p2], fill=MAGENTA_HI + (255,), width=2)

    # center diamond
    draw.polygon([(c, 38), (57, c), (c, 57), (38, c)], outline=CYAN_HI + (255,), width=2)

    # height from blurred luminance mask (emboss)
    mask = img.convert("L").filter(ImageFilter.GaussianBlur(2))
    mpx = mask.load()
    height = [mpx[x, y] / 255.0 for y in range(h) for x in range(w)]
    save(img, normals_from_height(height, w, h, 2.5), "rune")


# ----------------------------------------------------------------------------
# grid: neon floor tile (tileable!) with beveled line normals
# ----------------------------------------------------------------------------

def gen_grid() -> None:
    w = h = 64
    img = Image.new("RGBA", (w, h), GRID_BG + (255,))
    draw = ImageDraw.Draw(img)

    # subtle vertical glow gradient
    px = img.load()
    for y in range(h):
        t = y / h
        col = lerp_rgb((10, 4, 26), (30, 10, 56), t)
        for x in range(w):
            px[x, y] = col + (255,)

    # grid lines: bright core + soft glow, drawn wrapped for tileability
    for off in (0, 32):  # half-tile spacing -> fine grid
        for width, col, alpha in ((5, GRID_LINE, 60), (3, GRID_LINE, 140), (1, (255, 200, 255), 255)):
            draw.line([(off, 0), (off, h)], fill=col + (alpha,), width=width)
            draw.line([(0, off), (w, off)], fill=col + (alpha,), width=width)

    # glow dots at intersections
    for ox in (0, 32):
        for oy in (0, 32):
            draw.ellipse([ox - 2, oy - 2, ox + 2, oy + 2], fill=(255, 220, 255, 255))

    # height: lines raised — blurred mask of bright lines
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    for off in (0, 32):
        md.line([(off, 0), (off, h)], fill=255, width=3)
        md.line([(0, off), (w, off)], fill=255, width=3)
    mask = mask.filter(ImageFilter.GaussianBlur(2))
    mpx = mask.load()
    height = [mpx[x, y] / 255.0 for y in range(h) for x in range(w)]
    save(img, normals_from_height(height, w, h, 2.0), "grid")


# ----------------------------------------------------------------------------
# ship sheet: copy from shmup for the animated billboard
# ----------------------------------------------------------------------------

def copy_ship() -> None:
    src = os.path.join(os.path.dirname(__file__), "..", "..", "shmup", "assets", "ship_sheet.png")
    dst = os.path.join(OUT, "ship_sheet.png")
    if os.path.exists(src):
        shutil.copyfile(src, dst)
        print("  ship_sheet.png (copied from shmup)")
    else:
        print("  WARNING: shmup ship_sheet.png not found, skipped")


if __name__ == "__main__":
    print("generating void3d assets...")
    gen_crystal()
    gen_orb()
    gen_rune()
    gen_grid()
    copy_ship()
    print("done ->", os.path.abspath(OUT))
