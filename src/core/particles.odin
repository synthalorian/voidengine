package voidengine

import "core:math"
import "core:math/rand"
import "core:math/linalg"
import SDL "vendor:sdl2"

// ============================================================================
// Particle System — emitter component + update/render systems
// ============================================================================
// Attach a ParticleEmitter to any entity. If the entity also has a
// Transform, particles spawn at the transform position; otherwise at
// the emitter's own offset.
//
// CLEANUP: the emitter owns a dynamic array. Call particle_emitter_destroy
// before the owning entity/scene is torn down (engine component teardown
// frees the struct but not the array backing store).

ParticleEmitter :: struct {
    // Emission control
    rate: f32,              // particles per second (0 = manual bursts only)
    emit_accum: f32,
    max_particles: int,
    emitting: bool,
    offset: linalg.Vector2f32,

    // Particle shape
    lifetime_min: f32,
    lifetime_max: f32,
    speed_min: f32,
    speed_max: f32,
    angle_min: f32,         // radians; 0 = +X axis, PI/2 = +Y (down)
    angle_max: f32,
    size_start: f32,
    size_end: f32,
    color_start: SDL.Color,
    color_end: SDL.Color,
    gravity: linalg.Vector2f32,

    // Live particles
    particles: [dynamic]ParticleInstance,
}

ParticleInstance :: struct {
    position: linalg.Vector2f32,
    velocity: linalg.Vector2f32,
    age: f32,
    lifetime: f32,
}

make_particle_emitter :: proc(rate: f32, max_particles: int = 256) -> ParticleEmitter {
    return ParticleEmitter{
        rate = rate,
        max_particles = max_particles,
        emitting = true,
        lifetime_min = 0.4,
        lifetime_max = 0.8,
        speed_min = 40,
        speed_max = 120,
        angle_min = 0,
        angle_max = 2 * math.PI,
        size_start = 4,
        size_end = 1,
        color_start = SDL.Color{255, 220, 80, 255},
        color_end = SDL.Color{255, 60, 0, 0},
        gravity = {0, 0},
        particles = make([dynamic]ParticleInstance),
    }
}

particle_emitter_destroy :: proc(emitter: ^ParticleEmitter) {
    if emitter == nil {
        return
    }
    delete(emitter.particles)
    emitter.particles = nil
}

// particle_spawn emits a single particle from the emitter at world pos.
particle_spawn :: proc(emitter: ^ParticleEmitter, pos: linalg.Vector2f32) {
    if len(emitter.particles) >= emitter.max_particles {
        return
    }
    angle := rand_range(emitter.angle_min, emitter.angle_max)
    speed := rand_range(emitter.speed_min, emitter.speed_max)
    append(&emitter.particles, ParticleInstance{
        position = pos + emitter.offset,
        velocity = {math.cos(angle) * speed, math.sin(angle) * speed},
        age = 0,
        lifetime = rand_range(emitter.lifetime_min, emitter.lifetime_max),
    })
}

// particle_burst emits `count` particles immediately (explosions, impacts).
particle_burst :: proc(emitter: ^ParticleEmitter, pos: linalg.Vector2f32, count: int) {
    for i in 0..<count {
        particle_spawn(emitter, pos)
    }
}

// particle_update integrates and ages every emitter in the scene.
// Call once per fixed update.
particle_update :: proc(scene: ^Scene, dt: f64) {
    dt_f32 := f32(dt)
    for entity in scene.entities {
        if !entity.active {
            continue
        }
        emitter := entity_get_component(entity, ParticleEmitter)
        if emitter == nil {
            continue
        }

        transform := entity_get_component(entity, Transform)
        spawn_pos: linalg.Vector2f32
        if transform != nil {
            spawn_pos = transform.position
        }

        // Continuous emission
        if emitter.emitting && emitter.rate > 0 {
            emitter.emit_accum += emitter.rate * dt_f32
            for emitter.emit_accum >= 1.0 {
                emitter.emit_accum -= 1.0
                particle_spawn(emitter, spawn_pos)
            }
        }

        // Integrate + kill expired (swap-remove for O(1) compaction)
        i := 0
        for i < len(emitter.particles) {
            p := &emitter.particles[i]
            p.age += dt_f32
            if p.age >= p.lifetime {
                unordered_remove(&emitter.particles, i)
                continue
            }
            p.velocity += emitter.gravity * dt_f32
            p.position += p.velocity * dt_f32
            i += 1
        }
    }
}

// particle_render draws all particles as size/alpha-lerped rects.
particle_render :: proc(scene: ^Scene, renderer: ^SDL.Renderer) {
    for entity in scene.entities {
        if !entity.active {
            continue
        }
        emitter := entity_get_component(entity, ParticleEmitter)
        if emitter == nil {
            continue
        }
        for &p in emitter.particles {
            t := clamp(p.age / p.lifetime, 0, 1)
            r := u8(lerp(f32(emitter.color_start.r), f32(emitter.color_end.r), t))
            g := u8(lerp(f32(emitter.color_start.g), f32(emitter.color_end.g), t))
            b := u8(lerp(f32(emitter.color_start.b), f32(emitter.color_end.b), t))
            a := u8(lerp(f32(emitter.color_start.a), f32(emitter.color_end.a), t))
            size := lerp(emitter.size_start, emitter.size_end, t)
            half := i32(size / 2)
            SDL.SetRenderDrawColor(renderer, r, g, b, a)
            rect := SDL.Rect{
                x = i32(p.position.x) - half,
                y = i32(p.position.y) - half,
                w = max(i32(size), 1),
                h = max(i32(size), 1),
            }
            SDL.RenderFillRect(renderer, &rect)
        }
    }
}
