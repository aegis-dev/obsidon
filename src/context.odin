package obsidon

import "core:strings"
import "core:log"

import "window"
import "renderer"

run_game :: proc(name: string, buffer_width: u32, buffer_height: u32, scene: ^Scene) {
    validate_scene(scene)

    name_cstr := strings.unsafe_string_to_cstring(name)

    window.init(name_cstr)
    defer window.cleanup()

    renderer.init(window.get_window_handle(), buffer_width, buffer_height)
    defer renderer.cleanup()

    current_scene := scene
    current_scene->on_create()

    for !window.should_close() {
        free_all(context.temp_allocator)

        window.poll_events()

        renderer.begin_draw()

        new_scene := current_scene->on_update(0.0)
        if new_scene != nil {
            validate_scene(scene)

            current_scene->on_destroy()
            free(current_scene)

            current_scene := new_scene
            current_scene->on_create()
        } else {
             current_scene->on_draw(0.0)
        }

        renderer.end_draw_and_present()
    }
}

set_clear_color :: proc(r: f64, g: f64, b: f64, a: f64) {
	renderer.set_clear_color(r, g, b, a)
}

load_sprite :: proc() {

}

draw_sprite :: proc() {
	
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
