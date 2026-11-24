// Shared full screen triangle for internal passes (appended after the engine library).

struct Vs_Out {
    @builtin(position) clip: vec4f,
}

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> Vs_Out {
    let uv = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
    var out: Vs_Out;
    out.clip = vec4f(uv * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

fn obs_view_position(uv: vec2f, depth: f32) -> vec3f {
    let ndc = vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    let v = frame.inv_proj * ndc;
    return v.xyz / v.w;
}
