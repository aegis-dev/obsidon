// 4x4 box blur, matches the 4x4 pattern of the SSAO noise.
// scene_color_texture = raw SSAO.

@fragment
fn fs_main(fin: Vs_Out) -> @location(0) vec4f {
    let size = vec2i(textureDimensions(scene_color_texture));
    let p = vec2i(fin.clip.xy);
    var sum = 0.0;
    for (var y = -2; y < 2; y++) {
        for (var x = -2; x < 2; x++) {
            let q = clamp(p + vec2i(x, y), vec2i(0), size - 1);
            sum += textureLoad(scene_color_texture, q, 0).r;
        }
    }
    let ao = sum / 16.0;
    return vec4f(ao, ao, ao, 1.0);
}
