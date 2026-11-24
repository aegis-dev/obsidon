// 2D overlay (sprites, text, UI). Drawn on top of the 3D scene in gamma space.

struct Overlay_Draw {
    mvp:     mat4x4f,
    color:   vec4f,
    params:  vec4f, // use_color, flip_x, flip_y
    uv_rect: vec4f, // u0, v0, u1, v1
}

@group(0) @binding(0) var<storage, read> overlay_draws: array<Overlay_Draw>;
@group(0) @binding(1) var overlay_sampler: sampler;
@group(1) @binding(0) var overlay_texture: texture_2d<f32>;

struct Vs_Out {
    @builtin(position) clip: vec4f,
    @location(0) uv: vec2f,
    @location(1) @interpolate(flat) instance: u32,
}

@vertex
fn vs_main(@builtin(vertex_index) index: u32, @builtin(instance_index) instance: u32) -> Vs_Out {
    // Unit quad, two triangles: (0,0) (1,0) (0,1) (0,1) (1,0) (1,1)
    var corners = array<vec2f, 6>(
        vec2f(0.0, 0.0), vec2f(1.0, 0.0), vec2f(0.0, 1.0),
        vec2f(0.0, 1.0), vec2f(1.0, 0.0), vec2f(1.0, 1.0),
    );
    let d = overlay_draws[instance];
    let corner = corners[index];
    var t = vec2f(corner.x, 1.0 - corner.y);
    if (d.params.y > 0.5) { t.x = 1.0 - t.x; }
    if (d.params.z > 0.5) { t.y = 1.0 - t.y; }

    var out: Vs_Out;
    out.clip = d.mvp * vec4f(corner, 0.0, 1.0);
    out.uv = mix(d.uv_rect.xy, d.uv_rect.zw, t);
    out.instance = instance;
    return out;
}

fn linear_to_srgb(c: vec3f) -> vec3f {
    let lo = c * 12.92;
    let hi = 1.055 * pow(c, vec3f(1.0 / 2.4)) - 0.055;
    return select(hi, lo, c <= vec3f(0.0031308));
}

@fragment
fn fs_main(fin: Vs_Out) -> @location(0) vec4f {
    let d = overlay_draws[fin.instance];
    let texel = textureSample(overlay_texture, overlay_sampler, fin.uv);
    // Textures are sRGB, sampled as linear; the overlay blends in gamma space.
    let tex_rgb = linear_to_srgb(texel.rgb);
    let use_color = d.params.x > 0.5;
    let rgb = select(tex_rgb, d.color.rgb, use_color);
    let alpha = texel.a * select(1.0, d.color.a, use_color);
    return vec4f(rgb, alpha);
}
