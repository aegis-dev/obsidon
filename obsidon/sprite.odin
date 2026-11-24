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

// 2D sprites are drawn on the overlay layer, on top of the 3D scene (HUD, UI,
// menus). Coordinates are render buffer pixels with (0, 0) at the centre of
// the screen and +Y up. Angles are in degrees.
Sprite :: struct {
    width:   u32,
    height:  u32,
    texture: Texture,
}

sprite_load :: proc(png_data: []u8) -> Sprite {
    texture := texture_load(png_data, mipmaps = false)
    return Sprite{texture.width, texture.height, texture}
}

sprite_from_texture :: proc(texture: Texture) -> Sprite {
    return Sprite{texture.width, texture.height, texture}
}

sprite_destroy :: proc(sprite: ^Sprite) {
    texture_destroy(&sprite.texture)
}

sprite_draw :: proc(sprite: ^Sprite, position: Vec2, origin: Vec2, angle: f64, flip: bool, scale: f32) {
    renderer.overlay_draw(&sprite.texture, sprite_model(sprite, position, origin, angle, scale), {}, false, flip, false)
}

// Draw with the colour replacing the sprite colour (alpha multiplies). Colours are sRGB.
sprite_draw_colored :: proc(sprite: ^Sprite, position: Vec2, origin: Vec2, angle: f64, flip: bool, scale: f32, color: Color) {
    renderer.overlay_draw(&sprite.texture, sprite_model(sprite, position, origin, angle, scale), renderer.Vec4(color), true, flip, false)
}

@(private)
sprite_model :: proc(sprite: ^Sprite, position: Vec2, origin: Vec2, angle: f64, scale: f32) -> renderer.Mat4 {
    // Model = T(position) * Rz(angle) * S(scale) * T(-origin) * S(size)
    a := f32(deg_to_rad(angle))
    c, s := math.cos(a), math.sin(a)
    w := f32(sprite.width) * scale
    h := f32(sprite.height) * scale
    ox := f32(origin.x) * scale
    oy := f32(origin.y) * scale
    px := f32(position.x)
    py := f32(position.y)
    return renderer.Mat4{
        c * w, -s * h, 0, px - (c * ox - s * oy),
        s * w,  c * h, 0, py - (s * ox + c * oy),
        0, 0, 1, 0,
        0, 0, 0, 1,
    }
}
