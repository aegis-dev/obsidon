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

import "core:math"
import "core:math/linalg"

// World space math is 64-bit: positions stay precise millions of units away
// from the origin (rendering is camera-relative, see shader.world_position).
Vec2 :: [2]f64
Vec3 :: [3]f64
Vec4 :: [4]f64
Quat :: quaternion256
Mat4 :: matrix[4, 4]f64

// RGBA colour, components 0..1, sRGB (like colours in image editors).
Color :: [4]f32

VEC2_ZERO :: Vec2{0, 0}
VEC3_ZERO :: Vec3{0, 0, 0}
VEC4_ZERO :: Vec4{0, 0, 0, 0}
VEC3_ONE  :: Vec3{1, 1, 1}

// Obsidon uses a right-handed, Y-up coordinate system; -Z is forward.
VEC3_RIGHT   :: Vec3{1, 0, 0}
VEC3_UP      :: Vec3{0, 1, 0}
VEC3_FORWARD :: Vec3{0, 0, -1}

QUAT_IDENTITY :: Quat(1)

WHITE   :: Color{1, 1, 1, 1}
BLACK   :: Color{0, 0, 0, 1}
GRAY    :: Color{0.5, 0.5, 0.5, 1}
RED     :: Color{1, 0, 0, 1}
GREEN   :: Color{0, 1, 0, 1}
BLUE    :: Color{0, 0, 1, 1}
YELLOW  :: Color{1, 1, 0, 1}
CYAN    :: Color{0, 1, 1, 1}
MAGENTA :: Color{1, 0, 1, 1}
TRANSPARENT :: Color{0, 0, 0, 0}

rgb :: proc(r: f32, g: f32, b: f32) -> Color {
    return {r, g, b, 1}
}

rgba :: proc(r: f32, g: f32, b: f32, a: f32) -> Color {
    return {r, g, b, a}
}

// Colour from a 0xRRGGBB value.
color_hex :: proc(hex: u32, alpha: f32 = 1) -> Color {
    return {f32((hex >> 16) & 0xFF) / 255, f32((hex >> 8) & 0xFF) / 255, f32(hex & 0xFF) / 255, alpha}
}

deg_to_rad :: proc(degrees: f64) -> f64 { return degrees * (math.PI / 180.0) }
rad_to_deg :: proc(radians: f64) -> f64 { return radians * (180.0 / math.PI) }

// ---------------------------------------------------------------------------
// Vec2
// ---------------------------------------------------------------------------

vec2_distance :: proc(a: Vec2, b: Vec2) -> f64 {
    return linalg.distance(a, b)
}

// Unit vector pointing at `angle` degrees (counter-clockwise from +X).
vec2_direction :: proc(angle: f64) -> Vec2 {
    radians := deg_to_rad(angle)
    return Vec2{math.cos(radians), math.sin(radians)}
}

vec2_lerp :: proc(a: Vec2, b: Vec2, amount: f64) -> Vec2 {
    return a + (b - a) * amount
}

vec2_lerp_clamped :: proc(a: Vec2, b: Vec2, amount: f64) -> Vec2 {
    return vec2_lerp(a, b, math.clamp(amount, 0.0, 1.0))
}

vec2_rotate :: proc(v: Vec2, angle: f64) -> Vec2 {
    radians := deg_to_rad(angle)
    c := math.cos(radians)
    s := math.sin(radians)
    return Vec2{v.x * c - v.y * s, v.x * s + v.y * c}
}

vec2_angle :: proc(v: Vec2) -> f64 {
    return rad_to_deg(math.atan2(v.y, v.x))
}

vec2_normalize :: proc(v: Vec2) -> Vec2 {
    length := vec2_length(v)
    if length == 0 {
        return VEC2_ZERO
    }
    return v / length
}

vec2_length :: proc(v: Vec2) -> f64 {
    return linalg.length(v)
}

// ---------------------------------------------------------------------------
// Vec3
// ---------------------------------------------------------------------------

vec3_length :: proc(v: Vec3) -> f64 { return linalg.length(v) }
vec3_distance :: proc(a: Vec3, b: Vec3) -> f64 { return linalg.distance(a, b) }
vec3_dot :: proc(a: Vec3, b: Vec3) -> f64 { return linalg.dot(a, b) }
vec3_cross :: proc(a: Vec3, b: Vec3) -> Vec3 { return linalg.cross(a, b) }

vec3_normalize :: proc(v: Vec3) -> Vec3 {
    length := linalg.length(v)
    if length == 0 {
        return VEC3_ZERO
    }
    return v / length
}

vec3_lerp :: proc(a: Vec3, b: Vec3, amount: f64) -> Vec3 {
    return a + (b - a) * amount
}

vec3_lerp_clamped :: proc(a: Vec3, b: Vec3, amount: f64) -> Vec3 {
    return vec3_lerp(a, b, math.clamp(amount, 0.0, 1.0))
}

// Move `current` towards `target` by at most `max_distance`.
vec3_move_towards :: proc(current: Vec3, target: Vec3, max_distance: f64) -> Vec3 {
    delta := target - current
    d := linalg.length(delta)
    if d <= max_distance || d == 0 {
        return target
    }
    return current + delta / d * max_distance
}

// ---------------------------------------------------------------------------
// Quaternions (angles in degrees)
// ---------------------------------------------------------------------------

// Rotation from Euler angles in degrees: x = pitch, y = yaw, z = roll.
// Applied as yaw, then pitch, then roll (the usual camera / vehicle order).
quat_from_euler :: proc(degrees: Vec3) -> Quat {
    qx := linalg.quaternion_angle_axis_f64(deg_to_rad(degrees.x), {1, 0, 0})
    qy := linalg.quaternion_angle_axis_f64(deg_to_rad(degrees.y), {0, 1, 0})
    qz := linalg.quaternion_angle_axis_f64(deg_to_rad(degrees.z), {0, 0, 1})
    return qy * qx * qz
}

quat_angle_axis :: proc(degrees: f64, axis: Vec3) -> Quat {
    return linalg.quaternion_angle_axis_f64(deg_to_rad(degrees), vec3_normalize(axis))
}

// Rotation that makes -Z point along `forward` with +Y as close to `up` as possible.
quat_look_rotation :: proc(forward: Vec3, up := VEC3_UP) -> Quat {
    f := vec3_normalize(forward)
    u := up
    if abs(linalg.dot(f, vec3_normalize(u))) > 0.9999 {
        u = {0, 0, 1} if abs(f.y) > 0.5 else {0, 1, 0}
    }
    r := vec3_normalize(linalg.cross(f, u))
    u2 := linalg.cross(r, f)
    m := linalg.Matrix3f64{
        r.x, u2.x, -f.x,
        r.y, u2.y, -f.y,
        r.z, u2.z, -f.z,
    }
    return linalg.quaternion_from_matrix3_f64(m)
}

quat_rotate :: proc(q: Quat, v: Vec3) -> Vec3 {
    return linalg.quaternion_mul_vector3(q, v)
}

quat_slerp :: proc(a: Quat, b: Quat, t: f64) -> Quat {
    return linalg.quaternion_slerp_f64(a, b, t)
}

quat_normalize :: proc(q: Quat) -> Quat {
    return linalg.quaternion_normalize(q)
}

quat_inverse :: proc(q: Quat) -> Quat {
    return linalg.quaternion_inverse(q)
}

quat_forward :: proc(q: Quat) -> Vec3 { return quat_rotate(q, VEC3_FORWARD) }
quat_right :: proc(q: Quat) -> Vec3 { return quat_rotate(q, VEC3_RIGHT) }
quat_up :: proc(q: Quat) -> Vec3 { return quat_rotate(q, VEC3_UP) }
