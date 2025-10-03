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

import "core:math/linalg"

import obsidon "../.."

LineCollider :: struct {
    start: Vec2,
    end:   Vec2,
}

line_collider_init :: proc(start: Vec2, end: Vec2) -> LineCollider {
    return LineCollider{start, end}
}

line_collider_collides_with_ray :: proc(collider: ^LineCollider, ray: ^Ray, max_distance: f32) -> (bool, Vec2) {
    line_dir := collider.end - collider.start
    line_perp := Vec2{-line_dir.y, line_dir.x}

    denom := linalg.vector_dot(ray.direction, line_perp)
    if linalg.abs(denom) < 0.0001 {
        // Parallel lines
        return false, Vec2{0, 0}
    }

    diff := collider.start - ray.origin
    t := linalg.vector_dot(diff, line_perp) / denom
    u := linalg.vector_dot(diff, Vec2{-ray.direction.y, ray.direction.x}) / denom

    if t >= 0 && t <= max_distance && u >= 0 && u <= 1 {
        intersection_point := ray.origin + ray.direction * t
        return true, intersection_point
    }

    return false, Vec2{0, 0}
}
