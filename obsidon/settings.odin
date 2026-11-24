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

package obsidon

import "internal/renderer"
import "internal/window"

Window_Mode    :: window.Window_Mode
Shadow_Filter  :: renderer.Shadow_Filter
Ssao_Quality   :: renderer.Ssao_Quality
Tonemapper     :: renderer.Tonemapper
Texture_Filter :: renderer.Texture_Filter
Debug_View     :: renderer.Debug_View
Scaling_Mode   :: renderer.Scaling_Mode

// Internal render resolution. The image is scaled up (pixel perfect,
// letterboxed) to the window, so low resolutions give a crisp retro look.
Render_Resolution :: enum {
    Native,       // match the window
    R320x240,     // PS1
    R427x240,
    R640x360,
    R640x480,
    R854x480,
    R1280x720,
    R1920x1080,
    Custom,       // use Graphics_Settings.custom_resolution
}

Shadow_Resolution :: enum {
    R512,
    R1024,
    R2048,
    R4096,
}

Graphics_Settings :: struct {
    resolution:        Render_Resolution,
    custom_resolution: [2]u32,
    vsync:             bool,
    texture_filter:    Texture_Filter,

    // How the render buffer is shown in the window:
    // .Integer (whole-number scale, centred, black borders), .Fit, .Stretch.
    scaling:           Scaling_Mode,
    // .Nearest = crisp pixels, .Linear = smooth (for high resolution looks).
    upscale_filter:    Texture_Filter,

    // Sun shadows
    shadows:           bool,
    shadow_resolution: Shadow_Resolution,
    shadow_distance:   f32,           // world units covered by the shadow maps
    shadow_filter:     Shadow_Filter,
    // Cascaded shadow maps: 1-4 maps of increasing size along the view,
    // sharp shadows close to the camera and coverage far away.
    shadow_cascades:   int,

    // Shadows from spot lights (add_spot_light(..., cast_shadows = true)), up to 4 per frame.
    spot_shadows:           bool,
    spot_shadow_resolution: Shadow_Resolution,

    // Screen space ambient occlusion
    ssao:              bool,
    ssao_quality:      Ssao_Quality,
    ssao_radius:       f32,           // world units
    ssao_intensity:    f32,
    // How much AO also darkens direct light (0 = ambient only, physically
    // plausible; higher = more visible contact shadows in harsh lighting).
    ssao_direct_amount: f32,

    // HDR -> display
    tonemapper:        Tonemapper,
    exposure:          f32,

    // Glow around bright (HDR) pixels: emissive materials, lights, specular glints.
    bloom:             bool,
    bloom_intensity:   f32,  // how much bloom is added (default 0.35)
    bloom_threshold:   f32,  // brightness where bloom starts (default 1.0, linear HDR)

    // Show an intermediate buffer (AO, normals, depth) - for debugging.
    debug_view:        Debug_View,
}

Settings :: struct {
    title:         string,
    window_mode:   Window_Mode,
    window_width:  u32, // used in windowed mode
    window_height: u32,
    graphics:      Graphics_Settings,
}

default_graphics_settings :: proc() -> Graphics_Settings {
    return Graphics_Settings{
        resolution        = .Native,
        vsync             = true,
        texture_filter    = .Linear,
        scaling           = .Integer,
        upscale_filter    = .Nearest,
        shadows           = true,
        shadow_resolution = .R2048,
        shadow_distance   = 60,
        shadow_filter     = .PCF_3x3,
        shadow_cascades   = 3,
        spot_shadows      = true,
        spot_shadow_resolution = .R1024,
        ssao              = false,
        ssao_quality      = .Medium,
        ssao_radius       = 0.5,
        ssao_intensity    = 1.5,
        ssao_direct_amount = 0.5,
        tonemapper        = .ACES,
        exposure          = 1.0,
        bloom             = true,
        bloom_intensity   = 0.35,
        bloom_threshold   = 1.0,
    }
}

default_settings :: proc(title := "Obsidon") -> Settings {
    return Settings{
        title         = title,
        window_mode   = .Windowed,
        window_width  = 1280,
        window_height = 720,
        graphics      = default_graphics_settings(),
    }
}

// Change graphics settings while the game is running (e.g. from an options menu).
set_graphics_settings :: proc(settings: Graphics_Settings) {
    core.graphics_settings = settings
    renderer.apply_config(to_renderer_config(settings))
    sync_window_layout()
}

get_graphics_settings :: proc() -> Graphics_Settings {
    return core.graphics_settings
}


@(private)
to_renderer_config :: proc(s: Graphics_Settings) -> renderer.Graphics_Config {
    w, h: u32
    switch s.resolution {
    case .Native:
    case .R320x240: w, h = 320, 240
    case .R427x240: w, h = 427, 240
    case .R640x360: w, h = 640, 360
    case .R640x480: w, h = 640, 480
    case .R854x480: w, h = 854, 480
    case .R1280x720: w, h = 1280, 720
    case .R1920x1080: w, h = 1920, 1080
    case .Custom: w, h = s.custom_resolution.x, s.custom_resolution.y
    }
    resolution_value :: proc(r: Shadow_Resolution) -> u32 {
        switch r {
        case .R512: return 512
        case .R1024: return 1024
        case .R2048: return 2048
        case .R4096: return 4096
        }
        return 1024
    }
    shadow_res := resolution_value(s.shadow_resolution)
    return renderer.Graphics_Config{
        render_width      = w,
        render_height     = h,
        vsync             = s.vsync,
        texture_filter    = s.texture_filter,
        scaling           = s.scaling,
        upscale_filter    = s.upscale_filter,
        shadows           = s.shadows,
        shadow_resolution = shadow_res,
        shadow_distance   = s.shadow_distance if s.shadow_distance > 0 else 60,
        shadow_filter     = s.shadow_filter,
        shadow_cascades   = s.shadow_cascades if s.shadow_cascades > 0 else 1,
        spot_shadows      = s.spot_shadows,
        spot_shadow_resolution = resolution_value(s.spot_shadow_resolution),
        ssao              = s.ssao,
        ssao_quality      = s.ssao_quality,
        ssao_radius       = s.ssao_radius if s.ssao_radius > 0 else 0.5,
        ssao_intensity    = s.ssao_intensity if s.ssao_intensity > 0 else 1.0,
        ssao_direct       = s.ssao_direct_amount,
        tonemapper        = s.tonemapper,
        exposure          = s.exposure if s.exposure > 0 else 1.0,
        debug_view        = s.debug_view,
        bloom             = s.bloom,
        bloom_intensity   = s.bloom_intensity,
        bloom_threshold   = s.bloom_threshold,
    }
}
