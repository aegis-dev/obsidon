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