package main

import "core:fmt"
import "core:log"
import "base:runtime"

import obsidon "../src"

kekw_png: []u8 = #load("assets/baldman.png");

MyScene :: struct {
    using scene: obsidon.Scene,
    kekw_sprite: obsidon.Sprite,

    position: obsidon.Vec2,
    origin: obsidon.Vec2,
    angle: f32,
}

my_scene_create :: proc(s: ^obsidon.Scene) {
    my_scene := cast(^MyScene)s

    obsidon.set_clear_color(0.1, 0.2, 0.3, 1.0)

    my_scene.kekw_sprite = obsidon.sprite_load(kekw_png)

    my_scene.position = obsidon.Vec2{0.0, 0.0}
    my_scene.origin = obsidon.Vec2{f32(my_scene.kekw_sprite.width) / 2, f32(my_scene.kekw_sprite.height) / 2}
    // my_scene.origin = obsidon.Vec2{0.0, 0.0}

    // obsidon.set_sprite_color_override(obsidon.Vec4{0.0, 1.0, 0.0, 0.8})
    // obsidon.set_screen_color_override(obsidon.Vec4{0.0, 1.0, 0.0, 0.3})
}

my_scene_update :: proc(s: ^obsidon.Scene, dt: f32) -> ^obsidon.Scene {
    my_scene := cast(^MyScene)s

    // my_scene.position.x += 50 * dt
    my_scene.position.y += 20 * dt
    my_scene.angle += 50 * dt

    return nil
}

my_scene_draw :: proc(s: ^obsidon.Scene, dt: f32) {
    my_scene := cast(^MyScene)s

    obsidon.sprite_draw(&my_scene.kekw_sprite, my_scene.position, my_scene.origin, my_scene.angle, false, 1.0)
}

my_scene_destroy :: proc(s: ^obsidon.Scene) {
    my_scene := cast(^MyScene)s
    // custom logic here
    log.info("destroy")
}

create_scene :: proc() -> ^MyScene {
    my_scene := new(MyScene)
    my_scene.on_create = my_scene_create
    my_scene.on_update = my_scene_update
    my_scene.on_draw = my_scene_draw
    my_scene.on_destroy = my_scene_destroy
    return my_scene
}

main :: proc() {
    context = runtime.default_context()
    context.logger = log.create_console_logger()

    scene := create_scene()

    obsidon.run_game("game", 800, 600, scene)
}