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

import "core:image"
import "core:image/png"
import "core:log"
import "core:math"

import "internal/renderer"

Texture :: renderer.Texture

// Load a PNG (e.g. from #load("texture.png")).
// `srgb`: true for colour textures, false for data (normal maps, masks).
texture_load :: proc(png_data: []u8, srgb := true, mipmaps := true) -> Texture {
    img, err := png.load_from_bytes(png_data, {.alpha_add_if_missing})
    if err != nil {
        log.panicf("texture_load: failed to load PNG (%v)", err)
    }
    defer png.destroy(img)
    if img.depth != 8 || img.channels != 4 {
        log.panicf("texture_load: unsupported PNG format (%d channels, %d bit)", img.channels, img.depth)
    }
    return renderer.texture_create(img.pixels[:], u32(img.width), u32(img.height), srgb, mipmaps)
}

// Create a texture from RGBA8 pixels (top row first).
texture_create :: proc(pixels: []u8, width: u32, height: u32, srgb := true, mipmaps := true) -> Texture {
    return renderer.texture_create(pixels, width, height, srgb, mipmaps)
}

// Procedural checkerboard, handy for prototyping.
texture_checker :: proc(size: u32 = 64, cells: u32 = 8, a := WHITE, b := GRAY) -> Texture {
    pixels := make([]u8, size * size * 4, context.temp_allocator)
    cell := max(size / max(cells, 1), 1)
    for y in 0..<size {
        for x in 0..<size {
            c := a if ((x / cell) + (y / cell)) % 2 == 0 else b
            i := (y * size + x) * 4
            pixels[i + 0] = u8(c.r * 255)
            pixels[i + 1] = u8(c.g * 255)
            pixels[i + 2] = u8(c.b * 255)
            pixels[i + 3] = u8(c.a * 255)
        }
    }
    return renderer.texture_create(pixels, size, size)
}

// Build a tangent space normal map from a height field (row-major, top row
// first, values roughly 0..1). `strength` scales the slopes. Wraps around.
texture_normal_map_from_heights :: proc(heights: []f32, width: u32, height: u32, strength: f32 = 2) -> Texture {
    pixels := make([]u8, width * height * 4, context.temp_allocator)
    at :: proc(h: []f32, w, hh: u32, x, y: int) -> f32 {
        xx := (x + int(w)) % int(w)
        yy := (y + int(hh)) % int(hh)
        return h[yy * int(w) + xx]
    }
    for y in 0..<int(height) {
        for x in 0..<int(width) {
            dx := (at(heights, width, height, x + 1, y) - at(heights, width, height, x - 1, y)) * strength
            // Image rows go down, normal map +Y points up the image.
            dy := (at(heights, width, height, x, y - 1) - at(heights, width, height, x, y + 1)) * strength
            n := [3]f32{-dx, -dy, 1}
            l := math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
            n /= l
            i := (y * int(width) + x) * 4
            pixels[i + 0] = u8((n.x * 0.5 + 0.5) * 255)
            pixels[i + 1] = u8((n.y * 0.5 + 0.5) * 255)
            pixels[i + 2] = u8((n.z * 0.5 + 0.5) * 255)
            pixels[i + 3] = 255
        }
    }
    return renderer.texture_create(pixels, width, height, srgb = false)
}

texture_destroy :: proc(texture: ^Texture) {
    renderer.texture_destroy(texture)
}

@(private)
_ :: image.Image
