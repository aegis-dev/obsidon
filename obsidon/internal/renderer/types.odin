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

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4, 4]f32

DVec3 :: [3]f64
DMat4 :: matrix[4, 4]f64
DQuat :: quaternion256

// Mesh vertex. Matches `Vertex_In` in shader/wgsl/surface.wgsl.
Vertex :: struct {
    position: Vec3,
    normal:   Vec3,
    uv:       Vec2,
    color:    Vec4,
    // xyz: direction of +u on the surface, w: bitangent sign (glTF / MikkTSpace
    // convention). Leave zero and mesh_create computes it from the uvs.
    tangent:  Vec4,
}

// ---------------------------------------------------------------------------
// GPU structs - keep in sync with shader/wgsl/*.wgsl
// ---------------------------------------------------------------------------

Frame_Uniforms :: struct {
    view:            Mat4,
    proj:            Mat4,
    view_proj:       Mat4,
    inv_proj:        Mat4,
    light_view_proj: [4]Mat4,
    spot_view_proj:  [4]Mat4,
    camera_position: Vec4,
    resolution:      Vec4,
    time:            Vec4,
    ambient_sky:     Vec4,
    ambient_ground:  Vec4,
    sun_direction:   Vec4,
    sun_color:       Vec4,
    fog_color:       Vec4,
    fog_params:      Vec4,
    shadow_params:   Vec4,
    shadow_params2:  Vec4,
    shadow_splits:   Vec4,
    shadow_depth_bias:  Vec4,
    shadow_normal_bias: Vec4,
    ssao_params:     Vec4,
    ssao_params2:    Vec4,
    post_params:     Vec4,
    screen_tint:     Vec4,
    bloom_params:    Vec4,
    streak_params:   Vec4,
    streak_tint:     Vec4,
    counts:          [4]u32,
}

Draw_Data :: struct {
    model:         Mat4,
    normal_matrix: Mat4,
    tint:          Vec4,
}

Light_Data :: struct {
    position_range: Vec4,
    color:          Vec4,
    direction_cone: Vec4,
    cone_inner:     Vec4,
}

Overlay_Draw_Data :: struct {
    mvp:     Mat4,
    color:   Vec4,
    params:  Vec4, // use_color, flip_x, flip_y, 0
    uv_rect: Vec4, // u0, v0, u1, v1
}

#assert(size_of(Vertex) == 64)
#assert(size_of(Frame_Uniforms) == 12 * 64 + 22 * 16)
#assert(size_of(Draw_Data) == 144)
#assert(size_of(Light_Data) == 64)
#assert(size_of(Overlay_Draw_Data) == 112)

// ---------------------------------------------------------------------------
// Settings (mirrored by the public obsidon.Graphics_Settings)
// ---------------------------------------------------------------------------

Shadow_Filter :: enum {
    Hard,    // single (hardware 2x2) comparison
    PCF_3x3, // soft edges
    PCF_5x5, // softer edges
}

Ssao_Quality :: enum {
    Low,    // 8 samples
    Medium, // 16 samples
    High,   // 32 samples
}

Tonemapper :: enum {
    None,
    Reinhard,
    ACES,
}

// Show an intermediate buffer instead of the final image (engine debugging).
Debug_View :: enum {
    None,
    Ambient_Occlusion, // needs ssao
    Normals,           // needs ssao (normals come from the depth prepass)
    Depth,
    Shadow_Cascades,   // tints the scene by sun shadow cascade
}

// How the render buffer is scaled up to the window.
Scaling_Mode :: enum {
    // Largest whole-number scale that fits, centred with black borders.
    // Every buffer pixel becomes an identical square block. Falls back to
    // Fit when the window is smaller than the buffer.
    Integer,
    // Largest scale that fits (may be fractional), centred with black borders.
    Fit,
    // Fill the whole window, ignoring the aspect ratio.
    Stretch,
}

Texture_Filter :: enum {
    Nearest, // crisp pixels (retro)
    Linear,  // smooth + mipmaps
}

Graphics_Config :: struct {
    render_width:      u32, // 0 = native window size
    render_height:     u32,
    vsync:             bool,
    texture_filter:    Texture_Filter,
    scaling:           Scaling_Mode,
    upscale_filter:    Texture_Filter,

    shadows:           bool,
    shadow_resolution: u32,
    shadow_distance:   f32,
    shadow_filter:     Shadow_Filter,
    shadow_cascades:   int,
    spot_shadows:      bool,
    spot_shadow_resolution: u32,

    ssao:              bool,
    ssao_quality:      Ssao_Quality,
    ssao_radius:       f32,
    ssao_intensity:    f32,
    ssao_direct:       f32,

    tonemapper:        Tonemapper,
    exposure:          f32,

    bloom:             bool,
    bloom_intensity:   f32,
    bloom_threshold:   f32,

    lens_streaks:          bool,
    lens_streak_intensity: f32,
    lens_streak_threshold: f32,
    lens_streak_length:    f32,
    lens_streak_tint:      Vec4, // linear

    debug_view:        Debug_View,
}
