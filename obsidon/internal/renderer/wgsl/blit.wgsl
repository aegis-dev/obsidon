// Final upscale of the render target to the window (letterboxed, nearest filtering).

struct Blit_Params {
    tint:  vec4f, // rgb, a = amount
    flags: vec4f, // x: output is sRGB (decode gamma)
}

@group(0) @binding(0) var source_texture: texture_2d<f32>;
@group(0) @binding(1) var source_sampler: sampler;
@group(0) @binding(2) var<uniform> params: Blit_Params;

struct Vs_Out {
    @builtin(position) clip: vec4f,
    @location(0) uv: vec2f,
}

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> Vs_Out {
    let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
    var out: Vs_Out;
    out.clip = vec4f(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = vec2f(p.x, 1.0 - p.y);
    return out;
}

@fragment
fn fs_main(fin: Vs_Out) -> @location(0) vec4f {
    var c = textureSample(source_texture, source_sampler, fin.uv).rgb;
    c = mix(c, params.tint.rgb, params.tint.a);
    if (params.flags.x > 0.5) {
        c = pow(c, vec3f(2.2));
    }
    return vec4f(c, 1.0);
}
