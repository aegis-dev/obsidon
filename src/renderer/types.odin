package renderer

import "vendor:wgpu"

Vec2 :: [2]f32

Vec3 :: [3]f32

Vec4 :: [4]f32

Vertex :: struct #packed {
    position : Vec3,
    uv       : Vec2,
}

TexturedModel :: struct {
    model: Model,
    texture: Texture,
}
