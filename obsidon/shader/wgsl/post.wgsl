// ---------------------------------------------------------------------------
// Obsidon engine library - post-processing shaders
// ---------------------------------------------------------------------------

@group(0) @binding(1) var scene_color_texture: texture_2d<f32>;
@group(0) @binding(2) var scene_depth_texture: texture_depth_2d;
@group(0) @binding(3) var scene_sampler: sampler;         // linear, clamped
@group(0) @binding(4) var scene_sampler_nearest: sampler; // nearest, clamped
@group(0) @binding(5) var bloom_texture: texture_2d<f32>;  // bloom result (black when bloom is off)

// 0..1 screen position of the fragment (top-left origin), set by fs_main.
var<private> obs_post_uv: vec2f;

// Bloom light at `uv` (already blurred, HDR).
fn obs_bloom(uv: vec2f) -> vec3f {
    return textureSampleLevel(bloom_texture, scene_sampler, uv, 0.0).rgb;
}

fn obs_scene_color(uv: vec2f) -> vec4f {
    return textureSampleLevel(scene_color_texture, scene_sampler, uv, 0.0);
}

fn obs_scene_raw_depth(uv: vec2f) -> f32 {
    let size = vec2i(textureDimensions(scene_depth_texture));
    let p = clamp(vec2i(uv * vec2f(size)), vec2i(0), size - 1);
    return textureLoad(scene_depth_texture, p, 0);
}

// Distance along the view axis (reverse-Z depth buffer: 0 = infinitely far).
fn obs_scene_linear_depth(uv: vec2f) -> f32 {
    let d = obs_scene_raw_depth(uv);
    if (d <= 0.0) {
        return 1e30;
    }
    let ndc = vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, d, 1.0);
    let view = frame.inv_proj * ndc;
    return -view.z / view.w;
}

// World-space direction (camera-relative world, unit length) of the view ray
// through `uv`. The view matrix is rotation only, so its transpose inverts it.
fn obs_view_ray(uv: vec2f) -> vec3f {
    let ndc = vec4f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 1.0, 1.0);
    let v = frame.inv_proj * ndc;
    let dir_view = normalize(v.xyz / v.w);
    let rot = mat3x3f(frame.view[0].xyz, frame.view[1].xyz, frame.view[2].xyz);
    return normalize(transpose(rot) * dir_view);
}
