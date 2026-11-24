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

is_key_released :: proc(key: Key) -> bool {
    return instance.cur_keys[key] == .Up && instance.prev_keys[key] == .Down
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

is_button_released :: proc(button: Button) -> bool {
    return instance.cur_buttons[button] == .Up && instance.prev_buttons[button] == .Down
}

// Virtual cursor in render buffer pixels, (0,0) at the centre, y up.
get_mouse_position :: proc() -> Vec2 {
    return instance.mouse_position
}

// Raw mouse movement this frame in window pixels (x right, y up).
get_mouse_delta :: proc() -> Vec2 {
    return instance.mouse_delta
}

get_scroll :: proc() -> Vec2 {
    return instance.scroll
}

@(private)
refresh_keyboard :: proc() {
    // GLFW reports an error for key codes below KEY_SPACE.
    for k in i32(glfw.KEY_SPACE)..<KEY_COUNT {
        state := glfw.GetKey(instance.window, c.int(k))
        instance.prev_keys[k] = instance.cur_keys[k]
        instance.cur_keys[k] = .Down if state == glfw.PRESS || state == glfw.REPEAT else .Up
    }
}

@(private)
refresh_mouse_buttons :: proc() {
    for b in 0..<BUTTON_COUNT {
        state := glfw.GetMouseButton(instance.window, c.int(b))
        instance.prev_buttons[b] = instance.cur_buttons[b]
        instance.cur_buttons[b] = .Down if state == glfw.PRESS else .Up
    }
}

@(private)
refresh_mouse :: proc() {
    x, y := glfw.GetCursorPos(instance.window)
    if !instance.has_last_mouse {
        instance.last_mouse = {x, y}
        instance.has_last_mouse = true
    }
    delta := Vec2{f32(x - instance.last_mouse.x), -f32(y - instance.last_mouse.y)}
    instance.last_mouse = {x, y}
    instance.mouse_delta = delta

    bw := f32(instance.buffer_width if instance.buffer_width > 0 else instance.window_width)
    bh := f32(instance.buffer_height if instance.buffer_height > 0 else instance.window_height)
    vp := instance.viewport
    if vp.z <= 0 || vp.w <= 0 {
        vp = {0, 0, f32(max(instance.window_width, 1)), f32(max(instance.window_height, 1))}
    }
    if instance.cursor_locked {
        // Virtual cursor driven by relative motion, clamped to the buffer.
        instance.mouse_position += Vec2{delta.x * bw / vp.z, delta.y * bh / vp.w}
    } else {
        // Follow the OS cursor, mapped into the area the buffer is shown in.
        instance.mouse_position = Vec2{
            ((f32(x) - vp.x) / vp.z - 0.5) * bw,
            -((f32(y) - vp.y) / vp.w - 0.5) * bh,
        }
    }
    instance.mouse_position.x = clamp(instance.mouse_position.x, -bw * 0.5, bw * 0.5)
    instance.mouse_position.y = clamp(instance.mouse_position.y, -bh * 0.5, bh * 0.5)
}
