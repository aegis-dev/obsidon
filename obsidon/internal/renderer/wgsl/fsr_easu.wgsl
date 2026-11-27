// AMD FidelityFX Super Resolution 1.0 - EASU (Edge Adaptive Spatial Upsampling).
// WGSL port of the reference algorithm (ffx_fsr1.h, AMD FidelityFX SDK, MIT
// license - notice below and in THIRD_PARTY_NOTICES.md). Runs on the tonemapped (gamma space) LDR
// image, renders at the output (window rectangle) size. RCAS sharpening
// follows in the blit (blit.wgsl).
//
// For each output pixel: 12 taps around the source position, the local edge
// direction and length from luma gradients in the four bilinear quadrants, then
// a Lanczos-2 like kernel stretched along the edge, clamped to the 2x2
// neighbourhood (no ringing).
//
// FidelityFX Super Resolution 1.0 (portions of this file):
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

struct Easu_Params {
    input_size:  vec2f, // render buffer
    output_size: vec2f, // window rectangle
}

@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var<uniform> params: Easu_Params;

struct Vs_Out {
    @builtin(position) clip: vec4f,
}

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> Vs_Out {
    let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
    var out: Vs_Out;
    out.clip = vec4f(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

fn tap(p: vec2i) -> vec3f {
    let size = vec2i(params.input_size);
    return textureLoad(source, clamp(p, vec2i(0), size - 1), 0).rgb;
}

fn luma(c: vec3f) -> f32 {
    return c.b * 0.5 + (c.r * 0.5 + c.g);
}

// Direction and length contribution of one bilinear quadrant (a cross of five lumas).
fn easu_set(dir: ptr<function, vec2f>, len: ptr<function, f32>, w: f32, la: f32, lb: f32, lc: f32, ld: f32, le: f32) {
    // Horizontal: b c d around c.
    let dc = ld - lc;
    let cb = lc - lb;
    let dir_x = ld - lb;
    var len_x = saturate(abs(dir_x) / max(max(abs(dc), abs(cb)), 1e-6));
    len_x = len_x * len_x;
    // Vertical: a c e around c.
    let ec = le - lc;
    let ca = lc - la;
    let dir_y = le - la;
    var len_y = saturate(abs(dir_y) / max(max(abs(ec), abs(ca)), 1e-6));
    len_y = len_y * len_y;
    *dir += vec2f(dir_x, dir_y) * w;
    *len += (len_x + len_y) * w;
}

// One kernel tap: offset from the sample position, rotated into the edge
// frame and scaled by the anisotropic stretch.
fn easu_tap(acc_c: ptr<function, vec3f>, acc_w: ptr<function, f32>, off: vec2f, dir: vec2f, len2: vec2f, lob: f32, clp: f32, c: vec3f) {
    var v = vec2f(off.x * dir.x + off.y * dir.y, off.x * -dir.y + off.y * dir.x);
    v = v * len2;
    let d2 = min(dot(v, v), clp);
    // Lanczos-2 approximation: (25/16 * (2/5 x^2 - 1)^2 - (25/16 - 1)) * (lob x^2 - 1)^2
    var wb = 2.0 / 5.0 * d2 - 1.0;
    var wa = lob * d2 - 1.0;
    wb = wb * wb;
    wa = wa * wa;
    wb = 25.0 / 16.0 * wb - (25.0 / 16.0 - 1.0);
    let w = wb * wa;
    *acc_c += c * w;
    *acc_w += w;
}

@fragment
fn fs_main(fin: Vs_Out) -> @location(0) vec4f {
    // Source position of this output pixel (in source pixels, texel centres at integers).
    let scale = params.input_size / params.output_size;
    var pp = fin.clip.xy * scale - 0.5;
    let fp = floor(pp);
    pp = pp - fp;
    let f0 = vec2i(fp);

    //      b c
    //    e f g h
    //    i j k l
    //      n o
    let b = tap(f0 + vec2i(0, -1));
    let c = tap(f0 + vec2i(1, -1));
    let e = tap(f0 + vec2i(-1, 0));
    let f = tap(f0);
    let g = tap(f0 + vec2i(1, 0));
    let h = tap(f0 + vec2i(2, 0));
    let i = tap(f0 + vec2i(-1, 1));
    let j = tap(f0 + vec2i(0, 1));
    let k = tap(f0 + vec2i(1, 1));
    let l = tap(f0 + vec2i(2, 1));
    let n = tap(f0 + vec2i(0, 2));
    let o = tap(f0 + vec2i(1, 2));

    let bl = luma(b); let cl = luma(c); let el = luma(e); let fl = luma(f);
    let gl = luma(g); let hl = luma(h); let il = luma(i); let jl = luma(j);
    let kl = luma(k); let ll = luma(l); let nl = luma(n); let ol = luma(o);

    // Edge direction and length, bilinearly weighted over the four quadrants.
    var dir = vec2f(0.0);
    var len = 0.0;
    easu_set(&dir, &len, (1.0 - pp.x) * (1.0 - pp.y), bl, el, fl, gl, jl);
    easu_set(&dir, &len, pp.x * (1.0 - pp.y), cl, fl, gl, hl, kl);
    easu_set(&dir, &len, (1.0 - pp.x) * pp.y, fl, il, jl, kl, nl);
    easu_set(&dir, &len, pp.x * pp.y, gl, jl, kl, ll, ol);

    // Normalize the direction (no edge: along x).
    let dir_r = dot(dir, dir);
    if (dir_r < 1.0 / 32768.0) {
        dir = vec2f(1.0, 0.0);
    } else {
        dir = dir * inverseSqrt(dir_r);
    }
    // Length: 0 = no edge (round kernel) .. 1 = strong edge (stretched, sharper).
    len = len * 0.5;
    len = len * len;
    let stretch = dot(dir, dir) / max(abs(dir.x), abs(dir.y));
    let len2 = vec2f(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len);
    let lob = 0.5 + ((1.0 / 4.0 - 0.04) - 0.5) * len;
    let clp = 1.0 / lob;

    var acc_c = vec3f(0.0);
    var acc_w = 0.0;
    easu_tap(&acc_c, &acc_w, vec2f(0.0, -1.0) - pp, dir, len2, lob, clp, b);
    easu_tap(&acc_c, &acc_w, vec2f(1.0, -1.0) - pp, dir, len2, lob, clp, c);
    easu_tap(&acc_c, &acc_w, vec2f(-1.0, 1.0) - pp, dir, len2, lob, clp, i);
    easu_tap(&acc_c, &acc_w, vec2f(0.0, 1.0) - pp, dir, len2, lob, clp, j);
    easu_tap(&acc_c, &acc_w, vec2f(0.0, 0.0) - pp, dir, len2, lob, clp, f);
    easu_tap(&acc_c, &acc_w, vec2f(-1.0, 0.0) - pp, dir, len2, lob, clp, e);
    easu_tap(&acc_c, &acc_w, vec2f(1.0, 1.0) - pp, dir, len2, lob, clp, k);
    easu_tap(&acc_c, &acc_w, vec2f(2.0, 1.0) - pp, dir, len2, lob, clp, l);
    easu_tap(&acc_c, &acc_w, vec2f(2.0, 0.0) - pp, dir, len2, lob, clp, h);
    easu_tap(&acc_c, &acc_w, vec2f(1.0, 0.0) - pp, dir, len2, lob, clp, g);
    easu_tap(&acc_c, &acc_w, vec2f(1.0, 2.0) - pp, dir, len2, lob, clp, o);
    easu_tap(&acc_c, &acc_w, vec2f(0.0, 2.0) - pp, dir, len2, lob, clp, n);

    // Deringing: clamp to the 2x2 neighbourhood.
    let mn = min(min(f, g), min(j, k));
    let mx = max(max(f, g), max(j, k));
    let color = clamp(acc_c / max(acc_w, 1e-6), mn, mx);
    return vec4f(color, 1.0);
}
