package main

import "core:fmt"
import "core:math"
import "core:math/rand"

import obsidon "../../obsidon"

font_data := #load("assets/font.otf")

PLANET_POSITION     :: Vec3{900, -350, -2600}
PLANET_RADIUS       :: 700.0
GAS_GIANT_POSITION  :: Vec3{-5200, 1400, -9000}
GAS_GIANT_RADIUS    :: 1500.0
STATION_POSITION    :: Vec3{0, 0, 0}
ASTEROID_COUNT      :: 160

Asteroid :: struct {
    transform: Transform,
    spin_axis: Vec3,
    spin:      f64,
    mesh:      int,
}

Ship :: struct {
    transform: Transform,
    velocity:  Vec3,
    throttle:  f64,
}

Flight_Scene :: struct {
    using scene: Scene,

    // Shaders
    standard_shader:  Shader,
    psx_shader:       Shader,
    terran_shader:    Shader,
    cloud_shader:     Shader,
    gas_giant_shader: Shader,
    sky_shader:       Shader,
    glow_shader:      Shader,
    dither_shader:    Shader,
    vignette_shader:  Shader,

    // Materials
    hull_material:      Material,
    trim_material:      Material,
    paint_material:     Material,
    station_material:   Material,
    deck_material:      Material,
    asteroid_material:  Material,
    terran_material:    Material,
    cloud_material:     Material,
    gas_giant_material: Material,
    sky_material:       Material,
    glow_material:      Material,
    beacon_material:    Material,
    dither_material:    Material,
    vignette_material:  Material,

    // Meshes
    cube:       Mesh,
    sphere:     Mesh,
    cylinder:   Mesh,
    sky_sphere: Mesh,
    asteroids:  [4]Mesh,

    // Textures
    checker:     Texture,
    deck_tiles:  Texture,
    panels:      Texture,
    rock:        Texture,

    font: Font,

    ship:       Ship,
    rocks:      [ASTEROID_COUNT]Asteroid,
    camera_pos: Vec3,
    camera_rot: Quat,
    frames:     int,
    fps:        f64,
    post_on:    bool,
}

create_flight_scene :: proc() -> ^Scene {
    scene := new(Flight_Scene)
    bind_flight_scene(scene)
    return scene
}

// Scene callbacks.
bind_flight_scene :: proc(s: ^Scene) {
    s.on_create = flight_create
    s.on_update = flight_update
    s.on_draw = flight_draw
    s.on_destroy = flight_destroy
    s.on_reload = flight_reload
}

// After a hot reload: swap in the new code of our custom shaders. Materials
// keep their parameter values and textures.
@(private = "file")
flight_reload :: proc(s: ^Scene) {
    scene := cast(^Flight_Scene)s
    obsidon.shader_rebuild(scene.terran_shader, describe_terran_planet())
    obsidon.shader_rebuild(scene.cloud_shader, describe_cloud())
    obsidon.shader_rebuild(scene.gas_giant_shader, describe_gas_giant())
    obsidon.shader_rebuild(scene.sky_shader, describe_sky())
    obsidon.shader_rebuild(scene.glow_shader, describe_glow())
}

@(private = "file")
flight_create :: proc(s: ^Scene) {
    scene := cast(^Flight_Scene)s

    // ---- Lighting: a hemisphere ambient, the sun, no fog in space.
    obsidon.set_clear_color(0, 0, 0, 1)
    obsidon.set_ambient_light(obsidon.rgb(0.18, 0.22, 0.32), obsidon.rgb(0.06, 0.05, 0.05), 1)
    obsidon.set_sun({-0.55, -0.45, -0.7}, obsidon.rgb(1.0, 0.95, 0.88), 2.4)
    if options.no_sun {
        obsidon.set_sun_enabled(false)
    }
    obsidon.set_camera_fov(70)
    obsidon.set_camera_clip(0.1) // infinite far plane

    // ---- Shaders: built-in ones and our own (see shaders.odin)
    scene.standard_shader = obsidon.shader_standard()
    scene.psx_shader = obsidon.shader_psx(obsidon.Psx_Shader_Options{
        snap_resolution = {320, 180},
        affine_textures = true,
        vertex_lighting = true,
        color_levels    = 0, // dithering is done as a post effect below
    })
    scene.terran_shader = obsidon.shader_create(describe_terran_planet())
    scene.cloud_shader = obsidon.shader_create(describe_cloud())
    scene.gas_giant_shader = obsidon.shader_create(describe_gas_giant())
    scene.sky_shader = obsidon.shader_create(describe_sky())
    scene.glow_shader = obsidon.shader_create(describe_glow())
    scene.dither_shader = obsidon.shader_post_dither()
    scene.vignette_shader = obsidon.shader_post_vignette()

    // ---- Textures
    scene.checker = obsidon.texture_checker(64, 8, obsidon.rgb(0.75, 0.76, 0.8), obsidon.rgb(0.55, 0.57, 0.62))
    scene.deck_tiles = obsidon.texture_checker(64, 4, obsidon.rgb(0.42, 0.43, 0.47), obsidon.rgb(0.3, 0.31, 0.35))
    scene.rock = make_rock_texture()
    scene.panels = make_panel_normal_map()

    // ---- Materials
    scene.hull_material = obsidon.material_create(scene.standard_shader)
    obsidon.material_set_texture(&scene.hull_material, "albedo", &scene.checker)
    obsidon.material_set_color(&scene.hull_material, "color", obsidon.rgb(0.85, 0.87, 0.9))
    obsidon.material_set_float(&scene.hull_material, "specular", 0.6)
    obsidon.material_set_texture(&scene.hull_material, "normal", &scene.panels)

    scene.trim_material = obsidon.material_create(scene.standard_shader)
    obsidon.material_set_color(&scene.trim_material, "color", obsidon.color_hex(0xD9822B))

    scene.paint_material = obsidon.material_create(scene.standard_shader)
    obsidon.material_set_texture(&scene.paint_material, "albedo", &scene.deck_tiles)
    obsidon.material_set_float(&scene.paint_material, "specular", 0.2)

    scene.station_material = obsidon.material_create(scene.standard_shader)
    obsidon.material_set_texture(&scene.station_material, "albedo", &scene.checker)
    obsidon.material_set_color(&scene.station_material, "color", obsidon.rgb(0.7, 0.72, 0.78))

    scene.deck_material = obsidon.material_create(scene.standard_shader)
    obsidon.material_set_texture(&scene.deck_material, "albedo", &scene.deck_tiles)
    obsidon.material_set_texture(&scene.deck_material, "normal", &scene.panels)
    obsidon.material_set_vec2(&scene.deck_material, "uv_scale", {3, 3})
    obsidon.material_set_float(&scene.deck_material, "specular", 0.35)

    scene.asteroid_material = obsidon.material_create(scene.psx_shader)
    obsidon.material_set_texture(&scene.asteroid_material, "albedo", &scene.rock)

    scene.terran_material = obsidon.material_create(scene.terran_shader)
    scene.cloud_material = obsidon.material_create(scene.cloud_shader)
    scene.gas_giant_material = obsidon.material_create(scene.gas_giant_shader)
    scene.sky_material = obsidon.material_create(scene.sky_shader)

    scene.glow_material = obsidon.material_create(scene.glow_shader)
    scene.beacon_material = obsidon.material_create(scene.glow_shader)
    obsidon.material_set_color(&scene.beacon_material, "color", obsidon.rgb(1, 0.15, 0.1))
    obsidon.material_set_float(&scene.beacon_material, "pulse_speed", 4)
    obsidon.material_set_float(&scene.beacon_material, "strength", 8)

    // ---- Post processing: PS1-ish colour depth + vignette, after tonemapping.
    scene.dither_material = obsidon.material_create(scene.dither_shader)
    obsidon.material_set_float(&scene.dither_material, "levels", 32)
    scene.vignette_material = obsidon.material_create(scene.vignette_shader)
    obsidon.material_set_float(&scene.vignette_material, "strength", 0.45)
    if !options.no_post {
        obsidon.post_effect_add(&scene.dither_material)
        obsidon.post_effect_add(&scene.vignette_material)
        scene.post_on = true
    }

    // ---- Meshes
    scene.cube = obsidon.mesh_cube()
    scene.sphere = obsidon.mesh_sphere(0.5, 48, 32)
    scene.cylinder = obsidon.mesh_cylinder(0.5, 1, 32)
    scene.sky_sphere = obsidon.mesh_sphere(1, 32, 16)
    for i in 0..<len(scene.asteroids) {
        scene.asteroids[i] = make_asteroid_mesh(u64(i + 1))
    }

    scene.font = obsidon.font_load(font_data, 28)

    // ---- World
    rng := rand.create(1337)
    context.random_generator = rand.default_random_generator(&rng)
    for &a in scene.rocks {
        // A belt between the station and the planet.
        angle := rand.float64_range(0, 2 * math.PI)
        dist := rand.float64_range(70, 420)
        a.transform.position = {math.cos(angle) * dist, rand.float64_range(-40, 40), math.sin(angle) * dist - 150}
        size := math.pow(rand.float64_range(0.2, 1), 3) * 22 + 1.2
        a.transform.scale = {size, size * rand.float64_range(0.7, 1.1), size * rand.float64_range(0.8, 1.2)}
        a.transform.rotation = obsidon.quat_from_euler({rand.float64_range(0, 360), rand.float64_range(0, 360), 0})
        a.spin_axis = obsidon.vec3_normalize({rand.float64_range(-1, 1), rand.float64_range(-1, 1), rand.float64_range(-1, 1)})
        a.spin = rand.float64_range(-12, 12)
        a.mesh = rand.int_max(len(scene.asteroids))
    }

    scene.ship.transform = obsidon.transform_make(position = {0, 9, 32})
    scene.camera_pos = scene.ship.transform.position + {0, 3, 12}
    scene.camera_rot = obsidon.QUAT_IDENTITY
}

@(private = "file")
flight_update :: proc(s: ^Scene) -> ^Scene {
    scene := cast(^Flight_Scene)s
    dt := obsidon.get_delta_time()
    scene.frames += 1
    if dt > 0 {
        scene.fps = scene.fps * 0.95 + (1.0 / dt) * 0.05
    }

    if obsidon.is_key_pressed(.KEY_ESCAPE) {
        obsidon.quit_game()
        return nil
    }

    handle_debug_keys(scene)
    if options.settings_test {
        run_settings_test(scene.frames)
    }

    for &a in scene.rocks {
        obsidon.transform_rotate(&a.transform, a.spin_axis, a.spin * dt)
    }

    if options.view > 0 {
        setup_fixed_view(scene, options.view)
    } else {
        fly_ship(scene, dt)
        chase_camera(scene, dt)
    }

    if options.screenshot != "" {
        if scene.frames == options.frames {
            obsidon.save_screenshot(options.screenshot, options.window_shot)
        } else if scene.frames > options.frames {
            obsidon.quit_game()
        }
    }
    return nil
}

@(private = "file")
fly_ship :: proc(scene: ^Flight_Scene, dt: f64) {
    ship := &scene.ship
    t := &ship.transform

    // Mouse steers (pitch / yaw), Q/E roll.
    mouse := obsidon.get_mouse_delta()
    if obsidon.is_cursor_locked() {
        obsidon.transform_rotate_local(t, obsidon.VEC3_UP, -mouse.x * 0.08)
        obsidon.transform_rotate_local(t, obsidon.VEC3_RIGHT, mouse.y * 0.08)
    }
    roll := 0.0
    if obsidon.is_key_down(.KEY_Q) { roll += 1 }
    if obsidon.is_key_down(.KEY_E) { roll -= 1 }
    obsidon.transform_rotate_local(t, {0, 0, -1}, roll * 90 * dt)

    // W/S throttle, A/D strafe, Space/Ctrl up/down, Shift boost.
    if obsidon.is_key_down(.KEY_W) { ship.throttle = min(ship.throttle + dt * 0.8, 1) }
    if obsidon.is_key_down(.KEY_S) { ship.throttle = max(ship.throttle - dt * 0.8, -0.3) }
    boost := 4.0 if obsidon.is_key_down(.KEY_LEFT_SHIFT) else 1.0

    forward := obsidon.transform_forward(t^)
    right := obsidon.transform_right(t^)
    up := obsidon.transform_up(t^)
    thrust := forward * ship.throttle * 40 * boost
    if obsidon.is_key_down(.KEY_D) { thrust += right * 15 }
    if obsidon.is_key_down(.KEY_A) { thrust -= right * 15 }
    if obsidon.is_key_down(.KEY_SPACE) { thrust += up * 15 }
    if obsidon.is_key_down(.KEY_LEFT_CONTROL) { thrust -= up * 15 }

    ship.velocity += thrust * dt
    ship.velocity *= math.pow(0.6, dt) // space drag, for playability
    t.position += ship.velocity * dt
}

@(private = "file")
chase_camera :: proc(scene: ^Flight_Scene, dt: f64) {
    t := scene.ship.transform
    target := t.position + obsidon.quat_rotate(obsidon.transform_rotation(t), {0, 2.4, 9})
    follow := 1 - math.pow(0.0005, dt)
    scene.camera_pos = obsidon.vec3_lerp(scene.camera_pos, target, follow)
    scene.camera_rot = obsidon.quat_slerp(scene.camera_rot, obsidon.transform_rotation(t), 1 - math.pow(0.002, dt))
    obsidon.set_camera_position(scene.camera_pos)
    obsidon.set_camera_rotation(scene.camera_rot)
}

// Fixed camera presets, used for automated screenshots.
@(private = "file")
setup_fixed_view :: proc(scene: ^Flight_Scene, view: int) {
    ship := &scene.ship.transform
    switch view {
    case 1: // Station deck with the ship hovering above (shadows + SSAO).
        ship.position = {6, 7, 14}
        ship.rotation = obsidon.quat_from_euler({-5, 35, 10})
        obsidon.set_camera_position({28, 14, -22})
        obsidon.camera_look_at({0, 2, 0})
    case 2: // Looking out at the planets past the asteroid belt.
        ship.position = {10, 30, 60}
        ship.rotation = obsidon.quat_look_rotation(PLANET_POSITION - ship.position)
        obsidon.set_camera_position(ship.position + {-4, 3, 14})
        obsidon.camera_look_at(PLANET_POSITION * 0.02 + ship.position * 0.98)
    case 3: // Close to the planet.
        obsidon.set_camera_position(PLANET_POSITION + {-900, 700, 1000})
        obsidon.camera_look_at(PLANET_POSITION)
    case 4: // Top down over the deck (debugging)
        ship.position = {6, 7, 14}
        obsidon.set_camera_position({0, 60, 0.01})
        obsidon.camera_look_at({0, 0, 0}, {0, 0, -1})
    case 6: // Top down, ship inside the floodlight cone (spot light shadows)
        ship.position = {1.5, 6, 9}
        ship.rotation = obsidon.quat_from_euler({0, 30, 0})
        obsidon.set_camera_position({0, 60, 0.01})
        obsidon.camera_look_at({0, 0, 0}, {0, 0, -1})
    case:   // Chase view
        ship.position = {0, 9, 32}
        obsidon.set_camera_position(ship.position + {0, 2.4, 9})
        obsidon.camera_look_at(ship.position + {0, 1, -10})
    }
}

@(private = "file")
handle_debug_keys :: proc(scene: ^Flight_Scene) {
    gs := obsidon.get_graphics_settings()
    changed := false
    if obsidon.is_key_pressed(.KEY_F1) { gs.ssao = !gs.ssao; changed = true }
    if obsidon.is_key_pressed(.KEY_F2) { gs.shadows = !gs.shadows; changed = true }
    if obsidon.is_key_pressed(.KEY_F3) {
        gs.shadow_resolution = obsidon.Shadow_Resolution((int(gs.shadow_resolution) + 1) % len(obsidon.Shadow_Resolution))
        changed = true
    }
    if obsidon.is_key_pressed(.KEY_F4) {
        gs.resolution = .Native if gs.resolution != .Native else .R640x360
        changed = true
    }
    if obsidon.is_key_pressed(.KEY_F5) {
        gs.texture_filter = .Linear if gs.texture_filter == .Nearest else .Nearest
        changed = true
    }
    if changed {
        obsidon.set_graphics_settings(gs)
    }
    if obsidon.is_key_pressed(.KEY_F6) {
        scene.post_on = !scene.post_on
        obsidon.post_effect_set_enabled(&scene.dither_material, scene.post_on)
        obsidon.post_effect_set_enabled(&scene.vignette_material, scene.post_on)
    }
    if obsidon.is_key_pressed(.KEY_TAB) {
        obsidon.set_cursor_locked(!obsidon.is_cursor_locked())
    }
    if obsidon.is_key_pressed(.KEY_F12) {
        obsidon.save_screenshot("screenshot.png")
    }
}

@(private = "file")
flight_draw :: proc(s: ^Scene) {
    scene := cast(^Flight_Scene)s
    time := obsidon.get_time()
    camera := obsidon.get_camera_position()

    // ---- Sky: a big sphere around the camera
    obsidon.draw_mesh(&scene.sky_sphere, &scene.sky_material, {position = camera, scale = {5000, 5000, 5000}})

    // ---- Procedural planets
    planet_spin := obsidon.quat_angle_axis(time * 0.6, {0.1, 1, 0.05})
    obsidon.draw_mesh(&scene.sphere, &scene.terran_material, {
        position = PLANET_POSITION,
        rotation = planet_spin,
        scale    = PLANET_RADIUS * 2,
    })
    obsidon.draw_mesh(&scene.sphere, &scene.cloud_material, {
        position = PLANET_POSITION,
        rotation = obsidon.quat_angle_axis(time * 0.9, {0.1, 1, 0.05}),
        scale    = PLANET_RADIUS * 2 * 1.012,
    })
    obsidon.draw_mesh(&scene.sphere, &scene.gas_giant_material, {
        position = GAS_GIANT_POSITION,
        rotation = obsidon.quat_from_euler({18, time * 0.3, 8}),
        scale    = GAS_GIANT_RADIUS * 2,
    })

    // ---- Station
    draw_station(scene, time)

    // ---- Asteroids: one instanced draw per asteroid shape
    for &mesh, shape in scene.asteroids {
        batch := make([dynamic]Transform, 0, len(scene.rocks), context.temp_allocator)
        for a in scene.rocks {
            if a.mesh == shape {
                append(&batch, a.transform)
            }
        }
        obsidon.draw_mesh_instanced(&mesh, &scene.asteroid_material, batch[:])
    }

    // ---- Ship
    draw_ship(scene)

    // ---- HUD (2D overlay)
    draw_hud(scene)
}

@(private = "file")
draw_station :: proc(scene: ^Flight_Scene, time: f64) {
    base := obsidon.transform_matrix({position = STATION_POSITION})
    part :: proc(scene: ^Flight_Scene, base: obsidon.Mat4, mesh: ^Mesh, material: ^Material, position: Vec3, scale: Vec3, rotation := obsidon.QUAT_IDENTITY) {
        obsidon.draw_mesh_matrix(mesh, material, base * obsidon.transform_matrix({position = position, rotation = rotation, scale = scale}))
    }

    // Landing deck
    part(scene, base, &scene.cylinder, &scene.deck_material, {0, -0.5, 0}, {50, 1, 50})
    // Central tower and spine
    part(scene, base, &scene.cylinder, &scene.station_material, {0, 6, 0}, {6, 12, 6})
    part(scene, base, &scene.cylinder, &scene.station_material, {0, -14, 0}, {3, 28, 3})
    part(scene, base, &scene.cube, &scene.trim_material, {0, 12.5, 0}, {7, 1, 7})
    // Solar panels below the deck
    for i in 0..<4 {
        rot := obsidon.quat_angle_axis(f64(i) * 90 + 45, obsidon.VEC3_UP)
        offset := obsidon.quat_rotate(rot, {0, -18, 22})
        part(scene, base, &scene.cube, &scene.station_material, offset, {2, 1, 18}, rot)
    }
    // Cargo containers on the deck (good SSAO corners)
    containers := [?]Vec3{{-12, 1.5, -8}, {-12, 1.5, -4}, {-12, 4.5, -6}, {14, 1.5, 6}, {16, 1.5, 10}, {-6, 1.5, 15}}
    for c, i in containers {
        tint := obsidon.color_hex(0x3E7CB1) if i % 2 == 0 else obsidon.color_hex(0xB13E3E)
        obsidon.draw_mesh_matrix(&scene.cube, &scene.paint_material, base * obsidon.transform_matrix({position = c, scale = {6, 3, 3.5}}), tint)
    }
    // Landing pad marker lights + beacons
    for i in 0..<8 {
        angle := f64(i) / 8 * 2 * math.PI
        p := Vec3{math.cos(angle) * 22, 0.4, math.sin(angle) * 22}
        part(scene, base, &scene.sphere, &scene.beacon_material, p, {0.6, 0.6, 0.6})
    }
    blink := math.sin(time * 4) * 0.5 + 0.5
    obsidon.add_point_light(STATION_POSITION + {0, 14, 0}, obsidon.rgb(1, 0.2, 0.15), f32(2.5 * blink), 22)
    part(scene, base, &scene.sphere, &scene.beacon_material, {0, 13.5, 0}, {1.2, 1.2, 1.2})
    // Floodlight from the tower onto the deck
    obsidon.add_spot_light(STATION_POSITION + {0, 11, 4}, {0.2, -1, 0.9}, obsidon.rgb(0.8, 0.9, 1.0), 3, 40, 25, 40, cast_shadows = true)
}

@(private = "file")
draw_ship :: proc(scene: ^Flight_Scene) {
    t := scene.ship.transform
    m := obsidon.transform_matrix(t)
    part :: proc(scene: ^Flight_Scene, m: obsidon.Mat4, mesh: ^Mesh, material: ^Material, position: Vec3, scale: Vec3, rotation := obsidon.QUAT_IDENTITY, tint := obsidon.WHITE) {
        obsidon.draw_mesh_matrix(mesh, material, m * obsidon.transform_matrix({position = position, rotation = rotation, scale = scale}), tint)
    }
    // Hull, cockpit, wings, fins
    part(scene, m, &scene.cube, &scene.hull_material, {0, 0, 0}, {1.4, 0.6, 4})
    part(scene, m, &scene.cube, &scene.hull_material, {0, 0.1, -2.4}, {0.9, 0.45, 1.2})
    part(scene, m, &scene.cube, &scene.trim_material, {0, 0.45, -0.9}, {0.7, 0.35, 1.3}, tint = obsidon.rgb(0.2, 0.5, 0.7))
    part(scene, m, &scene.cube, &scene.hull_material, {2.2, -0.1, 0.6}, {3.2, 0.15, 1.6}, obsidon.quat_angle_axis(-8, {0, 0, 1}))
    part(scene, m, &scene.cube, &scene.hull_material, {-2.2, -0.1, 0.6}, {3.2, 0.15, 1.6}, obsidon.quat_angle_axis(8, {0, 0, 1}))
    part(scene, m, &scene.cube, &scene.trim_material, {3.7, -0.3, 0.6}, {0.2, 0.6, 1.8})
    part(scene, m, &scene.cube, &scene.trim_material, {-3.7, -0.3, 0.6}, {0.2, 0.6, 1.8})
    part(scene, m, &scene.cube, &scene.trim_material, {0, 0.7, 1.4}, {0.15, 0.9, 1.2})
    // Engines
    for x in ([2]f64{-0.45, 0.45}) {
        part(scene, m, &scene.cylinder, &scene.hull_material, {x, 0, 2.1}, {0.5, 0.6, 0.5}, obsidon.quat_angle_axis(90, {1, 0, 0}))
        glow := 0.4 + scene.ship.throttle * 0.6
        part(scene, m, &scene.sphere, &scene.glow_material, {x, 0, 2.45}, {0.42, 0.42, 0.3 + 0.6 * glow})
    }
    engine_pos := t.position + obsidon.quat_rotate(obsidon.transform_rotation(t), {0, 0, 3.5})
    obsidon.add_point_light(engine_pos, obsidon.rgb(1, 0.55, 0.25), f32(2 + scene.ship.throttle * 3), 18)
}

@(private = "file")
draw_hud :: proc(scene: ^Flight_Scene) {
    w := f64(obsidon.get_framebuffer_width())
    h := f64(obsidon.get_framebuffer_height())
    left := -w * 0.5 + 8
    top := h * 0.5 - 18
    scale: f32 = 0.5 if h <= 400 else 0.9
    hud := obsidon.rgb(0.55, 0.95, 0.75)

    speed := obsidon.vec3_length(scene.ship.velocity)
    p := scene.ship.transform.position
    gs := obsidon.get_graphics_settings()
    obsidon.text_draw(&scene.font, fmt.tprintf("SPD %5.1f m/s  THR %3.0f%%", speed, scene.ship.throttle * 100), {left, top}, scale, hud)
    obsidon.text_draw(&scene.font, fmt.tprintf("POS %.0f %.0f %.0f", p.x, p.y, p.z), {left, top - 16 * f64(scale) * 2}, scale, hud)
    obsidon.text_draw(&scene.font, fmt.tprintf("FPS %.0f  SSAO %v  SHADOWS %v %v", scene.fps, gs.ssao, gs.shadows, gs.shadow_resolution), {left, top - 32 * f64(scale) * 2}, scale, hud)
    obsidon.text_draw(&scene.font, "MOUSE steer  W/S throttle  Q/E roll  F1-F6 graphics  TAB cursor", {left, -h * 0.5 + 8}, scale * 0.8, obsidon.rgb(0.7, 0.7, 0.75))

    // Target marker over the station
    if screen, visible := obsidon.world_to_screen(STATION_POSITION + {0, 14, 0}); visible {
        dist := obsidon.vec3_distance(scene.ship.transform.position, STATION_POSITION)
        obsidon.text_draw(&scene.font, fmt.tprintf("[ STATION %.0fm ]", dist), screen + {-40, 10}, scale * 0.8, obsidon.rgb(1, 0.8, 0.3))
    }
}

@(private = "file")
flight_destroy :: proc(s: ^Scene) {
    scene := cast(^Flight_Scene)s

    obsidon.post_effect_remove(&scene.dither_material)
    obsidon.post_effect_remove(&scene.vignette_material)
    obsidon.font_destroy(&scene.font)
    obsidon.mesh_destroy(&scene.cube)
    obsidon.mesh_destroy(&scene.sphere)
    obsidon.mesh_destroy(&scene.cylinder)
    obsidon.mesh_destroy(&scene.sky_sphere)
    for &m in scene.asteroids {
        obsidon.mesh_destroy(&m)
    }
    obsidon.texture_destroy(&scene.checker)
    obsidon.texture_destroy(&scene.deck_tiles)
    obsidon.texture_destroy(&scene.rock)
    obsidon.texture_destroy(&scene.panels)

    materials := [?]^Material{
        &scene.hull_material, &scene.trim_material, &scene.paint_material, &scene.station_material, &scene.deck_material,
        &scene.asteroid_material, &scene.terran_material, &scene.cloud_material, &scene.gas_giant_material,
        &scene.sky_material, &scene.glow_material, &scene.beacon_material, &scene.dither_material,
        &scene.vignette_material,
    }
    for m in materials {
        obsidon.material_destroy(m)
    }
    shaders := [?]Shader{
        scene.standard_shader, scene.psx_shader, scene.terran_shader, scene.cloud_shader,
        scene.gas_giant_shader, scene.sky_shader, scene.glow_shader, scene.dither_shader, scene.vignette_shader,
    }
    for sh in shaders {
        obsidon.shader_destroy(sh)
    }
}

// Flips graphics settings at runtime to exercise target re-creation.
@(private = "file")
run_settings_test :: proc(frame: int) {
    gs := obsidon.get_graphics_settings()
    switch frame {
    case 10: gs.ssao = false
    case 20: gs.shadows = false
    case 30: gs.shadows = true; gs.shadow_resolution = .R512; gs.shadow_filter = .PCF_5x5
    case 40: gs.resolution = .Native; gs.texture_filter = .Linear
    case 50: gs.ssao = true; gs.ssao_quality = .High
    case 60: gs.resolution = .R320x240; gs.tonemapper = .Reinhard; gs.vsync = false
    case: return
    }
    obsidon.set_graphics_settings(gs)
}
