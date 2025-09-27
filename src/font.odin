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

import "core:log"
import "core:c"

import "vendor:stb/truetype"

import "renderer"

@(private)
Glyph :: struct {
    sprite:     Sprite,
    advance:    f32,
    offset_x:   f32,
    offset_y:   f32,
    width:      f32,
    height:     f32,
}

Font :: struct {
    glyphs: map[rune]Glyph,
}

font_load :: proc(ttf_data: []u8, font_size: f32) -> Font {
    font_info := truetype.fontinfo{}

       // Initialize font info
    if !truetype.InitFont(&font_info, raw_data(ttf_data), 0) {
        log.panic("Failed to initialize font")
    }

    scale := truetype.ScaleForPixelHeight(&font_info, font_size)

    font := Font{
        glyphs = make(map[rune]Glyph),
    }

    characters := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789,.!?;:\"'\\|/+=-_)(}{&^%$#@~<>"

    for char in characters {
        font.glyphs[char] = render_glyph(&font_info, char, scale)
    }

    return font
}

font_destroy :: proc(font: ^Font) {
    for _, &glyph in font.glyphs {
        glyph_destroy(&glyph)
    }
    delete(font.glyphs)
}

@(private) 
glyph_destroy :: proc(glyph: ^Glyph) {
    sprite_destroy(&glyph.sprite)
}

@(private)
render_glyph :: proc(font: ^truetype.fontinfo, char: rune, scale: f32) -> Glyph {
    width, height, xoff, yoff: i32
    bitmap_ptr := truetype.GetCodepointBitmap(font, 0, scale, char, &width, &height, &xoff, &yoff)
   
    advance, left_side_bearing: i32
    truetype.GetCodepointHMetrics(font, char, &advance, &left_side_bearing)

    // Convert grayscale to RGBA for PNG
    rgba_data := make([]u8, width * height * 4)
    defer delete(rgba_data)

    if bitmap_ptr == nil || width == 0 || height == 0 {
        log.panicf("Failed to render glyph for char '%c'", char)
    }
    defer truetype.FreeBitmap(bitmap_ptr, nil)

    for i in 0..<(width * height) {
        gray_value := bitmap_ptr[i]
        rgba_data[i * 4 + 0] = 255        // R
        rgba_data[i * 4 + 1] = 255        // G
        rgba_data[i * 4 + 2] = 255        // B
        rgba_data[i * 4 + 3] = gray_value // A
    }

    texture := renderer.texture_load_from_raw_pixels(rgba_data, u32(width), u32(height))
    quad_vertices := get_sprite_quad(u32(width), u32(height))
    model := renderer.model_load(quad_vertices[:])
    
    sprite := Sprite{
        u32(width),
        u32(height),
        renderer.TexturedModel{
            model,
            texture,
        },
    }

    return Glyph{
        sprite = sprite,
        advance = f32(advance) * scale,
        offset_x = f32(xoff),
        offset_y = f32(yoff),
        width = f32(width),
        height = f32(height),
    }
}
