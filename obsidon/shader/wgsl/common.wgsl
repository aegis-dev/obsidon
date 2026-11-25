// ---------------------------------------------------------------------------
// Obsidon engine library - common
// Keep in sync with internal/renderer/frame.odin
// ---------------------------------------------------------------------------

struct Frame {
    view:            mat4x4f, // camera rotation only (world space is camera-relative)
    proj:            mat4x4f,
    view_proj:       mat4x4f,
    inv_proj:        mat4x4f,
    light_view_proj: array<mat4x4f, 4>, // sun shadow cascades
    spot_view_proj:  array<mat4x4f, 4>, // shadowed spot lights
    camera_position: vec4f,   // absolute camera position (xyz)
    resolution:      vec4f,   // width, height, 1/width, 1/height
    time:            vec4f,   // time, delta time, frame index, 0
    ambient_sky:     vec4f,   // linear rgb * intensity
    ambient_ground:  vec4f,   // linear rgb * intensity
    sun_direction:   vec4f,   // xyz: normalized direction towards the sun
    sun_color:       vec4f,   // linear rgb * intensity
    fog_color:       vec4f,   // rgb, w: 1 = enabled
    fog_params:      vec4f,   // start, end
    shadow_params:   vec4f,   // sun shadows enabled, cascade count, pcf radius (texels)
    shadow_params2:  vec4f,   // cascade texel size (uv), shadow distance, fade start, spot texel size (uv)
    shadow_splits:   vec4f,   // far view depth of each cascade
    shadow_depth_bias:  vec4f, // per cascade, light space depth
    shadow_normal_bias: vec4f, // per cascade, world units
    ssao_params:     vec4f,   // enabled, radius, intensity, sample count
    ssao_params2:    vec4f,   // amount of AO applied to direct light
    post_params:     vec4f,   // exposure, tonemapper (0 none, 1 reinhard, 2 aces), surface is sRGB
    screen_tint:     vec4f,   // rgb, a = amount (obsidon.set_screen_color_override)
    bloom_params:    vec4f,   // intensity, threshold, knee, enabled
    streak_params:   vec4f,   // lens streaks: intensity (normalized), threshold, stretch, enabled
    streak_tint:     vec4f,   // lens streaks: linear rgb, applied per chain level
    counts:          vec4u,   // point/spot light count
}

@group(0) @binding(0) var<uniform> frame: Frame;

// Fragment coordinate of the current fragment, set at the start of fs_main.
var<private> obs_frag_coord: vec4f;

fn obs_world_to_clip(p: vec3f) -> vec4f {
    return frame.view_proj * vec4f(p, 1.0);
}

fn obs_world_to_view(p: vec3f) -> vec3f {
    return (frame.view * vec4f(p, 1.0)).xyz;
}

fn obs_view_direction(world_pos: vec3f) -> vec3f {
    // The camera sits at the origin of camera-relative world space.
    return normalize(-world_pos);
}

fn obs_fog(color: vec3f, world_pos: vec3f) -> vec3f {
    if (frame.fog_color.w < 0.5) {
        return color;
    }
    let d = length(world_pos);
    let f = clamp((d - frame.fog_params.x) / max(frame.fog_params.y - frame.fog_params.x, 0.0001), 0.0, 1.0);
    return mix(color, frame.fog_color.rgb, f);
}

// PS1 style vertex snapping: positions snap to a virtual pixel grid.
fn obs_snap_to_grid(clip: vec4f, grid: vec2f) -> vec4f {
    if (clip.w <= 0.0) {
        return clip;
    }
    let ndc = clip.xy / clip.w;
    let snapped = floor((ndc * 0.5 + 0.5) * grid + 0.5) / grid * 2.0 - 1.0;
    return vec4f(snapped * clip.w, clip.z, clip.w);
}

fn obs_bayer4(p: vec2f) -> f32 {
    var m = array<f32, 16>(
         0.0,  8.0,  2.0, 10.0,
        12.0,  4.0, 14.0,  6.0,
         3.0, 11.0,  1.0,  9.0,
        15.0,  7.0, 13.0,  5.0,
    );
    let i = (u32(p.x) % 4u) + (u32(p.y) % 4u) * 4u;
    return (m[i] + 0.5) / 16.0;
}

fn obs_dither(color: vec3f, levels: f32) -> vec3f {
    let steps = max(levels - 1.0, 1.0);
    let t = obs_bayer4(obs_frag_coord.xy) - 0.5;
    return clamp(floor(color * steps + 0.5 + t) / steps, vec3f(0.0), vec3f(1.0));
}

fn obs_quantize(color: vec3f, levels: vec3f) -> vec3f {
    let steps = max(levels - 1.0, vec3f(1.0));
    return floor(color * steps + 0.5) / steps;
}

fn obs_luminance(color: vec3f) -> f32 {
    return dot(color, vec3f(0.2126, 0.7152, 0.0722));
}

fn obs_hash(p: vec2f) -> f32 {
    let q = fract(p * vec2f(123.34, 456.21));
    let r = q + dot(q, q + 45.32);
    return fract(r.x * r.y);
}

fn obs_hash3(p: vec3f) -> f32 {
    var q = fract(p * 0.3183099 + vec3f(0.1, 0.2, 0.3));
    q *= 17.0;
    return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

// Smooth 3D value noise in 0..1.
fn obs_noise3(p: vec3f) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(obs_hash3(i + vec3f(0.0, 0.0, 0.0)), obs_hash3(i + vec3f(1.0, 0.0, 0.0)), u.x),
            mix(obs_hash3(i + vec3f(0.0, 1.0, 0.0)), obs_hash3(i + vec3f(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(obs_hash3(i + vec3f(0.0, 0.0, 1.0)), obs_hash3(i + vec3f(1.0, 0.0, 1.0)), u.x),
            mix(obs_hash3(i + vec3f(0.0, 1.0, 1.0)), obs_hash3(i + vec3f(1.0, 1.0, 1.0)), u.x), u.y),
        u.z);
}

// Fractal noise (sum of octaves) in roughly 0..1.
fn obs_fbm3(p: vec3f, octaves: f32) -> f32 {
    var sum = 0.0;
    var amplitude = 0.5;
    var total = 0.0;
    var q = p;
    let n = i32(clamp(octaves, 1.0, 10.0));
    for (var i = 0; i < n; i++) {
        sum += obs_noise3(q) * amplitude;
        total += amplitude;
        q = q * 2.03 + vec3f(1.7, 9.2, 3.4);
        amplitude *= 0.5;
    }
    return sum / total;
}
