package example

import obsidon "../obsidon"

baldman_png: []u8 = #load("assets/baldman.png")
kekw_png: []u8 = #load("assets/kekw.png")
font_bytes: []u8 = #load("assets/font.otf")

@(private="file")
GameScene :: struct {
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

@(private="file")
scene_create :: proc(s: ^Scene) {
    scene := cast(^GameScene)s

    obsidon.set_clear_color(0.1, 0.2, 0.3, 1.0)

    scene.baldman_sprite = obsidon.sprite_load(baldman_png)
    scene.kekw_sprite = obsidon.sprite_load(kekw_png)
    scene.font = obsidon.font_load(font_bytes, 56.0)
 
    scene.position = Vec2{0.0, 0.0}
    scene.baldman_origin = Vec2{f32(scene.baldman_sprite.width) / 2, f32(scene.baldman_sprite.height) / 2}
    scene.kekw_origin = Vec2{f32(scene.kekw_sprite.width) / 2, f32(scene.kekw_sprite.height) / 2}
    // my_scene.fart = obsidon.sound_load_from_file("C:\\Users\\elile\\Desktop\\Git\\obsidon\\example\\assets\\fart.wav")

    // obsidon.set_screen_color_override(Vec4{0.0, 1.0, 0.0, 0.3})
}

@(private="file")
scene_update :: proc(s: ^Scene) -> ^Scene {
    scene := cast(^GameScene)s

    dt := obsidon.get_delta_time()

    if obsidon.is_key_pressed(Key.KEY_ESCAPE) {
        obsidon.quit_game()
        return nil
    }

    if obsidon.is_key_down(Key.KEY_D) {
        scene.position.x += 50 * dt
    } else if obsidon.is_key_down(Key.KEY_A) {
        scene.position.x -= 50 * dt 
    }
    
    if obsidon.is_key_down(Key.KEY_W) {
        scene.position.y += 50 * dt
    } else if obsidon.is_key_down(Key.KEY_S) {
        scene.position.y -= 50 * dt 
    }

    if obsidon.is_key_pressed(Key.KEY_SPACE) {
        scene.flip = !scene.flip
        // obsidon.sound_play(&my_scene.fart)
        obsidon.sound_play_immediate("C:\\Users\\elile\\Desktop\\Git\\obsidon\\example\\assets\\fart.wav")
    }

    scene.angle += 50 * dt

    return nil
}

@(private="file")
scene_draw :: proc(s: ^Scene) {
    scene := cast(^GameScene)s

    obsidon.sprite_draw(&scene.kekw_sprite, scene.position, scene.kekw_origin, scene.angle, scene.flip, 1.0)
    obsidon.sprite_draw(&scene.baldman_sprite, obsidon.get_mouse_position() + obsidon.get_camera_position(), scene.baldman_origin, 0.0, false, 1.0)

    text := "Hello, Obsidon!\nThis is a test of the text rendering system.\n1234567890\n!@#$%^&*()_+-=[]{}|':\",.<>/?`~"
    obsidon.text_draw(&scene.font, text, Vec2{-200.0, 0.0}, 0.5, Vec4{1.0, 0.0, 0.0, 1.0})
}

@(private="file")
scene_destroy :: proc(s: ^Scene) {
    scene := cast(^GameScene)s

    obsidon.sprite_destroy(&scene.baldman_sprite)
    obsidon.sprite_destroy(&scene.kekw_sprite)
    obsidon.font_destroy(&scene.font)
}

create_game_scene :: proc() -> ^Scene {
    scene := new(GameScene)
    scene.on_create = scene_create
    scene.on_update = scene_update
    scene.on_draw = scene_draw
    scene.on_destroy = scene_destroy
    return scene
}
