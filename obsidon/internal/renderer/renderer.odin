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

import "base:runtime"

import "core:fmt"
import "core:log"
import "core:strings"

import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

import sh "../../shader"

MAX_LIGHTS            :: 256
MAX_OVERLAY_DRAWS     :: 16384
INITIAL_DRAW_CAPACITY :: 4096

HDR_FORMAT    :: wgpu.TextureFormat.RGBA16Float
LDR_FORMAT    :: wgpu.TextureFormat.RGBA8Unorm
DEPTH_FORMAT  :: wgpu.TextureFormat.Depth32Float
NORMAL_FORMAT :: wgpu.TextureFormat.RGBA16Float
AO_FORMAT     :: wgpu.TextureFormat.RGBA8Unorm

@(private)
VF :: wgpu.ShaderStageFlags{.Vertex, .Fragment}
@(private)
F :: wgpu.ShaderStageFlags{.Fragment}

@(private)
FULLSCREEN_WGSL :: string(#load("wgsl/fullscreen.wgsl"))
@(private)
SSAO_WGSL :: string(#load("wgsl/ssao.wgsl"))
@(private)
SSAO_BLUR_WGSL :: string(#load("wgsl/ssao_blur.wgsl"))
@(private)
TONEMAP_WGSL :: string(#load("wgsl/tonemap.wgsl"))
@(private)
BLOOM_WGSL :: string(#load("wgsl/bloom.wgsl"))
MAX_BLOOM_LEVELS :: 6
LENS_STREAK_WGSL :: string(#load("wgsl/lens_streak.wgsl"))
POST_COMPOSITE_WGSL :: string(#load("wgsl/post_composite.wgsl"))
MAX_STREAK_LEVELS :: 8
@(private)
DEBUG_VIEW_WGSL :: string(#load("wgsl/debug_view.wgsl"))
@(private)
BLIT_WGSL :: string(#load("wgsl/blit.wgsl"))
@(private)
OVERLAY_WGSL :: string(#load("wgsl/overlay.wgsl"))
FSR_EASU_WGSL :: string(#load("wgsl/fsr_easu.wgsl"))
BLIT_PARAMS_SIZE :: 48 // tint, flags, fsr (vec4 each)

MAX_CASCADES      :: 4
MAX_SPOT_SHADOWS  :: 4
MAX_SHADOW_VIEWS  :: MAX_CASCADES + MAX_SPOT_SHADOWS

Render_Target :: struct {
    texture: wgpu.Texture,
    view:    wgpu.TextureView,
    width:   u32,
    height:  u32,
    // Per-layer views of array targets (shadow maps).
    layers:      [4]wgpu.TextureView,
    layer_count: int,
}

Camera_State :: struct {
    position:     DVec3,
    rotation:     DQuat,
    fov_y:        f64, // radians
    near:         f64,
    far:          f64, // 0 = infinite
    orthographic: bool,
    ortho_height: f64,
}

Lighting_State :: struct {
    ambient_sky:    Vec3, // linear * intensity
    ambient_ground: Vec3,
    sun_enabled:    bool,
    sun_shadows:    bool,
    sun_direction:  DVec3, // direction the light travels
    sun_color:      Vec3,  // linear * intensity
    fog_enabled:    bool,
    fog_color:      Vec3,  // linear
    fog_start:      f32,
    fog_end:        f32,
    shadow_bias:    f32,   // multiplier on the automatic bias
}

@(private)
Draw_Instance :: struct {
    model: DMat4,
    tint:  Vec4,
}

@(private)
Draw_Command :: struct {
    mesh:     ^Mesh,
    material: ^Material,
    first:    u32,
    count:    u32,
    depth:    f32,
}

@(private)
Light_Instance :: struct {
    position:  DVec3,
    direction: Vec3,
    color:     Vec3,
    range:     f32,
    spot:      bool,
    cos_inner: f32,
    cos_outer: f32,
    cast_shadows: bool,
}

@(private)
Overlay_Command :: struct {
    texture: ^Texture,
    data:    Overlay_Draw_Data,
}

@(private)
Fullscreen_Pipelines :: struct {
    ssao:      wgpu.RenderPipeline,
    ssao_blur: wgpu.RenderPipeline,
    tonemap:   wgpu.RenderPipeline,
    debug_view: wgpu.RenderPipeline,
    bloom_prefilter: wgpu.RenderPipeline,
    bloom_down:      wgpu.RenderPipeline,
    bloom_up:        wgpu.RenderPipeline,
    streak_prefilter: wgpu.RenderPipeline,
    streak_down:      wgpu.RenderPipeline,
    streak_up:        wgpu.RenderPipeline,
    streak_composite: wgpu.RenderPipeline,
    post_composite:   wgpu.RenderPipeline,
    blit:      wgpu.RenderPipeline,
    overlay:   wgpu.RenderPipeline,
    easu:      wgpu.RenderPipeline,
}

Renderer_State :: struct {
    ctx:            runtime.Context,
    instance:       wgpu.Instance,
    surface:        wgpu.Surface,
    adapter:        wgpu.Adapter,
    device:         wgpu.Device,
    queue:          wgpu.Queue,
    surface_config: wgpu.SurfaceConfiguration,
    surface_srgb:   bool,
    window:         glfw.WindowHandle,
    window_width:   u32,
    window_height:  u32,
    surface_dirty:  bool,
    config:         Graphics_Config,
    render_width:   u32,
    render_height:  u32,

    // Samplers
    sampler_material: wgpu.Sampler,
    sampler_linear:   wgpu.Sampler,
    sampler_nearest:  wgpu.Sampler,
    sampler_shadow:   wgpu.Sampler,

    // Layouts
    frame_layout:      wgpu.BindGroupLayout, // group 0 of surface shaders
    fullscreen_layout: wgpu.BindGroupLayout, // group 0 of post / internal fullscreen passes
    blit_layout:       wgpu.BindGroupLayout,
    overlay_layout:    wgpu.BindGroupLayout,
    overlay_tex_layout: wgpu.BindGroupLayout,
    easu_layout:       wgpu.BindGroupLayout,
    fullscreen_pipeline_layout: wgpu.PipelineLayout,
    blit_pipeline_layout:       wgpu.PipelineLayout,
    overlay_pipeline_layout:    wgpu.PipelineLayout,
    easu_pipeline_layout:       wgpu.PipelineLayout,
    pipelines:         Fullscreen_Pipelines,

    // Buffers
    frame_buffer_camera: wgpu.Buffer,
    shadow_frame_buffers: [MAX_SHADOW_VIEWS]wgpu.Buffer, // one per cascade / spot shadow
    draw_buffer:         wgpu.Buffer,
    draw_capacity:       int,
    light_buffer:        wgpu.Buffer,
    overlay_buffer:      wgpu.Buffer,
    blit_buffer:         wgpu.Buffer,
    easu_buffer:         wgpu.Buffer, // FSR 1 EASU: input / output size

    // Default resources
    white_texture:       Texture,
    white_volume:        Texture, // 1x1x1 default for unset texture_3d slots
    black_texture:       Texture,
    flat_normal_texture: Texture,
    dummy_depth:         Render_Target,

    // Render targets
    hdr:        [2]Render_Target,
    ldr:        [2]Render_Target,
    // Window resolution targets (the viewport rectangle's size), only when it
    // differs from the render buffer (output_size = 0 otherwise):
    // - native overlay: the 2D overlay, composited over the image in the blit
    // - FSR 1: the EASU upscaled image, sharpened (RCAS) in the blit
    output_size:    [2]u32,
    overlay_target: Render_Target,
    overlay_active: bool,
    fsr_target:     Render_Target,
    fsr_active:     bool,
    easu_bg:        [2]wgpu.BindGroup, // source: ldr[i]
    depth:      Render_Target,
    normal:     Render_Target,
    ao_raw:     Render_Target,
    ao:         Render_Target,
    shadow_map: Render_Target,
    spot_shadow_map: Render_Target,
    cascade_count:   int,

    // Bind groups
    frame_bg_main:   wgpu.BindGroup,
    shadow_frame_bgs: [MAX_SHADOW_VIEWS]wgpu.BindGroup,
    fs_bg_ssao:      wgpu.BindGroup,
    fs_bg_blur:      wgpu.BindGroup,
    fs_bg_ao:        wgpu.BindGroup,
    fs_bg_hdr_plain: [2]wgpu.BindGroup, // HDR source without the bloom texture bound
    bloom:           [MAX_BLOOM_LEVELS]Render_Target,
    bloom_levels:    int,
    fs_bg_bloom:     [MAX_BLOOM_LEVELS]wgpu.BindGroup,
    streak:          [MAX_STREAK_LEVELS]Render_Target, // lens streak chain: width halves, height stays
    streak_levels:   int,
    fs_bg_streak:    [MAX_STREAK_LEVELS]wgpu.BindGroup,
    post_half:       Render_Target, // half resolution post effects render here, then composite
    fs_bg_post_half: wgpu.BindGroup,
    fs_bg_hdr:       [2]wgpu.BindGroup,
    fs_bg_ldr:       [2]wgpu.BindGroup,
    blit_bg:         [2]wgpu.BindGroup,
    overlay_bg:      wgpu.BindGroup,

    // Bumped whenever material bind groups must be rebuilt (sampler change).
    material_generation: u32,

    // Scene state
    camera:      Camera_State,
    lighting:    Lighting_State,
    clear_color: Vec4, // linear
    screen_tint: Vec4,
    time:        f64,
    delta_time:  f64,
    frame_index: u64,

    // Per frame lists
    instances:     [dynamic]Draw_Instance,
    commands:      [dynamic]Draw_Command,
    lights:        [dynamic]Light_Instance,
    overlay:       [dynamic]Overlay_Command,
    post_effects:  [dynamic]Post_Effect,

    // Scratch
    draw_data:     [dynamic]Draw_Data,
    light_data:    [MAX_LIGHTS]Light_Data,
    overlay_data:  [dynamic]Overlay_Draw_Data,

    screenshot_path:   string,
    screenshot_window: bool, // capture the window image instead of the render buffer
    surface_copyable:  bool,

    // Error scope result
    scope_done:    bool,
    scope_error:   string,
}

@(private)
state_storage: Renderer_State

// Package state lives behind a pointer so a hot reloaded build can adopt it.
@(private)
state: ^Renderer_State = &state_storage

get_state_ptr :: proc() -> rawptr { return state }
set_state_ptr :: proc(p: rawptr) { state = (^Renderer_State)(p) }
get_state_size :: proc() -> int { return size_of(Renderer_State) }

// ---------------------------------------------------------------------------
// Init / shutdown
// ---------------------------------------------------------------------------

init :: proc(window: glfw.WindowHandle, window_width: u32, window_height: u32, config: Graphics_Config) {
    state.ctx = context
    state.window = window
    state.window_width = window_width
    state.window_height = window_height

    state.instance = wgpu.CreateInstance(nil)
    if state.instance == nil {
        log.panic("WebGPU is not supported")
    }
    state.surface = glfwglue.GetSurface(state.instance, window)

    // Adapter
    {
        on_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: string, userdata1: rawptr, userdata2: rawptr) {
            context = state.ctx
            if status != .Success || adapter == nil {
                log.panicf("WebGPU: failed to get an adapter [%v] %s", status, message)
            }
            state.adapter = adapter
        }
        wgpu.InstanceRequestAdapter(
            state.instance,
            &{compatibleSurface = state.surface, powerPreference = .HighPerformance},
            {mode = .AllowProcessEvents, callback = on_adapter},
        )
        for state.adapter == nil {
            wgpu.InstanceProcessEvents(state.instance)
        }
    }

    // Device
    {
        on_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1: rawptr, userdata2: rawptr) {
            context = state.ctx
            if status != .Success || device == nil {
                log.panicf("WebGPU: failed to get a device [%v] %s", status, message)
            }
            state.device = device
        }
        on_error :: proc "c" (device: ^wgpu.Device, type: wgpu.ErrorType, message: string, userdata1: rawptr, userdata2: rawptr) {
            context = state.ctx
            log.panicf("WebGPU error [%v]: %s", type, message)
        }
        on_lost :: proc "c" (device: ^wgpu.Device, reason: wgpu.DeviceLostReason, message: string, userdata1: rawptr, userdata2: rawptr) {
            context = state.ctx
            if reason != .Destroyed && reason != .CallbackCancelled {
                log.errorf("WebGPU device lost [%v]: %s", reason, message)
            }
        }
        wgpu.AdapterRequestDevice(
            state.adapter,
            &wgpu.DeviceDescriptor{
                label = "obsidon",
                uncapturedErrorCallbackInfo = {callback = on_error},
                deviceLostCallbackInfo = {mode = .AllowProcessEvents, callback = on_lost},
            },
            {mode = .AllowProcessEvents, callback = on_device},
        )
        for state.device == nil {
            wgpu.InstanceProcessEvents(state.instance)
        }
    }

    state.queue = wgpu.DeviceGetQueue(state.device)
    state.config = config

    configure_surface()
    create_static_resources()
    create_internal_pipelines()
    create_targets()

    state.camera = Camera_State{
        rotation = 1,
        fov_y    = 60.0 * (3.14159265358979 / 180.0),
        near     = 0.1,
        far      = 0,
    }
    state.lighting = Lighting_State{
        ambient_sky    = {0.25, 0.27, 0.32},
        ambient_ground = {0.1, 0.09, 0.08},
        sun_enabled    = true,
        sun_shadows    = true,
        sun_direction  = {-0.4, -1.0, -0.3},
        sun_color      = {1.0, 0.95, 0.9},
        shadow_bias    = 1.0,
    }
    state.clear_color = {0.05, 0.05, 0.08, 1.0}
}

cleanup :: proc() {
    // Release order doesn't matter much at shutdown; the device takes everything with it.
    destroy_targets()
    delete(state.instances)
    delete(state.commands)
    delete(state.lights)
    delete(state.overlay)
    delete(state.post_effects)
    delete(state.draw_data)
    delete(state.overlay_data)
    if state.device != nil {
        wgpu.DeviceRelease(state.device)
    }
    if state.surface != nil {
        wgpu.SurfaceRelease(state.surface)
    }
    if state.adapter != nil {
        wgpu.AdapterRelease(state.adapter)
    }
    if state.instance != nil {
        wgpu.InstanceRelease(state.instance)
    }
}

// Apply new graphics settings at runtime (recreates render targets as needed).
apply_config :: proc(config: Graphics_Config) {
    vsync_changed := config.vsync != state.config.vsync
    filter_changed := config.texture_filter != state.config.texture_filter
    // Render targets only depend on these; per-frame values (intensities,
    // tints, exposure...) are read from the config every frame.
    Target_Key :: struct {
        w, h: u32,
        upscale: Upscale_Filter,
        shadows, spot_shadows, ssao, bloom, streaks: bool,
        shadow_res, spot_res: u32,
        cascades: int,
        native_overlay: bool,
    }
    target_key :: proc(c: Graphics_Config) -> Target_Key {
        return {c.render_width, c.render_height, c.upscale_filter, c.shadows, c.spot_shadows, c.ssao, c.bloom, c.lens_streaks, c.shadow_resolution, c.spot_shadow_resolution, c.shadow_cascades, c.native_overlay}
    }
    targets_changed := target_key(config) != target_key(state.config)
    state.config = config
    if vsync_changed {
        configure_surface()
    }
    if filter_changed {
        wgpu.SamplerRelease(state.sampler_material)
        state.sampler_material = create_material_sampler(config.texture_filter)
        state.material_generation += 1
    }
    if targets_changed {
        create_targets()
    }
}

get_config :: proc() -> Graphics_Config {
    return state.config
}

window_resized :: proc(width: u32, height: u32) {
    if width == state.window_width && height == state.window_height {
        return
    }
    state.window_width = width
    state.window_height = height
    state.surface_dirty = true
}

get_render_width :: proc() -> u32 { return state.render_width }
get_render_height :: proc() -> u32 { return state.render_height }

@(private)
configure_surface :: proc() {
    if state.window_width == 0 || state.window_height == 0 {
        return
    }
    caps, status := wgpu.SurfaceGetCapabilities(state.surface, state.adapter)
    if status != .Success {
        log.panic("WebGPU: could not query surface capabilities")
    }
    defer wgpu.SurfaceCapabilitiesFreeMembers(caps)

    format := caps.formats[0]
    for i in 0..<caps.formatCount {
        f := caps.formats[i]
        if f == .BGRA8Unorm || f == .RGBA8Unorm {
            format = f
            break
        }
    }
    state.surface_srgb = format == .BGRA8UnormSrgb || format == .RGBA8UnormSrgb
    state.surface_copyable = .CopySrc in caps.usages

    present_mode := wgpu.PresentMode.Fifo
    if !state.config.vsync {
        for i in 0..<caps.presentModeCount {
            m := caps.presentModes[i]
            if m == .Immediate {
                present_mode = .Immediate
                break
            }
            if m == .Mailbox {
                present_mode = .Mailbox
            }
        }
    }

    state.surface_config = wgpu.SurfaceConfiguration{
        device      = state.device,
        usage       = {.RenderAttachment, .CopySrc} if state.surface_copyable else {.RenderAttachment},
        format      = format,
        width       = state.window_width,
        height      = state.window_height,
        presentMode = present_mode,
        alphaMode   = .Opaque,
    }
    wgpu.SurfaceConfigure(state.surface, &state.surface_config)
    state.surface_dirty = false
}

// ---------------------------------------------------------------------------
// Static resources (samplers, layouts, buffers, default textures)
// ---------------------------------------------------------------------------

@(private)
create_material_sampler :: proc(filter: Texture_Filter) -> wgpu.Sampler {
    linear := filter == .Linear
    return wgpu.DeviceCreateSampler(state.device, &wgpu.SamplerDescriptor{
        addressModeU  = .Repeat,
        addressModeV  = .Repeat,
        addressModeW  = .Repeat,
        magFilter     = .Linear if linear else .Nearest,
        minFilter     = .Linear if linear else .Nearest,
        mipmapFilter  = .Linear if linear else .Nearest,
        lodMinClamp   = 0,
        lodMaxClamp   = 0 if !linear else 32,
        maxAnisotropy = 1,
    })
}

@(private)
create_static_resources :: proc() {
    d := state.device

    state.sampler_material = create_material_sampler(state.config.texture_filter)
    state.sampler_linear = wgpu.DeviceCreateSampler(d, &wgpu.SamplerDescriptor{
        addressModeU = .ClampToEdge, addressModeV = .ClampToEdge, addressModeW = .ClampToEdge,
        magFilter = .Linear, minFilter = .Linear, mipmapFilter = .Nearest,
        lodMaxClamp = 32, maxAnisotropy = 1,
    })
    state.sampler_nearest = wgpu.DeviceCreateSampler(d, &wgpu.SamplerDescriptor{
        addressModeU = .ClampToEdge, addressModeV = .ClampToEdge, addressModeW = .ClampToEdge,
        magFilter = .Nearest, minFilter = .Nearest, mipmapFilter = .Nearest,
        lodMaxClamp = 32, maxAnisotropy = 1,
    })
    state.sampler_shadow = wgpu.DeviceCreateSampler(d, &wgpu.SamplerDescriptor{
        addressModeU = .ClampToEdge, addressModeV = .ClampToEdge, addressModeW = .ClampToEdge,
        magFilter = .Linear, minFilter = .Linear, mipmapFilter = .Nearest,
        lodMaxClamp = 32, compare = .LessEqual, maxAnisotropy = 1,
    })

    state.frame_layout = make_layout({
        entry_uniform(0),
        entry_storage(1),
        entry_storage(2),
        entry_texture(3, .Depth, dimension = ._2DArray),
        entry_sampler(4, .Comparison),
        entry_texture(5, .Float),
        entry_texture(6, .Depth, dimension = ._2DArray),
    })
    state.fullscreen_layout = make_layout({
        entry_uniform(0),
        entry_texture(1, .Float),
        entry_texture(2, .Depth),
        entry_sampler(3, .Filtering),
        entry_sampler(4, .Filtering),
        entry_texture(5, .Float),
    })
    state.blit_layout = make_layout({
        entry_texture(0, .Float),
        entry_sampler(1, .Filtering),
        entry_uniform(2),
        entry_texture(3, .Float), // native overlay (black when unused)
    })
    state.easu_layout = make_layout({
        entry_texture(0, .Float),
        entry_uniform(1),
    })
    state.overlay_layout = make_layout({
        entry_storage(0),
        entry_sampler(1, .Filtering),
    })
    state.overlay_tex_layout = make_layout({
        entry_texture(0, .Float),
    })
    state.fullscreen_pipeline_layout = make_pipeline_layout({state.fullscreen_layout})
    state.blit_pipeline_layout = make_pipeline_layout({state.blit_layout})
    state.overlay_pipeline_layout = make_pipeline_layout({state.overlay_layout, state.overlay_tex_layout})
    state.easu_pipeline_layout = make_pipeline_layout({state.easu_layout})

    state.frame_buffer_camera = make_buffer(size_of(Frame_Uniforms), {.Uniform, .CopyDst})
    for i in 0..<MAX_SHADOW_VIEWS {
        state.shadow_frame_buffers[i] = make_buffer(size_of(Frame_Uniforms), {.Uniform, .CopyDst})
    }
    state.light_buffer = make_buffer(size_of(Light_Data) * MAX_LIGHTS, {.Storage, .CopyDst})
    state.overlay_buffer = make_buffer(size_of(Overlay_Draw_Data) * MAX_OVERLAY_DRAWS, {.Storage, .CopyDst})
    state.blit_buffer = make_buffer(BLIT_PARAMS_SIZE, {.Uniform, .CopyDst})
    state.easu_buffer = make_buffer(16, {.Uniform, .CopyDst})
    state.draw_capacity = INITIAL_DRAW_CAPACITY
    state.draw_buffer = make_buffer(u64(size_of(Draw_Data) * state.draw_capacity), {.Storage, .CopyDst})

    state.white_texture = texture_create_solid({255, 255, 255, 255}, srgb = true)
    white := [4]u8{255, 255, 255, 255}
    state.white_volume = texture_create_3d(white[:], 1, 1, 1, false)
    state.black_texture = texture_create_solid({0, 0, 0, 255}, srgb = true)
    state.flat_normal_texture = texture_create_solid({128, 128, 255, 255}, srgb = false)
    state.dummy_depth = make_depth_array(1, 1)

    state.overlay_bg = make_bind_group(state.overlay_layout, {
        bind_buffer(0, state.overlay_buffer, size_of(Overlay_Draw_Data) * MAX_OVERLAY_DRAWS),
        bind_sampler(1, state.sampler_nearest),
    })
}

@(private)
create_internal_pipelines :: proc() {
    fullscreen_source :: proc(body: string) -> string {
        return strings.concatenate({sh.LIBRARY_COMMON, "\n", sh.LIBRARY_POST, "\n", FULLSCREEN_WGSL, "\n", body}, context.temp_allocator)
    }

    ssao := create_module(fullscreen_source(SSAO_WGSL), "ssao")
    blur := create_module(fullscreen_source(SSAO_BLUR_WGSL), "ssao_blur")
    tonemap := create_module(fullscreen_source(TONEMAP_WGSL), "tonemap")
    debug_view := create_module(fullscreen_source(DEBUG_VIEW_WGSL), "debug_view")
    bloom := create_module(strings.concatenate({sh.LIBRARY_COMMON, "\n", sh.LIBRARY_POST, "\n", BLOOM_WGSL}, context.temp_allocator), "bloom")
    additive := wgpu.BlendState{
        color = {srcFactor = .One, dstFactor = .One, operation = .Add},
        alpha = {srcFactor = .One, dstFactor = .One, operation = .Add},
    }
    state.pipelines.bloom_prefilter = create_fullscreen_pipeline(bloom, state.fullscreen_pipeline_layout, HDR_FORMAT, nil, "bloom_prefilter", "fs_prefilter")
    state.pipelines.bloom_down = create_fullscreen_pipeline(bloom, state.fullscreen_pipeline_layout, HDR_FORMAT, nil, "bloom_down", "fs_downsample")
    state.pipelines.bloom_up = create_fullscreen_pipeline(bloom, state.fullscreen_pipeline_layout, HDR_FORMAT, &additive, "bloom_up", "fs_upsample")
    wgpu.ShaderModuleRelease(bloom)
    streak := create_module(strings.concatenate({sh.LIBRARY_COMMON, "\n", sh.LIBRARY_POST, "\n", LENS_STREAK_WGSL}, context.temp_allocator), "lens_streak")
    state.pipelines.streak_prefilter = create_fullscreen_pipeline(streak, state.fullscreen_pipeline_layout, HDR_FORMAT, nil, "streak_prefilter", "fs_prefilter")
    state.pipelines.streak_down = create_fullscreen_pipeline(streak, state.fullscreen_pipeline_layout, HDR_FORMAT, nil, "streak_down", "fs_downsample")
    state.pipelines.streak_up = create_fullscreen_pipeline(streak, state.fullscreen_pipeline_layout, HDR_FORMAT, &additive, "streak_up", "fs_upsample")
    state.pipelines.streak_composite = create_fullscreen_pipeline(streak, state.fullscreen_pipeline_layout, HDR_FORMAT, &additive, "streak_composite", "fs_composite")
    wgpu.ShaderModuleRelease(streak)
    // Half resolution post effects: out = scene * effect.a + effect.rgb
    over := wgpu.BlendState{
        color = {srcFactor = .One, dstFactor = .SrcAlpha, operation = .Add},
        alpha = {srcFactor = .Zero, dstFactor = .One, operation = .Add},
    }
    composite := create_module(fullscreen_source(POST_COMPOSITE_WGSL), "post_composite")
    state.pipelines.post_composite = create_fullscreen_pipeline(composite, state.fullscreen_pipeline_layout, HDR_FORMAT, &over, "post_composite")
    wgpu.ShaderModuleRelease(composite)
    blit := create_module(BLIT_WGSL, "blit")
    overlay := create_module(OVERLAY_WGSL, "overlay")

    state.pipelines.ssao = create_fullscreen_pipeline(ssao, state.fullscreen_pipeline_layout, AO_FORMAT, nil, "ssao")
    state.pipelines.ssao_blur = create_fullscreen_pipeline(blur, state.fullscreen_pipeline_layout, AO_FORMAT, nil, "ssao_blur")
    state.pipelines.tonemap = create_fullscreen_pipeline(tonemap, state.fullscreen_pipeline_layout, LDR_FORMAT, nil, "tonemap")
    state.pipelines.debug_view = create_fullscreen_pipeline(debug_view, state.fullscreen_pipeline_layout, LDR_FORMAT, nil, "debug_view")
    state.pipelines.blit = create_fullscreen_pipeline(blit, state.blit_pipeline_layout, state.surface_config.format, nil, "blit")

    alpha_blend := wgpu.BlendState{
        color = {srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha, operation = .Add},
        alpha = {srcFactor = .One, dstFactor = .OneMinusSrcAlpha, operation = .Add},
    }
    state.pipelines.overlay = create_fullscreen_pipeline(overlay, state.overlay_pipeline_layout, LDR_FORMAT, &alpha_blend, "overlay")
    easu := create_module(FSR_EASU_WGSL, "fsr_easu")
    state.pipelines.easu = create_fullscreen_pipeline(easu, state.easu_pipeline_layout, LDR_FORMAT, nil, "fsr_easu")
    wgpu.ShaderModuleRelease(easu)

    wgpu.ShaderModuleRelease(ssao)
    wgpu.ShaderModuleRelease(blur)
    wgpu.ShaderModuleRelease(tonemap)
    wgpu.ShaderModuleRelease(debug_view)
    wgpu.ShaderModuleRelease(blit)
    wgpu.ShaderModuleRelease(overlay)
}

// ---------------------------------------------------------------------------
// WebGPU helpers
// ---------------------------------------------------------------------------

@(private)
entry_uniform :: proc(binding: u32, visibility := VF) -> wgpu.BindGroupLayoutEntry {
    return {binding = binding, visibility = visibility, buffer = {type = .Uniform}}
}

@(private)
entry_storage :: proc(binding: u32, visibility := VF) -> wgpu.BindGroupLayoutEntry {
    return {binding = binding, visibility = visibility, buffer = {type = .ReadOnlyStorage}}
}

@(private)
entry_texture :: proc(binding: u32, sample_type: wgpu.TextureSampleType, visibility := VF, dimension := wgpu.TextureViewDimension._2D) -> wgpu.BindGroupLayoutEntry {
    return {binding = binding, visibility = visibility, texture = {sampleType = sample_type, viewDimension = dimension}}
}

@(private)
entry_sampler :: proc(binding: u32, type: wgpu.SamplerBindingType, visibility := VF) -> wgpu.BindGroupLayoutEntry {
    return {binding = binding, visibility = visibility, sampler = {type = type}}
}

@(private)
bind_buffer :: proc(binding: u32, buffer: wgpu.Buffer, size: u64) -> wgpu.BindGroupEntry {
    return {binding = binding, buffer = buffer, offset = 0, size = size}
}

@(private)
bind_texture :: proc(binding: u32, view: wgpu.TextureView) -> wgpu.BindGroupEntry {
    return {binding = binding, textureView = view}
}

@(private)
bind_sampler :: proc(binding: u32, sampler: wgpu.Sampler) -> wgpu.BindGroupEntry {
    return {binding = binding, sampler = sampler}
}

@(private)
make_layout :: proc(entries: []wgpu.BindGroupLayoutEntry) -> wgpu.BindGroupLayout {
    return wgpu.DeviceCreateBindGroupLayout(state.device, &wgpu.BindGroupLayoutDescriptor{
        entryCount = len(entries),
        entries    = raw_data(entries),
    })
}

@(private)
make_pipeline_layout :: proc(layouts: []wgpu.BindGroupLayout) -> wgpu.PipelineLayout {
    return wgpu.DeviceCreatePipelineLayout(state.device, &wgpu.PipelineLayoutDescriptor{
        bindGroupLayoutCount = len(layouts),
        bindGroupLayouts     = raw_data(layouts),
    })
}

@(private)
make_bind_group :: proc(layout: wgpu.BindGroupLayout, entries: []wgpu.BindGroupEntry) -> wgpu.BindGroup {
    return wgpu.DeviceCreateBindGroup(state.device, &wgpu.BindGroupDescriptor{
        layout     = layout,
        entryCount = len(entries),
        entries    = raw_data(entries),
    })
}

@(private)
make_buffer :: proc(size: u64, usage: wgpu.BufferUsageFlags) -> wgpu.Buffer {
    return wgpu.DeviceCreateBuffer(state.device, &wgpu.BufferDescriptor{size = size, usage = usage})
}

@(private)
make_target :: proc(width: u32, height: u32, format: wgpu.TextureFormat, usage: wgpu.TextureUsageFlags) -> Render_Target {
    texture := wgpu.DeviceCreateTexture(state.device, &wgpu.TextureDescriptor{
        size          = {width = width, height = height, depthOrArrayLayers = 1},
        format        = format,
        usage         = usage,
        dimension     = ._2D,
        mipLevelCount = 1,
        sampleCount   = 1,
    })
    view := wgpu.TextureCreateView(texture, nil)
    return Render_Target{texture = texture, view = view, width = width, height = height}
}

// Depth texture array (shadow maps): one array view for sampling plus a view per layer to render into.
@(private)
make_depth_array :: proc(size: u32, layers: int) -> Render_Target {
    texture := wgpu.DeviceCreateTexture(state.device, &wgpu.TextureDescriptor{
        size          = {width = size, height = size, depthOrArrayLayers = u32(layers)},
        format        = DEPTH_FORMAT,
        usage         = {.RenderAttachment, .TextureBinding},
        dimension     = ._2D,
        mipLevelCount = 1,
        sampleCount   = 1,
    })
    target := Render_Target{texture = texture, width = size, height = size, layer_count = layers}
    target.view = wgpu.TextureCreateView(texture, &wgpu.TextureViewDescriptor{
        format = DEPTH_FORMAT, dimension = ._2DArray, mipLevelCount = 1, arrayLayerCount = u32(layers), aspect = .All,
    })
    for i in 0..<layers {
        target.layers[i] = wgpu.TextureCreateView(texture, &wgpu.TextureViewDescriptor{
            format = DEPTH_FORMAT, dimension = ._2D, mipLevelCount = 1, baseArrayLayer = u32(i), arrayLayerCount = 1, aspect = .All,
        })
    }
    return target
}

@(private)
destroy_target :: proc(target: ^Render_Target) {
    for i in 0..<target.layer_count {
        wgpu.TextureViewRelease(target.layers[i])
    }
    if target.view != nil {
        wgpu.TextureViewRelease(target.view)
    }
    if target.texture != nil {
        wgpu.TextureDestroy(target.texture)
        wgpu.TextureRelease(target.texture)
    }
    target^ = {}
}

@(private)
release_bind_group :: proc(bg: ^wgpu.BindGroup) {
    if bg^ != nil {
        wgpu.BindGroupRelease(bg^)
        bg^ = nil
    }
}

@(private)
push_error_scope :: proc() {
    wgpu.DevicePushErrorScope(state.device, .Validation)
}

// Pops the error scope; returns the error message ("" when there was none).
@(private)
pop_error_scope :: proc() -> string {
    on_pop :: proc "c" (status: wgpu.PopErrorScopeStatus, type: wgpu.ErrorType, message: string, userdata1: rawptr, userdata2: rawptr) {
        context = state.ctx
        state.scope_done = true
        if type != .NoError && status == .Success {
            state.scope_error = strings.clone(message, context.temp_allocator)
        }
    }
    state.scope_done = false
    state.scope_error = ""
    wgpu.DevicePopErrorScope(state.device, {mode = .AllowProcessEvents, callback = on_pop})
    for !state.scope_done {
        wgpu.InstanceProcessEvents(state.instance)
    }
    return state.scope_error
}

@(private)
report_shader_error :: proc(label: string, source: string, message: string) {
    sb := strings.builder_make(context.temp_allocator)
    fmt.sbprintf(&sb, "Shader '%s' failed to compile:\n%s\n---- generated WGSL ----\n", label, message)
    line := 1
    remaining := source
    for l in strings.split_lines_iterator(&remaining) {
        fmt.sbprintf(&sb, "%4d | %s\n", line, l)
        line += 1
    }
    log.panic(strings.to_string(sb))
}

@(private)
create_module :: proc(source: string, label: string) -> wgpu.ShaderModule {
    push_error_scope()
    module := wgpu.DeviceCreateShaderModule(state.device, &wgpu.ShaderModuleDescriptor{
        label       = label,
        nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = source},
    })
    if err := pop_error_scope(); err != "" {
        report_shader_error(label, source, err)
    }
    return module
}

@(private)
create_fullscreen_pipeline :: proc(module: wgpu.ShaderModule, layout: wgpu.PipelineLayout, format: wgpu.TextureFormat, blend: ^wgpu.BlendState, label: string, fragment_entry := "fs_main") -> wgpu.RenderPipeline {
    push_error_scope()
    pipeline := wgpu.DeviceCreateRenderPipeline(state.device, &wgpu.RenderPipelineDescriptor{
        label  = label,
        layout = layout,
        vertex = {module = module, entryPoint = "vs_main"},
        fragment = &wgpu.FragmentState{
            module      = module,
            entryPoint  = fragment_entry,
            targetCount = 1,
            targets     = &wgpu.ColorTargetState{format = format, blend = blend, writeMask = wgpu.ColorWriteMaskFlags_All},
        },
        primitive   = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
        multisample = {count = 1, mask = 0xFFFFFFFF},
    })
    if err := pop_error_scope(); err != "" {
        log.panicf("Failed to create pipeline '%s': %s", label, err)
    }
    return pipeline
}
