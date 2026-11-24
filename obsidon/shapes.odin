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

import "internal/renderer"

// Solid colour 2D shapes on the overlay layer (UI panels, HUD markers).
// Same coordinate space as sprites and text: render buffer pixels, (0, 0) at
// the centre of the screen, +Y up. Colours are sRGB, alpha blends.

// Filled rectangle. `position` is the bottom-left corner.
draw_rect :: proc(position: Vec2, size: Vec2, color: Color) {
    if size.x <= 0 || size.y <= 0 {
        return
    }
    model := renderer.Mat4{
        f32(size.x), 0, 0, f32(position.x),
        0, f32(size.y), 0, f32(position.y),
        0, 0, 1, 0,
        0, 0, 0, 1,
    }
    renderer.overlay_draw(renderer.overlay_white_texture(), model, renderer.Vec4(color), true, false, false)
}

// Rectangle border drawn inside the rectangle.
draw_rect_outline :: proc(position: Vec2, size: Vec2, thickness: f64, color: Color) {
    t := min(thickness, size.x * 0.5, size.y * 0.5)
    draw_rect(position, {size.x, t}, color)
    draw_rect(position + {0, size.y - t}, {size.x, t}, color)
    draw_rect(position + {0, t}, {t, size.y - 2 * t}, color)
    draw_rect(position + {size.x - t, t}, {t, size.y - 2 * t}, color)
}

// Line segment of the given thickness (pixels).
draw_line :: proc(a: Vec2, b: Vec2, thickness: f64, color: Color) {
    d := b - a
    length := math.sqrt(d.x * d.x + d.y * d.y)
    if length < 1e-6 {
        return
    }
    // Unit quad -> x along the segment, y across it, centred on the line.
    dx := d / length
    nx := Vec2{-dx.y, dx.x} * thickness
    origin := a - nx * 0.5
    model := renderer.Mat4{
        f32(d.x), f32(nx.x), 0, f32(origin.x),
        f32(d.y), f32(nx.y), 0, f32(origin.y),
        0, 0, 1, 0,
        0, 0, 0, 1,
    }
    renderer.overlay_draw(renderer.overlay_white_texture(), model, renderer.Vec4(color), true, false, false)
}

// Circle outline (or an arc from `start` to `end` degrees, counter-clockwise from +X).
draw_circle_outline :: proc(center: Vec2, radius: f64, thickness: f64, color: Color, segments := 32, start: f64 = 0, end: f64 = 360) {
    n := max(segments, 3)
    a0 := deg_to_rad(start)
    step := deg_to_rad(end - start) / f64(n)
    prev := center + Vec2{math.cos(a0), math.sin(a0)} * radius
    for i in 1..=n {
        a := a0 + step * f64(i)
        p := center + Vec2{math.cos(a), math.sin(a)} * radius
        draw_line(prev, p, thickness, color)
        prev = p
    }
}

// Filled circle, made of horizontal strips (fine for small UI dots and gauges).
draw_circle :: proc(center: Vec2, radius: f64, color: Color) {
    if radius <= 0 {
        return
    }
    strips := max(int(math.ceil(radius * 2)), 2)
    h := radius * 2 / f64(strips)
    for i in 0..<strips {
        y := -radius + (f64(i) + 0.5) * h
        half := math.sqrt(max(radius * radius - y * y, 0))
        draw_rect({center.x - half, center.y + y - h * 0.5}, {half * 2, h}, color)
    }
}

// Texture stretched over a rectangle, multiplied by `tint` (sRGB).
draw_texture_rect :: proc(texture: ^Texture, position: Vec2, size: Vec2, tint := WHITE) {
    model := renderer.Mat4{
        f32(size.x), 0, 0, f32(position.x),
        0, f32(size.y), 0, f32(position.y),
        0, 0, 1, 0,
        0, 0, 0, 1,
    }
    // use_color = false keeps the texture colour; tint isn't supported by the
    // overlay shader in that mode, so a non-white tint replaces the colour.
    renderer.overlay_draw(texture, model, renderer.Vec4(tint), tint != WHITE, false, false)
}
