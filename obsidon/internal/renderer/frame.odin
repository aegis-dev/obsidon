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

import "core:c"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"

import "vendor:stb/image"
import "vendor:wgpu"

// ---------------------------------------------------------------------------
// Scene state
// ---------------------------------------------------------------------------

set_camera :: proc(camera: Camera_State) { state.camera = camera }
get_camera :: proc() -> Camera_State { return state.camera }
set_lighting :: proc(lighting: Lighting_State) { state.lighting = lighting }
get_lighting :: proc() -> Lighting_State { return state.lighting }
set_clear_color :: proc(linear_color: Vec4) { state.clear_color = linear_color }
set_screen_tint :: proc(tint: Vec4) { state.screen_tint = tint }

set_time :: proc(time: f64, delta_time: f64) {
    state.time = time
    state.delta_time = delta_time
}

// Save the next frame as a PNG. `window_image`: capture what the window shows
// (after scaling, including borders) instead of the render buffer.
request_screenshot :: proc(path: string, window_image := false) {
    delete(state.screenshot_path)
    state.screenshot_path = strings.clone(path)
    state.screenshot_window = window_image
}

// ---------------------------------------------------------------------------
// Submission
// ---------------------------------------------------------------------------

draw_mesh :: proc(mesh: ^Mesh, material: ^Material, model: DMat4, tint: Vec4) {
    if mesh == nil || material == nil || mesh.vertex_buffer == nil {
        log.panic("draw_mesh: invalid mesh or material")
    }
    if material.shader.mode != .Surface {
        log.panic("draw_mesh: material uses a post-processing shader")
    }
    first := u32(len(state.instances))
    append(&state.instances, Draw_Instance{model, tint})
    append(&state.commands, Draw_Command{mesh = mesh, material = material, first = first, count = 1})
}

// Many copies of a mesh in one draw call. `tints` is either empty (white),
// one colour for all instances, or one colour per instance.
draw_mesh_instanced :: proc(mesh: ^Mesh, material: ^Material, models: []DMat4, tints: []Vec4) {
    if len(models) == 0 {
        return
    }
    if mesh == nil || material == nil || mesh.vertex_buffer == nil {
        log.panic("draw_mesh_instanced: invalid mesh or material")
    }
    if material.shader.mode != .Surface {
        log.panic("draw_mesh_instanced: material uses a post-processing shader")
    }
    first := u32(len(state.instances))
    for model, i in models {
        tint := Vec4{1, 1, 1, 1}
        if len(tints) == len(models) {
            tint = tints[i]
        } else if len(tints) > 0 {
            tint = tints[0]
        }
        append(&state.instances, Draw_Instance{model, tint})
    }
    append(&state.commands, Draw_Command{mesh = mesh, material = material, first = first, count = u32(len(models))})
}

add_light :: proc(light: Light_Instance) {
    if len(state.lights) >= MAX_LIGHTS {
        return
    }
    append(&state.lights, light)
}

add_point_light :: proc(position: DVec3, color: Vec3, range: f32) {
    add_light(Light_Instance{position = position, color = color, range = range})
}

add_spot_light :: proc(position: DVec3, direction: Vec3, color: Vec3, range: f32, inner_angle: f32, outer_angle: f32, cast_shadows := false) {
    add_light(Light_Instance{
        position     = position,
        direction    = linalg.normalize(direction),
        color        = color,
        range        = range,
        spot         = true,
        cos_inner    = math.cos(inner_angle),
        cos_outer    = math.cos(outer_angle),
        cast_shadows = cast_shadows,
    })
}

// Draw a textured quad in the 2D overlay. `model` maps the unit quad to
// overlay pixel space (origin at the screen centre, y up).
overlay_draw :: proc(texture: ^Texture, model: Mat4, color: Vec4, use_color: bool, flip_x: bool, flip_y: bool, uv_rect := Vec4{0, 0, 1, 1}) {
    if len(state.overlay) >= MAX_OVERLAY_DRAWS {
        return
    }
    w := f32(state.render_width)
    h := f32(state.render_height)
    projection := Mat4{
        2.0 / w, 0, 0, 0,
        0, 2.0 / h, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    }
    append(&state.overlay, Overlay_Command{
        texture = texture,
        data = Overlay_Draw_Data{
            mvp     = projection * model,
            color   = color,
            params  = {1 if use_color else 0, 1 if flip_x else 0, 1 if flip_y else 0, 0},
            uv_rect = uv_rect,
        },
    })
}

// 1x1 white texture, for solid colour overlay shapes.
overlay_white_texture :: proc() -> ^Texture {
    return &state.white_texture
}

// ---------------------------------------------------------------------------
// Frame
// ---------------------------------------------------------------------------

@(private)
Frustum :: struct {
    planes: [5]linalg.Vector4f64,
}

end_frame :: proc() {
    defer clear_frame_lists()

    if state.window_width == 0 || state.window_height == 0 {
        return // minimized
    }
    if state.surface_dirty {
        configure_surface()
        if state.config.render_width == 0 {
            create_targets()
        }
    }

    surface_texture := wgpu.SurfaceGetCurrentTexture(state.surface)
    switch surface_texture.status {
    case .SuccessOptimal, .SuccessSuboptimal:
    case .Timeout, .Outdated, .Lost:
        if surface_texture.texture != nil {
            wgpu.TextureRelease(surface_texture.texture)
        }
        state.surface_dirty = true
        return
    case .Occluded:
        return
    case .Error:
        log.panicf("WebGPU: failed to acquire the surface texture (%v)", surface_texture.status)
    }
    defer wgpu.TextureRelease(surface_texture.texture)

    // ---- Matrices
    cam := state.camera
    aspect := f64(state.render_width) / f64(state.render_height)
    view64 := linalg.matrix4_from_quaternion(conj(cam.rotation))
    proj64 := projection_matrix(cam, aspect)
    view_proj64 := proj64 * view64

    view := to_mat4(view64)
    proj := to_mat4(proj64)
    view_proj := to_mat4(view_proj64)
    inv_proj := to_mat4(linalg.inverse(proj64))

    // ---- Shadow views: sun cascades + spot lights that cast shadows
    shadows_active := state.config.shadows && state.lighting.sun_enabled && state.lighting.sun_shadows
    cascade_count := state.cascade_count if shadows_active else 0
    cascades: [MAX_CASCADES]Shadow_View
    for c in 0..<cascade_count {
        cascades[c] = cascade_view(cam, aspect, c, cascade_count)
    }
    spot_slots := make([]int, len(state.lights), context.temp_allocator)
    spots: [MAX_SPOT_SHADOWS]Shadow_View
    spot_count := 0
    for light, i in state.lights {
        spot_slots[i] = -1
        if state.config.spot_shadows && light.spot && light.cast_shadows && spot_count < MAX_SPOT_SHADOWS {
            spots[spot_count] = spot_view(cam, light)
            spot_slots[i] = spot_count
            spot_count += 1
        }
    }

    // ---- Frame uniforms
    l := state.lighting
    sun_dir := linalg.normalize(-l.sun_direction)
    frame := Frame_Uniforms{
        view            = view,
        proj            = proj,
        view_proj       = view_proj,
        inv_proj        = inv_proj,
        camera_position = {f32(cam.position.x), f32(cam.position.y), f32(cam.position.z), 0},
        resolution      = {f32(state.render_width), f32(state.render_height), 1.0 / f32(state.render_width), 1.0 / f32(state.render_height)},
        time            = {f32(state.time), f32(state.delta_time), f32(state.frame_index % 1_000_000), 0},
        ambient_sky     = {l.ambient_sky.r, l.ambient_sky.g, l.ambient_sky.b, 1},
        ambient_ground  = {l.ambient_ground.r, l.ambient_ground.g, l.ambient_ground.b, 1},
        sun_direction   = {f32(sun_dir.x), f32(sun_dir.y), f32(sun_dir.z), 0},
        fog_color       = {l.fog_color.r, l.fog_color.g, l.fog_color.b, 1 if l.fog_enabled else 0},
        fog_params      = {l.fog_start, l.fog_end, 0, 0},
        post_params     = {state.config.exposure, f32(state.config.tonemapper), 1 if state.surface_srgb else 0, f32(state.config.debug_view)},
        screen_tint     = state.screen_tint,
        bloom_params    = {state.config.bloom_intensity, state.config.bloom_threshold, 0.5, 1 if state.bloom_levels > 0 else 0},
        counts          = {u32(len(state.lights)), 0, 0, 0},
    }
    if state.streak_levels > 0 {
        // Each level's weight relative to the next narrower one: above 1 the
        // wide levels carry more light and the tail reaches further. Normalize
        // by the peak response to a point light (level k spreads its light over
        // 2^k texels), so the length setting doesn't change the core brightness.
        stretch := 0.6 + state.config.lens_streak_length
        peak, weight: f32 = 0, 1
        for _ in 0..<state.streak_levels {
            peak += weight
            weight *= stretch * 0.5
        }
        intensity := state.config.lens_streak_intensity / max(peak, 1e-4)
        frame.streak_params = {intensity, state.config.lens_streak_threshold, stretch, 1}
        frame.streak_tint = state.config.lens_streak_tint
    }
    if l.sun_enabled {
        frame.sun_color = {l.sun_color.r, l.sun_color.g, l.sun_color.b, 1}
    }
    {
        pcf: f32
        switch state.config.shadow_filter {
        case .Hard: pcf = 0
        case .PCF_3x3: pcf = 1
        case .PCF_5x5: pcf = 2
        }
        bias := max(l.shadow_bias, 0)
        frame.shadow_params = {1 if cascade_count > 0 else 0, f32(cascade_count), pcf, 0}
        sun_texel := 1.0 / f32(state.shadow_map.width) if state.shadow_map.width > 0 else 0
        spot_texel := 1.0 / f32(state.spot_shadow_map.width) if state.spot_shadow_map.width > 0 else 0
        frame.shadow_params2 = {sun_texel, state.config.shadow_distance, state.config.shadow_distance * 0.85, spot_texel}
        for c in 0..<cascade_count {
            v := cascades[c]
            frame.light_view_proj[c] = to_mat4(v.proj * v.view)
            frame.shadow_splits[c] = f32(v.split)
            frame.shadow_depth_bias[c] = f32(v.texel_world / v.depth_range) * bias
            frame.shadow_normal_bias[c] = f32(v.texel_world) * 1.5 * bias
        }
        for s in 0..<spot_count {
            frame.spot_view_proj[s] = to_mat4(spots[s].proj * spots[s].view)
        }
    }
    if state.config.ssao {
        samples: f32
        switch state.config.ssao_quality {
        case .Low: samples = 8
        case .Medium: samples = 16
        case .High: samples = 32
        }
        frame.ssao_params = {1, state.config.ssao_radius, state.config.ssao_intensity, samples}
        frame.ssao_params2 = {clamp(state.config.ssao_direct, 0, 1), 0, 0, 0}
    }
    wgpu.QueueWriteBuffer(state.queue, state.frame_buffer_camera, 0, &frame, size_of(frame))

    // Frame data for each shadow view: same as the camera, but seen from the light.
    write_light_frame :: proc(index: int, base: Frame_Uniforms, v: Shadow_View) {
        f := base
        f.view = to_mat4(v.view)
        f.proj = to_mat4(v.proj)
        f.view_proj = to_mat4(v.proj * v.view)
        wgpu.QueueWriteBuffer(state.queue, state.shadow_frame_buffers[index], 0, &f, size_of(f))
    }
    for c in 0..<cascade_count {
        write_light_frame(c, frame, cascades[c])
    }
    for s in 0..<spot_count {
        write_light_frame(MAX_CASCADES + s, frame, spots[s])
    }

    // ---- Per draw data (camera-relative, so f32 is precise anywhere in the universe)
    frustum := extract_frustum(view_proj64)
    camera_visible := make([]bool, len(state.commands), context.temp_allocator)
    centers := make([]DVec3, len(state.commands), context.temp_allocator)
    radii := make([]f64, len(state.commands), context.temp_allocator)
    resize(&state.draw_data, len(state.instances))
    for inst, i in state.instances {
        m := inst.model
        m[0, 3] -= cam.position.x
        m[1, 3] -= cam.position.y
        m[2, 3] -= cam.position.z
        model := to_mat4(m)
        state.draw_data[i] = Draw_Data{
            model         = model,
            normal_matrix = linalg.transpose(linalg.inverse(model)),
            tint          = inst.tint,
        }
    }
    forward := linalg.quaternion_mul_vector3(cam.rotation, DVec3{0, 0, -1})
    instance_sphere :: proc(cmd: Draw_Command, index: u32, cam: Camera_State) -> (center: DVec3, radius: f64) {
        m := state.instances[index].model
        b := cmd.mesh.bounds_center
        c := m * linalg.Vector4f64{f64(b.x), f64(b.y), f64(b.z), 1}
        scale := max(linalg.length(m[0].xyz), linalg.length(m[1].xyz), linalg.length(m[2].xyz))
        return c.xyz - cam.position, f64(cmd.mesh.bounds_radius) * scale
    }
    for &cmd, i in state.commands {
        center, radius := instance_sphere(cmd, cmd.first, cam)
        if cmd.count > 1 {
            // Sphere around all instances: centroid + farthest reach.
            sum: DVec3
            for k in cmd.first..<cmd.first + cmd.count {
                c, _ := instance_sphere(cmd, k, cam)
                sum += c
            }
            center = sum / f64(cmd.count)
            radius = 0
            for k in cmd.first..<cmd.first + cmd.count {
                c, r := instance_sphere(cmd, k, cam)
                radius = max(radius, linalg.length(c - center) + r)
            }
        }
        camera_visible[i] = sphere_in_frustum(frustum, center, radius)
        centers[i] = center
        radii[i] = radius
        cmd.depth = f32(linalg.dot(center, forward))
    }

    // Casters visible from each shadow view.
    shadow_visible: [MAX_SHADOW_VIEWS][]bool
    cull_for_view :: proc(v: Shadow_View, centers: []DVec3, radii: []f64) -> []bool {
        fr := extract_frustum(v.proj * v.view)
        out := make([]bool, len(centers), context.temp_allocator)
        for c, i in centers {
            out[i] = sphere_in_frustum(fr, c, radii[i])
        }
        return out
    }
    for c in 0..<cascade_count {
        shadow_visible[c] = cull_for_view(cascades[c], centers, radii)
    }
    for s in 0..<spot_count {
        shadow_visible[MAX_CASCADES + s] = cull_for_view(spots[s], centers, radii)
    }
    if len(state.draw_data) > state.draw_capacity {
        for state.draw_capacity < len(state.draw_data) {
            state.draw_capacity *= 2
        }
        wgpu.BufferDestroy(state.draw_buffer)
        wgpu.BufferRelease(state.draw_buffer)
        state.draw_buffer = make_buffer(u64(size_of(Draw_Data) * state.draw_capacity), {.Storage, .CopyDst})
        rebuild_frame_bind_groups()
    }
    if len(state.draw_data) > 0 {
        wgpu.QueueWriteBuffer(state.queue, state.draw_buffer, 0, raw_data(state.draw_data), uint(size_of(Draw_Data) * len(state.draw_data)))
    }

    // ---- Lights
    for light, i in state.lights {
        p := light.position - cam.position
        state.light_data[i] = Light_Data{
            position_range = {f32(p.x), f32(p.y), f32(p.z), light.range},
            color          = {light.color.r, light.color.g, light.color.b, 1 if light.spot else 0},
            direction_cone = {light.direction.x, light.direction.y, light.direction.z, light.cos_outer},
            cone_inner     = {light.cos_inner, f32(spot_slots[i]), spots[max(spot_slots[i], 0)].texel_angle if spot_slots[i] >= 0 else 0, 0},
        }
    }
    if len(state.lights) > 0 {
        wgpu.QueueWriteBuffer(state.queue, state.light_buffer, 0, &state.light_data[0], uint(size_of(Light_Data) * len(state.lights)))
    }

    // ---- Overlay
    resize(&state.overlay_data, len(state.overlay))
    for o, i in state.overlay {
        state.overlay_data[i] = o.data
    }
    if len(state.overlay_data) > 0 {
        wgpu.QueueWriteBuffer(state.queue, state.overlay_buffer, 0, raw_data(state.overlay_data), uint(size_of(Overlay_Draw_Data) * len(state.overlay_data)))
    }

    // ---- Blit params
    blit_params := [2]Vec4{state.screen_tint, {1 if state.surface_srgb else 0, 0, 0, 0}}
    wgpu.QueueWriteBuffer(state.queue, state.blit_buffer, 0, &blit_params, size_of(blit_params))

    // ---- Materials
    for cmd in state.commands {
        material_prepare(cmd.material)
    }
    for e in state.post_effects {
        if e.enabled {
            material_prepare(e.material)
        }
    }

    // ---- Sort: opaque by pipeline/material, transparent back to front
    order := make([]int, len(state.commands), context.temp_allocator)
    for i in 0..<len(order) {
        order[i] = i
    }
    Sort_Context :: struct {
        commands: []Draw_Command,
    }
    sort_ctx := Sort_Context{state.commands[:]}
    context.user_ptr = &sort_ctx
    slice.sort_by(order, proc(a, b: int) -> bool {
        ctx := (^Sort_Context)(context.user_ptr)
        ca := ctx.commands[a]
        cb := ctx.commands[b]
        qa := ca.material.shader.state.queue
        qb := cb.material.shader.state.queue
        if qa != qb {
            return qa < qb
        }
        switch qa {
        case .Background:
            return ca.first < cb.first // submission order
        case .Transparent:
            return ca.depth > cb.depth // back to front
        case .Geometry:
        }
        if ca.material.shader != cb.material.shader {
            return uintptr(ca.material.shader) < uintptr(cb.material.shader)
        }
        if ca.material != cb.material {
            return uintptr(ca.material) < uintptr(cb.material)
        }
        return uintptr(ca.mesh) < uintptr(cb.mesh)
    })

    encoder := wgpu.DeviceCreateCommandEncoder(state.device, nil)
    defer wgpu.CommandEncoderRelease(encoder)

    // ---- Shadow passes: one per cascade and per shadowed spot light
    shadow_pass :: proc(encoder: wgpu.CommandEncoder, target: wgpu.TextureView, frame_bg: wgpu.BindGroup, order: []int, visible: []bool) {
        pass := wgpu.CommandEncoderBeginRenderPass(encoder, &wgpu.RenderPassDescriptor{
            label = "shadow",
            depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                view = target,
                depthLoadOp = .Clear,
                depthStoreOp = .Store,
                depthClearValue = 1.0,
            },
        })
        draw_commands(pass, order, .Shadow, frame_bg, visible)
        wgpu.RenderPassEncoderEnd(pass)
        wgpu.RenderPassEncoderRelease(pass)
    }
    for c in 0..<cascade_count {
        shadow_pass(encoder, state.shadow_map.layers[c], state.shadow_frame_bgs[c], order, shadow_visible[c])
    }
    for s in 0..<spot_count {
        shadow_pass(encoder, state.spot_shadow_map.layers[s], state.shadow_frame_bgs[MAX_CASCADES + s], order, shadow_visible[MAX_CASCADES + s])
    }

    // ---- Depth/normal prepass + SSAO
    if state.config.ssao {
        pass := wgpu.CommandEncoderBeginRenderPass(encoder, &wgpu.RenderPassDescriptor{
            label = "prepass",
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = state.normal.view,
                loadOp = .Clear,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
                clearValue = {0, 0, 1, 0},
            },
            depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                view = state.depth.view,
                depthLoadOp = .Clear,
                depthStoreOp = .Store,
                depthClearValue = 0.0,
            },
        })
        draw_commands(pass, order, .Prepass, state.frame_bg_main, camera_visible)
        wgpu.RenderPassEncoderEnd(pass)
        wgpu.RenderPassEncoderRelease(pass)

        fullscreen_pass(encoder, state.ao_raw.view, state.pipelines.ssao, state.fs_bg_ssao, nil, "ssao")
        fullscreen_pass(encoder, state.ao.view, state.pipelines.ssao_blur, state.fs_bg_blur, nil, "ssao_blur")
    }

    // ---- Main pass
    {
        cc := state.clear_color
        pass := wgpu.CommandEncoderBeginRenderPass(encoder, &wgpu.RenderPassDescriptor{
            label = "main",
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = state.hdr[0].view,
                loadOp = .Clear,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
                clearValue = {f64(cc.r), f64(cc.g), f64(cc.b), f64(cc.a)},
            },
            depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment{
                view = state.depth.view,
                depthLoadOp = .Load if state.config.ssao else .Clear,
                depthStoreOp = .Store,
                depthClearValue = 0.0,
            },
        })
        draw_commands(pass, order, .Main, state.frame_bg_main, camera_visible)
        wgpu.RenderPassEncoderEnd(pass)
        wgpu.RenderPassEncoderRelease(pass)
    }

    // ---- HDR post effects
    hdr_index := 0
    for e in state.post_effects {
        if !e.enabled || e.stage != .Before_Tonemap {
            continue
        }
        fullscreen_pass(encoder, state.hdr[1 - hdr_index].view, get_pipeline(e.material.shader, .Post_HDR), state.fs_bg_hdr[hdr_index], e.material.bind_group, "post_hdr")
        hdr_index = 1 - hdr_index
    }

    // ---- Bloom: threshold + downsample pyramid, then additive upsample back to level 0
    if state.bloom_levels > 0 {
        fullscreen_pass(encoder, state.bloom[0].view, state.pipelines.bloom_prefilter, state.fs_bg_hdr_plain[hdr_index], nil, "bloom_prefilter")
        for i in 1..<state.bloom_levels {
            fullscreen_pass(encoder, state.bloom[i].view, state.pipelines.bloom_down, state.fs_bg_bloom[i - 1], nil, "bloom_down")
        }
        for i := state.bloom_levels - 1; i > 0; i -= 1 {
            fullscreen_pass(encoder, state.bloom[i - 1].view, state.pipelines.bloom_up, state.fs_bg_bloom[i], nil, "bloom_up", load = true)
        }
    }

    // ---- Lens streaks: bright pass, width-only downsample chain, additive
    // upsample, then added onto the HDR image (after bloom read it).
    if state.streak_levels > 0 {
        fullscreen_pass(encoder, state.streak[0].view, state.pipelines.streak_prefilter, state.fs_bg_hdr_plain[hdr_index], nil, "streak_prefilter")
        for i in 1..<state.streak_levels {
            fullscreen_pass(encoder, state.streak[i].view, state.pipelines.streak_down, state.fs_bg_streak[i - 1], nil, "streak_down")
        }
        for i := state.streak_levels - 1; i > 0; i -= 1 {
            fullscreen_pass(encoder, state.streak[i - 1].view, state.pipelines.streak_up, state.fs_bg_streak[i], nil, "streak_up", load = true)
        }
        fullscreen_pass(encoder, state.hdr[hdr_index].view, state.pipelines.streak_composite, state.fs_bg_streak[0], nil, "streak_composite", load = true)
    }

    // ---- Tonemap (or a debug view of an intermediate buffer)
    debug_bg: wgpu.BindGroup
    switch state.config.debug_view {
    case .None:
    case .Ambient_Occlusion: debug_bg = state.fs_bg_ao
    case .Normals: debug_bg = state.fs_bg_ssao
    case .Depth, .Shadow_Cascades: debug_bg = state.fs_bg_hdr[hdr_index]
    }
    if debug_bg != nil {
        fullscreen_pass(encoder, state.ldr[0].view, state.pipelines.debug_view, debug_bg, nil, "debug_view")
    } else {
        fullscreen_pass(encoder, state.ldr[0].view, state.pipelines.tonemap, state.fs_bg_hdr[hdr_index], nil, "tonemap")
    }

    // ---- LDR post effects
    ldr_index := 0
    for e in state.post_effects {
        if !e.enabled || e.stage != .After_Tonemap {
            continue
        }
        fullscreen_pass(encoder, state.ldr[1 - ldr_index].view, get_pipeline(e.material.shader, .Post_LDR), state.fs_bg_ldr[ldr_index], e.material.bind_group, "post_ldr")
        ldr_index = 1 - ldr_index
    }

    // ---- 2D overlay
    if len(state.overlay) > 0 {
        pass := wgpu.CommandEncoderBeginRenderPass(encoder, &wgpu.RenderPassDescriptor{
            label = "overlay",
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = state.ldr[ldr_index].view,
                loadOp = .Load,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            },
        })
        wgpu.RenderPassEncoderSetPipeline(pass, state.pipelines.overlay)
        wgpu.RenderPassEncoderSetBindGroup(pass, 0, state.overlay_bg)
        last_texture: ^Texture
        for o, i in state.overlay {
            if o.texture != last_texture {
                if o.texture.overlay_bg == nil {
                    o.texture.overlay_bg = make_bind_group(state.overlay_tex_layout, {bind_texture(0, o.texture.view)})
                }
                wgpu.RenderPassEncoderSetBindGroup(pass, 1, o.texture.overlay_bg)
                last_texture = o.texture
            }
            wgpu.RenderPassEncoderDraw(pass, 6, 1, 0, u32(i))
        }
        wgpu.RenderPassEncoderEnd(pass)
        wgpu.RenderPassEncoderRelease(pass)
    }

    // ---- Blit to the window
    surface_view := wgpu.TextureCreateView(surface_texture.texture, nil)
    defer wgpu.TextureViewRelease(surface_view)
    {
        pass := wgpu.CommandEncoderBeginRenderPass(encoder, &wgpu.RenderPassDescriptor{
            label = "blit",
            colorAttachmentCount = 1,
            colorAttachments = &wgpu.RenderPassColorAttachment{
                view = surface_view,
                loadOp = .Clear,
                storeOp = .Store,
                depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
                clearValue = {0, 0, 0, 1},
            },
        })
        vp := get_viewport()
        wgpu.RenderPassEncoderSetViewport(pass, vp.x, vp.y, vp.z, vp.w, 0, 1)
        wgpu.RenderPassEncoderSetPipeline(pass, state.pipelines.blit)
        wgpu.RenderPassEncoderSetBindGroup(pass, 0, state.blit_bg[ldr_index])
        wgpu.RenderPassEncoderDraw(pass, 3, 1, 0, 0)
        wgpu.RenderPassEncoderEnd(pass)
        wgpu.RenderPassEncoderRelease(pass)
    }

    // ---- Screenshot copy
    screenshot_buffer: wgpu.Buffer
    shot: Screenshot_Source
    if state.screenshot_path != "" {
        shot = {state.ldr[ldr_index].texture, state.render_width, state.render_height, false, 0}
        if state.screenshot_window {
            if state.surface_copyable {
                format := state.surface_config.format
                shot = {surface_texture.texture, state.window_width, state.window_height, format == .BGRA8Unorm || format == .BGRA8UnormSrgb, 0}
            } else {
                log.warn("screenshot: the window surface can't be read back, saving the render buffer instead")
            }
        }
        shot.bytes_per_row = (shot.width * 4 + 255) & ~u32(255)
        screenshot_buffer = make_buffer(u64(shot.bytes_per_row * shot.height), {.MapRead, .CopyDst})
        wgpu.CommandEncoderCopyTextureToBuffer(
            encoder,
            &wgpu.TexelCopyTextureInfo{texture = shot.texture, aspect = .All},
            &wgpu.TexelCopyBufferInfo{buffer = screenshot_buffer, layout = {bytesPerRow = shot.bytes_per_row, rowsPerImage = shot.height}},
            &wgpu.Extent3D{width = shot.width, height = shot.height, depthOrArrayLayers = 1},
        )
    }

    commands := wgpu.CommandEncoderFinish(encoder, nil)
    defer wgpu.CommandBufferRelease(commands)
    wgpu.QueueSubmit(state.queue, {commands})
    wgpu.SurfacePresent(state.surface)
    state.frame_index += 1

    if screenshot_buffer != nil {
        save_screenshot(screenshot_buffer, shot)
    }
}

@(private)
Screenshot_Source :: struct {
    texture:       wgpu.Texture,
    width:         u32,
    height:        u32,
    bgra:          bool,
    bytes_per_row: u32,
}

@(private)
clear_frame_lists :: proc() {
    clear(&state.instances)
    clear(&state.commands)
    clear(&state.lights)
    clear(&state.overlay)
}

@(private)
draw_commands :: proc(pass: wgpu.RenderPassEncoder, order: []int, kind: Pipeline_Kind, frame_bg: wgpu.BindGroup, visible: []bool) {
    last_pipeline: wgpu.RenderPipeline
    last_material: ^Material
    last_mesh: ^Mesh
    for idx in order {
        cmd := state.commands[idx]
        st := cmd.material.shader.state
        switch kind {
        case .Shadow:
            if !st.cast_shadows || st.blend != .Opaque {
                continue
            }
        case .Prepass:
            if st.blend != .Opaque || !st.depth_write {
                continue
            }
        case .Main, .Post_HDR, .Post_LDR:
        }
        if visible != nil && !visible[idx] {
            continue
        }

        pipeline := get_pipeline(cmd.material.shader, kind)
        if pipeline != last_pipeline {
            wgpu.RenderPassEncoderSetPipeline(pass, pipeline)
            wgpu.RenderPassEncoderSetBindGroup(pass, 0, frame_bg)
            last_pipeline = pipeline
            last_material = nil
        }
        if cmd.material != last_material {
            wgpu.RenderPassEncoderSetBindGroup(pass, 1, cmd.material.bind_group)
            last_material = cmd.material
        }
        mesh := cmd.mesh
        if mesh != last_mesh {
            wgpu.RenderPassEncoderSetVertexBuffer(pass, 0, mesh.vertex_buffer, 0, u64(mesh.vertex_count) * size_of(Vertex))
            if mesh.index_buffer != nil {
                wgpu.RenderPassEncoderSetIndexBuffer(pass, mesh.index_buffer, .Uint32, 0, u64(mesh.index_count) * size_of(u32))
            }
            last_mesh = mesh
        }
        if mesh.index_buffer != nil {
            wgpu.RenderPassEncoderDrawIndexed(pass, mesh.index_count, cmd.count, 0, 0, cmd.first)
        } else {
            wgpu.RenderPassEncoderDraw(pass, mesh.vertex_count, cmd.count, 0, cmd.first)
        }
    }
}

@(private)
fullscreen_pass :: proc(encoder: wgpu.CommandEncoder, target: wgpu.TextureView, pipeline: wgpu.RenderPipeline, group0: wgpu.BindGroup, group1: wgpu.BindGroup, label: string, load := false) {
    pass := wgpu.CommandEncoderBeginRenderPass(encoder, &wgpu.RenderPassDescriptor{
        label = label,
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment{
            view = target,
            loadOp = .Load if load else .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = {0, 0, 0, 1},
        },
    })
    wgpu.RenderPassEncoderSetPipeline(pass, pipeline)
    wgpu.RenderPassEncoderSetBindGroup(pass, 0, group0)
    if group1 != nil {
        wgpu.RenderPassEncoderSetBindGroup(pass, 1, group1)
    }
    wgpu.RenderPassEncoderDraw(pass, 3, 1, 0, 0)
    wgpu.RenderPassEncoderEnd(pass)
    wgpu.RenderPassEncoderRelease(pass)
}

@(private)
save_screenshot :: proc(buffer: wgpu.Buffer, shot: Screenshot_Source) {
    bytes_per_row := shot.bytes_per_row
    defer {
        wgpu.BufferDestroy(buffer)
        wgpu.BufferRelease(buffer)
        delete(state.screenshot_path)
        state.screenshot_path = ""
    }

    @(static) mapped: bool
    @(static) map_ok: bool
    mapped = false
    on_map :: proc "c" (status: wgpu.MapAsyncStatus, message: string, userdata1: rawptr, userdata2: rawptr) {
        mapped = true
        map_ok = status == .Success
    }
    size := uint(bytes_per_row * shot.height)
    wgpu.BufferMapAsync(buffer, {.Read}, 0, size, {mode = .AllowProcessEvents, callback = on_map})
    for !mapped {
        wgpu.DevicePoll(state.device, true)
        wgpu.InstanceProcessEvents(state.instance)
    }
    if !map_ok {
        log.error("screenshot: failed to read back the frame")
        return
    }

    data := wgpu.BufferGetConstMappedRange(buffer, 0, size)
    w, h := shot.width, shot.height
    pixels := make([]u8, w * h * 4, context.temp_allocator)
    for y in 0..<h {
        row := data[y * bytes_per_row:][:w * 4]
        copy(pixels[y * w * 4:][:w * 4], row)
    }
    if shot.bgra {
        for i := 0; i < len(pixels); i += 4 {
            pixels[i], pixels[i + 2] = pixels[i + 2], pixels[i]
        }
    }
    for i := 3; i < len(pixels); i += 4 {
        pixels[i] = 255
    }
    wgpu.BufferUnmap(buffer)

    path := strings.clone_to_cstring(state.screenshot_path, context.temp_allocator)
    if image.write_png(path, c.int(w), c.int(h), 4, raw_data(pixels), c.int(w * 4)) == 0 {
        log.errorf("screenshot: failed to write %s", state.screenshot_path)
    } else {
        log.infof("screenshot saved to %s", state.screenshot_path)
    }
}

// ---------------------------------------------------------------------------
// Math helpers
// ---------------------------------------------------------------------------

@(private)
to_mat4 :: proc(m: DMat4) -> Mat4 {
    out: Mat4
    for col in 0..<4 {
        for row in 0..<4 {
            out[row, col] = f32(m[row, col])
        }
    }
    return out
}

// Reverse-Z projection (depth 1 at the near plane, 0 at the far plane / infinity).
@(private)
projection_matrix :: proc(cam: Camera_State, aspect: f64) -> DMat4 {
    near := max(cam.near, 1e-6)
    if cam.orthographic {
        far := cam.far if cam.far > near else 10000.0
        h := cam.ortho_height * 0.5
        w := h * aspect
        return DMat4{
            1.0 / w, 0, 0, 0,
            0, 1.0 / h, 0, 0,
            0, 0, 1.0 / (far - near), far / (far - near),
            0, 0, 0, 1,
        }
    }
    f := 1.0 / math.tan(cam.fov_y * 0.5)
    a, b: f64
    if cam.far > near {
        a = near / (cam.far - near)
        b = cam.far * near / (cam.far - near)
    } else {
        a = 0
        b = near
    }
    return DMat4{
        f / aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, a, b,
        0, 0, -1, 0,
    }
}

@(private)
Shadow_View :: struct {
    view:        DMat4,
    proj:        DMat4,
    split:       f64, // cascades: far view depth covered
    texel_world: f64, // cascades: world size of one shadow map texel
    depth_range: f64, // cascades: depth range of the projection
    texel_angle: f32, // spots: angular size of one texel (for normal offset)
}

// Light view basis looking along `dir`, centred on `center` (camera-relative).
@(private)
look_matrix :: proc(dir: DVec3, center: DVec3) -> (view: DMat4, right: DVec3, up: DVec3) {
    up_hint := DVec3{0, 1, 0}
    if abs(linalg.dot(dir, up_hint)) > 0.99 {
        up_hint = {0, 0, 1}
    }
    right = linalg.normalize(linalg.cross(dir, up_hint))
    up = linalg.cross(right, dir)
    back := -dir
    view = DMat4{
        right.x, right.y, right.z, -linalg.dot(right, center),
        up.x, up.y, up.z, -linalg.dot(up, center),
        back.x, back.y, back.z, -linalg.dot(back, center),
        0, 0, 0, 1,
    }
    return
}

// Sun shadow cascade `index` of `count`: an orthographic view covering a
// slice of the camera frustum. Splits mix logarithmic and linear spacing.
@(private)
cascade_view :: proc(cam: Camera_State, aspect: f64, index: int, count: int) -> Shadow_View {
    total := f64(max(state.config.shadow_distance, 1))
    res := f64(max(state.config.shadow_resolution, 64))
    near := clamp(cam.near, 0.05, total * 0.5)
    split :: proc(i, count: int, near, far: f64) -> f64 {
        t := f64(i) / f64(count)
        LAMBDA :: 0.75
        return LAMBDA * near * math.pow(far / near, t) + (1 - LAMBDA) * (near + (far - near) * t)
    }
    d0 := 0.0 if index == 0 else split(index, count, near, total)
    d1 := total if index == count - 1 else split(index + 1, count, near, total)

    // Bounding sphere of the frustum slice [d0, d1].
    ty := math.tan(cam.fov_y * 0.5)
    tx := ty * aspect
    k := tx * tx + ty * ty
    if cam.orthographic {
        k = 0
    }
    z := clamp((d0 + d1) * (1 + k) * 0.5, d0, d1)
    radius := max(math.sqrt((d1 - z) * (d1 - z) + d1 * d1 * k), math.sqrt((z - d0) * (z - d0) + d0 * d0 * k))
    // Quantize the radius so the shadow map scale stays stable.
    radius = math.ceil(radius * 16) / 16

    forward := linalg.quaternion_mul_vector3(cam.rotation, DVec3{0, 0, -1})
    center := forward * z
    light_dir := linalg.normalize(state.lighting.sun_direction)
    _, right, up := look_matrix(light_dir, center)

    // Snap the centre to whole texels in absolute coordinates to avoid
    // shimmering edges when the camera moves.
    texel := 2 * radius / res
    abs_center := cam.position + center
    cx := linalg.dot(abs_center, right)
    cy := linalg.dot(abs_center, up)
    center += right * (math.floor(cx / texel) * texel - cx)
    center += up * (math.floor(cy / texel) * texel - cy)
    view, _, _ := look_matrix(light_dir, center)

    // Standard-Z ortho. Extend far towards the light so tall casters outside
    // the slice still cast into it.
    z_near := -max(4 * radius, 2 * total)
    z_far := radius
    proj := DMat4{
        1 / radius, 0, 0, 0,
        0, 1 / radius, 0, 0,
        0, 0, -1 / (z_far - z_near), -z_near / (z_far - z_near),
        0, 0, 0, 1,
    }
    return Shadow_View{view = view, proj = proj, split = d1, texel_world = texel, depth_range = z_far - z_near}
}

// Perspective shadow view for a spot light (camera-relative, standard Z).
@(private)
spot_view :: proc(cam: Camera_State, light: Light_Instance) -> Shadow_View {
    pos := light.position - cam.position
    dir := linalg.normalize(DVec3{f64(light.direction.x), f64(light.direction.y), f64(light.direction.z)})
    view, _, _ := look_matrix(dir, pos)
    fov := min(2 * math.acos(f64(clamp(light.cos_outer, -1, 1))) + 0.1, 3.0)
    f := 1 / math.tan(fov * 0.5)
    far := f64(max(light.range, 0.1))
    near := max(far * 0.01, 0.05)
    proj := DMat4{
        f, 0, 0, 0,
        0, f, 0, 0,
        0, 0, far / (near - far), near * far / (near - far),
        0, 0, -1, 0,
    }
    res := f64(max(state.config.spot_shadow_resolution, 64))
    return Shadow_View{view = view, proj = proj, texel_angle = f32(2 * math.tan(fov * 0.5) / res)}
}

@(private)
extract_frustum :: proc(m: DMat4) -> Frustum {
    row :: proc(m: DMat4, r: int) -> linalg.Vector4f64 {
        return {m[r, 0], m[r, 1], m[r, 2], m[r, 3]}
    }
    r0, r1, r3 := row(m, 0), row(m, 1), row(m, 3)
    fr: Frustum
    fr.planes[0] = r3 + r0
    fr.planes[1] = r3 - r0
    fr.planes[2] = r3 + r1
    fr.planes[3] = r3 - r1
    fr.planes[4] = r3 // w > 0: in front of the camera
    for &p in fr.planes {
        len := linalg.length(p.xyz)
        if len > 0 {
            p /= len
        }
    }
    return fr
}

@(private)
sphere_in_frustum :: proc(fr: Frustum, center: DVec3, radius: f64) -> bool {
    for p in fr.planes {
        if linalg.dot(p.xyz, center) + p.w < -radius {
            return false
        }
    }
    return true
}

// Rectangle of the window (x, y, width, height in window pixels, origin
// top-left) the render buffer is shown in, according to the scaling mode.
get_viewport :: proc() -> Vec4 {
    bw := f32(max(state.render_width, 1))
    bh := f32(max(state.render_height, 1))
    ww := f32(state.window_width)
    wh := f32(state.window_height)

    w, h: f32
    switch state.config.scaling {
    case .Stretch:
        return {0, 0, ww, wh}
    case .Integer:
        scale := math.floor(min(ww / bw, wh / bh))
        if scale >= 1 {
            w, h = bw * scale, bh * scale
            break
        }
        fallthrough // window smaller than the buffer: shrink to fit
    case .Fit:
        scale := min(ww / bw, wh / bh)
        w, h = math.round(bw * scale), math.round(bh * scale)
    }
    // Whole-pixel offsets keep the image neatly centred and crisp.
    return {math.floor((ww - w) * 0.5), math.floor((wh - h) * 0.5), w, h}
}
