// Copyright 2025 Egidijus Vaišvila
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

package window

import "core:c"

import "vendor:glfw"

get_key_state :: proc(key: Key) -> State {
    return instance.cur_keys[key]
}

is_key_down :: proc(key: Key) -> bool {
    return instance.cur_keys[key] == .Down
}

is_key_pressed :: proc(key: Key) -> bool {
    return instance.cur_keys[key] == .Down && instance.prev_keys[key] == .Up
}

get_button_state :: proc(button: Button) -> State {
    return instance.cur_buttons[button]
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
    position := Vec2{f32(x), f32(y)} - Vec2{f32(instance.window_width / 2), f32(instance.window_height / 2)}
    normalized := position * instance.mouse_sensitivity

    instance.mouse_position.x = normalized.x
    instance.mouse_position.y = -normalized.y
}
