package main

import "core:fmt"
import "core:log"
import "base:runtime"

import obsidon "../src"

MyScene :: struct {
    using scene: obsidon.Scene,
    counter: int,
}

my_scene_create :: proc(s: ^obsidon.Scene) {
    my_scene := cast(^MyScene)s
    my_scene.counter += 1
    // custom logic here
    log.info("create")
}

my_scene_update :: proc(s: ^obsidon.Scene, dt: f32) -> ^obsidon.Scene {
    my_scene := cast(^MyScene)s
    my_scene.counter += 1
    // custom logic here

    return nil
}

my_scene_draw :: proc(s: ^obsidon.Scene, dt: f32) {
    my_scene := cast(^MyScene)s
    my_scene.counter += 1
    // custom logic here
}

my_scene_destroy :: proc(s: ^obsidon.Scene) {
    my_scene := cast(^MyScene)s
    my_scene.counter += 1
    // custom logic here
    log.info("destroy")
}

create_scene :: proc() -> ^MyScene {
    my_scene := new(MyScene)
    my_scene.on_create = my_scene_create
    my_scene.on_update = my_scene_update
    my_scene.on_draw = my_scene_draw
    my_scene.on_destroy = my_scene_destroy
    my_scene.counter = 0
    return my_scene
}

main :: proc() {
    context = runtime.default_context()
    context.logger = log.create_console_logger()

    scene := create_scene()

    obsidon.run_game("game", 800, 600, scene)
}