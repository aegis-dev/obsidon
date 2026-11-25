// Composite of a half resolution post effect onto the HDR image (blend:
// src * 1 + dst * src.a). scene_color_texture = the half resolution result.

@fragment
fn fs_main(fin: Vs_Out) -> @location(0) vec4f {
    let uv = fin.clip.xy * frame.resolution.zw;
    return textureSampleLevel(scene_color_texture, scene_sampler, uv, 0.0);
}
