package engine

import "core:math"

// --- Vec2 ---

Vec2 :: struct {
	x: f32,
	y: f32,
}

vec2 :: proc(x, y: f32) -> Vec2 {
	return Vec2{x, y}
}

vec2_zero :: proc() -> Vec2 {
	return Vec2{0, 0}
}

vec2_one :: proc() -> Vec2 {
	return Vec2{1, 1}
}

vec2_add :: proc(a, b: Vec2) -> Vec2 {
	return Vec2{a.x + b.x, a.y + b.y}
}

vec2_sub :: proc(a, b: Vec2) -> Vec2 {
	return Vec2{a.x - b.x, a.y - b.y}
}

vec2_mul :: proc(v: Vec2, s: f32) -> Vec2 {
	return Vec2{v.x * s, v.y * s}
}

vec2_div :: proc(v: Vec2, s: f32) -> Vec2 {
	return Vec2{v.x / s, v.y / s}
}

vec2_dot :: proc(a, b: Vec2) -> f32 {
	return a.x * b.x + a.y * b.y
}

vec2_len :: proc(v: Vec2) -> f32 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}

vec2_len_sq :: proc(v: Vec2) -> f32 {
	return v.x * v.x + v.y * v.y
}

vec2_normalize :: proc(v: Vec2) -> Vec2 {
	len := vec2_len(v)
	if len == 0 {
		return Vec2{0, 0}
	}
	return Vec2{v.x / len, v.y / len}
}

vec2_dist :: proc(a, b: Vec2) -> f32 {
	dx := a.x - b.x
	dy := a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
}

vec2_dist_sq :: proc(a, b: Vec2) -> f32 {
	dx := a.x - b.x
	dy := a.y - b.y
	return dx * dx + dy * dy
}

vec2_lerp :: proc(a, b: Vec2, t: f32) -> Vec2 {
	return Vec2{
		x = lerp(a.x, b.x, t),
		y = lerp(a.y, b.y, t),
	}
}

// --- Rect ---

Rect :: struct {
	x: f32,
	y: f32,
	w: f32,
	h: f32,
}

rect :: proc(x, y, w, h: f32) -> Rect {
	return Rect{x, y, w, h}
}

rect_center :: proc(r: Rect) -> Vec2 {
	return Vec2{r.x + r.w * 0.5, r.y + r.h * 0.5}
}

rect_top_left :: proc(r: Rect) -> Vec2 {
	return Vec2{r.x, r.y}
}

rect_bottom_right :: proc(r: Rect) -> Vec2 {
	return Vec2{r.x + r.w, r.y + r.h}
}

rect_contains_point :: proc(r: Rect, p: Vec2) -> bool {
	return p.x >= r.x && p.x <= r.x + r.w &&
	       p.y >= r.y && p.y <= r.y + r.h
}

rect_contains_rect :: proc(a, b: Rect) -> bool {
	return b.x >= a.x && b.x + b.w <= a.x + a.w &&
	       b.y >= a.y && b.y + b.h <= a.y + a.h
}

rect_intersects :: proc(a, b: Rect) -> bool {
	return a.x < b.x + b.w && a.x + a.w > b.x &&
	       a.y < b.y + b.h && a.y + a.h > b.y
}

rect_intersection :: proc(a, b: Rect) -> Rect {
	x1 := max(a.x, b.x)
	y1 := max(a.y, b.y)
	x2 := min(a.x + a.w, b.x + b.w)
	y2 := min(a.y + a.h, b.y + b.h)

	if x2 < x1 || y2 < y1 {
		return Rect{0, 0, 0, 0}
	}

	return Rect{x1, y1, x2 - x1, y2 - y1}
}

rect_expand :: proc(r: Rect, amount: f32) -> Rect {
	return Rect{
		x = r.x - amount,
		y = r.y - amount,
		w = r.w + amount * 2,
		h = r.h + amount * 2,
	}
}

// --- Color ---

Color :: struct {
	r: f32,
	g: f32,
	b: f32,
	a: f32,
}

color :: proc(r, g, b: f32, a: f32 = 1.0) -> Color {
	return Color{r, g, b, a}
}

COLOR_WHITE  :: Color{1.0, 1.0, 1.0, 1.0}
COLOR_BLACK  :: Color{0.0, 0.0, 0.0, 1.0}
COLOR_RED    :: Color{1.0, 0.0, 0.0, 1.0}
COLOR_GREEN  :: Color{0.0, 1.0, 0.0, 1.0}
COLOR_BLUE   :: Color{0.0, 0.0, 1.0, 1.0}
COLOR_YELLOW :: Color{1.0, 1.0, 0.0, 1.0}
COLOR_CYAN   :: Color{0.0, 1.0, 1.0, 1.0}
COLOR_PURPLE :: Color{1.0, 0.0, 1.0, 1.0}

// --- General math utilities ---

lerp :: proc(a, b, t: f32) -> f32 {
	return a + (b - a) * t
}

clamp :: proc(v, min_val, max_val: f32) -> f32 {
	if v < min_val { return min_val }
	if v > max_val { return max_val }
	return v
}

clamp_int :: proc(v, min_val, max_val: int) -> int {
	if v < min_val { return min_val }
	if v > max_val { return max_val }
	return v
}

clamp_vec2 :: proc(v: Vec2, min_val, max_val: f32) -> Vec2 {
	return Vec2{
		x = clamp(v.x, min_val, max_val),
		y = clamp(v.y, min_val, max_val),
	}
}

remap :: proc(v, old_min, old_max, new_min, new_max: f32) -> f32 {
	t := (v - old_min) / (old_max - old_min)
	return lerp(new_min, new_max, t)
}

sign :: proc(v: f32) -> f32 {
	if v < 0 { return -1 }
	if v > 0 { return 1 }
	return 0
}

approach :: proc(current, target, delta: f32) -> f32 {
	if current < target {
		return min(current + delta, target)
	} else if current > target {
		return max(current - delta, target)
	}
	return target
}

// --- Collision detection ---

point_in_rect :: proc(p: Vec2, r: Rect) -> bool {
	return rect_contains_point(r, p)
}

circle_circle_collision :: proc(a_pos: Vec2, a_radius: f32, b_pos: Vec2, b_radius: f32) -> bool {
	dist_sq := vec2_dist_sq(a_pos, b_pos)
	radius_sum := a_radius + b_radius
	return dist_sq <= radius_sum * radius_sum
}

rect_circle_collision :: proc(r: Rect, c_pos: Vec2, c_radius: f32) -> bool {
	// Find the closest point on the rectangle to the circle center
	closest_x := clamp(c_pos.x, r.x, r.x + r.w)
	closest_y := clamp(c_pos.y, r.y, r.y + r.h)

	dx := c_pos.x - closest_x
	dy := c_pos.y - closest_y

	return (dx * dx + dy * dy) <= (c_radius * c_radius)
}

line_intersection :: proc(a1, a2, b1, b2: Vec2) -> (Vec2, bool) {
	// Line-line intersection using cross products
	den := (a1.x - a2.x) * (b1.y - b2.y) - (a1.y - a2.y) * (b1.x - b2.x)
	if den == 0 {
		return Vec2{}, false // Parallel lines
	}

	t := ((a1.x - b1.x) * (b1.y - b2.y) - (a1.y - b1.y) * (b1.x - b2.x)) / den
	u := -((a1.x - a2.x) * (a1.y - b1.y) - (a1.y - a2.y) * (a1.x - b1.x)) / den

	if t >= 0 && t <= 1 && u >= 0 && u <= 1 {
		return Vec2{
			x = a1.x + t * (a2.x - a1.x),
			y = a1.y + t * (a2.y - a1.y),
		}, true
	}

	return Vec2{}, false
}

// --- Random utilities ---

// Global random seed (v0.7.0: proper random state)
random_seed: u32 = 123456789

random_set_seed :: proc(seed: u32) {
	random_seed = seed
}

random_get_seed :: proc() -> u32 {
	return random_seed
}

// Generate next random value and update seed
random_next :: proc() -> u32 {
	random_seed = random_seed * 1103515245 + 12345
	return random_seed & 0x7fffffff
}

// Return random float in range [0, 1)
random_f32 :: proc() -> f32 {
	return f32(random_next()) / f32(0x7fffffff)
}

random_range :: proc(min_val, max_val: f32) -> f32 {
	return min_val + random_f32() * (max_val - min_val)
}

random_int :: proc(min_val, max_val: int) -> int {
	return min_val + int(random_f32() * f32(max_val - min_val + 1))
}

random_vec2_in_rect :: proc(r: Rect) -> Vec2 {
	return Vec2{
		x = r.x + random_range(0, r.w),
		y = r.y + random_range(0, r.h),
	}
}
