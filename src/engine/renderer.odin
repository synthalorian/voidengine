package engine

import "core:fmt"
import "core:strings"
import "core:os"
import "core:time"
import SDL "vendor:sdl2"
import SDL_Image "vendor:sdl2/image"

// Window and renderer are owned by engine.odin, accessed here via globals.
window:   ^SDL.Window
renderer: ^SDL.Renderer

// Sprite texture cache: id -> texture
Sprite_Entry :: struct {
	texture: ^SDL.Texture,
	w, h:    f32,
	path:    string,
	mtime:   time.Time,     // For hot-reload tracking
}

sprites: [dynamic]Sprite_Entry

// --- Renderer lifecycle (called from engine.odin) ---

renderer_init :: proc(w, h: i32, title: cstring) -> bool {
	if SDL.Init(SDL.INIT_VIDEO | SDL.INIT_EVENTS) != 0 {
		fmt.println("[RENDERER] SDL_Init failed:", SDL.GetError())
		return false
	}

	if SDL_Image.Init(SDL_Image.INIT_PNG) != SDL_Image.INIT_PNG {
		fmt.println("[RENDERER] SDL_image init failed:", SDL.GetError())
		return false
	}

	window = SDL.CreateWindow(
		title,
		SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED,
		i32(w), i32(h),
		SDL.WINDOW_SHOWN | SDL.WINDOW_RESIZABLE,
	)
	if window == nil {
		fmt.println("[RENDERER] CreateWindow failed:", SDL.GetError())
		return false
	}

	renderer = SDL.CreateRenderer(window, -1, SDL.RENDERER_ACCELERATED | SDL.RENDERER_PRESENTVSYNC)
	if renderer == nil {
		fmt.println("[RENDERER] CreateRenderer failed:", SDL.GetError())
		return false
	}

	return true
}

renderer_shutdown :: proc() {
	for entry in sprites {
		if entry.texture != nil {
			SDL.DestroyTexture(entry.texture)
		}
		delete(entry.path)
	}
	delete(sprites)

	// Also clean up atlases and fonts
	atlases_shutdown()
	font_shutdown()

	if renderer != nil {
		SDL.DestroyRenderer(renderer)
		renderer = nil
	}
	if window != nil {
		SDL.DestroyWindow(window)
		window = nil
	}
	SDL_Image.Quit()
	SDL.Quit()
}

// --- Drawing API ---

clear :: proc(r, g, b: f32) {
	if renderer == nil { return }
	SDL.SetRenderDrawColor(renderer, u8(r * 255), u8(g * 255), u8(b * 255), 255)
	SDL.RenderClear(renderer)
}

present :: proc() {
	if renderer == nil { return }
	SDL.RenderPresent(renderer)
}

draw_rect :: proc(x, y, w, h: f32, r, g, b: f32) {
	if renderer == nil { return }
	SDL.SetRenderDrawColor(renderer, u8(r * 255), u8(g * 255), u8(b * 255), 255)
	rect := SDL.FRect{ x = x, y = y, w = w, h = h }
	SDL.RenderFillRectF(renderer, &rect)
	renderer_increment_draw_calls()
}

load_sprite :: proc(path: string) -> int {
	if renderer == nil { return -1 }

	cstr := strings.clone_to_cstring(path)
	defer delete(cstr)

	texture := SDL_Image.LoadTexture(renderer, cstr)
	if texture == nil {
		fmt.println("[RENDERER] Failed to load sprite:", path, "-", SDL.GetError())
		return -1
	}

	tw, th: i32
	SDL.QueryTexture(texture, nil, nil, &tw, &th)

	// Get file modification time for hot-reload
	mtime := get_file_mtime(path)

	id := len(sprites)
	append(&sprites, Sprite_Entry{
		texture = texture,
		w = f32(tw),
		h = f32(th),
		path    = strings.clone(path),
		mtime   = mtime,
	})
	return id
}

draw_sprite :: proc(x, y: f32, sprite_id: int) {
	if renderer == nil { return }
	if sprite_id < 0 || sprite_id >= len(sprites) { return }

	entry := sprites[sprite_id]
	dst := SDL.FRect{
		x = x,
		y = y,
		w = entry.w,
		h = entry.h,
	}
	SDL.RenderCopyF(renderer, entry.texture, nil, &dst)
	renderer_increment_draw_calls()
}

// --- Hot-reload for sprites ---

get_file_mtime :: proc(path: string) -> time.Time {
	f, err := os.open(path)
	if err != os.ERROR_NONE {
		return time.Time{}
	}
	defer os.close(f)

	stat, stat_err := os.fstat(f, context.temp_allocator)
	if stat_err != os.ERROR_NONE {
		return time.Time{}
	}

	return stat.modification_time
}

reload_sprite :: proc(sprite_id: int) {
	if sprite_id < 0 || sprite_id >= len(sprites) { return }

	entry := &sprites[sprite_id]
	if entry.texture != nil {
		SDL.DestroyTexture(entry.texture)
	}

	cstr := strings.clone_to_cstring(entry.path)
	defer delete(cstr)

	texture := SDL_Image.LoadTexture(renderer, cstr)
	if texture == nil {
		fmt.println("[RENDERER] Hot-reload failed for sprite:", entry.path)
		return
	}

	tw, th: i32
	SDL.QueryTexture(texture, nil, nil, &tw, &th)

	entry.texture = texture
	entry.w = f32(tw)
	entry.h = f32(th)
	entry.mtime = get_file_mtime(entry.path)

	fmt.println("[RENDERER] Hot-reloaded sprite:", entry.path)
}

check_sprite_reload :: proc() {
	for i in 0..<len(sprites) {
		entry := &sprites[i]
		current_mtime := get_file_mtime(entry.path)
		if current_mtime._nsec > entry.mtime._nsec {
			reload_sprite(i)
		}
	}
}
