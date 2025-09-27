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

import "core:math/linalg"
import "core:math"

import "internal/renderer"

Vec2 :: renderer.Vec2

Vec3 :: renderer.Vec3

Vec4 :: renderer.Vec4

VEC2_ZERO :: Vec2{0, 0}

VEC3_ZERO :: Vec3{0, 0, 0}

VEC4_ZERO :: Vec4{0, 0, 0, 0}

vec2_distance :: proc(a: Vec2, b: Vec2) -> f32 {
    dx := b.x - a.x
    dy := b.y - a.y
    return math.sqrt(dx * dx + dy * dy)
}

vec2_direction :: proc(angle: f32) -> Vec2 {
    radians := angle * (math.PI / 180.0)
    return Vec2{math.cos(radians), math.sin(radians)}
}
    
vec2_lerp :: proc(a: Vec2, b: Vec2, amount: f32) -> Vec2 {
    direction := b - a
    return a + direction * amount
}

vec2_lerp_clamped :: proc(a: Vec2, b: Vec2, amount: f32) -> Vec2 {
    amount := math.clamp(amount, 0.0, 1.0)
    return vec2_lerp(a, b, amount)
}

vec2_rotate :: proc(v: Vec2, angle: f32) -> Vec2 {
    radians := angle * (math.PI / 180.0)
    cos_a := math.cos(radians)
    sin_a := math.sin(radians)
    return Vec2{
        v.x * cos_a - v.y * sin_a,
        v.x * sin_a + v.y * cos_a
    }
}

vec2_angle :: proc(v: Vec2) -> f32 {
    return math.atan2(v.y, v.x) * (180.0 / math.PI)
}

vec2_normalize :: proc(v: Vec2) -> Vec2 {
    return linalg.normalize(v)
}
