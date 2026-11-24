// Screen space ambient occlusion.
// scene_color_texture = view-space normals from the depth prepass.

@fragment
fn fs_main(fin: Vs_Out) -> @location(0) vec4f {
    let size = vec2i(textureDimensions(scene_depth_texture));
    let p = vec2i(fin.clip.xy);
    let depth = textureLoad(scene_depth_texture, p, 0);
    if (depth <= 0.0) {
        return vec4f(1.0); // sky
    }

    let uv = fin.clip.xy * frame.resolution.zw;
    let pos = obs_view_position(uv, depth);
    let n = normalize(textureLoad(scene_color_texture, p, 0).xyz);

    // Per pixel random rotation of the sample kernel (interleaved gradient noise).
    let noise = fract(52.9829189 * fract(dot(fin.clip.xy, vec2f(0.06711056, 0.00583715)))) * 6.2831853;
    let random_vec = vec3f(cos(noise), sin(noise), 0.0);
    let tangent = normalize(random_vec - n * dot(random_vec, n) + vec3f(1e-5, 0.0, 0.0));
    let bitangent = cross(n, tangent);

    let radius = frame.ssao_params.y;
    let count = max(i32(frame.ssao_params.w), 1);
    var occlusion = 0.0;
    for (var i = 0; i < count; i++) {
        // Fibonacci spiral over the hemisphere, samples denser near the centre.
        let fi = f32(i) + 0.5;
        let cos_theta = 1.0 - fi / f32(count);
        let sin_theta = sqrt(1.0 - cos_theta * cos_theta);
        let phi = fi * 2.3999632;
        var scale = fi / f32(count);
        scale = mix(0.1, 1.0, scale * scale);
        let local = vec3f(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
        let sample_pos = pos + (tangent * local.x + bitangent * local.y + n * local.z) * radius * scale;

        let clip = frame.proj * vec4f(sample_pos, 1.0);
        if (clip.w <= 0.0) {
            continue;
        }
        let suv = vec2f(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
        if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
            continue;
        }
        let sp = clamp(vec2i(suv * vec2f(size)), vec2i(0), size - 1);
        let sd = textureLoad(scene_depth_texture, sp, 0);
        if (sd <= 0.0) {
            continue;
        }
        let scene_z = obs_view_position(suv, sd).z;
        let range_check = smoothstep(0.0, 1.0, radius / max(abs(pos.z - scene_z), 1e-4));
        if (scene_z >= sample_pos.z + 0.02 * radius) {
            occlusion += range_check;
        }
    }

    let ao = clamp(1.0 - occlusion / f32(count), 0.0, 1.0);
    return vec4f(vec3f(pow(ao, frame.ssao_params.z)), 1.0);
}
