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
