package obsidon

import "window"

Key :: window.Key

Button :: window.Button

is_key_down :: proc(key: Key) -> bool {
    return window.is_key_down(key)
}

is_key_pressed :: proc(key: Key) -> bool {
    return window.is_key_pressed(key)
}

is_button_down :: proc(button: Button) -> bool {
    return window.is_button_down(button)
}

is_button_pressed :: proc(button: Button) -> bool {
    return window.is_button_pressed(button)
}

get_mouse_position :: proc() -> Vec2 {
    return window.get_mouse_position()
}
