package voidengine_test

import "core:testing"
import "core:os"
import engine "../src/core"

@(test)
create_engine_config :: proc(t: ^testing.T) {
    config := engine.EngineConfig{
        title = "Test",
        width = 800,
        height = 600,
        target_fps = 60.0,
        enable_hot_reload = false,
        asset_path = "assets",
    }
    testing.expect(t, config.width == 800, "width should be 800")
    testing.expect(t, config.height == 600, "height should be 600")
}

@test
transform_helper :: proc(t: ^testing.T) {
    transform := engine.make_transform(10.0, 20.0)
    testing.expect(t, transform.position.x == 10.0, "x should be 10")
    testing.expect(t, transform.position.y == 20.0, "y should be 20")
}

@test
sprite_helper :: proc(t: ^testing.T) {
    sprite := engine.make_sprite(32, 64, engine.color(255, 0, 0, 255))
    testing.expect(t, sprite.width == 32, "width should be 32")
    testing.expect(t, sprite.height == 64, "height should be 64")
    testing.expect(t, sprite.color.r == 255, "r should be 255")
}

@test
collision_layer_mask :: proc(t: ^testing.T) {
    layer := engine.CollisionLayer.Player
    mask := engine.CollisionMask{engine.CollisionLayer.Enemy}
    testing.expect(t, layer not_in mask, "player layer should not be in enemy mask")
    testing.expect(t, engine.CollisionLayer.Enemy in mask, "enemy layer should be in mask")
}

@test
collider_creation :: proc(t: ^testing.T) {
    collider := engine.make_collider(16, 16, engine.CollisionLayer.Player,
        engine.CollisionMask{engine.CollisionLayer.Enemy})
    testing.expect(t, collider.width == 16, "width should be 16")
    testing.expect(t, collider.layer == engine.CollisionLayer.Player, "layer should be player")
}

@(test)
entity_components :: proc(t: ^testing.T) {
    scene := engine.Scene{entities = make([dynamic]^engine.Entity)}
    defer engine.scene_cleanup(&scene)

    entity := engine.entity_create(&scene)
    testing.expect(t, entity != nil, "entity should be created")

    transform := new(engine.Transform)
    transform^ = engine.make_transform(5.0, 5.0)
    engine.entity_add_component(entity, engine.Transform, transform)

    retrieved := engine.entity_get_component(entity, engine.Transform)
    testing.expect(t, retrieved != nil, "component should be retrievable")
    testing.expect(t, retrieved.position.x == 5.0, "retrieved x should match")
}

@test
entities_collide_overlap :: proc(t: ^testing.T) {
    scene := engine.Scene{entities = make([dynamic]^engine.Entity)}
    defer engine.scene_cleanup(&scene)

    a := engine.entity_create(&scene)
    ta := new(engine.Transform)
    ta^ = engine.make_transform(0, 0)
    ca := new(engine.Collider)
    ca^ = engine.make_collider(10, 10, engine.CollisionLayer.Player, engine.CollisionMask{engine.CollisionLayer.Enemy})
    engine.entity_add_component(a, engine.Transform, ta)
    engine.entity_add_component(a, engine.Collider, ca)

    b := engine.entity_create(&scene)
    tb := new(engine.Transform)
    tb^ = engine.make_transform(5, 5)
    cb := new(engine.Collider)
    cb^ = engine.make_collider(10, 10, engine.CollisionLayer.Enemy, engine.CollisionMask{engine.CollisionLayer.Player})
    engine.entity_add_component(b, engine.Transform, tb)
    engine.entity_add_component(b, engine.Collider, cb)

    testing.expect(t, engine.entities_collide(a, b), "overlapping entities should collide")
}

@(test)
entities_no_collide_separated :: proc(t: ^testing.T) {
    scene := engine.Scene{entities = make([dynamic]^engine.Entity)}
    defer engine.scene_cleanup(&scene)

    a := engine.entity_create(&scene)
    ta := new(engine.Transform)
    ta^ = engine.make_transform(0, 0)
    ca := new(engine.Collider)
    ca^ = engine.make_collider(10, 10, engine.CollisionLayer.Player, engine.CollisionMask{engine.CollisionLayer.Enemy})
    engine.entity_add_component(a, engine.Transform, ta)
    engine.entity_add_component(a, engine.Collider, ca)

    b := engine.entity_create(&scene)
    tb := new(engine.Transform)
    tb^ = engine.make_transform(100, 100)
    cb := new(engine.Collider)
    cb^ = engine.make_collider(10, 10, engine.CollisionLayer.Enemy, engine.CollisionMask{engine.CollisionLayer.Player})
    engine.entity_add_component(b, engine.Transform, tb)
    engine.entity_add_component(b, engine.Collider, cb)

    testing.expect(t, !engine.entities_collide(a, b), "separated entities should not collide")
}

@(test)
entity_pointers_stay_valid :: proc(t: ^testing.T) {
    // Regression: entity_create used to return pointers into a dynamic
    // array of values — appending more entities could realloc and
    // invalidate previously returned pointers.
    scene := engine.Scene{entities = make([dynamic]^engine.Entity)}
    defer engine.scene_cleanup(&scene)

    first := engine.entity_create(&scene)
    first_id := first.id

    // Force many reallocs of the backing array
    for i in 0..<256 {
        engine.entity_create(&scene)
    }

    testing.expect(t, first.id == first_id, "first entity pointer must stay valid after growth")
    testing.expect(t, first.active, "first entity must still be active")

    transform := new(engine.Transform)
    transform^ = engine.make_transform(42.0, 0.0)
    engine.entity_add_component(first, engine.Transform, transform)
    retrieved := engine.entity_get_component(first, engine.Transform)
    testing.expect(t, retrieved != nil && retrieved.position.x == 42.0,
        "components on early entity must survive array growth")
}

@(test)
math_helpers :: proc(t: ^testing.T) {
    testing.expect(t, engine.clamp(5.0, 0.0, 10.0) == 5.0, "clamp inside range")
    testing.expect(t, engine.clamp(-5.0, 0.0, 10.0) == 0.0, "clamp below")
    testing.expect(t, engine.clamp(15.0, 0.0, 10.0) == 10.0, "clamp above")
    testing.expect(t, engine.lerp(0.0, 10.0, 0.5) == 5.0, "lerp midpoint")
}

// ============================================================================
// Animation
// ============================================================================

@(test)
animation_advances_and_loops :: proc(t: ^testing.T) {
    scene := engine.Scene{entities = make([dynamic]^engine.Entity)}
    defer engine.scene_cleanup(&scene)

    entity := engine.entity_create(&scene)
    frame_arr := [3]i32{0, 1, 2}
    anim := new(engine.Animation)
    anim^ = engine.make_animation(16, 16, 4, frame_arr[:], 0.1, true)
    engine.entity_add_component(entity, engine.Animation, anim)

    engine.animation_update(&scene, 0.15) // 1.5 frames -> current 1
    testing.expect(t, anim.current == 1, "should advance one frame")

    engine.animation_update(&scene, 0.25) // 0.05 carry + 0.25 = 3 advances: 1->2->wrap->1
    testing.expect(t, anim.current == 1, "looping animation should wrap around")
    testing.expect(t, anim.playing, "looped animation should keep playing")
}

@(test)
animation_non_looping_stops :: proc(t: ^testing.T) {
    scene := engine.Scene{entities = make([dynamic]^engine.Entity)}
    defer engine.scene_cleanup(&scene)

    entity := engine.entity_create(&scene)
    frame_arr := [2]i32{0, 1}
    anim := new(engine.Animation)
    anim^ = engine.make_animation(16, 16, 4, frame_arr[:], 0.1, false)
    engine.entity_add_component(entity, engine.Animation, anim)

    engine.animation_update(&scene, 0.5) // way past the end
    testing.expect(t, anim.current == 1, "non-looping animation clamps to last frame")
    testing.expect(t, !anim.playing, "non-looping animation should stop")
}

@(test)
animation_src_rect_mapping :: proc(t: ^testing.T) {
    frame_arr := [1]i32{5}
    anim := engine.make_animation(32, 16, 4, frame_arr[:], 0.1)
    rect := engine.animation_src_rect(&anim)
    // frame 5 with 4 columns -> col 1, row 1
    testing.expect(t, rect.x == 32, "src x should be col * frame_width")
    testing.expect(t, rect.y == 16, "src y should be row * frame_height")
    testing.expect(t, rect.w == 32 && rect.h == 16, "src size should match frame size")
}

// ============================================================================
// Tilemap
// ============================================================================

@(test)
tilemap_csv_load_and_query :: proc(t: ^testing.T) {
    path := "/tmp/voidengine_test_map.csv"
    csv := "1,1,1\n1,0,2\n1,1,1\n"
    write_err := os.write_entire_file_from_bytes(path, transmute([]u8)csv)
    testing.expect(t, write_err == nil, "should write temp CSV")
    defer os.remove(path)

    tm := engine.tilemap_load_csv(path, 16)
    testing.expect(t, tm != nil, "tilemap should load")
    defer engine.tilemap_destroy(tm)

    testing.expect(t, tm.width == 3 && tm.height == 3, "3x3 map")
    testing.expect(t, tm.tile_size == 16, "tile size preserved")
    testing.expect(t, engine.tilemap_get(tm, 1, 1) == 0, "center is empty")
    testing.expect(t, engine.tilemap_get(tm, 2, 1) == 2, "tile id 2 at (2,1)")
    testing.expect(t, engine.tilemap_get(tm, 99, 99) == 0, "out of bounds reads as empty")
}

@(test)
tilemap_solid_collision :: proc(t: ^testing.T) {
    tm := engine.tilemap_create(4, 4, 16)
    defer engine.tilemap_destroy(tm)

    engine.tilemap_set(tm, 2, 2, 1)
    engine.tilemap_set_solid(tm, 1)

    testing.expect(t, engine.tilemap_is_solid(tm, 2, 2), "tile 1 is solid after set_solid")
    testing.expect(t, !engine.tilemap_is_solid(tm, 0, 0), "empty tile is never solid")
    testing.expect(t, engine.tilemap_is_solid_at_world(tm, 40.0, 40.0), "world pos inside tile (2,2)")

    scene := engine.Scene{entities = make([dynamic]^engine.Entity)}
    defer engine.scene_cleanup(&scene)

    entity := engine.entity_create(&scene)
    tr := new(engine.Transform)
    tr^ = engine.make_transform(40, 40) // center of tile (2,2)
    col := new(engine.Collider)
    col^ = engine.make_collider(16, 16, engine.CollisionLayer.Player, engine.CollisionMask{engine.CollisionLayer.Wall})
    engine.entity_add_component(entity, engine.Transform, tr)
    engine.entity_add_component(entity, engine.Collider, col)

    testing.expect(t, engine.tilemap_collide(entity, tm), "entity inside solid tile collides")

    tr.position = {0, 0}
    testing.expect(t, !engine.tilemap_collide(entity, tm), "entity on empty tiles does not collide")
}

// ============================================================================
// Particles
// ============================================================================

@(test)
particle_burst_and_expiry :: proc(t: ^testing.T) {
    scene := engine.Scene{entities = make([dynamic]^engine.Entity)}
    defer engine.scene_cleanup(&scene)

    entity := engine.entity_create(&scene)
    tr := new(engine.Transform)
    tr^ = engine.make_transform(100, 100)
    engine.entity_add_component(entity, engine.Transform, tr)

    emitter := new(engine.ParticleEmitter)
    emitter^ = engine.make_particle_emitter(0, 64) // rate 0: bursts only
    emitter.lifetime_min = 0.5
    emitter.lifetime_max = 0.5
    defer engine.particle_emitter_destroy(emitter)
    engine.entity_add_component(entity, engine.ParticleEmitter, emitter)

    engine.particle_burst(emitter, {100, 100}, 16)
    testing.expect(t, len(emitter.particles) == 16, "burst spawns 16 particles")

    engine.particle_update(&scene, 0.25) // half their lifetime
    testing.expect(t, len(emitter.particles) == 16, "particles still alive mid-life")

    engine.particle_update(&scene, 0.3) // past expiry
    testing.expect(t, len(emitter.particles) == 0, "all particles expired")
}

@(test)
particle_rate_emission :: proc(t: ^testing.T) {
    scene := engine.Scene{entities = make([dynamic]^engine.Entity)}
    defer engine.scene_cleanup(&scene)

    entity := engine.entity_create(&scene)
    emitter := new(engine.ParticleEmitter)
    emitter^ = engine.make_particle_emitter(100, 256) // 100/sec
    emitter.lifetime_min = 10
    emitter.lifetime_max = 10
    defer engine.particle_emitter_destroy(emitter)
    engine.entity_add_component(entity, engine.ParticleEmitter, emitter)

    engine.particle_update(&scene, 0.5) // half a second -> ~50 particles
    count := len(emitter.particles)
    testing.expect(t, count >= 45 && count <= 55, "rate emission lands near 50 after 0.5s")
}
