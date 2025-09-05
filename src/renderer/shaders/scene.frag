#version 450

layout(location = 0) in vec2 frag_texture_coords;
layout(location = 0) out vec4 color;

layout(set = 0, binding = 0) uniform sampler2D texture_sampler;

void main() {
	color = texture(texture_sampler, frag_texture_coords);
}