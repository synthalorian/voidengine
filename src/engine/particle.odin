package engine

import "core:math"
import "core:fmt"

// --- Particle ---

Particle :: struct {
	position:     Vec2,
	velocity:     Vec2,
	acceleration: Vec2,
	life:         f32,     // Current life (counts down)
	max_life:     f32,     // Maximum life
	size:         f32,     // Current size
	start_size:   f32,
	end_size:     f32,
	color:        Color,
	start_color:  Color,
	end_color:    Color,
	rotation:     f32,
	rot_speed:    f32,
	active:       bool,
}

// --- Emitter ---

Emitter_Shape :: enum {
	POINT,
	CIRCLE,
	RECTANGLE,
}

Particle_Emitter :: struct {
	// Transform
	position:     Vec2,
	emit_area:    Vec2,    // For rectangle: width, height. For circle: radius, 0
	shape:        Emitter_Shape,

	// Emission
	emission_rate: f32,    // Particles per second
	emission_timer: f32,
	burst_count:   int,    // Particles per emission
	max_particles: int,

	// Particle properties
	min_life:      f32,
	max_life:      f32,
	min_speed:     f32,
	max_speed:     f32,
	min_size:      f32,
	max_size:      f32,
	end_size:      f32,    // Size at end of life (0 = shrink to nothing)
	start_color:   Color,
	end_color:     Color,
	gravity:       Vec2,
	direction:     f32,    // Emission direction in degrees (0 = right)
	spread:        f32,    // Spread angle in degrees

	// State
	particles:     [dynamic]Particle,
	active:        bool,
	looping:       bool,
}

emitters: [dynamic]Particle_Emitter

// --- Emitter Management ---

particle_init :: proc() {
	emitters = make([dynamic]Particle_Emitter)
}

particle_shutdown :: proc() {
	for &emitter in emitters {
		delete(emitter.particles)
	}
	delete(emitters)
}

particle_emitter_create :: proc() -> int {
	id := len(emitters)
	append(&emitters, Particle_Emitter{
		position      = vec2_zero(),
		emit_area     = vec2_zero(),
		shape         = .POINT,
		emission_rate = 50.0,
		burst_count   = 1,
		max_particles = 100,
		min_life      = 0.5,
		max_life      = 1.5,
		min_speed     = 50.0,
		max_speed     = 150.0,
		min_size      = 2.0,
		max_size      = 5.0,
		end_size      = 0.0,
		start_color   = COLOR_WHITE,
		end_color     = COLOR_WHITE,
		gravity       = Vec2{0, 100},
		direction     = -90.0, // Up by default
		spread        = 30.0,
		particles     = make([dynamic]Particle),
		active        = true,
		looping       = true,
	})
	return id
}

particle_emitter_destroy :: proc(emitter_id: int) {
	if emitter_id < 0 || emitter_id >= len(emitters) {
		return
	}
	delete(emitters[emitter_id].particles)
	ordered_remove(&emitters, emitter_id)
}

particle_emitter_set_position :: proc(emitter_id: int, pos: Vec2) {
	if emitter_id < 0 || emitter_id >= len(emitters) {
		return
	}
	emitters[emitter_id].position = pos
}

particle_emitter_start :: proc(emitter_id: int) {
	if emitter_id < 0 || emitter_id >= len(emitters) {
		return
	}
	emitters[emitter_id].active = true
}

particle_emitter_stop :: proc(emitter_id: int) {
	if emitter_id < 0 || emitter_id >= len(emitters) {
		return
	}
	emitters[emitter_id].active = false
}

particle_emitter_burst :: proc(emitter_id: int, count: int) {
	if emitter_id < 0 || emitter_id >= len(emitters) {
		return
	}
	emitter := &emitters[emitter_id]
	for _ in 0..<count {
		spawn_particle(emitter)
	}
}

// --- Particle Spawning ---

spawn_particle :: proc(emitter: ^Particle_Emitter) {
	if len(emitter.particles) >= emitter.max_particles {
		return
	}

	life := emitter.min_life + random_range(0, emitter.max_life - emitter.min_life)
	speed := emitter.min_speed + random_range(0, emitter.max_speed - emitter.min_speed)
	size := emitter.min_size + random_range(0, emitter.max_size - emitter.min_size)

	// Calculate spawn position based on shape
	spawn_pos := emitter.position
	switch emitter.shape {
	case .CIRCLE:
		angle := random_range(0, 360)
		rad := random_range(0, emitter.emit_area.x)
		spawn_pos.x += math.cos(math.to_radians_f32(angle)) * rad
		spawn_pos.y += math.sin(math.to_radians_f32(angle)) * rad
	case .RECTANGLE:
		spawn_pos.x += random_range(-emitter.emit_area.x * 0.5, emitter.emit_area.x * 0.5)
		spawn_pos.y += random_range(-emitter.emit_area.y * 0.5, emitter.emit_area.y * 0.5)
	case .POINT:
		// Already at position
	}

	// Calculate velocity based on direction and spread
	base_angle := emitter.direction + random_range(-emitter.spread * 0.5, emitter.spread * 0.5)
	vel := Vec2{
		x = math.cos(math.to_radians_f32(base_angle)) * speed,
		y = math.sin(math.to_radians_f32(base_angle)) * speed,
	}

	append(&emitter.particles, Particle{
		position     = spawn_pos,
		velocity     = vel,
		acceleration = emitter.gravity,
		life         = life,
		max_life     = life,
		size         = size,
		start_size   = size,
		end_size     = emitter.end_size,
		color        = emitter.start_color,
		start_color  = emitter.start_color,
		end_color    = emitter.end_color,
		rotation     = random_range(0, 360),
		rot_speed    = random_range(-180, 180),
		active       = true,
	})
}

// --- Update ---

particle_update :: proc(dt: f32) {
	for &emitter in emitters {
		if emitter.active && emitter.looping {
			emitter.emission_timer += dt
			emit_interval := 1.0 / emitter.emission_rate
			for emitter.emission_timer >= emit_interval {
				emitter.emission_timer -= emit_interval
				for _ in 0..<emitter.burst_count {
					spawn_particle(&emitter)
				}
			}
		}

		// Update particles
		for i := len(emitter.particles) - 1; i >= 0; i -= 1 {
			p := &emitter.particles[i]
			if !p.active { continue }

			p.life -= dt
			if p.life <= 0 {
				p.active = false
				ordered_remove(&emitter.particles, i)
				continue
			}

			// Update physics
			p.velocity = vec2_add(p.velocity, vec2_mul(p.acceleration, dt))
			p.position = vec2_add(p.position, vec2_mul(p.velocity, dt))
			p.rotation += p.rot_speed * dt

			// Update size
			t := 1.0 - (p.life / p.max_life)
			p.size = lerp(p.start_size, p.end_size, t)

			// Update color
			p.color.r = lerp(p.start_color.r, p.end_color.r, t)
			p.color.g = lerp(p.start_color.g, p.end_color.g, t)
			p.color.b = lerp(p.start_color.b, p.end_color.b, t)
			p.color.a = lerp(p.start_color.a, p.end_color.a, t)
		}
	}
}

// --- Rendering ---

particle_draw :: proc(emitter_id: int) {
	if emitter_id < 0 || emitter_id >= len(emitters) {
		return
	}
	emitter := &emitters[emitter_id]
	for p in emitter.particles {
		if !p.active { continue }
		draw_rect(
			p.position.x - p.size * 0.5,
			p.position.y - p.size * 0.5,
			p.size,
			p.size,
			p.color.r,
			p.color.g,
			p.color.b,
		)
	}
}

particle_draw_all :: proc() {
	for i in 0..<len(emitters) {
		particle_draw(i)
	}
}

// --- Preset emitters ---

particle_preset_explosion :: proc(pos: Vec2) -> int {
	id := particle_emitter_create()
	emitter := &emitters[id]
	emitter.position = pos
	emitter.shape = .CIRCLE
	emitter.emit_area = Vec2{10, 0}
	emitter.emission_rate = 0 // No continuous emission
	emitter.burst_count = 30
	emitter.max_particles = 30
	emitter.min_life = 0.3
	emitter.max_life = 0.8
	emitter.min_speed = 100.0
	emitter.max_speed = 300.0
	emitter.min_size = 4.0
	emitter.max_size = 8.0
	emitter.end_size = 0.0
	emitter.start_color = COLOR_YELLOW
	emitter.end_color = COLOR_RED
	emitter.gravity = Vec2{0, 200}
	emitter.direction = 0
	emitter.spread = 360.0
	emitter.looping = false
	particle_emitter_burst(id, 30)
	return id
}

particle_preset_smoke :: proc(pos: Vec2) -> int {
	id := particle_emitter_create()
	emitter := &emitters[id]
	emitter.position = pos
	emitter.shape = .POINT
	emitter.emission_rate = 20.0
	emitter.burst_count = 1
	emitter.max_particles = 50
	emitter.min_life = 1.0
	emitter.max_life = 2.5
	emitter.min_speed = 20.0
	emitter.max_speed = 50.0
	emitter.min_size = 5.0
	emitter.max_size = 10.0
	emitter.end_size = 20.0
	emitter.start_color = Color{0.8, 0.8, 0.8, 0.6}
	emitter.end_color = Color{0.5, 0.5, 0.5, 0.0}
	emitter.gravity = Vec2{0, -30}
	emitter.direction = -90.0
	emitter.spread = 20.0
	return id
}

particle_preset_sparkle :: proc(pos: Vec2) -> int {
	id := particle_emitter_create()
	emitter := &emitters[id]
	emitter.position = pos
	emitter.shape = .POINT
	emitter.emission_rate = 10.0
	emitter.burst_count = 1
	emitter.max_particles = 30
	emitter.min_life = 0.5
	emitter.max_life = 1.0
	emitter.min_speed = 50.0
	emitter.max_speed = 100.0
	emitter.min_size = 2.0
	emitter.max_size = 4.0
	emitter.end_size = 0.0
	emitter.start_color = COLOR_CYAN
	emitter.end_color = COLOR_BLUE
	emitter.gravity = Vec2{0, 50}
	emitter.direction = -90.0
	emitter.spread = 45.0
	return id
}
