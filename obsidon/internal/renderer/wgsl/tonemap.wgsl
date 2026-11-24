// HDR -> LDR. Applies exposure, the tonemapper and gamma encoding.

fn aces(x: vec3f) -> vec3f {
    // Narkowicz 2015 ACES filmic fit
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3f(0.0), vec3f(1.0));
}

@fragment
fn fs_main(fin: Vs_Out) -> @location(0) vec4f {
    var c = textureLoad(scene_color_texture, vec2i(fin.clip.xy), 0).rgb;
    if (frame.bloom_params.w > 0.5) {
        let uv = fin.clip.xy * frame.resolution.zw;
        c += textureSampleLevel(bloom_texture, scene_sampler, uv, 0.0).rgb * frame.bloom_params.x;
    }
    c *= frame.post_params.x;
    let mode = i32(frame.post_params.y);
    if (mode == 1) {
        c = c / (1.0 + c);
    } else if (mode == 2) {
        c = aces(c);
    }
    c = clamp(c, vec3f(0.0), vec3f(1.0));
    return vec4f(pow(c, vec3f(1.0 / 2.2)), 1.0);
}
