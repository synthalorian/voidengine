package engine

import "core:math"

// --- Rigid Body ---

Body_Type :: enum {
	DYNAMIC,
	STATIC,
	KINEMATIC,
}

Rigid_Body :: struct {
	id:          int,
	position:    Vec2,
	velocity:    Vec2,
	acceleration: Vec2,
	size:        Vec2,     // For AABB: width, height
	radius:      f32,      // For circle bodies
	body_type:   Body_Type,
	mass:        f32,
	inv_mass:    f32,
	restitution: f32,      // Bounciness (0-1)
	friction:    f32,      // Surface friction (0-1)
	gravity_scale: f32,
	is_grounded: bool,
	use_circle:  bool,     // true = circle collider, false = AABB
}

// Physics world
Physics_World :: struct {
	bodies:      [dynamic]Rigid_Body,
	gravity:     Vec2,
	damping:     f32,      // Global velocity damping
	iterations:  int,      // Solver iterations for stability
}

physics_world: Physics_World

// --- Physics World Management ---

physics_init :: proc(gravity: Vec2 = {0, 980}, damping: f32 = 0.99, iterations: int = 3) {
	physics_world = Physics_World{
		bodies     = make([dynamic]Rigid_Body),
		gravity    = gravity,
		damping    = damping,
		iterations = iterations,
	}
}

physics_shutdown :: proc() {
	delete(physics_world.bodies)
}

physics_set_gravity :: proc(gravity: Vec2) {
	physics_world.gravity = gravity
}

// --- Body Creation ---

physics_add_body :: proc(pos: Vec2, size: Vec2, body_type: Body_Type = .DYNAMIC) -> int {
	id := len(physics_world.bodies)
	mass: f32 = 1.0
	if body_type == .STATIC {
		mass = 0.0
	}
	inv_mass := mass > 0 ? 1.0 / mass : 0.0

	append(&physics_world.bodies, Rigid_Body{
		id            = id,
		position      = pos,
		velocity      = vec2_zero(),
		acceleration  = vec2_zero(),
		size          = size,
		radius        = min(size.x, size.y) * 0.5,
		body_type     = body_type,
		mass          = mass,
		inv_mass      = inv_mass,
		restitution   = 0.3,
		friction      = 0.5,
		gravity_scale = 1.0,
		is_grounded   = false,
		use_circle    = false,
	})
	return id
}

physics_add_circle_body :: proc(pos: Vec2, radius: f32, body_type: Body_Type = .DYNAMIC) -> int {
	id := len(physics_world.bodies)
	mass: f32 = 1.0
	if body_type == .STATIC {
		mass = 0.0
	}
	inv_mass := mass > 0 ? 1.0 / mass : 0.0

	append(&physics_world.bodies, Rigid_Body{
		id            = id,
		position      = pos,
		velocity      = vec2_zero(),
		acceleration  = vec2_zero(),
		size          = {radius * 2, radius * 2},
		radius        = radius,
		body_type     = body_type,
		mass          = mass,
		inv_mass      = inv_mass,
		restitution   = 0.3,
		friction      = 0.5,
		gravity_scale = 1.0,
		is_grounded   = false,
		use_circle    = true,
	})
	return id
}

physics_remove_body :: proc(body_id: int) {
	if body_id < 0 || body_id >= len(physics_world.bodies) {
		return
	}
	ordered_remove(&physics_world.bodies, body_id)
	// Update IDs
	for i in body_id..<len(physics_world.bodies) {
		physics_world.bodies[i].id = i
	}
}

physics_get_body :: proc(body_id: int) -> ^Rigid_Body {
	if body_id < 0 || body_id >= len(physics_world.bodies) {
		return nil
	}
	return &physics_world.bodies[body_id]
}

physics_body_count :: proc() -> int {
	return len(physics_world.bodies)
}

// --- Body Properties ---

physics_set_velocity :: proc(body_id: int, vel: Vec2) {
	body := physics_get_body(body_id)
	if body != nil {
		body.velocity = vel
	}
}

physics_add_velocity :: proc(body_id: int, vel: Vec2) {
	body := physics_get_body(body_id)
	if body != nil {
		body.velocity = vec2_add(body.velocity, vel)
	}
}

physics_set_position :: proc(body_id: int, pos: Vec2) {
	body := physics_get_body(body_id)
	if body != nil {
		body.position = pos
	}
}

physics_apply_force :: proc(body_id: int, force: Vec2) {
	body := physics_get_body(body_id)
	if body != nil && body.inv_mass > 0 {
		body.acceleration = vec2_add(body.acceleration, vec2_mul(force, body.inv_mass))
	}
}

physics_apply_impulse :: proc(body_id: int, impulse: Vec2) {
	body := physics_get_body(body_id)
	if body != nil && body.inv_mass > 0 {
		body.velocity = vec2_add(body.velocity, vec2_mul(impulse, body.inv_mass))
	}
}

// --- Collision Detection ---

Collision_Manifold :: struct {
	a:        int,       // Body A ID
	b:        int,       // Body B ID
	normal:   Vec2,      // Collision normal (from A to B)
	penetration: f32,    // Penetration depth
	has_collision: bool,
}

aabb_vs_aabb :: proc(a, b: ^Rigid_Body) -> Collision_Manifold {
	manifold := Collision_Manifold{a = a.id, b = b.id}

	a_half := vec2_mul(a.size, 0.5)
	b_half := vec2_mul(b.size, 0.5)

	a_min := vec2_sub(a.position, a_half)
	a_max := vec2_add(a.position, a_half)
	b_min := vec2_sub(b.position, b_half)
	b_max := vec2_add(b.position, b_half)

	// Check for overlap
	if a_max.x < b_min.x || a_min.x > b_max.x || a_max.y < b_min.y || a_min.y > b_max.y {
		return manifold // No collision
	}

	// Calculate penetration depth on each axis
	x_overlap := min(a_max.x - b_min.x, b_max.x - a_min.x)
	y_overlap := min(a_max.y - b_min.y, b_max.y - a_min.y)

	// Find minimum overlap axis
	if x_overlap < y_overlap {
		manifold.penetration = x_overlap
		manifold.normal = (a.position.x < b.position.x) ? Vec2{-1, 0} : Vec2{1, 0}
	} else {
		manifold.penetration = y_overlap
		manifold.normal = (a.position.y < b.position.y) ? Vec2{0, -1} : Vec2{0, 1}
	}

	manifold.has_collision = true
	return manifold
}

circle_vs_circle :: proc(a, b: ^Rigid_Body) -> Collision_Manifold {
	manifold := Collision_Manifold{a = a.id, b = b.id}

	diff := vec2_sub(b.position, a.position)
	dist_sq := vec2_len_sq(diff)
	radius_sum := a.radius + b.radius

	if dist_sq >= radius_sum * radius_sum {
		return manifold // No collision
	}

	dist := math.sqrt(dist_sq)
	manifold.penetration = radius_sum - dist

	if dist > 0 {
		manifold.normal = vec2_div(diff, dist)
	} else {
		manifold.normal = Vec2{1, 0} // Arbitrary normal if centers overlap
	}

	manifold.has_collision = true
	return manifold
}

circle_vs_aabb :: proc(circle, aabb: ^Rigid_Body) -> Collision_Manifold {
	manifold := Collision_Manifold{a = circle.id, b = aabb.id}

	a_half := vec2_mul(aabb.size, 0.5)
	aabb_min := vec2_sub(aabb.position, a_half)
	aabb_max := vec2_add(aabb.position, a_half)

	// Find closest point on AABB to circle center
	closest_x := clamp(circle.position.x, aabb_min.x, aabb_max.x)
	closest_y := clamp(circle.position.y, aabb_min.y, aabb_max.y)
	closest := Vec2{closest_x, closest_y}

	diff := vec2_sub(circle.position, closest)
	dist_sq := vec2_len_sq(diff)

	if dist_sq > circle.radius * circle.radius {
		return manifold // No collision
	}

	dist := math.sqrt(dist_sq)
	if dist > 0 {
		manifold.normal = vec2_div(diff, dist)
		manifold.penetration = circle.radius - dist
	} else {
		// Circle center is inside AABB
		// Find the closest face
		dx1 := circle.position.x - aabb_min.x
		dx2 := aabb_max.x - circle.position.x
		dy1 := circle.position.y - aabb_min.y
		dy2 := aabb_max.y - circle.position.y

		min_dist := min(dx1, dx2, dy1, dy2)
		if min_dist == dx1 {
			manifold.normal = Vec2{-1, 0}
			manifold.penetration = dx1 + circle.radius
		} else if min_dist == dx2 {
			manifold.normal = Vec2{1, 0}
			manifold.penetration = dx2 + circle.radius
		} else if min_dist == dy1 {
			manifold.normal = Vec2{0, -1}
			manifold.penetration = dy1 + circle.radius
		} else {
			manifold.normal = Vec2{0, 1}
			manifold.penetration = dy2 + circle.radius
		}
	}

	manifold.has_collision = true
	return manifold
}

// --- Collision Resolution ---

resolve_collision :: proc(manifold: ^Collision_Manifold) {
	a := physics_get_body(manifold.a)
	b := physics_get_body(manifold.b)
	if a == nil || b == nil { return }
	if a.body_type == .STATIC && b.body_type == .STATIC { return }

	// Relative velocity
	rel_vel := vec2_sub(b.velocity, a.velocity)
	vel_along_normal := vec2_dot(rel_vel, manifold.normal)

	// Don't resolve if velocities are separating
	if vel_along_normal > 0 {
		return
	}

	// Calculate restitution
	e := min(a.restitution, b.restitution)

	// Calculate impulse scalar
	j := -(1 + e) * vel_along_normal
	j /= a.inv_mass + b.inv_mass

	// Apply impulse
	impulse := vec2_mul(manifold.normal, j)
	a.velocity = vec2_sub(a.velocity, vec2_mul(impulse, a.inv_mass))
	b.velocity = vec2_add(b.velocity, vec2_mul(impulse, b.inv_mass))

	// Friction
	rel_vel = vec2_sub(b.velocity, a.velocity)
	tangent := vec2_sub(rel_vel, vec2_mul(manifold.normal, vec2_dot(rel_vel, manifold.normal)))
	tangent_len := vec2_len(tangent)
	if tangent_len > 0.001 {
		tangent = vec2_div(tangent, tangent_len)
	}

	jf := -vec2_dot(rel_vel, tangent)
	jf /= a.inv_mass + b.inv_mass

	mu := math.sqrt(a.friction * a.friction + b.friction * b.friction)
	jf = clamp(jf, -j * mu, j * mu)

	friction_impulse := vec2_mul(tangent, jf)
	a.velocity = vec2_sub(a.velocity, vec2_mul(friction_impulse, a.inv_mass))
	b.velocity = vec2_add(b.velocity, vec2_mul(friction_impulse, b.inv_mass))
}

positional_correction :: proc(manifold: ^Collision_Manifold) {
	a := physics_get_body(manifold.a)
	b := physics_get_body(manifold.b)
	if a == nil || b == nil { return }
	if a.body_type == .STATIC && b.body_type == .STATIC { return }

	PERCENT :: 0.4  // Penetration percentage to correct
	SLOP :: 0.05     // Penetration allowance

	correction_mag := max(manifold.penetration - SLOP, 0) / (a.inv_mass + b.inv_mass)
	correction := vec2_mul(manifold.normal, correction_mag * PERCENT)

	a.position = vec2_sub(a.position, vec2_mul(correction, a.inv_mass))
	b.position = vec2_add(b.position, vec2_mul(correction, b.inv_mass))
}

// --- Physics Step ---

physics_step :: proc(dt: f32) {
	// Apply gravity and integrate velocity
	for &body in physics_world.bodies {
		if body.body_type != .DYNAMIC { continue }

		// Apply gravity
		grav_force := vec2_mul(physics_world.gravity, body.gravity_scale)
		body.acceleration = vec2_add(body.acceleration, grav_force)

		// Integrate: v += a * dt
		body.velocity = vec2_add(body.velocity, vec2_mul(body.acceleration, dt))

		// Apply damping
		body.velocity = vec2_mul(body.velocity, physics_world.damping)

		// Clear acceleration
		body.acceleration = vec2_zero()

		// Reset grounded state (will be set during collision)
		body.is_grounded = false
	}

	// Integrate position
	for &body in physics_world.bodies {
		if body.body_type != .DYNAMIC { continue }
		body.position = vec2_add(body.position, vec2_mul(body.velocity, dt))
	}

	// Detect and resolve collisions (multiple iterations for stability)
	for _ in 0..<physics_world.iterations {
		for i in 0..<len(physics_world.bodies) {
			for j in i+1..<len(physics_world.bodies) {
				a := &physics_world.bodies[i]
				b := &physics_world.bodies[j]

				// Skip if both are static
				if a.body_type == .STATIC && b.body_type == .STATIC {
					continue
				}

				manifold: Collision_Manifold

				// Determine collision type
				if a.use_circle && b.use_circle {
					manifold = circle_vs_circle(a, b)
				} else if !a.use_circle && !b.use_circle {
					manifold = aabb_vs_aabb(a, b)
				} else if a.use_circle && !b.use_circle {
					manifold = circle_vs_aabb(a, b)
				} else {
					manifold = circle_vs_aabb(b, a)
					// Flip normal to point from A to B
					manifold.normal = vec2_mul(manifold.normal, -1)
					manifold.a = a.id
					manifold.b = b.id
				}

				if manifold.has_collision {
					resolve_collision(&manifold)
					positional_correction(&manifold)

					// Check if grounded (normal pointing up)
					if manifold.normal.y < -0.7 {
						if a.body_type == .DYNAMIC {
							a.is_grounded = true
						}
					}
					if manifold.normal.y > 0.7 {
						if b.body_type == .DYNAMIC {
							b.is_grounded = true
						}
					}
				}
			}
		}
	}
}

// --- Raycasting ---

physics_raycast :: proc(origin: Vec2, direction: Vec2, max_dist: f32, hit_body_id: ^int) -> (hit_point: Vec2, hit: bool) {
	dir := vec2_normalize(direction)
	step := vec2_mul(dir, 1.0) // 1 pixel steps
	current := origin
	steps := int(max_dist)

	for _ in 0..<steps {
		current = vec2_add(current, step)

		for &body in physics_world.bodies {
			if body.body_type == .DYNAMIC { continue } // Raycast against static bodies

			if body.use_circle {
				if vec2_dist(current, body.position) <= body.radius {
					hit_body_id^ = body.id
					return current, true
				}
			} else {
				half := vec2_mul(body.size, 0.5)
				min_p := vec2_sub(body.position, half)
				max_p := vec2_add(body.position, half)
				if current.x >= min_p.x && current.x <= max_p.x &&
				   current.y >= min_p.y && current.y <= max_p.y {
					hit_body_id^ = body.id
					return current, true
				}
			}
		}
	}

	return Vec2{}, false
}

// --- Utility ---

physics_body_get_rect :: proc(body_id: int) -> Rect {
	body := physics_get_body(body_id)
	if body == nil {
		return Rect{0, 0, 0, 0}
	}
	return Rect{
		x = body.position.x - body.size.x * 0.5,
		y = body.position.y - body.size.y * 0.5,
		w = body.size.x,
		h = body.size.y,
	}
}

physics_body_get_aabb :: proc(body_id: int) -> (min_p: Vec2, max_p: Vec2) {
	body := physics_get_body(body_id)
	if body == nil {
		return Vec2{}, Vec2{}
	}
	if body.use_circle {
		return vec2_sub(body.position, Vec2{body.radius, body.radius}),
		       vec2_add(body.position, Vec2{body.radius, body.radius})
	}
	half := vec2_mul(body.size, 0.5)
	return vec2_sub(body.position, half), vec2_add(body.position, half)
}

physics_clear_bodies :: proc() {
	clear_dynamic_array(&physics_world.bodies)
}
