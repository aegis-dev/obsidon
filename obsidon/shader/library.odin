// Copyright 2026 Egidijus Vaišvila
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

package shader

// Reusable building blocks.
//
// Everything in this file is built only from the public primitives, the same
// way you write your own: a building block is just an Odin procedure that
// takes and returns `Value`s. Identical sub-expressions are merged
// automatically, so calling blocks repeatedly costs nothing extra.
//
//     my_glow :: proc(color: sh.Value) -> sh.Value {
//         return sh.mul(color, sh.pulse(4, 0.6, 1.2))
//     }

// ---------------------------------------------------------------------------
// Surface
// ---------------------------------------------------------------------------

// 0 when facing the camera, 1 at grazing angles. `power` sharpens the edge.
fresnel :: proc(world_normal: Value, world_pos: Value, power: Arg = 5) -> Value {
    view := view_direction(world_pos)
    facing := saturate(dot(normalize(world_normal), view))
    return pow(one_minus(facing), power)
}

// Coloured light around the silhouette (shields, holograms, atmospheres).
rim_light :: proc(world_normal: Value, world_pos: Value, color: Value, power: Arg = 3) -> Value {
    return mul(rgb_of(color), fresnel(world_normal, world_pos, power))
}

// Sample a texture projected along the three world axes, blended by the
// normal - textures terrain, rocks and procedural meshes without uvs.
// `scale` is texture repeats per world unit.
triplanar :: proc(tex: Texture_Ref, world_pos: Value, world_normal: Value, scale: Arg = 1, sharpness: Arg = 4) -> Value {
    p := mul(add(world_pos, camera_position()), scale) // absolute position so the texture stays put
    n := normalize(world_normal)
    weights := pow(abs(n), sharpness)
    weights = div(weights, add(add(x(weights), y(weights)), z(weights)))
    sx := sample(tex, swizzle(p, "zy"))
    sy := sample(tex, swizzle(p, "xz"))
    sz := sample(tex, swizzle(p, "xy"))
    return add(add(mul(sx, x(weights)), mul(sy, y(weights))), mul(sz, z(weights)))
}

// Cel shading: quantize the light into `steps` bands (keeps the light colour).
toon_ramp :: proc(light: Value, steps: Arg = 3) -> Value {
    brightness := max(max(x(light), y(light)), max(z(light), 0.0001))
    banded := div(ceil(mul(brightness, steps)), steps)
    return mul(light, div(banded, brightness))
}

// Blend a colour towards grey.
desaturate :: proc(color: Value, amount: Arg) -> Value {
    c := rgb_of(color)
    return mix(c, vec3(luminance(c), luminance(c), luminance(c)), amount)
}

// Map v from [in_min, in_max] to [out_min, out_max].
remap :: proc(v: Arg, in_min: Arg, in_max: Arg, out_min: Arg, out_max: Arg) -> Value {
    t := div(sub(v, in_min), sub(in_max, in_min))
    return mix(out_min, out_max, t)
}

// Value oscillating between lo and hi, `speed` cycles per second.
pulse :: proc(speed: Arg = 1, lo: Arg = 0, hi: Arg = 1) -> Value {
    s := add(mul(sin(mul(time(), mul(speed, 6.2831853))), 0.5), 0.5)
    return mix(lo, hi, s)
}

// ---------------------------------------------------------------------------
// UVs
// ---------------------------------------------------------------------------

// Move uvs over time (`speed` in uv units per second).
uv_scroll :: proc(uv_value: Value, speed: Value) -> Value {
    expect_type("uv_scroll speed", speed, .Vec2)
    return add(uv_value, mul(speed, time()))
}

// Rotate uvs around `center` by `angle` radians.
uv_rotate :: proc(uv_value: Value, angle: Arg, center := [2]f32{0.5, 0.5}) -> Value {
    c := vec2(center.x, center.y)
    p := sub(uv_value, c)
    s := sin(to_value(angle))
    k := cos(to_value(angle))
    rotated := vec2(sub(mul(x(p), k), mul(y(p), s)), add(mul(x(p), s), mul(y(p), k)))
    return add(rotated, c)
}

// 0 / 1 checker pattern with `cells` squares per uv unit.
checker :: proc(uv_value: Value, cells: Arg = 8) -> Value {
    cell := floor(mul(uv_value, cells))
    return mod(abs(add(x(cell), y(cell))), 2)
}

// ---------------------------------------------------------------------------
// Post-processing
// ---------------------------------------------------------------------------

// 1 in the centre, darker towards the corners.
vignette :: proc(uv_value: Value, radius: Arg = 0.75, softness: Arg = 0.45) -> Value {
    d := length(sub(uv_value, vec2(0.5, 0.5)))
    return smoothstep(radius, sub(radius, softness), d)
}

// CRT-like horizontal lines; multiply the colour with the result.
scanlines :: proc(uv_value: Value, lines: Arg = 240, strength: Arg = 0.25) -> Value {
    wave := add(mul(sin(mul(y(uv_value), mul(lines, 6.2831853))), 0.5), 0.5)
    return sub(1, mul(wave, strength))
}

// Split the colour channels sideways, stronger towards the screen edges.
chromatic_aberration :: proc(uv_value: Value, amount: Arg = 0.003) -> Value {
    ensure_post("chromatic_aberration")
    offset := mul(sub(uv_value, vec2(0.5, 0.5)), amount)
    r := x(scene_color(add(uv_value, offset)))
    g := y(scene_color(uv_value))
    b_ := z(scene_color(sub(uv_value, offset)))
    return vec3(r, g, b_)
}

// The engine's bloom texture at `uv` (post shaders, black when bloom is off).
bloom :: proc(uv_value: Value) -> Value {
    ensure_post("bloom")
    expect_type("bloom", uv_value, .Vec2)
    return call("obs_bloom", .Vec3, uv_value)
}

// ---------------------------------------------------------------------------

// rgb of a vec4, unchanged vec3.
@(private)
rgb_of :: proc(color: Value) -> Value {
    if color.type == .Vec4 {
        return rgb(color)
    }
    return color
}
