package main

import "core:fmt"
import "core:log"
import "base:runtime"

import obsidon "../src"

kekw_png: []u8 = #load("assets/baldman.png");
font_bytes: []u8 = #load("assets/font.otf");

MyScene :: struct {
    using scene: obsidon.Scene,
    kekw_sprite: obsidon.Sprite,
    font: obsidon.Font,

    position: obsidon.Vec2,
    origin: obsidon.Vec2,
    angle: f32,
    flip: bool,
}

my_scene_create :: proc(s: ^obsidon.Scene) {
    my_scene := cast(^MyScene)s

    obsidon.set_clear_color(0.1, 0.2, 0.3, 1.0)

    my_scene.font = obsidon.font_load(font_bytes, 56.0)

    my_scene.kekw_sprite = obsidon.sprite_load(kekw_png)

    my_scene.position = obsidon.Vec2{0.0, 0.0}
    my_scene.origin = obsidon.Vec2{f32(my_scene.kekw_sprite.width) / 2, f32(my_scene.kekw_sprite.height) / 2}
    // my_scene.origin = obsidon.Vec2{0.0, 0.0}

    // obsidon.set_sprite_color_override(obsidon.Vec4{0.0, 1.0, 0.0, 0.8})
    // obsidon.set_screen_color_override(obsidon.Vec4{0.0, 1.0, 0.0, 0.3})
}

my_scene_update :: proc(s: ^obsidon.Scene, dt: f32) -> ^obsidon.Scene {
    my_scene := cast(^MyScene)s

    if obsidon.is_key_pressed(obsidon.Key.KEY_ESCAPE) {
        obsidon.quit_game()
        return nil
    }

    if obsidon.is_key_down(obsidon.Key.KEY_D) {
        my_scene.position.x += 50 * dt
    } else if obsidon.is_key_down(obsidon.Key.KEY_A) {
        my_scene.position.x -= 50 * dt 
    }
    
    if obsidon.is_key_down(obsidon.Key.KEY_W) {
        my_scene.position.y += 50 * dt
    } else if obsidon.is_key_down(obsidon.Key.KEY_S) {
        my_scene.position.y -= 50 * dt 
    }

    if obsidon.is_key_pressed(obsidon.Key.KEY_SPACE) {
       my_scene.flip = !my_scene.flip
    }

    my_scene.angle += 50 * dt

    return nil
}

my_scene_draw :: proc(s: ^obsidon.Scene, dt: f32) {
    my_scene := cast(^MyScene)s

    obsidon.sprite_draw(&my_scene.kekw_sprite, my_scene.position, my_scene.origin, my_scene.angle, my_scene.flip, 1.0)

    obsidon.sprite_draw(&my_scene.kekw_sprite, obsidon.get_mouse_position(), my_scene.origin, 0.0, false, 1.0)

    text := "Hello, Obsidon!\nThis is a test of the text rendering system.\n1234567890\n!@#$%^&*()_+-=[]{}|;':\",.<>/?`~"
    obsidon.text_draw(&my_scene.font, text, obsidon.Vec2{-200.0, 0.0}, 0.5, obsidon.Vec4{1.0, 0.0, 0.0, 1.0})
}

my_scene_destroy :: proc(s: ^obsidon.Scene) {
    my_scene := cast(^MyScene)s
    // custom logic here
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