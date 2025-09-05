package obsidon

import "core:strings"
import "core:log"

import "window"
import "renderer"

run_game :: proc(name: string, res_width: int, res_height: int, scene: ^Scene) {
    validate_scene(scene)

    name_cstr := strings.unsafe_string_to_cstring(name)

    win := window.init(name_cstr)
    defer window.cleanup(win)

    current_scene := scene
    current_scene->on_create()

    window.should_close(win)

    for !window.should_close(win) {
        free_all(context.temp_allocator)

        window.poll_events(win)

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

        window.swap_buffers(win)
    }
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
