package obsidon

import "window"
import "renderer"

Key :: window.Key
Button :: window.Button
State :: window.State

get_key_state :: proc(key: Key) -> State {
    return window.get_key_state(key)
}

is_key_down :: proc(key: Key) -> bool {
    return window.is_key_down(key)
}

is_key_pressed :: proc(key: Key) -> bool {
    return window.is_key_pressed(key)
}

get_button_state :: proc(button: Button) -> State {
    return window.get_button_state(button)
}

is_button_down :: proc(button: Button) -> bool {
    return window.is_button_down(button)
}

is_button_pressed :: proc(button: Button) -> bool {
    return window.is_button_pressed(button)
}

// Get mouse position in screen space
get_mouse_position :: proc() -> Vec2 {
    return window.get_mouse_position()
}

// Get mouse position in world space (taking camera position into account)
get_mouse_absolute_position :: proc() -> Vec2 {
    return window.get_mouse_position() + renderer.get_camera_position()
}
