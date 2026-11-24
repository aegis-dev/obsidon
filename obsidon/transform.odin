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

// Position, rotation and scale of an object.
//
// The zero value is usable: a zero rotation is treated as "no rotation" and a
// zero scale as 1, so `Transform{position = {0, 2, 0}}` just works.
Transform :: struct {
    position: Vec3,
    rotation: Quat,
    scale:    Vec3,
}

transform_make :: proc(position := VEC3_ZERO, rotation := QUAT_IDENTITY, scale := VEC3_ONE) -> Transform {
    return Transform{position, rotation, scale}
}

transform_matrix :: proc(t: Transform) -> Mat4 {
    rotation := t.rotation
    if rotation == 0 {
        rotation = QUAT_IDENTITY
    }
    scale := t.scale
    if scale == {0, 0, 0} {
        scale = VEC3_ONE
    }
    return linalg.matrix4_from_trs_f64(t.position, rotation, scale)
}

transform_forward :: proc(t: Transform) -> Vec3 { return quat_forward(transform_rotation(t)) }
transform_right :: proc(t: Transform) -> Vec3 { return quat_right(transform_rotation(t)) }
transform_up :: proc(t: Transform) -> Vec3 { return quat_up(transform_rotation(t)) }

// Rotate around a world-space axis.
transform_rotate :: proc(t: ^Transform, axis: Vec3, degrees: f64) {
    t.rotation = quat_normalize(quat_angle_axis(degrees, axis) * transform_rotation(t^))
}

// Rotate around an axis in the object's own space (e.g. pitch / yaw / roll of a ship).
transform_rotate_local :: proc(t: ^Transform, axis: Vec3, degrees: f64) {
    t.rotation = quat_normalize(transform_rotation(t^) * quat_angle_axis(degrees, axis))
}

// Point the object's forward (-Z) at `target`.
transform_look_at :: proc(t: ^Transform, target: Vec3, up := VEC3_UP) {
    t.rotation = quat_look_rotation(target - t.position, up)
}

// Rotation with the zero value mapped to identity.
transform_rotation :: proc(t: Transform) -> Quat {
    return QUAT_IDENTITY if t.rotation == 0 else t.rotation
}
