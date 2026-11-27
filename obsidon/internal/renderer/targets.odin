// Copyright 2025 Egidijus Vaišvila
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

package renderer

import "vendor:wgpu"

// (Re)create all render targets and the bind groups referencing them
// according to the current graphics config and window size.
@(private)
create_targets :: proc() {
    destroy_targets()

    w := state.config.render_width
    h := state.config.render_height
    if w == 0 || h == 0 {
        w = max(state.window_width, 1)
        h = max(state.window_height, 1)
    }
    state.render_width = w
    state.render_height = h

    color_usage := wgpu.TextureUsageFlags{.RenderAttachment, .TextureBinding}
    state.hdr[0] = make_target(w, h, HDR_FORMAT, color_usage)
    state.hdr[1] = make_target(w, h, HDR_FORMAT, color_usage)
    state.ldr[0] = make_target(w, h, LDR_FORMAT, color_usage + {.CopySrc})
    state.ldr[1] = make_target(w, h, LDR_FORMAT, color_usage + {.CopySrc})
    state.depth = make_target(w, h, DEPTH_FORMAT, color_usage)

    if state.config.ssao {
        state.normal = make_target(w, h, NORMAL_FORMAT, color_usage)
        state.ao_raw = make_target(w, h, AO_FORMAT, color_usage)
        state.ao = make_target(w, h, AO_FORMAT, color_usage)
    }
    state.cascade_count = clamp(state.config.shadow_cascades, 1, MAX_CASCADES)
    if state.config.shadows {
        state.shadow_map = make_depth_array(max(state.config.shadow_resolution, 64), state.cascade_count)
    }
    if state.config.spot_shadows {
        state.spot_shadow_map = make_depth_array(max(state.config.spot_shadow_resolution, 64), MAX_SPOT_SHADOWS)
    }

    // Bloom pyramid: half resolution and down.
    state.bloom_levels = 0
    if state.config.bloom {
        bw, bh := max(w / 2, 1), max(h / 2, 1)
        for i in 0..<MAX_BLOOM_LEVELS {
            state.bloom[i] = make_target(bw, bh, HDR_FORMAT, color_usage)
            state.bloom_levels += 1
            if bw <= 8 || bh <= 8 {
                break
            }
            bw, bh = max(bw / 2, 1), max(bh / 2, 1)
        }
    }

    // Lens streak chain: half resolution, then only the width halves (thin streaks).
    state.streak_levels = 0
    if state.config.lens_streaks {
        sw, sh_ := max(w / 2, 1), max(h / 2, 1)
        for i in 0..<MAX_STREAK_LEVELS {
            state.streak[i] = make_target(sw, sh_, HDR_FORMAT, color_usage)
            state.streak_levels += 1
            if sw <= 8 {
                break
            }
            sw = max(sw / 2, 1)
        }
    }

    state.post_half = make_target(max(w / 2, 1), max(h / 2, 1), HDR_FORMAT, color_usage)

    rebuild_frame_bind_groups()

    // Binding 5 is the bloom texture for passes that read it (black otherwise).
    fullscreen_bg :: proc(color: wgpu.TextureView, with_bloom := true) -> wgpu.BindGroup {
        aux := state.black_texture.view
        if with_bloom && state.bloom_levels > 0 {
            aux = state.bloom[0].view
        }
        return make_bind_group(state.fullscreen_layout, {
            bind_buffer(0, state.frame_buffer_camera, size_of(Frame_Uniforms)),
            bind_texture(1, color),
            bind_texture(2, state.depth.view),
            bind_sampler(3, state.sampler_linear),
            bind_sampler(4, state.sampler_nearest),
            bind_texture(5, aux),
        })
    }

    for i in 0..<state.bloom_levels {
        state.fs_bg_bloom[i] = fullscreen_bg(state.bloom[i].view, false)
    }
    for i in 0..<state.streak_levels {
        state.fs_bg_streak[i] = fullscreen_bg(state.streak[i].view, false)
    }
    state.fs_bg_post_half = fullscreen_bg(state.post_half.view, false)

    if state.config.ssao {
        state.fs_bg_ssao = fullscreen_bg(state.normal.view)
        state.fs_bg_blur = fullscreen_bg(state.ao_raw.view)
        state.fs_bg_ao = fullscreen_bg(state.ao.view)
    }
    for i in 0..<2 {
        state.fs_bg_hdr[i] = fullscreen_bg(state.hdr[i].view)
        state.fs_bg_hdr_plain[i] = fullscreen_bg(state.hdr[i].view, false)
        state.fs_bg_ldr[i] = fullscreen_bg(state.ldr[i].view)
    }
    update_output_targets(force = true)
}

// Targets at the size of the window rectangle the render buffer is shown in
// (get_viewport: follows the scaling mode, render resolution and window
// size), used only when that rectangle differs from the buffer:
// - native overlay (config.native_overlay): the overlay renders there instead
//   of into the LDR buffer, so the UI is drawn at window resolution
// - FSR 1 (upscale_filter = .FSR1, rectangle larger than the buffer on both
//   axes): EASU upscales into it, the blit sharpens (RCAS). Shrinking or a 1:1
//   rectangle falls back to bilinear.
// Checked every frame; rebuilt only when something changed.
@(private)
update_output_targets :: proc(force := false) {
    size: [2]u32
    vp := get_viewport()
    if vp.z >= 1 && vp.w >= 1 {
        size = {u32(vp.z), u32(vp.w)}
    }
    if size == {state.render_width, state.render_height} {
        size = {}
    }
    overlay := size != {} && state.config.native_overlay
    fsr := size != {} && state.config.upscale_filter == .FSR1 && size.x > state.render_width && size.y > state.render_height
    if !force && size == state.output_size && overlay == state.overlay_active && fsr == state.fsr_active {
        return
    }
    destroy_target(&state.overlay_target)
    destroy_target(&state.fsr_target)
    for i in 0..<2 {
        release_bind_group(&state.easu_bg[i])
    }
    state.output_size = size
    state.overlay_active = overlay
    state.fsr_active = fsr
    usage := wgpu.TextureUsageFlags{.RenderAttachment, .TextureBinding, .CopySrc}
    if overlay {
        state.overlay_target = make_target(size.x, size.y, LDR_FORMAT, usage)
    }
    if fsr {
        state.fsr_target = make_target(size.x, size.y, LDR_FORMAT, usage)
        easu_params := [4]f32{f32(state.render_width), f32(state.render_height), f32(size.x), f32(size.y)}
        wgpu.QueueWriteBuffer(state.queue, state.easu_buffer, 0, &easu_params, size_of(easu_params))
        for i in 0..<2 {
            state.easu_bg[i] = make_bind_group(state.easu_layout, {
                bind_texture(0, state.ldr[i].view),
                bind_buffer(1, state.easu_buffer, 16),
            })
        }
    }
    overlay_view := state.overlay_target.view if overlay else state.black_texture.view
    for i in 0..<2 {
        release_bind_group(&state.blit_bg[i])
        state.blit_bg[i] = make_bind_group(state.blit_layout, {
            bind_texture(0, state.fsr_target.view if fsr else state.ldr[i].view),
            bind_sampler(1, state.sampler_nearest if state.config.upscale_filter == .Nearest else state.sampler_linear),
            bind_buffer(2, state.blit_buffer, BLIT_PARAMS_SIZE),
            bind_texture(3, overlay_view),
        })
    }
}

// Window pixels per overlay pixel (1 unless the native overlay is in use).
get_overlay_scale :: proc() -> [2]f32 {
    if !state.overlay_active {
        return {1, 1}
    }
    return {f32(state.output_size.x) / f32(max(state.render_width, 1)), f32(state.output_size.y) / f32(max(state.render_height, 1))}
}

// Whether FSR 1 upscaling runs this frame (see update_output_targets).
is_fsr_active :: proc() -> bool {
    return state.fsr_active
}

// Frame bind groups reference the draw buffer, so they are rebuilt when it grows.
@(private)
rebuild_frame_bind_groups :: proc() {
    release_bind_group(&state.frame_bg_main)
    for &bg in state.shadow_frame_bgs {
        release_bind_group(&bg)
    }

    shadow_view := state.shadow_map.view if state.config.shadows else state.dummy_depth.view
    spot_view := state.spot_shadow_map.view if state.config.spot_shadows else state.dummy_depth.view
    ao_view := state.ao.view if state.config.ssao else state.white_texture.view
    draw_size := u64(size_of(Draw_Data) * state.draw_capacity)

    state.frame_bg_main = make_bind_group(state.frame_layout, {
        bind_buffer(0, state.frame_buffer_camera, size_of(Frame_Uniforms)),
        bind_buffer(1, state.draw_buffer, draw_size),
        bind_buffer(2, state.light_buffer, size_of(Light_Data) * MAX_LIGHTS),
        bind_texture(3, shadow_view),
        bind_sampler(4, state.sampler_shadow),
        bind_texture(5, ao_view),
        bind_texture(6, spot_view),
    })
    // Shadow passes render into the shadow maps, so they can't also sample them.
    for i in 0..<MAX_SHADOW_VIEWS {
        state.shadow_frame_bgs[i] = make_bind_group(state.frame_layout, {
            bind_buffer(0, state.shadow_frame_buffers[i], size_of(Frame_Uniforms)),
            bind_buffer(1, state.draw_buffer, draw_size),
            bind_buffer(2, state.light_buffer, size_of(Light_Data) * MAX_LIGHTS),
            bind_texture(3, state.dummy_depth.view),
            bind_sampler(4, state.sampler_shadow),
            bind_texture(5, state.white_texture.view),
            bind_texture(6, state.dummy_depth.view),
        })
    }
}

@(private)
destroy_targets :: proc() {
    release_bind_group(&state.frame_bg_main)
    for &bg in state.shadow_frame_bgs {
        release_bind_group(&bg)
    }
    release_bind_group(&state.fs_bg_ssao)
    release_bind_group(&state.fs_bg_blur)
    release_bind_group(&state.fs_bg_ao)
    for i in 0..<2 {
        release_bind_group(&state.fs_bg_hdr[i])
        release_bind_group(&state.fs_bg_hdr_plain[i])
        release_bind_group(&state.fs_bg_ldr[i])
        release_bind_group(&state.blit_bg[i])
        destroy_target(&state.hdr[i])
        destroy_target(&state.ldr[i])
    }
    for i in 0..<MAX_BLOOM_LEVELS {
        release_bind_group(&state.fs_bg_bloom[i])
        destroy_target(&state.bloom[i])
    }
    state.bloom_levels = 0
    for i in 0..<MAX_STREAK_LEVELS {
        release_bind_group(&state.fs_bg_streak[i])
        destroy_target(&state.streak[i])
    }
    state.streak_levels = 0
    release_bind_group(&state.fs_bg_post_half)
    destroy_target(&state.post_half)
    destroy_target(&state.overlay_target)
    destroy_target(&state.fsr_target)
    for i in 0..<2 {
        release_bind_group(&state.easu_bg[i])
    }
    state.output_size = {}
    state.overlay_active = false
    state.fsr_active = false
    destroy_target(&state.depth)
    destroy_target(&state.normal)
    destroy_target(&state.ao_raw)
    destroy_target(&state.ao)
    destroy_target(&state.shadow_map)
    destroy_target(&state.spot_shadow_map)
}
