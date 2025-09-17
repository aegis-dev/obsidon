package renderer

import "core:strconv"
import "vendor:wgpu"

Vec2 :: [2]f32

Vec3 :: [3]f32

Vertex :: struct {
    position : Vec3,
    uv       : Vec2,
}

Model :: struct {
    vertex_buffer: wgpu.Buffer,
    vertex_count:  u32,
    buffer_size:  u64,
}

Texture :: struct {
    width: u32,
    height: u32,
    texture: wgpu.Texture,
    view: wgpu.TextureView,
    bind_group: wgpu.BindGroup,
}

TexturedModel :: struct {
    model: Model,
    texture: Texture,
}
