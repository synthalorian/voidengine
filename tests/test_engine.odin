package voidengine_test

import "core:testing"
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
    scene := engine.Scene{entities = make([dynamic]engine.Entity)}
    defer delete(scene.entities)

    entity := engine.entity_create(&scene)
    testing.expect(t, entity != nil, "entity should be created")

    transform := new(engine.Transform)
    transform^ = engine.make_transform(5.0, 5.0)
    engine.entity_add_component(entity, engine.Transform, transform)

    retrieved := engine.entity_get_component(entity, engine.Transform)
    testing.expect(t, retrieved != nil, "component should be retrievable")
    testing.expect(t, retrieved.position.x == 5.0, "retrieved x should match")

    free(transform)
}

@test
entities_collide_overlap :: proc(t: ^testing.T) {
    scene := engine.Scene{entities = make([dynamic]engine.Entity)}
    defer delete(scene.entities)

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

    free(ta); free(ca)
    free(tb); free(cb)
}

@(test)
entities_no_collide_separated :: proc(t: ^testing.T) {
    scene := engine.Scene{entities = make([dynamic]engine.Entity)}
    defer delete(scene.entities)

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

    free(ta); free(ca)
    free(tb); free(cb)
}

@(test)
math_helpers :: proc(t: ^testing.T) {
    testing.expect(t, engine.clamp(5.0, 0.0, 10.0) == 5.0, "clamp inside range")
    testing.expect(t, engine.clamp(-5.0, 0.0, 10.0) == 0.0, "clamp below")
    testing.expect(t, engine.clamp(15.0, 0.0, 10.0) == 10.0, "clamp above")
    testing.expect(t, engine.lerp(0.0, 10.0, 0.5) == 5.0, "lerp midpoint")
}
