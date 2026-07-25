package voidengine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import SDL "vendor:sdl2"

// ============================================================================
// Tilemap — grid-based maps with optional tileset rendering and collision
// ============================================================================
// Tiles are stored row-major. Tile id 0 is always "empty" (not rendered,
// not solid). Any id in `solid_ids` participates in collision.

Tilemap :: struct {
    width: i32,          // tiles across
    height: i32,         // tiles down
    tile_size: i32,      // pixels per tile (square)
    tiles: []i32,        // row-major tile ids
    solid_ids: map[i32]bool,
}

tilemap_create :: proc(width, height, tile_size: i32, allocator := context.allocator) -> ^Tilemap {
    tm := new(Tilemap, allocator)
    tm.width = width
    tm.height = height
    tm.tile_size = tile_size
    tm.tiles = make([]i32, width * height, allocator)
    tm.solid_ids = make(map[i32]bool, allocator)
    return tm
}

tilemap_destroy :: proc(tm: ^Tilemap) {
    if tm == nil {
        return
    }
    delete(tm.tiles)
    delete(tm.solid_ids)
    free(tm)
}

tilemap_in_bounds :: proc(tm: ^Tilemap, tx, ty: i32) -> bool {
    return tx >= 0 && tx < tm.width && ty >= 0 && ty < tm.height
}

tilemap_get :: proc(tm: ^Tilemap, tx, ty: i32) -> i32 {
    if !tilemap_in_bounds(tm, tx, ty) {
        return 0
    }
    return tm.tiles[ty * tm.width + tx]
}

tilemap_set :: proc(tm: ^Tilemap, tx, ty, id: i32) {
    if tilemap_in_bounds(tm, tx, ty) {
        tm.tiles[ty * tm.width + tx] = id
    }
}

// Mark a tile id as solid (collidable). Tile id 0 is never solid.
tilemap_set_solid :: proc(tm: ^Tilemap, id: i32, solid: bool = true) {
    if id == 0 {
        return
    }
    if solid {
        tm.solid_ids[id] = true
    } else {
        delete_key(&tm.solid_ids, id)
    }
}

tilemap_is_solid :: proc(tm: ^Tilemap, tx, ty: i32) -> bool {
    id := tilemap_get(tm, tx, ty)
    return id != 0 && tm.solid_ids[id]
}

// World-space (pixel) solid check.
tilemap_is_solid_at_world :: proc(tm: ^Tilemap, x, y: f32) -> bool {
    tx := i32(x) / tm.tile_size
    ty := i32(y) / tm.tile_size
    return tilemap_is_solid(tm, tx, ty)
}

// ============================================================================
// CSV Loading
// ============================================================================
// Format: rows separated by newlines, tile ids separated by commas.
// Whitespace is trimmed; empty trailing lines are ignored.
// Example:
//   1,1,1,1
//   1,0,0,1
//   1,1,1,1

tilemap_load_csv :: proc(path: string, tile_size: i32, allocator := context.allocator) -> ^Tilemap {
    data, err := os.read_entire_file_from_path(path, context.temp_allocator)
    if err != nil {
        fmt.eprintln("tilemap_load_csv: failed to read", path)
        return nil
    }

    text := string(data)
    lines := strings.split(text, "\n", context.temp_allocator)

    // Count non-empty rows and determine width from the first row
    rows := make([dynamic][]string, context.temp_allocator)
    width: i32 = 0
    for line in lines {
        trimmed := strings.trim_space(line)
        if trimmed == "" {
            continue
        }
        cells := strings.split(trimmed, ",", context.temp_allocator)
        if width == 0 {
            width = i32(len(cells))
        }
        append(&rows, cells)
    }

    if len(rows) == 0 || width == 0 {
        fmt.eprintln("tilemap_load_csv: no tile data in", path)
        return nil
    }

    tm := tilemap_create(width, i32(len(rows)), tile_size, allocator)

    for cells, y in rows {
        for cell, x in cells {
            value, parse_ok := strconv.parse_int(strings.trim_space(cell))
            if parse_ok && i32(x) < width {
                tm.tiles[y * int(width) + x] = i32(value)
            }
        }
    }

    return tm
}

// ============================================================================
// Collision
// ============================================================================

// tilemap_collide checks an entity's AABB (Transform + Collider) against
// all solid tiles it overlaps. Returns true on any overlap.
tilemap_collide :: proc(entity: ^Entity, tm: ^Tilemap) -> bool {
    transform := entity_get_component(entity, Transform)
    collider := entity_get_component(entity, Collider)
    if transform == nil || collider == nil || tm == nil {
        return false
    }

    left   := transform.position.x + collider.offset.x - collider.width / 2
    top    := transform.position.y + collider.offset.y - collider.height / 2
    right  := left + collider.width
    bottom := top + collider.height

    tx0 := max(i32(left) / tm.tile_size, 0)
    ty0 := max(i32(top) / tm.tile_size, 0)
    tx1 := min(i32(right) / tm.tile_size, tm.width - 1)
    ty1 := min(i32(bottom) / tm.tile_size, tm.height - 1)

    for ty in ty0..=ty1 {
        for tx in tx0..=tx1 {
            if tilemap_is_solid(tm, tx, ty) {
                return true
            }
        }
    }
    return false
}

// ============================================================================
// Rendering
// ============================================================================

// tilemap_render draws the map. If tileset is non-nil, tiles are sampled
// from the sheet (row-major, `columns` across, tile_size cells) with
// RenderCopy. Tile id 0 is skipped. When tileset is nil, solid tiles are
// drawn as debug rects.
tilemap_render :: proc(renderer: ^SDL.Renderer, tm: ^Tilemap,
    tileset: ^SDL.Texture = nil, columns: i32 = 1,
    offset_x: i32 = 0, offset_y: i32 = 0) {

    for ty in 0..<tm.height {
        for tx in 0..<tm.width {
            id := tilemap_get(tm, tx, ty)
            if id == 0 {
                continue
            }
            dst := SDL.Rect{
                x = offset_x + tx * tm.tile_size,
                y = offset_y + ty * tm.tile_size,
                w = tm.tile_size,
                h = tm.tile_size,
            }
            if tileset != nil {
                frame := id - 1 // tile ids are 1-based into the sheet
                col := frame % max(columns, 1)
                row := frame / max(columns, 1)
                src := SDL.Rect{
                    x = col * tm.tile_size,
                    y = row * tm.tile_size,
                    w = tm.tile_size,
                    h = tm.tile_size,
                }
                SDL.RenderCopy(renderer, tileset, &src, &dst)
            } else {
                // Debug: solid tiles magenta, others dim gray
                if tm.solid_ids[id] {
                    SDL.SetRenderDrawColor(renderer, 255, 0, 255, 255)
                } else {
                    SDL.SetRenderDrawColor(renderer, 80, 80, 90, 255)
                }
                SDL.RenderFillRect(renderer, &dst)
            }
        }
    }
}
