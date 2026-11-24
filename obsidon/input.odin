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

package obsidon

import "internal/window"

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

is_key_released :: proc(key: Key) -> bool {
    return window.is_key_released(key)
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

is_button_released :: proc(button: Button) -> bool {
    return window.is_button_released(button)
}

// Cursor position in overlay space (render buffer pixels, centred, y up).
// While the cursor is locked this is a virtual cursor moved by the mouse.
get_mouse_position :: proc() -> Vec2 {
    p := window.get_mouse_position()
    return Vec2{f64(p.x), f64(p.y)}
}

// Mouse movement since the last frame in window pixels (x right, y up).
// Use it for mouse look / steering.
get_mouse_delta :: proc() -> Vec2 {
    d := window.get_mouse_delta()
    return Vec2{f64(d.x), f64(d.y)}
}

// Mouse wheel movement since the last frame.
get_mouse_scroll :: proc() -> Vec2 {
    s := window.get_scroll()
    return Vec2{f64(s.x), f64(s.y)}
}

// Locked (default): cursor hidden and captured, for mouse look.
// Unlocked: the normal OS cursor, for menus.
set_cursor_locked :: proc(locked: bool) {
    window.set_cursor_locked(locked)
}

is_cursor_locked :: proc() -> bool {
    return window.is_cursor_locked()
}
