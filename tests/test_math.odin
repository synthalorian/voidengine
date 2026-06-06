package tests

import "core:fmt"
import "core:testing"
import "engine:engine"

main :: proc() {
	fmt.println("=== Running Math Tests ===")

	// Vec2 tests
	v1 := engine.vec2(3, 4)
	assert(v1.x == 3 && v1.y == 4, "vec2 creation failed")

	v2 := engine.vec2(1, 2)
	v3 := engine.vec2_add(v1, v2)
	assert(v3.x == 4 && v3.y == 6, "vec2_add failed")

	v4 := engine.vec2_sub(v1, v2)
	assert(v4.x == 2 && v4.y == 2, "vec2_sub failed")

	v5 := engine.vec2_mul(v1, 2)
	assert(v5.x == 6 && v5.y == 8, "vec2_mul failed")

	len := engine.vec2_len(v1)
	assert(len == 5, "vec2_len failed")

	dot := engine.vec2_dot(v1, v2)
	assert(dot == 11, "vec2_dot failed")

	// Vec2 lerp
	va := engine.vec2(0, 0)
	vb := engine.vec2(10, 20)
	vl := engine.vec2_lerp(va, vb, 0.5)
	assert(vl.x == 5 && vl.y == 10, "vec2_lerp failed")

	// Rect tests
	r1 := engine.rect(0, 0, 100, 100)
	r2 := engine.rect(50, 50, 100, 100)
	assert(engine.rect_intersects(r1, r2), "rect_intersects failed")

	r3 := engine.rect(200, 200, 50, 50)
	assert(!engine.rect_intersects(r1, r3), "rect_intersects should be false")

	p1 := engine.vec2(50, 50)
	assert(engine.rect_contains_point(r1, p1), "rect_contains_point failed")

	p2 := engine.vec2(150, 150)
	assert(!engine.rect_contains_point(r1, p2), "rect_contains_point should be false")

	// Rect intersection
	ri := engine.rect_intersection(r1, r2)
	assert(ri.x == 50 && ri.y == 50 && ri.w == 50 && ri.h == 50, "rect_intersection failed")

	// Clamp tests
	assert(engine.clamp(5, 0, 10) == 5, "clamp middle failed")
	assert(engine.clamp(-5, 0, 10) == 0, "clamp min failed")
	assert(engine.clamp(15, 0, 10) == 10, "clamp max failed")

	// Lerp tests
	assert(engine.lerp(0, 10, 0.5) == 5, "lerp failed")
	assert(engine.lerp(0, 10, 0) == 0, "lerp t=0 failed")
	assert(engine.lerp(0, 10, 1) == 10, "lerp t=1 failed")

	// Approach tests
	assert(engine.approach(0, 10, 3) == 3, "approach failed")
	assert(engine.approach(10, 0, 3) == 7, "approach down failed")
	assert(engine.approach(5, 5, 3) == 5, "approach equal failed")

	// Collision tests
	assert(engine.circle_circle_collision({0, 0}, 5, {3, 4}, 5), "circle_circle_collision failed")
	assert(!engine.circle_circle_collision({0, 0}, 1, {10, 10}, 1), "circle_circle_collision should be false")

	assert(engine.rect_circle_collision(r1, {50, 50}, 10), "rect_circle_collision failed")

	fmt.println("✅ All math tests passed")
}
