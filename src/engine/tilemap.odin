package engine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:encoding/json"
import "core:strconv"
import SDL "vendor:sdl2"

// --- Tilemap ---

Tileset :: struct {
	first_gid:     int,
	image_path:    string,
	tile_width:    int,
	tile_height:   int,
	tile_count:    int,
	columns:       int,
	sprite_id:     int,     // Loaded sprite ID for the tileset image
}

Layer :: struct {
	name:        string,
	width:       int,
	height:      int,
	data:        []int,   // Tile GIDs
	visible:     bool,
	opacity:     f32,
}

Tilemap :: struct {
	width:         int,     // Map width in tiles
	height:        int,     // Map height in tiles
	tile_width:    int,     // Tile width in pixels
	tile_height:   int,     // Tile height in pixels
	tilesets:      [dynamic]Tileset,
	layers:        [dynamic]Layer,
	properties:    map[string]string,
}

// --- Loading ---

tilemap_load :: proc(path: string) -> (Tilemap, bool) {
	tilemap := Tilemap{}

	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != os.ERROR_NONE {
		log_error("Failed to read tilemap: %s", path)
		return tilemap, false
	}
	defer delete(data)

	// Parse JSON
	raw_json, parse_err := json.parse(data, json.DEFAULT_SPECIFICATION)
	if parse_err != nil {
		log_error("Failed to parse tilemap JSON: %s - %v", path, parse_err)
		return tilemap, false
	}
	defer json.destroy_value(raw_json)

	root, ok := raw_json.(json.Object)
	if !ok {
		log_error("Tilemap JSON root is not an object: %s", path)
		return tilemap, false
	}

	// Map dimensions
	if w, ok := root["width"]; ok {
		if w_f, ok := w.(json.Integer); ok {
			tilemap.width = int(w_f)
		}
	}
	if h, ok := root["height"]; ok {
		if h_f, ok := h.(json.Integer); ok {
			tilemap.height = int(h_f)
		}
	}
	if tw, ok := root["tilewidth"]; ok {
		if tw_f, ok := tw.(json.Integer); ok {
			tilemap.tile_width = int(tw_f)
		}
	}
	if th, ok := root["tileheight"]; ok {
		if th_f, ok := th.(json.Integer); ok {
			tilemap.tile_height = int(th_f)
		}
	}

	// Parse tilesets
	if tilesets_val, ok := root["tilesets"]; ok {
		if tilesets_arr, ok := tilesets_val.(json.Array); ok {
			for ts_val in tilesets_arr {
				if ts_obj, ok := ts_val.(json.Object); ok {
					tileset := Tileset{}
					if fg, ok := ts_obj["firstgid"]; ok {
						if fg_i, ok := fg.(json.Integer); ok {
							tileset.first_gid = int(fg_i)
						}
					}
					if img, ok := ts_obj["image"]; ok {
						if img_s, ok := img.(json.String); ok {
							// Tiled stores paths relative to the map file
							// We need to resolve relative to the project
							tileset.image_path = fmt.tprintf("%s", img_s)
						}
					}
					if tw, ok := ts_obj["tilewidth"]; ok {
						if tw_i, ok := tw.(json.Integer); ok {
							tileset.tile_width = int(tw_i)
						}
					}
					if th, ok := ts_obj["tileheight"]; ok {
						if th_i, ok := th.(json.Integer); ok {
							tileset.tile_height = int(th_i)
						}
					}
					if tc, ok := ts_obj["tilecount"]; ok {
						if tc_i, ok := tc.(json.Integer); ok {
							tileset.tile_count = int(tc_i)
						}
					}
					if col, ok := ts_obj["columns"]; ok {
						if col_i, ok := col.(json.Integer); ok {
							tileset.columns = int(col_i)
						}
					}

					// Try to load the tileset image
					if tileset.image_path != "" {
						tileset.sprite_id = load_sprite(tileset.image_path)
					}

					append(&tilemap.tilesets, tileset)
				}
			}
		}
	}

	// Parse layers
	if layers_val, ok := root["layers"]; ok {
		if layers_arr, ok := layers_val.(json.Array); ok {
			for layer_val in layers_arr {
				if layer_obj, ok := layer_val.(json.Object); ok {
					layer := Layer{}
					if name, ok := layer_obj["name"]; ok {
						if name_s, ok := name.(json.String); ok {
							layer.name = fmt.tprintf("%s", name_s)
						}
					}
					if w, ok := layer_obj["width"]; ok {
						if w_i, ok := w.(json.Integer); ok {
							layer.width = int(w_i)
						}
					}
					if h, ok := layer_obj["height"]; ok {
						if h_i, ok := h.(json.Integer); ok {
							layer.height = int(h_i)
						}
					}
					if data, ok := layer_obj["data"]; ok {
						if data_arr, ok := data.(json.Array); ok {
							layer.data = make([]int, len(data_arr))
							for val, i in data_arr {
								if v_i, ok := val.(json.Integer); ok {
									layer.data[i] = int(v_i)
								}
							}
						}
					}
					if vis, ok := layer_obj["visible"]; ok {
						if vis_b, ok := vis.(json.Boolean); ok {
							layer.visible = bool(vis_b)
						}
					}
					if op, ok := layer_obj["opacity"]; ok {
						if op_f, ok := op.(json.Float); ok {
							layer.opacity = f32(op_f)
						}
					}

					append(&tilemap.layers, layer)
				}
			}
		}
	}

	log_info("Loaded tilemap: %s (%dx%d, %d layers, %d tilesets)",
		path, tilemap.width, tilemap.height, len(tilemap.layers), len(tilemap.tilesets))
	return tilemap, true
}

tilemap_destroy :: proc(tilemap: ^Tilemap) {
	for layer in tilemap.layers {
		delete(layer.data)
		delete(layer.name)
	}
	delete(tilemap.layers)
	for tileset in tilemap.tilesets {
		delete(tileset.image_path)
	}
	delete(tilemap.tilesets)
}

// --- Rendering ---

tilemap_draw :: proc(tilemap: ^Tilemap) {
	for layer in tilemap.layers {
		if !layer.visible { continue }

		for y in 0..<layer.height {
			for x in 0..<layer.width {
				idx := y * layer.width + x
				if idx >= len(layer.data) { continue }

				gid := layer.data[idx]
				if gid == 0 { continue } // Empty tile

				// Find which tileset this GID belongs to
				tileset_idx := -1
				for ts, i in tilemap.tilesets {
					if gid >= ts.first_gid && gid < ts.first_gid + ts.tile_count {
						tileset_idx = i
						break
					}
				}
				if tileset_idx < 0 { continue }

				tileset := &tilemap.tilesets[tileset_idx]
				if tileset.sprite_id < 0 { continue }

				// Calculate tile index within tileset
				tile_idx := gid - tileset.first_gid
				tile_x := tile_idx % tileset.columns
				tile_y := tile_idx / tileset.columns

				// Calculate source rectangle
				src_x := f32(tile_x * tileset.tile_width)
				src_y := f32(tile_y * tileset.tile_height)

				// Calculate destination position
				dst_x := f32(x * tilemap.tile_width)
				dst_y := f32(y * tilemap.tile_height)

				// Draw the tile
				draw_tile(tileset.sprite_id, src_x, src_y, f32(tileset.tile_width), f32(tileset.tile_height), dst_x, dst_y)
			}
		}
	}
}

// Draw a tile from a sprite using a source rectangle
draw_tile :: proc(sprite_id: int, src_x, src_y, src_w, src_h, dst_x, dst_y: f32) {
	if renderer == nil { return }
	if sprite_id < 0 || sprite_id >= len(sprites) { return }

	entry := sprites[sprite_id]
	src: SDL.Rect = {
		x = i32(src_x),
		y = i32(src_y),
		w = i32(src_w),
		h = i32(src_h),
	}
	dst: SDL.FRect = {
		x = dst_x,
		y = dst_y,
		w = src_w,
		h = src_h,
	}
	SDL.RenderCopyF(renderer, entry.texture, &src, &dst)
	renderer_increment_draw_calls()
}

// --- Camera-aware rendering ---

tilemap_draw_camera :: proc(tilemap: ^Tilemap) {
	// Calculate visible tile range
	viewport := camera_get_viewport()
	start_x := int(viewport.x / f32(tilemap.tile_width))
	start_y := int(viewport.y / f32(tilemap.tile_height))
	end_x := int((viewport.x + viewport.w) / f32(tilemap.tile_width)) + 1
	end_y := int((viewport.y + viewport.h) / f32(tilemap.tile_height)) + 1

	start_x = clamp_int(start_x, 0, tilemap.width - 1)
	start_y = clamp_int(start_y, 0, tilemap.height - 1)
	end_x = clamp_int(end_x, 0, tilemap.width)
	end_y = clamp_int(end_y, 0, tilemap.height)

	for layer in tilemap.layers {
		if !layer.visible { continue }

		for y in start_y..<end_y {
			for x in start_x..<end_x {
				idx := y * layer.width + x
				if idx >= len(layer.data) { continue }

				gid := layer.data[idx]
				if gid == 0 { continue }

				tileset_idx := -1
				for ts, i in tilemap.tilesets {
					if gid >= ts.first_gid && gid < ts.first_gid + ts.tile_count {
						tileset_idx = i
						break
					}
				}
				if tileset_idx < 0 { continue }

				tileset := &tilemap.tilesets[tileset_idx]
				if tileset.sprite_id < 0 { continue }

				tile_idx := gid - tileset.first_gid
				tile_x := tile_idx % tileset.columns
				tile_y := tile_idx / tileset.columns

				src_x := f32(tile_x * tileset.tile_width)
				src_y := f32(tile_y * tileset.tile_height)

				// World position
				world_x := f32(x * tilemap.tile_width)
				world_y := f32(y * tilemap.tile_height)

				// Transform through camera
				screen_pos := camera_world_to_screen(Vec2{world_x, world_y})
				size_w := f32(tilemap.tile_width) * main_camera.zoom
				size_h := f32(tilemap.tile_height) * main_camera.zoom

			src: SDL.Rect = {
				x = i32(src_x),
				y = i32(src_y),
				w = i32(tileset.tile_width),
				h = i32(tileset.tile_height),
			}
			dst: SDL.FRect = {
				x = screen_pos.x,
				y = screen_pos.y,
				w = size_w,
				h = size_h,
			}
			SDL.RenderCopyF(renderer, sprites[tileset.sprite_id].texture, &src, &dst)
				renderer_increment_draw_calls()
			}
		}
	}
}

// --- Collision helpers ---

// Get tile ID at world position
tilemap_get_tile_at :: proc(tilemap: ^Tilemap, layer_idx: int, world_x, world_y: f32) -> int {
	if layer_idx < 0 || layer_idx >= len(tilemap.layers) {
		return 0
	}
	layer := &tilemap.layers[layer_idx]

	tile_x := int(world_x / f32(tilemap.tile_width))
	tile_y := int(world_y / f32(tilemap.tile_height))

	if tile_x < 0 || tile_x >= layer.width || tile_y < 0 || tile_y >= layer.height {
		return 0
	}

	idx := tile_y * layer.width + tile_x
	if idx >= len(layer.data) {
		return 0
	}

	return layer.data[idx]
}

// Check if a world rect collides with any solid tiles
tilemap_check_collision :: proc(tilemap: ^Tilemap, layer_idx: int, world_rect: Rect) -> (bool, Vec2) {
	// Get tile range that the rect covers
	start_x := int(world_rect.x / f32(tilemap.tile_width))
	start_y := int(world_rect.y / f32(tilemap.tile_height))
	end_x := int((world_rect.x + world_rect.w) / f32(tilemap.tile_width))
	end_y := int((world_rect.y + world_rect.h) / f32(tilemap.tile_height))

	start_x = max(start_x, 0)
	start_y = max(start_y, 0)
	end_x = min(end_x, tilemap.width - 1)
	end_y = min(end_y, tilemap.height - 1)

	for y in start_y..=end_y {
		for x in start_x..=end_x {
			gid := tilemap_get_tile_at(tilemap, layer_idx, f32(x * tilemap.tile_width), f32(y * tilemap.tile_height))
			if gid != 0 {
				return true, Vec2{f32(x * tilemap.tile_width), f32(y * tilemap.tile_height)}
			}
		}
	}

	return false, Vec2{}
}
