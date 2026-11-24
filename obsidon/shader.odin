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
import sh "shader"

// A compiled shader. Build one with the `obsidon/shader` package:
//
//     sh.begin()
//     ... describe the shader with sh.* primitives ...
//     my_shader := obsidon.shader_create(sh.end())
//
// or use one of the built-in shaders below.
Shader :: ^renderer.Shader

shader_create :: proc(desc: sh.Shader_Desc) -> Shader {
    return renderer.shader_create(desc)
}

shader_destroy :: proc(shader: Shader) {
    renderer.shader_destroy(shader)
}

// Replace a shader's code in place, e.g. after hot reloading game code or to
// switch variants at runtime. Materials using the shader keep their values and
// textures (matched by parameter name).
shader_rebuild :: proc(shader: Shader, desc: sh.Shader_Desc) {
    renderer.shader_rebuild(shader, desc)
}

// ---------------------------------------------------------------------------
// Built-in shaders
// ---------------------------------------------------------------------------

Standard_Shader_Options :: struct {
    // Alpha blended (glass, smoke). Not part of shadows / SSAO.
    transparent:     bool,
    // Discard pixels with alpha below 0.5 (foliage, fences).
    alpha_clip:      bool,
    // Render back faces too.
    double_sided:    bool,
    // Gouraud (per vertex) lighting instead of per pixel.
    vertex_lighting: bool,
}

// General purpose lit shader.
//
// Material parameters:
//   texture "albedo"            - colour texture (default white)
//   color   "color"             - colour multiplier (default white)
//   float   "specular"          - specular strength (default 0.25)
//   float   "shininess"         - highlight sharpness (default 32)
//   color   "emission"          - self illumination colour (default black)
//   float   "emission_strength" - emission multiplier, > 1 for HDR glow (default 1)
//   texture "normal"            - tangent space normal map, load with srgb = false (default flat)
//   float   "normal_strength"   - normal map strength (default 1)
//   vec2    "uv_scale"          - texture tiling (default 1, 1)
//   texture "emission_map"      - multiplies the emission colour (default white)
shader_standard :: proc(options := Standard_Shader_Options{}) -> Shader {
    sh.begin(name = "standard")
    configure_common(options.transparent, options.double_sided)

    albedo := surface_albedo()
    pos := sh.world_position()
    n := sh.normal_map(sh.texture("normal", .Flat_Normal), surface_uv(), sh.param_float("normal_strength", 1))
    sh.set_normal(n)

    light := sh.lighting_per_vertex(pos, n) if options.vertex_lighting else sh.lighting(pos, n)
    color := sh.mul(sh.rgb(albedo), light)
    spec := sh.mul(sh.specular(pos, n, sh.param_float("shininess", 32)), sh.param_float("specular", 0.25))
    color = sh.add(color, spec)
    emission := sh.mul(sh.rgb(sh.param_color("emission", {0, 0, 0, 1})), sh.param_float("emission_strength", 1))
    emission = sh.mul(emission, sh.rgb(sh.sample(sh.texture("emission_map"), surface_uv())))
    color = sh.add(color, emission)
    color = sh.fog(color, pos)

    if options.alpha_clip {
        sh.set_alpha_clip(sh.a(albedo))
    }
    sh.set_color(sh.vec4(color, sh.a(albedo)))
    return shader_create(sh.end())
}

// Built-in standard shader variants shared by engine features (glTF models).
// Destroyed automatically when the game exits.

@(private)
cached_standard_shader :: proc(options: Standard_Shader_Options) -> Shader {
    if s, ok := core.standard_shaders[options]; ok {
        return s
    }
    s := shader_standard(options)
    core.standard_shaders[options] = s
    return s
}

@(private)
destroy_cached_shaders :: proc() {
    for _, s in core.standard_shaders {
        shader_destroy(s)
    }
    delete(core.standard_shaders)
    core.standard_shaders = nil
}

// Unlit shader: colour = texture * colour, no lighting (UI in 3D, skyboxes,
// glowing things). Parameters: texture "albedo", color "color",
// float "emission_strength" (default 1, > 1 for HDR glow).
shader_unlit :: proc(options := Standard_Shader_Options{}) -> Shader {
    sh.begin(name = "unlit")
    configure_common(options.transparent, options.double_sided)
    albedo := surface_albedo()
    color := sh.mul(sh.rgb(albedo), sh.param_float("emission_strength", 1))
    color = sh.fog(color, sh.world_position())
    if options.alpha_clip {
        sh.set_alpha_clip(sh.a(albedo))
    }
    sh.set_color(sh.vec4(color, sh.a(albedo)))
    return shader_create(sh.end())
}

Psx_Shader_Options :: struct {
    // Virtual resolution vertices snap to. {0, 0} = render resolution.
    snap_resolution: [2]f32,
    // Disable perspective correction for textures (the famous PS1 warping).
    affine_textures: bool,
    // Per vertex (Gouraud) lighting.
    vertex_lighting: bool,
    // Colour levels per channel for ordered dithering (32 = PS1 15-bit colour). 0 = off.
    color_levels:    f32,
    alpha_clip:      bool,
    double_sided:    bool,
}

PSX_DEFAULTS :: Psx_Shader_Options{
    snap_resolution = {320, 240},
    affine_textures = true,
    vertex_lighting = true,
    color_levels    = 32,
}

// PS1 inspired shader: wobbly snapped vertices, affine texture mapping,
// Gouraud lighting, fog and dithered colour depth. Same parameters as
// shader_standard (minus specular).
shader_psx :: proc(options := PSX_DEFAULTS) -> Shader {
    sh.begin(name = "psx")
    configure_common(false, options.double_sided)

    // Vertex wobble: snap the projected vertex to a low resolution grid.
    grid := sh.resolution()
    if options.snap_resolution.x > 0 && options.snap_resolution.y > 0 {
        grid = sh.vec2(options.snap_resolution.x, options.snap_resolution.y)
    }
    sh.set_clip_position(sh.snap_to_grid(sh.clip_position(), grid))

    uv := sh.uv()
    if options.affine_textures {
        uv = sh.affine(uv)
    }
    albedo := sh.mul(sh.sample(sh.texture("albedo"), uv), sh.param_color("color"))
    albedo = sh.mul(albedo, sh.mul(sh.vertex_color(), sh.tint()))

    pos := sh.world_position()
    n := sh.world_normal()
    light := sh.lighting_per_vertex(pos, n) if options.vertex_lighting else sh.lighting(pos, n)
    color := sh.mul(sh.rgb(albedo), light)
    emission := sh.mul(sh.rgb(sh.param_color("emission", {0, 0, 0, 1})), sh.param_float("emission_strength", 1))
    color = sh.add(color, emission)
    color = sh.fog(color, pos)
    if options.color_levels > 1 {
        color = sh.dither(color, options.color_levels)
    }
    if options.alpha_clip {
        sh.set_alpha_clip(sh.a(albedo))
    }
    sh.set_color(sh.vec4(color, sh.a(albedo)))
    return shader_create(sh.end())
}

// Post effect: reduce colour depth with ordered dithering (after tonemapping).
// Parameter: float "levels" (default 32).
shader_post_dither :: proc() -> Shader {
    sh.begin(.Post, "post_dither")
    uv := sh.screen_uv()
    c := sh.scene_color(uv)
    sh.set_color(sh.vec4(sh.dither(sh.rgb(c), sh.param_float("levels", 32)), 1))
    return shader_create(sh.end())
}

// Post effect: darkened screen corners.
// Parameters: float "strength" (default 0.5), float "radius" (default 0.75).
shader_post_vignette :: proc() -> Shader {
    sh.begin(.Post, "post_vignette")
    uv := sh.screen_uv()
    c := sh.scene_color(uv)
    d := sh.length(sh.sub(uv, sh.vec2(0.5, 0.5)))
    radius := sh.param_float("radius", 0.75)
    v := sh.smoothstep(radius, sh.sub(radius, 0.45), d)
    v = sh.mix(1, v, sh.param_float("strength", 0.5))
    sh.set_color(sh.vec4(sh.mul(sh.rgb(c), v), 1))
    return shader_create(sh.end())
}

@(private)
configure_common :: proc(transparent: bool, double_sided: bool) {
    if transparent {
        sh.set_blend(.Alpha)
    }
    if double_sided {
        sh.set_cull(.None)
    }
}

// Mesh uvs times the "uv_scale" parameter (texture tiling).
@(private)
surface_uv :: proc() -> sh.Value {
    return sh.mul(sh.uv(), sh.param_vec2("uv_scale", {1, 1}))
}

// albedo texture * colour param * vertex colour * draw tint
@(private)
surface_albedo :: proc() -> sh.Value {
    albedo := sh.mul(sh.sample(sh.texture("albedo"), surface_uv()), sh.param_color("color"))
    return sh.mul(albedo, sh.mul(sh.vertex_color(), sh.tint()))
}
