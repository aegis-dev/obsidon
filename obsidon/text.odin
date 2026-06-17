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

text_draw :: proc(font: ^Font, text: string, position: Vec2, scale: f32, color: Vec4, line_spacing: f32 = 0.2, ui: bool = false) {
    glyph_position := position
    line_height := f64((font.ascent - font.descent + font.line_gap) * scale * (1.0 + line_spacing))
    fallback_glyph := font.glyphs[' ']

    for char in text {
        if char == '\n' {
            glyph_position.x = position.x
            glyph_position.y -= line_height
            continue
        }
        
        glyph, ok := font.glyphs[char]
        if !ok {
            glyph = fallback_glyph
        }

        if glyph.width == 0 || glyph.height == 0 {
            glyph_position.x += f64(glyph.advance * scale)
        } else {
            draw_position := glyph_position + Vec2{
                f64(glyph.offset_x * scale),
                -f64((glyph.height + glyph.offset_y) * scale),
            }

            if ui {
                sprite_draw_ui_colored(&glyph.sprite, draw_position, VEC2_ZERO, 0.0, false, scale, color)
            } else {
                sprite_draw_colored(&glyph.sprite, draw_position, VEC2_ZERO, 0.0, false, scale, color)
            }

            glyph_position.x += f64((glyph.advance + 1) * scale) // +1 for letter spacing
        }
    }
}

// TODO: add multi-line support
text_width :: proc(font: ^Font, text: string, scale: f32) -> f32 {
    width: f32 = 0.0
    for char in text {
        if char == '\n' {
            continue
        }

        glyph, ok := font.glyphs[char]
        if !ok {
            glyph = font.glyphs[' ']
        }
       
        if char == ' ' {
            width += glyph.advance * scale
        } else {
            width += (glyph.advance + 1) * scale // +1 for letter spacing
        }
    }
    return width
}
