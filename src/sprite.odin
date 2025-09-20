package obsidon

import "renderer"

Sprite :: struct {
    width: u32,
    height: u32,
    textured_model: renderer.TexturedModel
}

sprite_load :: proc(png_data: []u8) -> Sprite {
    texture := renderer.load_texture_from_png(png_data)
    quad_vertices := get_sprite_quad(texture.width, texture.height)
    model := renderer.load_vertex_buffer(quad_vertices[:])
    return Sprite {
        texture.width,
        texture.height,
        renderer.TexturedModel {
            model,
            texture,
        }
    }
}

sprite_destroy :: proc(sprite: Sprite) {
    // TODO
}

sprite_draw :: proc(sprite: ^Sprite, position: Vec2, origin: Vec2, angle: f32, flip: bool, scale: f32) {
	renderer.draw(&sprite.textured_model, position, origin, angle, flip, scale)
}

set_sprite_color_override :: proc(color: Vec4) {
    renderer.set_offscreen_color_override(color)
}

clear_sprite_color_override :: proc() {
    renderer.clear_offscreen_color_override()
}

@(private)
get_sprite_quad :: proc(width: u32, height: u32) -> [6]renderer.Vertex {
	width  := f32(width)
	height := f32(height)

    vertices := [6]renderer.Vertex {
		//               positions                  tex coords
		renderer.Vertex {Vec3 {width, height, 0.0}, Vec2 {1.0, 0.0}},
		renderer.Vertex {Vec3 {width, 0.0,    0.0}, Vec2 {1.0, 1.0}},
		renderer.Vertex {Vec3 {0.0,   height, 0.0}, Vec2 {0.0, 0.0}},

		renderer.Vertex {Vec3 {0.0,   height, 0.0}, Vec2 {0.0, 0.0}},
		renderer.Vertex {Vec3 {width, 0.0,    0.0}, Vec2 {1.0, 1.0}},
		renderer.Vertex {Vec3 {0.0,   0.0,    0.0}, Vec2 {0.0, 1.0}},
	}

	return vertices
}
