package engine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:encoding/json"
import "core:path/filepath"
import SDL "vendor:sdl2"
import SDL_Image "vendor:sdl2/image"

// --- Asset Pipeline ---
// v0.7.0: Texture atlas packing and audio bank bundling

// Atlas region for tracking sprite positions
Atlas_Region :: struct {
	x, y:      int,
	w, h:      int,
	name:      string,
	rotated:   bool,
}

// Texture atlas: packs multiple sprites into one texture
Texture_Atlas :: struct {
	texture:   ^SDL.Texture,
	width:     int,
	height:    int,
	regions:   map[string]Atlas_Region,
	path:      string,
}

// Audio bank: bundles multiple sounds into one file
Audio_Bank :: struct {
	sounds:    map[string]int,  // name -> sound_id
	path:      string,
}

// Global atlas and bank storage
// v0.7.0: Renamed to avoid conflict with atlas_font.odin
texture_atlases: [dynamic]Texture_Atlas
audio_banks: [dynamic]Audio_Bank

// Initialize asset pipeline
asset_pipeline_init :: proc() {
	texture_atlases = make([dynamic]Texture_Atlas)
	audio_banks = make([dynamic]Audio_Bank)
}

// Shutdown asset pipeline
asset_pipeline_shutdown :: proc() {
	// Clean up atlases
	for atlas in texture_atlases {
		if atlas.texture != nil {
			SDL.DestroyTexture(atlas.texture)
		}
		for name in atlas.regions {
			delete(name)
		}
		delete(atlas.regions)
	}
	delete(texture_atlases)
	
	// Clean up audio banks
	for bank in audio_banks {
		for name in bank.sounds {
			delete(name)
		}
		delete(bank.sounds)
	}
	delete(audio_banks)
}

// --- Texture Atlas Packing ---

// Simple shelf packing algorithm for texture atlas
// Packs images into rows (shelves) of fixed height
Atlas_Pack_Result :: struct {
	success:   bool,
	atlas:     Texture_Atlas,
	unpacked:  [dynamic]string,  // Images that didn't fit
}

// Pack multiple sprite files into a single atlas texture
// sprite_files: map of name -> file_path
atlas_pack :: proc(name: string, sprite_files: map[string]string, max_size: int = 2048) -> Atlas_Pack_Result {
	result := Atlas_Pack_Result{
		success = false,
		unpacked = make([dynamic]string),
	}
	
	if len(sprite_files) == 0 {
		log_warn("No sprites to pack into atlas")
		return result
	}
	
	log_info("Packing %d sprites into atlas '%s'", len(sprite_files), name)
	
	// Load all images and get their dimensions
	Image_Info :: struct {
		path:   string,
		w, h:   int,
		surface: ^SDL.Surface,
	}
	
	images := make([dynamic]Image_Info)
	defer {
		for img in images {
			if img.surface != nil {
				SDL.FreeSurface(img.surface)
			}
		}
		delete(images)
	}
	
	for sprite_name, file_path in sprite_files {
		if !os.exists(file_path) {
			log_warn("Sprite file not found: %s", file_path)
			append(&result.unpacked, sprite_name)
			continue
		}
		
		surface := SDL_Image.Load(strings.clone_to_cstring(file_path))
		if surface == nil {
			log_warn("Failed to load sprite: %s", file_path)
			append(&result.unpacked, sprite_name)
			continue
		}
		
		append(&images, Image_Info{
			path = file_path,
			w = int(surface.w),
			h = int(surface.h),
			surface = surface,
		})
	}
	
	if len(images) == 0 {
		log_warn("No valid images to pack")
		return result
	}
	
	// Simple shelf packing: sort by height, pack into rows
	// Sort images by height (tallest first)
	for i := 0; i < len(images); i += 1 {
		for j := i + 1; j < len(images); j += 1 {
			if images[j].h > images[i].h {
				images[i], images[j] = images[j], images[i]
			}
		}
	}
	
	// Create atlas surface
	atlas_surface := SDL.CreateRGBSurfaceWithFormat(0, i32(max_size), i32(max_size), 32, u32(SDL.PixelFormatEnum.RGBA32))
	if atlas_surface == nil {
		log_error("Failed to create atlas surface")
		return result
	}
	defer SDL.FreeSurface(atlas_surface)
	
	// Pack images using shelf algorithm
	regions := make(map[string]Atlas_Region)
	current_x: int = 0
	current_y: int = 0
	shelf_height: int = 0
	
	for img in images {
		// Check if we need a new shelf
		if current_x + img.w > max_size {
			current_y += shelf_height
			current_x = 0
			shelf_height = 0
		}
		
		// Check if we exceeded max height
		if current_y + img.h > max_size {
			log_warn("Atlas full, couldn't fit: %s", img.path)
			append(&result.unpacked, img.path)
			continue
		}
		
		// Copy image to atlas
		src_rect := SDL.Rect{0, 0, i32(img.w), i32(img.h)}
		dst_rect := SDL.Rect{i32(current_x), i32(current_y), i32(img.w), i32(img.h)}
		SDL.BlitSurface(img.surface, &src_rect, atlas_surface, &dst_rect)
		
		// Store region
		regions[img.path] = Atlas_Region{
			x = current_x,
			y = current_y,
			w = img.w,
			h = img.h,
			name = img.path,
		}
		
		current_x += img.w
		if img.h > shelf_height {
			shelf_height = img.h
		}
	}
	
	// Create texture from surface
	texture := SDL.CreateTextureFromSurface(renderer, atlas_surface)
	if texture == nil {
		log_error("Failed to create atlas texture")
		delete(regions)
		return result
	}
	
	result.success = true
	result.atlas = Texture_Atlas{
		texture = texture,
		width = max_size,
		height = current_y + shelf_height,
		regions = regions,
		path = name,
	}
	
	append(&texture_atlases, result.atlas)
	log_info("Packed atlas '%s': %dx%d with %d regions", name, result.atlas.width, result.atlas.height, len(regions))
	
	return result
}

// Get a region from an atlas by name
atlas_get_region :: proc(atlas_idx: int, name: string) -> (Atlas_Region, bool) {
	if atlas_idx < 0 || atlas_idx >= len(texture_atlases) {
		return Atlas_Region{}, false
	}
	region, ok := texture_atlases[atlas_idx].regions[name]
	return region, ok
}

// Draw a sprite from an atlas
atlas_draw_sprite :: proc(atlas_idx: int, name: string, x, y: f32) -> bool {
	region, ok := atlas_get_region(atlas_idx, name)
	if !ok {
		return false
	}
	
	if atlas_idx < 0 || atlas_idx >= len(texture_atlases) {
		return false
	}
	
	atlas := texture_atlases[atlas_idx]
	src := SDL.Rect{
		i32(region.x),
		i32(region.y),
		i32(region.w),
		i32(region.h),
	}
	dst := SDL.Rect{
		i32(x),
		i32(y),
		i32(region.w),
		i32(region.h),
	}
	
	SDL.RenderCopy(renderer, atlas.texture, &src, &dst)
	return true
}

// Save atlas metadata to JSON for runtime reference
atlas_save_metadata :: proc(atlas_idx: int, path: string) -> bool {
	if atlas_idx < 0 || atlas_idx >= len(texture_atlases) {
		return false
	}
	
	atlas := texture_atlases[atlas_idx]
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	
	fmt.sbprintln(&builder, "{")
	fmt.sbprintf(&builder, "  \"name\": \"%s\",\n", atlas.path)
	fmt.sbprintf(&builder, "  \"width\": %d,\n", atlas.width)
	fmt.sbprintf(&builder, "  \"height\": %d,\n", atlas.height)
	fmt.sbprintln(&builder, "  \"regions\": {")
	
	first := true
	for name, region in atlas.regions {
		if !first {
			fmt.sbprintln(&builder, ",")
		}
		first = false
		fmt.sbprintf(&builder, "    \"%s\": {\"x\": %d, \"y\": %d, \"w\": %d, \"h\": %d}",
			name, region.x, region.y, region.w, region.h)
	}
	
	fmt.sbprintln(&builder, "")
	fmt.sbprintln(&builder, "  }")
	fmt.sbprintln(&builder, "}")
	
	data := transmute([]u8)strings.to_string(builder)
	return try_write_file(path, data)
}

// --- Audio Bank Bundling ---

// Create an audio bank from multiple sound files
audio_bank_create :: proc(name: string, sound_files: map[string]string) -> int {
	bank := Audio_Bank{
		sounds = make(map[string]int),
		path = name,
	}
	
	log_info("Creating audio bank '%s' with %d sounds", name, len(sound_files))
	
	for sound_name, file_path in sound_files {
		if !os.exists(file_path) {
			log_warn("Sound file not found: %s", file_path)
			continue
		}
		
		sound_id := load_sound(file_path)
		if sound_id >= 0 {
			bank.sounds[sound_name] = sound_id
			log_info("  Added sound '%s' -> id %d", sound_name, sound_id)
		} else {
			log_warn("  Failed to load sound: %s", file_path)
		}
	}
	
	idx := len(audio_banks)
	append(&audio_banks, bank)
	
	log_info("Audio bank '%s' created with %d sounds", name, len(bank.sounds))
	return idx
}

// Get a sound ID from an audio bank
audio_bank_get_sound :: proc(bank_idx: int, name: string) -> int {
	if bank_idx < 0 || bank_idx >= len(audio_banks) {
		return -1
	}
	
	sound_id, ok := audio_banks[bank_idx].sounds[name]
	if !ok {
		log_warn("Sound '%s' not found in audio bank", name)
		return -1
	}
	
	return sound_id
}

// Play a sound from an audio bank
audio_bank_play :: proc(bank_idx: int, name: string) -> bool {
	sound_id := audio_bank_get_sound(bank_idx, name)
	if sound_id < 0 {
		return false
	}
	
	play_sound(sound_id)
	return true
}

// Save audio bank metadata to JSON
audio_bank_save_metadata :: proc(bank_idx: int, path: string) -> bool {
	if bank_idx < 0 || bank_idx >= len(audio_banks) {
		return false
	}
	
	bank := audio_banks[bank_idx]
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	
	fmt.sbprintln(&builder, "{")
	fmt.sbprintf(&builder, "  \"name\": \"%s\",\n", bank.path)
	fmt.sbprintln(&builder, "  \"sounds\": {")
	
	first := true
	for name, sound_id in bank.sounds {
		if !first {
			fmt.sbprintln(&builder, ",")
		}
		first = false
		fmt.sbprintf(&builder, "    \"%s\": %d", name, sound_id)
	}
	
	fmt.sbprintln(&builder, "")
	fmt.sbprintln(&builder, "  }")
	fmt.sbprintln(&builder, "}")
	
	data := transmute([]u8)strings.to_string(builder)
	return try_write_file(path, data)
}

// --- Asset Pipeline Helpers ---

// Scan a directory for image files and return as map
scan_images :: proc(dir: string) -> map[string]string {
	result := make(map[string]string)
	
	if !os.exists(dir) || !os.is_dir(dir) {
		log_warn("Directory not found: %s", dir)
		return result
	}
	
	fd, err := os.open(dir)
	if err != os.ERROR_NONE {
		log_warn("Cannot open directory: %s", dir)
		return result
	}
	defer os.close(fd)
	
	fis, read_err := os.read_dir(fd, -1, context.allocator)
	if read_err != os.ERROR_NONE {
		log_warn("Cannot read directory: %s", dir)
		return result
	}
	defer delete(fis)
	
	for fi in fis {
		if fi.type == .Regular {
			ext := filepath.ext(fi.name)
			if ext == ".png" || ext == ".jpg" || ext == ".bmp" {
				name := fi.name[:len(fi.name) - len(ext)]
				path := fmt.tprintf("%s/%s", dir, fi.name)
				result[name] = path
			}
		}
	}
	
	return result
}

// Scan a directory for audio files and return as map
scan_audio :: proc(dir: string) -> map[string]string {
	result := make(map[string]string)
	
	if !os.exists(dir) || !os.is_dir(dir) {
		log_warn("Directory not found: %s", dir)
		return result
	}
	
	fd, err := os.open(dir)
	if err != os.ERROR_NONE {
		log_warn("Cannot open directory: %s", dir)
		return result
	}
	defer os.close(fd)
	
	fis, read_err := os.read_dir(fd, -1, context.allocator)
	if read_err != os.ERROR_NONE {
		log_warn("Cannot read directory: %s", dir)
		return result
	}
	defer delete(fis)
	
	for fi in fis {
		if fi.type == .Regular {
			ext := filepath.ext(fi.name)
			if ext == ".wav" || ext == ".ogg" || ext == ".mp3" {
				name := fi.name[:len(fi.name) - len(ext)]
				path := fmt.tprintf("%s/%s", dir, fi.name)
				result[name] = path
			}
		}
	}
	
	return result
}
