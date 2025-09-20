package renderer

import "vendor:wgpu"

Model :: struct {
    vertex_buffer: wgpu.Buffer,
    vertex_count:  u32,
    buffer_size:  u64,
}

model_load :: proc(vertices: []Vertex) -> Model {
	vertex_buffer_size := u64(size_of(Vertex) * len(vertices))

	vertex_buffer := wgpu.DeviceCreateBuffer(instance.device, &{
		size  = vertex_buffer_size,
		usage = { .Vertex, .CopyDst },
		mappedAtCreation = false,
	})

	wgpu.QueueWriteBuffer(instance.queue, vertex_buffer, 0, rawptr(&vertices[0]), uint(vertex_buffer_size))

	return Model {vertex_buffer, u32(len(vertices)), vertex_buffer_size}
}

model_destroy :: proc(model: ^Model) {
    wgpu.BufferDestroy(model.vertex_buffer)
}