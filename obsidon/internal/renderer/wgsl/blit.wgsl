// Final upscale of the render target to the window rectangle (get_viewport):
// nearest / bilinear sampling, or FSR 1 RCAS sharpening of the EASU upscaled
// image (fsr_easu.wgsl, already at the rectangle's size). Then the native
// overlay on top, the screen tint and the output encoding.
//
// rcas() is a port of FidelityFX Super Resolution 1.0 RCAS (ffx_fsr1.h):
// Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

struct Blit_Params {
    tint:  vec4f, // rgb, a = amount
    flags: vec4f, // x: output is sRGB (decode gamma), y: composite the native overlay, z: film grain, w: frame
    fsr:   vec4f, // x: RCAS (source is the EASU output, 1:1), y: sharpness (exp2(-stops))
}

@group(0) @binding(0) var source_texture: texture_2d<f32>;
@group(0) @binding(1) var source_sampler: sampler;
@group(0) @binding(2) var<uniform> params: Blit_Params;
// Native overlay at window resolution (premultiplied alpha, gamma space),
// exactly the size of the viewport: sampled 1:1.
@group(0) @binding(3) var overlay_texture: texture_2d<f32>;

struct Vs_Out {
    @builtin(position) clip: vec4f,
    @location(0) uv: vec2f,
}

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> Vs_Out {
    let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
    var out: Vs_Out;
    out.clip = vec4f(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = vec2f(p.x, 1.0 - p.y);
    return out;
}

fn luma(c: vec3f) -> f32 {
    return c.b * 0.5 + (c.r * 0.5 + c.g);
}

// Film grain: white noise per window pixel, new every frame.
// (Integer PCG hash: no precision patterns at large pixel / frame values.)
fn grain(p: vec2f, frame: f32) -> f32 {
    var h = u32(p.x) * 1973u + u32(p.y) * 9277u + u32(frame) * 26699u;
    h = h * 747796405u + 2891336453u;
    h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
    h = (h >> 22u) ^ h;
    return f32(h) / 4294967295.0 - 0.5;
}

fn load_source(p: vec2i, size: vec2i) -> vec3f {
    return textureLoad(source_texture, clamp(p, vec2i(0), size - 1), 0).rgb;
}

// AMD FidelityFX Super Resolution 1.0 - RCAS (Robust Contrast Adaptive
// Sharpening). WGSL port of ffx_fsr1.h (MIT license, see the top of this
// file and THIRD_PARTY_NOTICES.md). A 5 tap cross; the negative lobe is limited so
// the result can't leave the local min / max (no ringing, no clipping).
fn rcas(p: vec2i, sharpness: f32) -> vec3f {
    let size = vec2i(textureDimensions(source_texture));
    //    b
    //  d e f
    //    h
    let b = load_source(p + vec2i(0, -1), size);
    let d = load_source(p + vec2i(-1, 0), size);
    let e = load_source(p, size);
    let f = load_source(p + vec2i(1, 0), size);
    let h = load_source(p + vec2i(0, 1), size);
    let mn4 = min(min(b, d), min(f, h));
    let mx4 = max(max(b, d), max(f, h));
    // Largest negative lobe that keeps every channel within [0, 1].
    let hit_min = min(mn4, e) / max(4.0 * mx4, vec3f(1e-5));
    let hit_max = (1.0 - max(mx4, e)) / min(4.0 * mn4 - 4.0, vec3f(-1e-5));
    let lobe_rgb = max(-hit_min, hit_max);
    let RCAS_LIMIT = 0.25 - 1.0 / 16.0;
    var lobe = max(-RCAS_LIMIT, min(max(lobe_rgb.r, max(lobe_rgb.g, lobe_rgb.b)), 0.0)) * sharpness;
    // Noise detection (FSR_RCAS_DENOISE): less sharpening where the centre
    // stands out alone (dithering, grain), full sharpening on real edges.
    let bl = luma(b); let dl = luma(d); let el = luma(e); let fl = luma(f); let hl = luma(h);
    let range = max(max(max(bl, dl), max(el, fl)), hl) - min(min(min(bl, dl), min(el, fl)), hl);
    var nz = saturate(abs(0.25 * (bl + dl + fl + hl) - el) / max(range, 1e-5));
    lobe = lobe * (1.0 - 0.5 * nz);
    return (lobe * (b + d + f + h) + e) / (4.0 * lobe + 1.0);
}

@fragment
fn fs_main(fin: Vs_Out) -> @location(0) vec4f {
    var c: vec3f;
    if (params.fsr.x > 0.5) {
        let size = vec2f(textureDimensions(source_texture));
        c = rcas(vec2i(clamp(fin.uv * size, vec2f(0.0), size - 1.0)), params.fsr.y);
    } else {
        c = textureSample(source_texture, source_sampler, fin.uv).rgb;
    }
    if (params.flags.z > 0.0) {
        c = c + grain(floor(fin.clip.xy), params.flags.w) * params.flags.z;
    }
    if (params.flags.y > 0.5) {
        let size = vec2f(textureDimensions(overlay_texture));
        let ui = textureLoad(overlay_texture, vec2i(clamp(fin.uv * size, vec2f(0.0), size - 1.0)), 0);
        c = ui.rgb + c * (1.0 - ui.a);
    }
    c = mix(c, params.tint.rgb, params.tint.a);
    if (params.flags.x > 0.5) {
        c = pow(c, vec3f(2.2));
    }
    return vec4f(c, 1.0);
}
