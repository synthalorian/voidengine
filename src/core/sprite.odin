package voidengine

import "core:fmt"
import "core:strings"
import SDL "vendor:sdl2"
import IMG "vendor:sdl2/image"

// ============================================================================
// Texture Manager — loads and caches SDL textures by name
// ============================================================================
TextureManager :: struct {
    textures: map[string]^SDL.Texture,
    renderer: ^SDL.Renderer,
}

texture_manager_init :: proc(tm: ^TextureManager, renderer: ^SDL.Renderer) {
    tm.textures = make(map[string]^SDL.Texture)
    tm.renderer = renderer
    IMG.Init(IMG.INIT_PNG | IMG.INIT_JPG)
}

texture_manager_shutdown :: proc(tm: ^TextureManager) {
    for _, texture in tm.textures {
        SDL.DestroyTexture(texture)
    }
    delete(tm.textures)
    IMG.Quit()
}

// texture_load loads an image file (PNG/JPG/BMP) and caches it under `name`.
// Loading the same name twice returns the cached texture.
texture_load :: proc(engine: ^Engine, name, path: string) -> ^SDL.Texture {
    tm := &engine.textures
    if texture, ok := tm.textures[name]; ok {
        return texture
    }

    cpath := strings.clone_to_cstring(path)
    defer delete(cpath)

    surface := IMG.Load(cpath)
    if surface == nil {
        fmt.eprintln("Failed to load image:", path, "-", IMG.GetError())
        return nil
    }
    defer SDL.FreeSurface(surface)

    texture := SDL.CreateTextureFromSurface(tm.renderer, surface)
    if texture == nil {
        fmt.eprintln("Failed to create texture:", path, "-", SDL.GetError())
        return nil
    }

    // Caller keeps `name` alive or we clone it for the map key
    key := strings.clone(name)
    tm.textures[key] = texture
    return texture
}

texture_get :: proc(engine: ^Engine, name: string) -> ^SDL.Texture {
    if texture, ok := engine.textures.textures[name]; ok {
        return texture
    }
    return nil
}

// ============================================================================
// Animation — frame-based sprite sheet animation component
// ============================================================================
Animation :: struct {
    frame_width: i32,
    frame_height: i32,
    columns: i32,        // sprite sheet columns (frames laid out row-major)
    frames: []i32,       // frame indices to play, in order
    frame_time: f32,     // seconds per frame
    timer: f32,
    current: int,        // index into frames
    loop: bool,
    playing: bool,
}

make_animation :: proc(frame_width, frame_height, columns: i32,
    frames: []i32, frame_time: f32, loop: bool = true) -> Animation {
    return Animation{
        frame_width = frame_width,
        frame_height = frame_height,
        columns = columns,
        frames = frames,
        frame_time = frame_time,
        timer = 0,
        current = 0,
        loop = loop,
        playing = true,
    }
}

animation_play :: proc(anim: ^Animation) {
    anim.playing = true
}

animation_pause :: proc(anim: ^Animation) {
    anim.playing = false
}

animation_reset :: proc(anim: ^Animation) {
    anim.current = 0
    anim.timer = 0
}

// animation_frame_index returns the current sprite-sheet frame index.
animation_frame_index :: proc(anim: ^Animation) -> i32 {
    if len(anim.frames) == 0 {
        return 0
    }
    return anim.frames[anim.current]
}

// animation_src_rect computes the source rect for the current frame.
animation_src_rect :: proc(anim: ^Animation) -> SDL.Rect {
    frame := animation_frame_index(anim)
    col := frame % max(anim.columns, 1)
    row := frame / max(anim.columns, 1)
    return SDL.Rect{
        x = col * anim.frame_width,
        y = row * anim.frame_height,
        w = anim.frame_width,
        h = anim.frame_height,
    }
}

// animation_update advances all Animation components in a scene.
// Call once per frame (render-rate) or per fixed update for deterministic timing.
animation_update :: proc(scene: ^Scene, dt: f64) {
    dt_f32 := f32(dt)
    for entity in scene.entities {
        if !entity.active {
            continue
        }
        anim := entity_get_component(entity, Animation)
        if anim == nil || !anim.playing || len(anim.frames) == 0 {
            continue
        }
        anim.timer += dt_f32
        for anim.timer >= anim.frame_time {
            anim.timer -= anim.frame_time
            anim.current += 1
            if anim.current >= len(anim.frames) {
                if anim.loop {
                    anim.current = 0
                } else {
                    anim.current = len(anim.frames) - 1
                    anim.playing = false
                }
            }
        }
    }
}

// ============================================================================
// Sprite Rendering System
// ============================================================================

// sprite_render draws every entity with Transform + Sprite.
// Textured sprites use RenderCopyEx (with Animation src rect when present);
// untextured sprites fall back to filled colored rects (legacy behavior).
sprite_render :: proc(scene: ^Scene, renderer: ^SDL.Renderer) {
    for entity in scene.entities {
        if !entity.active {
            continue
        }
        transform := entity_get_component(entity, Transform)
        sprite := entity_get_component(entity, Sprite)
        if transform == nil || sprite == nil {
            continue
        }

        w := i32(f32(sprite.width) * transform.scale.x)
        h := i32(f32(sprite.height) * transform.scale.y)
        dst := SDL.Rect{
            x = i32(transform.position.x) - w / 2,
            y = i32(transform.position.y) - h / 2,
            w = w,
            h = h,
        }

        if sprite.texture != nil {
            anim := entity_get_component(entity, Animation)
            src: ^SDL.Rect = nil
            src_rect: SDL.Rect
            if anim != nil {
                src_rect = animation_src_rect(anim)
                src = &src_rect
            }
            SDL.SetTextureColorMod(sprite.texture, sprite.color.r, sprite.color.g, sprite.color.b)
            SDL.SetTextureAlphaMod(sprite.texture, sprite.color.a)
            SDL.RenderCopyEx(renderer, sprite.texture, src, &dst,
                f64(transform.rotation) * 57.29578, // rad -> deg
                nil, sprite.flip)
        } else {
            SDL.SetRenderDrawColor(renderer, sprite.color.r, sprite.color.g, sprite.color.b, sprite.color.a)
            SDL.RenderFillRect(renderer, &dst)
        }
    }
}
