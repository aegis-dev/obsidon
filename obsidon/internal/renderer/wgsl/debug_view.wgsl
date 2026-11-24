// Debug visualisation of intermediate buffers. post_params.w selects the mode:
// 1 = ambient occlusion, 2 = view-space normals, 3 = depth, 4 = shadow map
// scene_color_texture holds the buffer to show.

@fragment
fn fs_main(fin: Vs_Out) -> @location(0) vec4f {
    let mode = i32(frame.post_params.w);
    let uv = fin.clip.xy * frame.resolution.zw;
    if (mode == 4) {
        let d = obs_scene_linear_depth(uv);
        var tint = vec3f(1.0);
        if (frame.shadow_params.x > 0.5) {
            let count = i32(frame.shadow_params.y);
            var colors = array<vec3f, 4>(vec3f(1.0, 0.35, 0.35), vec3f(0.35, 1.0, 0.35), vec3f(0.35, 0.5, 1.0), vec3f(1.0, 1.0, 0.35));
            for (var i = 0; i < count; i++) {
                if (d < frame.shadow_splits[i]) {
                    tint = colors[i];
                    break;
                }
            }
        }
        let c = textureLoad(scene_color_texture, vec2i(fin.clip.xy), 0).rgb;
        let mapped = c / (1.0 + c);
        return vec4f(pow(mapped * tint, vec3f(1.0 / 2.2)), 1.0);
    }
    if (mode == 3) {
        let d = obs_scene_linear_depth(uv);
        let v = clamp(log2(max(d, 0.001)) / 12.0, 0.0, 1.0);
        return vec4f(vec3f(1.0 - v), 1.0);
    }
    let c = textureSampleLevel(scene_color_texture, scene_sampler_nearest, uv, 0.0);
    if (mode == 2) {
        return vec4f(c.xyz * 0.5 + 0.5, 1.0);
    }
    return vec4f(c.rrr, 1.0);
}
