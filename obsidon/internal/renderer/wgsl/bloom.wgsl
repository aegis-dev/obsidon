// Bloom: soft threshold + 13-tap downsample pyramid, tent upsample (additive).
// scene_color_texture = source level.

struct Bloom_Out {
    @builtin(position) clip: vec4f,
    @location(0) uv: vec2f,
}

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> Bloom_Out {
    let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
    var out: Bloom_Out;
    out.clip = vec4f(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = vec2f(p.x, 1.0 - p.y);
    return out;
}

fn bloom_tap(uv: vec2f) -> vec3f {
    return textureSampleLevel(scene_color_texture, scene_sampler, uv, 0.0).rgb;
}

fn bloom_downsample13(uv: vec2f) -> vec3f {
    let t = 1.0 / vec2f(textureDimensions(scene_color_texture));
    let a = bloom_tap(uv + t * vec2f(-2.0,  2.0));
    let b = bloom_tap(uv + t * vec2f( 0.0,  2.0));
    let c = bloom_tap(uv + t * vec2f( 2.0,  2.0));
    let d = bloom_tap(uv + t * vec2f(-2.0,  0.0));
    let e = bloom_tap(uv);
    let f = bloom_tap(uv + t * vec2f( 2.0,  0.0));
    let g = bloom_tap(uv + t * vec2f(-2.0, -2.0));
    let h = bloom_tap(uv + t * vec2f( 0.0, -2.0));
    let i = bloom_tap(uv + t * vec2f( 2.0, -2.0));
    let j = bloom_tap(uv + t * vec2f(-1.0,  1.0));
    let k = bloom_tap(uv + t * vec2f( 1.0,  1.0));
    let l = bloom_tap(uv + t * vec2f(-1.0, -1.0));
    let m = bloom_tap(uv + t * vec2f( 1.0, -1.0));
    return e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
}

// First level: keep only what is brighter than the threshold (soft knee).
@fragment
fn fs_prefilter(fin: Bloom_Out) -> @location(0) vec4f {
    let c = min(bloom_downsample13(fin.uv), vec3f(10000.0));
    let threshold = frame.bloom_params.y;
    let knee = max(threshold * frame.bloom_params.z, 1e-4);
    let brightness = max(c.r, max(c.g, c.b));
    var soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-5);
    let contribution = max(soft, brightness - threshold) / max(brightness, 1e-5);
    return vec4f(c * contribution, 1.0);
}

@fragment
fn fs_downsample(fin: Bloom_Out) -> @location(0) vec4f {
    return vec4f(bloom_downsample13(fin.uv), 1.0);
}

// Added onto the next bigger level with additive blending.
@fragment
fn fs_upsample(fin: Bloom_Out) -> @location(0) vec4f {
    let t = 1.0 / vec2f(textureDimensions(scene_color_texture));
    let a = bloom_tap(fin.uv + t * vec2f(-1.0,  1.0));
    let b = bloom_tap(fin.uv + t * vec2f( 0.0,  1.0));
    let c = bloom_tap(fin.uv + t * vec2f( 1.0,  1.0));
    let d = bloom_tap(fin.uv + t * vec2f(-1.0,  0.0));
    let e = bloom_tap(fin.uv);
    let f = bloom_tap(fin.uv + t * vec2f( 1.0,  0.0));
    let g = bloom_tap(fin.uv + t * vec2f(-1.0, -1.0));
    let h = bloom_tap(fin.uv + t * vec2f( 0.0, -1.0));
    let i = bloom_tap(fin.uv + t * vec2f( 1.0, -1.0));
    let sum = e * 4.0 + (b + d + f + h) * 2.0 + (a + c + g + i);
    return vec4f(sum / 16.0, 1.0);
}
