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

import "renderer"

set_camera_position :: proc(position: Vec2) {
    renderer.set_camera_position(position)
}

set_camera_angle :: proc(angle: f32) {
    renderer.set_camera_angle(angle)
}

set_camera_zoom :: proc(zoom: f32) {
    renderer.set_camera_zoom(zoom)
}

get_camera_position :: proc() -> Vec2 {
    return renderer.get_camera_position()
}

get_camera_angle :: proc() -> f32 {
    return renderer.get_camera_angle()
}

get_camera_zoom :: proc() -> f32 {
    return renderer.get_camera_zoom()
}
