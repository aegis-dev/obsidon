#version 450

layout(location = 0) in vec3 position;
layout(location = 1) in vec2 texture_coords;

layout(location = 0) out vec2 frag_texture_coords;

layout(set = 0, binding = 0) uniform MVPBlock {
    mat4 mvp_matrix;
} ubo;

void main() {
	gl_Position = ubo.mvp_matrix * vec4(position, 1.0);
    frag_texture_coords = texture_coords;
}