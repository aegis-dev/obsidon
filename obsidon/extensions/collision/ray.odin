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

package collision

import obsidon "../.."

Vec2 :: obsidon.Vec2

Ray :: struct {
    origin:    Vec2,
    direction: Vec2,
}

ray_init :: proc(origin: Vec2, direction: Vec2) -> Ray {
    return Ray{origin, obsidon.vec2_normalize(direction)}
}

ray_at :: proc(ray: ^Ray, distance: f32) -> Vec2 {
    return ray.origin + ray.direction * distance
}
