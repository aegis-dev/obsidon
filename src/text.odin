package obsidon

text_draw :: proc(font: ^Font, text: string, position: Vec2, scale: f32, color: Vec4, line_spacing: f32 = 0.2, ui: bool = false) {
    glyph_position := position
    a_glyph := font.glyphs['A']

    for char in text {
        if char == '\n' {
            glyph_position.x = position.x
            glyph_position.y -= a_glyph.height * scale + a_glyph.height * line_spacing * scale // 0.2 for line spacing
            continue
        }
        
        glyph := font.glyphs[char]
        if glyph.width == 0 || glyph.height == 0 {
            glyph_position.x += a_glyph.advance * scale
        } else {
            y_offset := glyph.height + glyph.offset_y // Adjust for baseline
            offset := Vec2{0.0, y_offset * 2 * scale}

            if ui {
                sprite_draw_ui_colored(&glyph.sprite, glyph_position, offset, 0.0, false, scale, color)
            } else {
                sprite_draw_colored(&glyph.sprite, glyph_position, offset, 0.0, false, scale, color)
            }

            glyph_position.x += (glyph.advance + 1) * scale // +1 for letter spacing
        }
    }
}

// TODO: add multi-line support
text_width :: proc(font: ^Font, text: string, scale: f32) -> f32 {
    width: f32 = 0.0
    for char in text {
        glyph: Glyph
        if char == ' ' {
            // Use 'A' as a placeholder for space width
            glyph = font.glyphs['A']
        } else {
            glyph = font.glyphs[char]
        }
       
        if (char == ' ') {
            width += glyph.advance * scale
        } else {
            width += (glyph.advance + 1) * scale // +1 for letter spacing
        }
    }
    return width
}
