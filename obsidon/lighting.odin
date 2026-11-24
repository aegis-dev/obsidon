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

import "internal/renderer"

// Lighting model:
//  - Ambient light: hemisphere lighting, `sky` colour from above and `ground`
//    colour from below. Darkened by SSAO when it is enabled.
//  - Sun: one directional light, optionally casting shadows.
//  - Point and spot lights: submitted every frame from on_draw (like meshes),
//    up to 256 per frame.
// All colours are sRGB; intensity multiplies the colour (values > 1 are fine,
// the HDR image is tonemapped).

set_ambient_light :: proc(sky: Color, ground: Color, intensity: f32 = 1) {
    l := renderer.get_lighting()
    l.ambient_sky = linear_rgb(sky, intensity)
    l.ambient_ground = linear_rgb(ground, intensity)
    renderer.set_lighting(l)
}

// Directional light. `direction` is the direction the light travels
// (e.g. {0, -1, 0} for a sun straight overhead).
set_sun :: proc(direction: Vec3, color := WHITE, intensity: f32 = 1) {
    l := renderer.get_lighting()
    l.sun_direction = vec3_normalize(direction) if direction != {} else Vec3{0, -1, 0}
    l.sun_color = linear_rgb(color, intensity)
    l.sun_enabled = true
    renderer.set_lighting(l)
}

set_sun_enabled :: proc(enabled: bool) {
    l := renderer.get_lighting()
    l.sun_enabled = enabled
    renderer.set_lighting(l)
}

set_sun_shadows :: proc(enabled: bool) {
    l := renderer.get_lighting()
    l.sun_shadows = enabled
    renderer.set_lighting(l)
}

get_sun_direction :: proc() -> Vec3 {
    return renderer.get_lighting().sun_direction
}

// Scale the automatic shadow bias (raise it against shadow acne, lower it
// against light leaking / detached shadows). Default 1.
set_shadow_bias :: proc(multiplier: f32) {
    l := renderer.get_lighting()
    l.shadow_bias = multiplier
    renderer.set_lighting(l)
}

// Linear distance fog from `start` to `end` world units.
// Shaders apply it with shader.fog().
set_fog :: proc(color: Color, start: f32, end: f32) {
    l := renderer.get_lighting()
    l.fog_enabled = true
    l.fog_color = linear_rgb(color, 1)
    l.fog_start = start
    l.fog_end = end
    renderer.set_lighting(l)
}

disable_fog :: proc() {
    l := renderer.get_lighting()
    l.fog_enabled = false
    renderer.set_lighting(l)
}

// Add a point light for this frame (call from on_draw).
add_point_light :: proc(position: Vec3, color: Color, intensity: f32, range: f32) {
    renderer.add_point_light(position, linear_rgb(color, intensity), range)
}

// Add a spot light for this frame (call from on_draw). Angles are in degrees
// from the centre of the cone; light fades between inner and outer angle.
// `cast_shadows` needs Graphics_Settings.spot_shadows; up to 4 per frame.
add_spot_light :: proc(position: Vec3, direction: Vec3, color: Color, intensity: f32, range: f32, inner_angle: f32 = 20, outer_angle: f32 = 30, cast_shadows := false) {
    d := vec3_normalize(direction)
    renderer.add_spot_light(
        position,
        {f32(d.x), f32(d.y), f32(d.z)},
        linear_rgb(color, intensity),
        range,
        f32(deg_to_rad(f64(inner_angle))),
        f32(deg_to_rad(f64(max(outer_angle, inner_angle + 0.1)))),
        cast_shadows,
    )
}

@(private)
linear_rgb :: proc(c: Color, intensity: f32) -> renderer.Vec3 {
    l := renderer.srgb_to_linear(c)
    return {l.r * intensity, l.g * intensity, l.b * intensity}
}
