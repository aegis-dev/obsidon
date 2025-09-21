package main

import "base:runtime"

import "core:fmt"
import "core:log"

import obsidon "../src"

// Aliases for convenience
Vec2 :: obsidon.Vec2
Vec4 :: obsidon.Vec4
Sprite :: obsidon.Sprite
Font :: obsidon.Font
Scene :: obsidon.Scene
Sound :: obsidon.Sound
Key :: obsidon.Key
Button :: obsidon.Button

baldman_png: []u8 = #load("assets/baldman.png");
kekw_png: []u8 = #load("assets/kekw.png");
font_bytes: []u8 = #load("assets/font.otf");

MyScene :: struct {
    using scene: Scene,
    baldman_sprite: Sprite,
    kekw_sprite: Sprite,
    font: Font,
    fart: Sound,

    position: Vec2,
    baldman_origin: Vec2,
    kekw_origin: Vec2,

    angle: f32,
    flip: bool,
}

my_scene_create :: proc(s: ^Scene) {
    my_scene := cast(^MyScene)s

    obsidon.set_clear_color(0.1, 0.2, 0.3, 1.0)

    my_scene.baldman_sprite = obsidon.sprite_load(baldman_png)
    my_scene.kekw_sprite = obsidon.sprite_load(kekw_png)
    my_scene.font = obsidon.font_load(font_bytes, 56.0)
 
    my_scene.position = Vec2{0.0, 0.0}
    my_scene.baldman_origin = Vec2{f32(my_scene.baldman_sprite.width) / 2, f32(my_scene.baldman_sprite.height) / 2}
    my_scene.kekw_origin = Vec2{f32(my_scene.kekw_sprite.width) / 2, f32(my_scene.kekw_sprite.height) / 2}
    // my_scene.fart = obsidon.sound_load_from_file("C:\\Users\\elile\\Desktop\\Git\\obsidon\\example\\assets\\fart.wav")
    // my_scene.origin = Vec2{0.0, 0.0}

    // obsidon.set_sprite_color_override(Vec4{0.0, 1.0, 0.0, 0.8})
    // obsidon.set_screen_color_override(Vec4{0.0, 1.0, 0.0, 0.3})
}

my_scene_update :: proc(s: ^Scene) -> ^Scene {
    my_scene := cast(^MyScene)s

    dt := obsidon.get_delta_time()

    if obsidon.is_key_pressed(Key.KEY_ESCAPE) {
        obsidon.quit_game()
        return nil
    }

    if obsidon.is_key_down(Key.KEY_D) {
        my_scene.position.x += 50 * dt
    } else if obsidon.is_key_down(Key.KEY_A) {
        my_scene.position.x -= 50 * dt 
    }
    
    if obsidon.is_key_down(Key.KEY_W) {
        my_scene.position.y += 50 * dt
    } else if obsidon.is_key_down(Key.KEY_S) {
        my_scene.position.y -= 50 * dt 
    }

    if obsidon.is_key_pressed(Key.KEY_SPACE) {
        my_scene.flip = !my_scene.flip
        // obsidon.sound_play(&my_scene.fart)
        obsidon.sound_play_immediate("C:\\Users\\elile\\Desktop\\Git\\obsidon\\example\\assets\\fart.wav")
    }

    my_scene.angle += 50 * dt

    return nil
}

my_scene_draw :: proc(s: ^Scene) {
    my_scene := cast(^MyScene)s

    obsidon.sprite_draw(&my_scene.kekw_sprite, my_scene.position, my_scene.kekw_origin, my_scene.angle, my_scene.flip, 1.0)
    obsidon.sprite_draw(&my_scene.baldman_sprite, obsidon.get_mouse_position() + obsidon.get_camera_position(), my_scene.baldman_origin, 0.0, false, 1.0)

    text := "Hello, Obsidon!\nThis is a test of the text rendering system.\n1234567890\n!@#$%^&*()_+-=[]{}|;':\",.<>/?`~"
    obsidon.text_draw(&my_scene.font, text, Vec2{-200.0, 0.0}, 0.5, Vec4{1.0, 0.0, 0.0, 1.0})
}

my_scene_destroy :: proc(s: ^Scene) {
    my_scene := cast(^MyScene)s

    obsidon.sprite_destroy(&my_scene.baldman_sprite)
    obsidon.sprite_destroy(&my_scene.kekw_sprite)
    obsidon.font_destroy(&my_scene.font)
}

create_scene :: proc() -> ^Scene {
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