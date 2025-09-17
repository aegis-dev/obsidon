package obsidon

import "renderer"

Sprite :: struct {
    width: u32,
    height: u32,
    textured_model: renderer.TexturedModel
}

load_sprite :: proc(png_data: []u8) -> Sprite {
    texture := renderer.load_texture_from_png(png_data)
    quad_vertices := get_sprite_quad(texture.width, texture.height)
    model := renderer.load_vertex_buffer(quad_vertices)
    return Sprite {
        texture.width,
        texture.height,
        renderer.TexturedModel {
            model,
            texture,
        }
    }
}

draw_sprite :: proc() {
	// TODO
}

@(private)
get_sprite_quad :: proc(width: u32, height: u32) -> []renderer.Vertex {
	width  := f32(width)
	height := f32(height)

	vertices := []renderer.Vertex {
		//               positions                  tex coords
		renderer.Vertex {Vec3 {width, 0.0,    0.0}, Vec2 {1.0, 1.0}},
		renderer.Vertex {Vec3 {width, height, 0.0}, Vec2 {1.0, 0.0}},
		renderer.Vertex {Vec3 {0.0,   0.0,    0.0}, Vec2 {0.0, 1.0}},
		renderer.Vertex {Vec3 {0.0,   0.0,    0.0}, Vec2 {0.0, 1.0}},
		renderer.Vertex {Vec3 {width, height, 0.0}, Vec2 {1.0, 0.0}},
		renderer.Vertex {Vec3 {0.0,   height, 0.0}, Vec2 {0.0, 0.0}},
	}

	return vertices
}
