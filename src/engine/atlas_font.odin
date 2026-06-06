package engine

import "core:fmt"
import "core:strings"
import SDL "vendor:sdl2"
import SDL_Image "vendor:sdl2/image"
import SDL_TTF "vendor:sdl2/ttf"

// --- Font system ---

Font_Entry :: struct {
	font: ^SDL_TTF.Font,
	path: string,
	size: i32,
}

fonts: [dynamic]Font_Entry
font_initialized: bool

// --- Atlas system ---

Atlas_Frame :: struct {
	src_x, src_y: f32,    // Position in atlas texture
	src_w, src_h: f32,    // Size in atlas texture
}

Atlas_Entry :: struct {
	texture: ^SDL.Texture,
	w, h:    f32,
	frames:  [dynamic]Atlas_Frame,
}

atlases: [dynamic]Atlas_Entry

// --- Font lifecycle ---

font_init :: proc() -> bool {
	if SDL_TTF.Init() != 0 {
		fmt.println("[RENDERER] TTF_Init failed:", SDL.GetError())
		return false
	}
	font_initialized = true
	return true
}

font_shutdown :: proc() {
	for entry in fonts {
		if entry.font != nil {
			SDL_TTF.CloseFont(entry.font)
		}
		delete(entry.path)
	}
	delete(fonts)
	SDL_TTF.Quit()
	font_initialized = false
}

// --- Font API ---

load_font :: proc(path: string, size: i32) -> int {
	if !font_initialized { return -1 }

	cstr := strings.clone_to_cstring(path)
	defer delete(cstr)

	font := SDL_TTF.OpenFont(cstr, i32(size))
	if font == nil {
		fmt.println("[RENDERER] Failed to load font:", path, "-", SDL.GetError())
		return -1
	}

	id := len(fonts)
	append(&fonts, Font_Entry{
		font = font,
		path = strings.clone(path),
		size = size,
	})
	return id
}

draw_text :: proc(x, y: f32, text: string, font_id: int = 0, r: f32 = 1.0, g: f32 = 1.0, b: f32 = 1.0) {
	if renderer == nil { return }
	if font_id < 0 || font_id >= len(fonts) { return }

	entry := fonts[font_id]
	if entry.font == nil { return }

	cstr := strings.clone_to_cstring(text)
	defer delete(cstr)

	fg := SDL.Color{ u8(r * 255), u8(g * 255), u8(b * 255), 255 }
	surface := SDL_TTF.RenderUTF8_Blended(entry.font, cstr, fg)
	if surface == nil {
		fmt.println("[RENDERER] Failed to render text:", SDL.GetError())
		return
	}
	defer SDL.FreeSurface(surface)

	texture := SDL.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		fmt.println("[RENDERER] Failed to create text texture:", SDL.GetError())
		return
	}
	defer SDL.DestroyTexture(texture)

	dst := SDL.FRect{
		x = x,
		y = y,
		w = f32(surface.w),
		h = f32(surface.h),
	}
	SDL.RenderCopyF(renderer, texture, nil, &dst)
}

// --- Atlas API ---

load_atlas :: proc(path: string) -> int {
	if renderer == nil { return -1 }

	cstr := strings.clone_to_cstring(path)
	defer delete(cstr)

	// Load the atlas texture (same as loading a sprite)
	texture := SDL_Image.LoadTexture(renderer, cstr)
	if texture == nil {
		fmt.println("[RENDERER] Failed to load atlas:", path, "-", SDL.GetError())
		return -1
	}

	tw, th: i32
	SDL.QueryTexture(texture, nil, nil, &tw, &th)

	id := len(atlases)
	append(&atlases, Atlas_Entry{
		texture = texture,
		w = f32(tw),
		h = f32(th),
		frames = make([dynamic]Atlas_Frame),
	})
	return id
}

add_atlas_frame :: proc(atlas_id: int, src_x, src_y, src_w, src_h: f32) -> int {
	if atlas_id < 0 || atlas_id >= len(atlases) { return -1 }

	frame := Atlas_Frame{
		src_x = src_x,
		src_y = src_y,
		src_w = src_w,
		src_h = src_h,
	}

	frame_id := len(atlases[atlas_id].frames)
	append(&atlases[atlas_id].frames, frame)
	return frame_id
}

draw_atlas_frame :: proc(x, y: f32, atlas_id: int, frame_id: int) {
	if renderer == nil { return }
	if atlas_id < 0 || atlas_id >= len(atlases) { return }

	atlas := atlases[atlas_id]
	if frame_id < 0 || frame_id >= len(atlas.frames) { return }

	frame := atlas.frames[frame_id]
	src := SDL.Rect{
		x = i32(frame.src_x),
		y = i32(frame.src_y),
		w = i32(frame.src_w),
		h = i32(frame.src_h),
	}
	dst := SDL.FRect{
		x = x,
		y = y,
		w = frame.src_w,
		h = frame.src_h,
	}
	SDL.RenderCopyF(renderer, atlas.texture, &src, &dst)
}

// Cleanup function for atlases
atlases_shutdown :: proc() {
	for atlas in atlases {
		if atlas.texture != nil {
			SDL.DestroyTexture(atlas.texture)
		}
		delete(atlas.frames)
	}
	delete(atlases)
}
