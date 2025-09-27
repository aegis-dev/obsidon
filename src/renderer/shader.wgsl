// Copyright 2025 Egidijus Vaišvila
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

const MAX_DRAWS: u32 = 8192;

struct VertexInput {
    @location(0) position: vec3<f32>,   // vertex position
    @location(1) tex_coords: vec2<f32>, // texture coordinates
};

struct DrawCallMetadata {
    mvp: mat4x4<f32>,
    color: vec4<f32>,
    use_color: f32,
    flip_x: f32,
    flip_y: f32,
};

struct DrawCallMetadataBlock {
    data: array<DrawCallMetadata, MAX_DRAWS>,
};

@group(0) @binding(0) var my_texture: texture_2d<f32>;
@group(0) @binding(1) var my_sampler: sampler;
@group(0) @binding(2) var<storage, read> draw_call_metadata: DrawCallMetadataBlock;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
    @location(1) instance_idx: u32,
};

@vertex
fn vs_main(input: VertexInput, @builtin(instance_index) instance_idx: u32) -> VertexOutput {
    var out: VertexOutput;
    let metadata = draw_call_metadata.data[instance_idx];
    out.position = metadata.mvp * vec4<f32>(input.position, 1.0);

    var uv = input.tex_coords;
    if (metadata.flip_x > 0.5) { uv.x = 1.0 - uv.x; }
    if (metadata.flip_y > 0.5) { uv.y = 1.0 - uv.y; }
    out.tex_coords = uv;

    out.instance_idx = instance_idx;
    return out;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let metadata = draw_call_metadata.data[input.instance_idx];
    let tex_color = textureSample(my_texture, my_sampler, input.tex_coords);

    // Mix override color into the texture RGB; keep original texture alpha.
    let factor = clamp(metadata.use_color * metadata.color.a, 0.0, 1.0);
    let rgb = mix(tex_color.rgb, metadata.color.rgb, factor);
    return vec4<f32>(rgb, tex_color.a);
}