package obsidon

import "core:strings"
import "core:log"
import "core:time"

import "window"
import "renderer"

@(private)
should_quit: bool = false

run_game :: proc(name: string, buffer_width: u32, buffer_height: u32, scene: ^Scene) {
    validate_scene(scene)

    name_cstr := strings.unsafe_string_to_cstring(name)

    window_width, window_height := window.init(name_cstr, buffer_width, buffer_height)
    defer window.cleanup()

    renderer.init(window.get_window_handle(), window_width, window_height, buffer_width, buffer_height)
    defer renderer.cleanup()

    current_scene := scene
    current_scene->on_create()

    delta_time := 0.0
    last_frame_time := time.now()

    for !window.should_close() {
        free_all(context.temp_allocator)

        window.poll_events()

        if should_quit {
            break
        }

        time_now := time.now()
        delta_time = time.duration_seconds(time.diff(last_frame_time, time_now))
        last_frame_time = time_now

        renderer.begin_draw()

        new_scene := current_scene->on_update(f32(delta_time))
        if new_scene != nil {
            validate_scene(scene)

            current_scene->on_destroy()
            free(current_scene)

            current_scene := new_scene
            current_scene->on_create()
        } else {
             current_scene->on_draw(f32(delta_time))
        }

        renderer.end_draw_and_present()
    }
}

quit_game :: proc() {
    should_quit = true
}

set_clear_color :: proc(r: f64, g: f64, b: f64, a: f64) {
	renderer.set_clear_color(r, g, b, a)
}

get_window_width :: proc() -> u32 {
    return window.get_window_width()
}

get_window_height :: proc() -> u32 {
    return window.get_window_height()
}

get_framebuffer_width :: proc() -> u32 {
    return renderer.get_framebuffer_width()
}

get_framebuffer_height :: proc() -> u32 {
    return renderer.get_framebuffer_height()
}

set_screen_color_override :: proc(color: Vec4) {
    renderer.set_screen_color_override(color)
}

clear_screen_color_override :: proc() {
    renderer.clear_screen_color_override()
}

@(private)
validate_scene :: proc(scene: ^Scene) {
    if scene.on_create == nil {
        log.panic("scene.on_create is nil")
    }
    if scene.on_update == nil {
        log.panic("scene.on_update is nil")
    }
    if scene.on_draw == nil {
        log.panic("scene.on_draw is nil")
    }
    if scene.on_destroy == nil {
        log.panic("scene.on_destroy is nil")
    }
}
