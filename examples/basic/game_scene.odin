package example

import "core:fmt"
import "core:math"

import obsidon "../../obsidon"
import sh "../../obsidon/shader"

baldman_png: []u8 = #load("assets/baldman.png")
kekw_png: []u8 = #load("assets/kekw.png")
font_bytes: []u8 = #load("assets/font.otf")

@(private = "file")
GameScene :: struct {
    using scene: Scene,

    standard: Shader,
    psx:      Shader,
    wobble:   Shader,

    ground_material: Material,
    crate_material:  Material,
    psx_material:    Material,
    wobble_material: Material,

    plane:  Mesh,
    cube:   Mesh,
    sphere: Mesh,

    checker: Texture,
    kekw:    Texture,

    baldman: Sprite,
    font:    Font,

    yaw:   f64,
    pitch: f64,
    position: Vec3,
}

// A custom shader built from primitives: vertices wave over time,
// colour comes from a parameter, lit per pixel, with fog.
@(private = "file")
make_wobble_shader :: proc() -> Shader {
    sh.begin(name = "wobble")
    world := sh.object_to_world(sh.position())
    wave := sh.mul(sh.sin(sh.add(sh.mul(sh.time(), 3), sh.mul(sh.y(world), 4))), 0.15)
    sh.set_world_position(sh.add(world, sh.vec3(wave, 0, 0)))

    albedo := sh.rgb(sh.param_color("color", {0.3, 0.8, 0.5, 1}))
    lit := sh.mul(albedo, sh.lighting(sh.world_position(), sh.world_normal()))
    lit = sh.add(lit, sh.specular(sh.world_position(), sh.world_normal(), 64))
    sh.set_color(sh.fog(lit, sh.world_position()))
    return obsidon.shader_create(sh.end())
}

@(private = "file")
scene_create :: proc(s: ^Scene) {
    scene := cast(^GameScene)s

    obsidon.set_clear_color(0.45, 0.6, 0.8)
    obsidon.set_ambient_light(obsidon.rgb(0.55, 0.65, 0.85), obsidon.rgb(0.25, 0.2, 0.15), 0.6)
    obsidon.set_sun({-0.5, -1, -0.3}, obsidon.rgb(1, 0.95, 0.85), 2.5)
    obsidon.set_fog(obsidon.rgb(0.45, 0.6, 0.8), 15, 60)

    scene.standard = obsidon.shader_standard()
    scene.psx = obsidon.shader_psx()
    scene.wobble = make_wobble_shader()

    scene.checker = obsidon.texture_checker(64, 8, obsidon.rgb(0.8, 0.8, 0.8), obsidon.rgb(0.5, 0.5, 0.55))
    scene.kekw = obsidon.texture_load(kekw_png)

    scene.ground_material = obsidon.material_create(scene.standard)
    obsidon.material_set_texture(&scene.ground_material, "albedo", &scene.checker)

    scene.crate_material = obsidon.material_create(scene.standard)
    obsidon.material_set_texture(&scene.crate_material, "albedo", &scene.kekw)
    obsidon.material_set_float(&scene.crate_material, "specular", 0.6)

    scene.psx_material = obsidon.material_create(scene.psx)
    obsidon.material_set_texture(&scene.psx_material, "albedo", &scene.kekw)

    scene.wobble_material = obsidon.material_create(scene.wobble)

    scene.plane = obsidon.mesh_plane({40, 40}, 1, 10)
    scene.cube = obsidon.mesh_cube()
    scene.sphere = obsidon.mesh_sphere()

    scene.baldman = obsidon.sprite_load(baldman_png)
    scene.font = obsidon.font_load(font_bytes, 28)

    scene.position = {0, 2, 8}
}

@(private = "file")
scene_update :: proc(s: ^Scene) -> ^Scene {
    scene := cast(^GameScene)s
    dt := obsidon.get_delta_time()

    if obsidon.is_key_pressed(.KEY_ESCAPE) {
        obsidon.quit_game()
        return nil
    }

    // Mouse look + WASD fly camera
    mouse := obsidon.get_mouse_delta()
    scene.yaw -= mouse.x * 0.1
    scene.pitch = math.clamp(scene.pitch + mouse.y * 0.1, -89, 89)
    obsidon.set_camera_euler({scene.pitch, scene.yaw, 0})

    move: Vec3
    if obsidon.is_key_down(.KEY_W) { move += obsidon.get_camera_forward() }
    if obsidon.is_key_down(.KEY_S) { move -= obsidon.get_camera_forward() }
    if obsidon.is_key_down(.KEY_D) { move += obsidon.get_camera_right() }
    if obsidon.is_key_down(.KEY_A) { move -= obsidon.get_camera_right() }
    scene.position += obsidon.vec3_normalize(move) * 6 * dt
    obsidon.set_camera_position(scene.position)

    // Toggle SSAO at runtime
    if obsidon.is_key_pressed(.KEY_F1) {
        gs := obsidon.get_graphics_settings()
        gs.ssao = !gs.ssao
        obsidon.set_graphics_settings(gs)
    }
    return nil
}

@(private = "file")
scene_draw :: proc(s: ^Scene) {
    scene := cast(^GameScene)s
    t := obsidon.get_time()

    obsidon.draw_mesh(&scene.plane, &scene.ground_material, {})
    obsidon.draw_mesh(&scene.cube, &scene.crate_material, {
        position = {-2, 0.5, 0},
        rotation = obsidon.quat_angle_axis(t * 30, obsidon.VEC3_UP),
    })
    obsidon.draw_mesh(&scene.cube, &scene.psx_material, {position = {0, 1, -2}, scale = {2, 2, 2}})
    obsidon.draw_mesh(&scene.sphere, &scene.wobble_material, {position = {2.5, 1, 0}, scale = {1.5, 1.5, 1.5}})
    obsidon.draw_mesh(&scene.sphere, &scene.ground_material, {position = {0, 0.5, 2}}, tint = obsidon.rgb(1, 0.4, 0.3))

    // A light orbiting the scene
    light_pos := Vec3{math.cos(t) * 4, 1.5, math.sin(t) * 4}
    obsidon.add_point_light(light_pos, obsidon.rgb(1, 0.6, 0.2), 3, 6)

    // 2D overlay: sprites and text, (0, 0) is the screen centre
    w := f64(obsidon.get_framebuffer_width())
    h := f64(obsidon.get_framebuffer_height())
    origin := Vec2{f64(scene.baldman.width) / 2, f64(scene.baldman.height) / 2}
    obsidon.sprite_draw(&scene.baldman, obsidon.get_mouse_position(), origin, 0, false, 0.25)
    obsidon.text_draw(&scene.font, fmt.tprintf("Hello, Obsidon 3D!  %.0f fps", 1 / max(obsidon.get_delta_time(), 0.0001)), {-w / 2 + 8, h / 2 - 20}, 0.6, obsidon.WHITE)
}

@(private = "file")
scene_destroy :: proc(s: ^Scene) {
    scene := cast(^GameScene)s
    obsidon.font_destroy(&scene.font)
    obsidon.sprite_destroy(&scene.baldman)
    obsidon.mesh_destroy(&scene.plane)
    obsidon.mesh_destroy(&scene.cube)
    obsidon.mesh_destroy(&scene.sphere)
    obsidon.texture_destroy(&scene.checker)
    obsidon.texture_destroy(&scene.kekw)
    obsidon.material_destroy(&scene.ground_material)
    obsidon.material_destroy(&scene.crate_material)
    obsidon.material_destroy(&scene.psx_material)
    obsidon.material_destroy(&scene.wobble_material)
    obsidon.shader_destroy(scene.standard)
    obsidon.shader_destroy(scene.psx)
    obsidon.shader_destroy(scene.wobble)
}

create_game_scene :: proc() -> ^Scene {
    scene := new(GameScene)
    scene.on_create = scene_create
    scene.on_update = scene_update
    scene.on_draw = scene_draw
    scene.on_destroy = scene_destroy
    return scene
}
