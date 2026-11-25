// Anamorphic lens streaks: thin horizontal flares across bright lights.
//
// A bright pass at half resolution, then a chain that halves only the width
// (the height stays at half resolution, so the streaks stay thin), then an
// additive upsample back up the chain. Summing all levels gives the long,
// smoothly fading tail. The result is added onto the HDR image.
// scene_color_texture = source level.

struct Streak_Out {
    @builtin(position) clip: vec4f,
    @location(0) uv: vec2f,
}

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> Streak_Out {
    let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
    var out: Streak_Out;
    out.clip = vec4f(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = vec2f(p.x, 1.0 - p.y);
    return out;
}

fn streak_tap(uv: vec2f) -> vec3f {
    return textureSampleLevel(scene_color_texture, scene_sampler, uv, 0.0).rgb;
}

// Horizontal tent: the centre tap sits between two source texels (bilinear
// averages them), the side taps cover the neighbouring pairs.
fn streak_tent(uv: vec2f, dx: f32) -> vec3f {
    return streak_tap(uv) * 0.5 + (streak_tap(uv - vec2f(dx, 0.0)) + streak_tap(uv + vec2f(dx, 0.0))) * 0.25;
}

// Whether a sample is bright enough to streak (0..1, soft). Starts where the
// bright pass's soft knee starts (half the threshold), so everything that
// streaks also counts as bright area for the shape tests below.
fn streak_mask(uv: vec2f, threshold: f32) -> f32 {
    let c = streak_tap(uv);
    let knee = max(threshold * 0.5, 1e-4);
    return clamp((max(c.r, max(c.g, c.b)) - (threshold - knee)) / knee, 0.0, 1.0);
}

// Full resolution HDR -> half resolution, keeping only very bright pixels.
@fragment
fn fs_prefilter(fin: Streak_Out) -> @location(0) vec4f {
    let t = 1.0 / vec2f(textureDimensions(scene_color_texture));
    let c = min(streak_tent(fin.uv, 2.0 * t.x), vec3f(10000.0));
    let threshold = frame.streak_params.y;
    let knee = max(threshold * 0.5, 1e-4);
    let brightness = max(c.r, max(c.g, c.b));
    var soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-5);
    let contribution = max(soft, brightness - threshold) / max(brightness, 1e-5);
    var bright = c * contribution;

    // Thin core: a lens throws the streak from the centre line of a light, so
    // a big bright source (a star's disc) gives a thin line, not a band as
    // tall as the disc. Compare the bright area above and below this pixel
    // (taps 1..256 rows away): balanced only on the source's centre row.
    // A point light has nothing bright above or below and passes whole.
    var above = 0.0;
    var below = 0.0;
    var side = 0.0;
    var d = 1.0;
    for (var i = 0; i < 9; i++) {
        above += streak_mask(fin.uv - vec2f(0.0, d * t.y), threshold) * d;
        below += streak_mask(fin.uv + vec2f(0.0, d * t.y), threshold) * d;
        side += (streak_mask(fin.uv - vec2f(d * t.x, 0.0), threshold) + streak_mask(fin.uv + vec2f(d * t.x, 0.0), threshold)) * d;
        d *= 2.0;
    }
    let balance = abs(above - below) / (above + below + 2.0);
    bright *= 1.0 - smoothstep(0.0, 0.25, balance);
    // Sources filling a big part of the view (a star seen from close by)
    // aren't point-like: their streak fades out. The sums add the tap
    // distances still inside bright area: ~254 up to 64 px each way, ~510
    // once the 128 px taps are inside too. Measured both ways, so a column
    // near a big disc's limb or a slice of it between hull parts doesn't
    // pass as a small light.
    bright *= 1.0 - smoothstep(270.0, 480.0, max(above + below, side));

    // Compress very bright sources (a star next to an engine glow) so one
    // light doesn't drown the frame in a white bar.
    let level = max(bright.r, max(bright.g, bright.b));
    return vec4f(bright / (1.0 + level * 0.05), 1.0);
}

// Halve the width only.
@fragment
fn fs_downsample(fin: Streak_Out) -> @location(0) vec4f {
    let t = 1.0 / vec2f(textureDimensions(scene_color_texture));
    return vec4f(streak_tent(fin.uv, 2.0 * t.x), 1.0);
}

// Added onto the next wider level with additive blending, weighted by the
// stretch (from the length setting): more weight on the wide levels = longer
// tails. The tint is applied once per level, so the core keeps the light's
// colour and the tails shift towards the tint (lens coating dispersion).
@fragment
fn fs_upsample(fin: Streak_Out) -> @location(0) vec4f {
    let t = 1.0 / vec2f(textureDimensions(scene_color_texture));
    return vec4f(streak_tent(fin.uv, t.x) * frame.streak_tint.rgb * frame.streak_params.z, 1.0);
}

// Final level 0 -> HDR image (additive).
@fragment
fn fs_composite(fin: Streak_Out) -> @location(0) vec4f {
    let s = streak_tap(fin.uv);
    return vec4f(s * frame.streak_params.x, 0.0);
}
