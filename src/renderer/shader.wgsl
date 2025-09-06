// Vertex input structure
struct VertexInput {
    @location(0) position: vec3<f32>,   // vertex position
    @location(1) tex_coords: vec2<f32>, // texture coordinates
};

// Vertex output structure (goes to fragment shader)
struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.position = vec4<f32>(input.position, 1.0); // clip-space position
    out.tex_coords = input.tex_coords;
    return out;
}

// Texture + sampler bindings
@group(0) @binding(0) var my_texture: texture_2d<f32>;
@group(0) @binding(1) var my_sampler: sampler;

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    return textureSample(my_texture, my_sampler, input.tex_coords);
}