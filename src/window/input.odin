package window

import "core:c"

import "vendor:glfw"

is_key_down :: proc(key: Key) -> bool {
    return instance.cur_keys[key] == .Down
}

is_key_pressed :: proc(key: Key) -> bool {
    return instance.cur_keys[key] == .Down && instance.prev_keys[key] == .Up
}

is_button_down :: proc(button: Button) -> bool {
    return instance.cur_buttons[button] == .Down
}

is_button_pressed :: proc(button: Button) -> bool {
    return instance.cur_buttons[button] == .Down && instance.prev_buttons[button] == .Up
}

get_mouse_position :: proc() -> Vec2 {
    return instance.mouse_position
}

@(private)
refresh_keyboard :: proc() {
    for k in 0..<len(instance.cur_keys) {
        state := glfw.GetKey(instance.window, c.int(k))
        instance.prev_keys[k] = instance.cur_keys[k]
        if state == glfw.PRESS || state == glfw.REPEAT {
            instance.cur_keys[k] = State.Down
        } else {
            instance.cur_keys[k] = State.Up
        }
    }
}

@(private)
refresh_mouse_buttons :: proc() {
    for b in 0..<len(instance.cur_buttons) {
        state := glfw.GetMouseButton(instance.window, c.int(b))
        instance.prev_buttons[b] = instance.cur_buttons[b]
        if state == glfw.PRESS {
            instance.cur_buttons[b] = State.Down
        } else {
            instance.cur_buttons[b] = State.Up
        }
    }
}

@(private)
refresh_mouse_position :: proc() {
    x, y := glfw.GetCursorPos(instance.window)
    mx := f32(x) - f32(instance.window_width) / 2.0
    my := f32(y) - f32(instance.window_height) / 2.0
    delta := Vec2{mx, my} - instance.last_mouse_position

    instance.last_mouse_position = Vec2{f32(mx), f32(my)}

    normalized := delta * instance.mouse_sensitivity
    
    instance.mouse_position -= normalized
}
