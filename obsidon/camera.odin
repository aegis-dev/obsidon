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

import "internal/renderer"

// The camera looks along its -Z axis with +Y up (right-handed, Y-up world).

set_camera_position :: proc(position: Vec3) {
    c := renderer.get_camera()
    c.position = position
    renderer.set_camera(c)
}

get_camera_position :: proc() -> Vec3 {
    return renderer.get_camera().position
}

set_camera_rotation :: proc(rotation: Quat) {
    c := renderer.get_camera()
    c.rotation = quat_normalize(rotation) if rotation != 0 else QUAT_IDENTITY
    renderer.set_camera(c)
}

get_camera_rotation :: proc() -> Quat {
    return renderer.get_camera().rotation
}

// Euler angles in degrees: x = pitch, y = yaw, z = roll.
set_camera_euler :: proc(degrees: Vec3) {
    set_camera_rotation(quat_from_euler(degrees))
}

camera_look_at :: proc(target: Vec3, up := VEC3_UP) {
    set_camera_rotation(quat_look_rotation(target - get_camera_position(), up))
}

// Place the camera from a transform (e.g. attach it to a ship).
set_camera_transform :: proc(t: Transform) {
    set_camera_position(t.position)
    set_camera_rotation(transform_rotation(t))
}

get_camera_forward :: proc() -> Vec3 { return quat_forward(get_camera_rotation()) }
get_camera_right :: proc() -> Vec3 { return quat_right(get_camera_rotation()) }
get_camera_up :: proc() -> Vec3 { return quat_up(get_camera_rotation()) }

// Vertical field of view in degrees (perspective camera).
set_camera_fov :: proc(degrees: f64) {
    c := renderer.get_camera()
    c.fov_y = deg_to_rad(math.clamp(degrees, 1, 179))
    c.orthographic = false
    renderer.set_camera(c)
}

get_camera_fov :: proc() -> f64 {
    return rad_to_deg(renderer.get_camera().fov_y)
}

// Near and far clip distances. far = 0 means infinite (great for space).
set_camera_clip :: proc(near: f64, far: f64 = 0) {
    c := renderer.get_camera()
    c.near = max(near, 1e-5)
    c.far = far
    renderer.set_camera(c)
}

// Orthographic projection showing `height` world units vertically.
set_camera_orthographic :: proc(height: f64) {
    c := renderer.get_camera()
    c.orthographic = true
    c.ortho_height = height
    renderer.set_camera(c)
}

set_camera_perspective :: proc(fov_degrees: f64 = 60) {
    set_camera_fov(fov_degrees)
}

// Project a world position to overlay coordinates (render buffer pixels,
// origin at the centre, y up - the same space sprites and text use).
// `visible` is false when the point is behind the camera.
world_to_screen :: proc(world: Vec3) -> (screen: Vec2, visible: bool) {
    c := renderer.get_camera()
    rel := world - c.position
    view := quat_rotate(quat_inverse(c.rotation), rel)
    w := f64(renderer.get_render_width())
    h := f64(renderer.get_render_height())
    if c.orthographic {
        half_h := c.ortho_height * 0.5
        half_w := half_h * w / h
        return Vec2{view.x / half_w * w * 0.5, view.y / half_h * h * 0.5}, true
    }
    if view.z >= 0 {
        return {}, false
    }
    f := 1.0 / math.tan(c.fov_y * 0.5)
    aspect := w / h
    ndc := Vec2{view.x * f / aspect / -view.z, view.y * f / -view.z}
    return Vec2{ndc.x * w * 0.5, ndc.y * h * 0.5}, true
}

// Ray from the camera through an overlay coordinate (see world_to_screen),
// e.g. obsidon.get_mouse_position(). Useful for picking.
screen_to_ray :: proc(screen: Vec2) -> (origin: Vec3, direction: Vec3) {
    c := renderer.get_camera()
    w := f64(renderer.get_render_width())
    h := f64(renderer.get_render_height())
    ndc := Vec2{screen.x / (w * 0.5), screen.y / (h * 0.5)}
    if c.orthographic {
        half_h := c.ortho_height * 0.5
        half_w := half_h * w / h
        origin = c.position + quat_rotate(c.rotation, Vec3{ndc.x * half_w, ndc.y * half_h, 0})
        direction = quat_forward(c.rotation)
        return
    }
    f := 1.0 / math.tan(c.fov_y * 0.5)
    aspect := w / h
    local := Vec3{ndc.x * aspect / f, ndc.y / f, -1}
    return c.position, linalg.normalize(quat_rotate(c.rotation, local))
}
