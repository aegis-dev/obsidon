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

// 3D texture from tightly packed RGBA8 texels (x fastest, then y, then z).
// Linear data; declare the slot with shader.texture_3d and sample with a vec3.
texture_create_3d :: proc(texels: []u8, width, height, depth: u32, mipmaps := true) -> Texture {
    return renderer.texture_create_3d(texels, width, height, depth, mipmaps)
}

// Tileable fractal value noise volume (size^3), four independent channels.
// Each channel is 5 octaves of smooth value noise in 0..1 (mean 0.5) with the
// coarsest lattice 4 cells across the volume, so sampling at p * 0.25 behaves
// like shader.fbm(p, 5) - one texture read instead of ~40 hash evaluations.
// Use for clouds, fog, nebulae, rock detail; decorrelate by using different
// channels, scales and offsets. Deterministic for a given size and seed.
texture_noise_3d :: proc(size: u32 = 64, seed: u32 = 1) -> Texture {
    n := int(max(size, 8))
    texels := make([]u8, n * n * n * 4)
    defer delete(texels)

    hash :: #force_inline proc "contextless" (x, y, z, salt: u32) -> f32 {
        h := x * 0x8da6b343 ~ y * 0xd8163841 ~ z * 0xcb1ab31f ~ salt * 0x165667b1
        h = (h ~ (h >> 15)) * 0x2c1b3c6d
        h = (h ~ (h >> 12)) * 0x297a2d39
        h ~= h >> 15
        return f32(h) * (1.0 / 4294967295.0)
    }
    fade :: #force_inline proc "contextless" (t: f32) -> f32 {
        return t * t * (3 - 2 * t)
    }

    for z in 0 ..< n {
        for y in 0 ..< n {
            for x in 0 ..< n {
                for c in 0 ..< 4 {
                    sum, total: f32
                    amplitude: f32 = 0.5
                    octave: u32 = 0
                    for period := 4; period <= n; period *= 2 {
                        // Lattice coordinates; corners wrap at `period` (tileable).
                        scale := f32(period) / f32(n)
                        fx, fy, fz := f32(x) * scale, f32(y) * scale, f32(z) * scale
                        ix, iy, iz := int(fx), int(fy), int(fz)
                        tx, ty, tz := fade(fx - f32(ix)), fade(fy - f32(iy)), fade(fz - f32(iz))
                        x0, y0, z0 := u32(ix % period), u32(iy % period), u32(iz % period)
                        x1, y1, z1 := u32((ix + 1) % period), u32((iy + 1) % period), u32((iz + 1) % period)
                        salt := seed * 977 + u32(c) * 131 + octave * 17
                        a := math.lerp(hash(x0, y0, z0, salt), hash(x1, y0, z0, salt), tx)
                        b := math.lerp(hash(x0, y1, z0, salt), hash(x1, y1, z0, salt), tx)
                        cc := math.lerp(hash(x0, y0, z1, salt), hash(x1, y0, z1, salt), tx)
                        d := math.lerp(hash(x0, y1, z1, salt), hash(x1, y1, z1, salt), tx)
                        v := math.lerp(math.lerp(a, b, ty), math.lerp(cc, d, ty), tz)
                        sum += v * amplitude
                        total += amplitude
                        amplitude *= 0.5
                        octave += 1
                    }
                    texels[((z * n + y) * n + x) * 4 + c] = u8(clamp(sum / total, 0, 1) * 255 + 0.5)
                }
            }
        }
    }
    return renderer.texture_create_3d(texels, u32(n), u32(n), u32(n))
}

@(private)
_ :: image.Image
