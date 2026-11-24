// Copyright 2026 Egidijus Vaišvila
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

// Package shader is Obsidon's shader graph builder.
//
// Shaders are described in plain Odin code by composing small primitives
// (inputs, math, texture sampling, lighting, fog, ...). The builder turns the
// graph into WGSL for every render pass the engine needs (main colour pass,
// shadow pass, depth/normal pre-pass), so a single description automatically
// works with shadows, SSAO and every other engine feature.
//
// Usage:
//
//     sh.begin()
//     albedo := sh.mul(sh.sample(sh.texture("albedo"), sh.uv()), sh.param_color("tint", {1, 1, 1, 1}))
//     lit    := sh.mul(sh.rgb(albedo), sh.lighting(sh.world_position(), sh.world_normal()))
//     sh.set_color(sh.vec4(lit, sh.a(albedo)))
//     desc := sh.end()
//
// Everything is computed per pixel by default: vertex inputs (uv, normal,
// world_position, ...) are interpolated automatically when the pixel stage
// uses them. Values that feed the vertex outputs (set_world_position,
// set_clip_position) run in the vertex shader. Wrap a value in `per_vertex()`
// to compute it per vertex and interpolate the result (Gouraud lighting), or
// in `affine()` / `flat()` to also pick the interpolation mode (PS1-style
// affine texture mapping, flat shading).
package shader

import "core:log"
import "core:strings"

MAX_PARAMS   :: 16
MAX_TEXTURES :: 8

Type :: enum u8 {
    Invalid,
    Float,
    Vec2,
    Vec3,
    Vec4,
}

// A typed handle to a node in the shader graph.
Value :: struct {
    id:   i32,
    type: Type,
}

// A handle to a texture slot declared with `texture()`.
Texture_Ref :: struct {
    index: i32,
}

Mode :: enum u8 {
    // Shader used to render meshes (materials).
    Surface,
    // Full screen post-processing effect.
    Post,
}

Blend_Mode :: enum u8 {
    Opaque,
    Alpha,
    Additive,
}

Cull_Mode :: enum u8 {
    Back,
    Front,
    None,
}

Default_Texture :: enum u8 {
    White,
    Black,
    Flat_Normal,
}

// Draw order groups. Within Geometry draws are sorted for speed, within
// Transparent back to front, Background keeps submission order.
Render_Queue :: enum u8 {
    // Skies, star fields, backdrops: drawn first, behind everything.
    Background,
    // Regular opaque geometry.
    Geometry,
    // Blended geometry (set automatically by set_blend).
    Transparent,
}

Pipeline_State :: struct {
    blend:        Blend_Mode,
    cull:         Cull_Mode,
    depth_write:  bool,
    depth_test:   bool,
    cast_shadows: bool,
    queue:        Render_Queue,
}

Param_Info :: struct {
    name:          string,
    type:          Type,
    default_value: [4]f32,
    // Colour params are given in sRGB and converted to linear by the engine.
    is_color:      bool,
}

Texture_Info :: struct {
    name:          string,
    default_value: Default_Texture,
}

// Result of building a shader. Pass it to `obsidon.shader_create`.
Shader_Desc :: struct {
    mode:     Mode,
    name:     string,
    state:    Pipeline_State,
    params:   []Param_Info,
    textures: []Texture_Info,

    // Generated WGSL. Shadow and prepass sources are empty for post effects.
    main_source:    string,
    shadow_source:  string,
    prepass_source: string,
    // Whether the shadow pass needs a fragment stage (alpha clipping).
    shadow_has_fragment: bool,
}

@(private)
// Where a node can be evaluated. Nodes are evaluated in whichever stage needs
// them; `Vertex_Only` sources (vertex attributes, per-draw data) are
// interpolated automatically when the fragment stage uses them.
Stage :: enum u8 {
    Any,
    Vertex_Only,
    Fragment_Only,
}

// Shader stage code is being generated for.
@(private)
Emit :: enum u8 {
    Vertex,
    Fragment,
}

@(private)
Op :: enum u8 {
    None,
    Literal,     // consts
    Construct,   // vecN(args...)
    Binary,      // a <text> b
    Negate,
    Call,        // text(args...) - plain WGSL / engine function
    Stage_Call,  // text_vs(args...) or text_fs(args...) depending on stage
    Swizzle,     // a.text
    Input,       // text is the WGSL expression (stage specific handled in codegen)
    Final_World, // final world position (after set_world_position)
    Param,
    Sample,
    Interpolate, // index = Interpolation
}

@(private)
Interpolation :: enum u8 {
    Perspective,
    Linear,
    Flat,
}

@(private)
Node :: struct {
    op:     Op,
    type:   Type,
    stage:  Stage,
    args:   [4]i32,
    nargs:  u8,
    consts: [4]f32,
    index:  i32,
    text:   string,
    // Broadcast float arguments to the result type (WGSL needs matching types).
    splat:  bool,
}

@(private)
Builder :: struct {
    active:    bool,
    mode:      Mode,
    name:      string,
    nodes:     [dynamic]Node,
    params:    [dynamic]Param_Info,
    textures:  [dynamic]Texture_Info,
    state:     Pipeline_State,

    out_color:      i32,
    out_world:      i32,
    out_clip:       i32,
    out_normal:     i32,
    out_alpha_clip: i32,
    alpha_clip_threshold: f32,
}

@(private)
b: Builder

// Start describing a new shader. Every primitive call until `end()` adds to it.
begin :: proc(mode := Mode.Surface, name := "shader") {
    if b.active {
        log.panic("shader.begin: previous shader was not finished with shader.end()")
    }
    b = Builder{}
    b.active = true
    b.mode = mode
    b.name = name
    b.nodes = make([dynamic]Node)
    b.params = make([dynamic]Param_Info)
    b.textures = make([dynamic]Texture_Info)
    append(&b.nodes, Node{}) // id 0 is "none"
    b.state = Pipeline_State{
        blend        = .Opaque,
        cull         = .Back,
        depth_write  = true,
        depth_test   = true,
        cast_shadows = true,
        queue        = .Geometry,
    }
}

// Finish the shader and generate WGSL for all passes.
// The returned description owns its memory; free it with `desc_destroy` once
// the engine has created the shader from it.
end :: proc() -> Shader_Desc {
    ensure_active("end")
    defer {
        delete(b.nodes)
        b.active = false
    }

    if b.out_color == 0 {
        log.panicf("shader '%s': no output colour, call shader.set_color()", b.name)
    }

    desc := Shader_Desc{
        mode     = b.mode,
        name     = strings.clone(b.name),
        state    = b.state,
        params   = b.params[:],
        textures = b.textures[:],
    }

    if b.state.blend != .Opaque {
        // Transparent geometry doesn't take part in the depth prepass or shadows.
        desc.state.cast_shadows = false
        if desc.state.queue == .Geometry {
            desc.state.queue = .Transparent
        }
    }

    switch b.mode {
    case .Surface:
        if b.out_world == 0 {
            b.out_world = object_to_world(position()).id
        }
        if b.out_clip == 0 {
            b.out_clip = clip_position().id
        }
        if b.out_normal == 0 {
            b.out_normal = world_normal().id
        }
        desc.main_source = generate(.Main)
        desc.prepass_source = generate(.Prepass)
        desc.shadow_source = generate(.Shadow)
        desc.shadow_has_fragment = b.out_alpha_clip != 0
    case .Post:
        desc.main_source = generate(.Post)
    }

    return desc
}

desc_destroy :: proc(desc: ^Shader_Desc) {
    delete(desc.name)
    delete(desc.main_source)
    delete(desc.shadow_source)
    delete(desc.prepass_source)
    delete(desc.params)
    delete(desc.textures)
    desc^ = {}
}

// ---------------------------------------------------------------------------
// Pipeline state
// ---------------------------------------------------------------------------

set_blend :: proc(mode: Blend_Mode) {
    ensure_active("set_blend")
    b.state.blend = mode
    if mode != .Opaque {
        b.state.depth_write = false
    }
}

set_cull :: proc(mode: Cull_Mode) {
    ensure_active("set_cull")
    b.state.cull = mode
}

set_depth_write :: proc(enabled: bool) {
    ensure_active("set_depth_write")
    b.state.depth_write = enabled
}

set_depth_test :: proc(enabled: bool) {
    ensure_active("set_depth_test")
    b.state.depth_test = enabled
}

set_cast_shadows :: proc(enabled: bool) {
    ensure_active("set_cast_shadows")
    b.state.cast_shadows = enabled
}

// Choose when the shader draws, e.g. .Background for skies (typically
// together with set_depth_write(false) and set_cast_shadows(false)).
set_queue :: proc(queue: Render_Queue) {
    ensure_active("set_queue")
    b.state.queue = queue
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

// Final colour of the fragment (vec3 or vec4). Colours are in linear space,
// values above 1.0 are fine (HDR) and get tonemapped by the engine.
set_color :: proc(color: Value) {
    ensure_active("set_color")
    switch color.type {
    case .Vec4: b.out_color = color.id
    case .Vec3: b.out_color = vec4(color, 1.0).id
    case .Float: b.out_color = vec4(vec3(color, color, color), 1.0).id
    case .Vec2, .Invalid: type_error("set_color", "expects vec3 or vec4", color)
    }
}

// Discard fragments whose alpha is below the threshold (cutout transparency).
// Also applied in the shadow and depth passes.
set_alpha_clip :: proc(alpha: Value, threshold: f32 = 0.5) {
    ensure_active("set_alpha_clip")
    expect_type("set_alpha_clip", alpha, .Float)
    b.out_alpha_clip = alpha.id
    b.alpha_clip_threshold = threshold
}

// Override the world-space vertex position (vertex displacement, wind, waves...).
// Default: object_to_world(position()).
set_world_position :: proc(world_position: Value) {
    ensure_active("set_world_position")
    ensure_surface("set_world_position")
    expect_type("set_world_position", world_position, .Vec3)
    b.out_world = world_position.id
}

// Override the clip-space position (e.g. PS1 vertex snapping).
// Default: clip_position().
set_clip_position :: proc(clip: Value) {
    ensure_active("set_clip_position")
    ensure_surface("set_clip_position")
    expect_type("set_clip_position", clip, .Vec4)
    b.out_clip = clip.id
}

// World-space surface normal used for screen-space effects (SSAO).
// Default: world_normal().
set_normal :: proc(normal: Value) {
    ensure_active("set_normal")
    ensure_surface("set_normal")
    expect_type("set_normal", normal, .Vec3)
    b.out_normal = normal.id
}

// ---------------------------------------------------------------------------
// Material parameters & textures
// ---------------------------------------------------------------------------

param_float :: proc(name: string, default_value: f32 = 0) -> Value {
    return add_param(name, .Float, {default_value, 0, 0, 0})
}

param_vec2 :: proc(name: string, default_value: [2]f32 = {}) -> Value {
    return add_param(name, .Vec2, {default_value.x, default_value.y, 0, 0})
}

param_vec3 :: proc(name: string, default_value: [3]f32 = {}) -> Value {
    return add_param(name, .Vec3, {default_value.x, default_value.y, default_value.z, 0})
}

param_vec4 :: proc(name: string, default_value: [4]f32 = {}) -> Value {
    return add_param(name, .Vec4, default_value)
}

// Colour parameter. Defaults and values set from code are sRGB and get
// converted to linear space automatically by the engine.
param_color :: proc(name: string, default_value: [4]f32 = {1, 1, 1, 1}) -> Value {
    return add_param(name, .Vec4, default_value, is_color = true)
}

// Declare a texture slot. Unset slots use `default_value` (white by default).
texture :: proc(name: string, default_value := Default_Texture.White) -> Texture_Ref {
    ensure_active("texture")
    for t, i in b.textures {
        if t.name == name {
            return Texture_Ref{i32(i)}
        }
    }
    if len(b.textures) >= MAX_TEXTURES {
        log.panicf("shader '%s': too many textures (max %d)", b.name, MAX_TEXTURES)
    }
    append(&b.textures, Texture_Info{strings.clone(name), default_value})
    return Texture_Ref{i32(len(b.textures) - 1)}
}

// Sample a texture. In the vertex stage the top mip level is used.
sample :: proc(tex: Texture_Ref, uv: Value) -> Value {
    ensure_active("sample")
    expect_type("sample", uv, .Vec2)
    if tex.index < 0 || int(tex.index) >= len(b.textures) {
        log.panic("shader.sample: invalid texture reference")
    }
    return add_node(Node{op = .Sample, type = .Vec4, index = tex.index}, uv)
}

@(private)
add_param :: proc(name: string, type: Type, default_value: [4]f32, is_color := false) -> Value {
    ensure_active("param")
    index := -1
    for p, i in b.params {
        if p.name == name {
            if p.type != type {
                log.panicf("shader '%s': parameter '%s' declared twice with different types", b.name, name)
            }
            index = i
        }
    }
    if index < 0 {
        if len(b.params) >= MAX_PARAMS {
            log.panicf("shader '%s': too many parameters (max %d)", b.name, MAX_PARAMS)
        }
        append(&b.params, Param_Info{strings.clone(name), type, default_value, is_color})
        index = len(b.params) - 1
    }
    return add_node(Node{op = .Param, type = type, stage = .Any, index = i32(index)})
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

@(private)
ensure_active :: proc(what: string) {
    if !b.active {
        log.panicf("shader.%s: called outside of shader.begin()/shader.end()", what)
    }
}

@(private)
ensure_surface :: proc(what: string) {
    if b.mode != .Surface {
        log.panicf("shader.%s: only available in surface shaders", what)
    }
}

@(private)
ensure_post :: proc(what: string) {
    if b.mode != .Post {
        log.panicf("shader.%s: only available in post-processing shaders", what)
    }
}

@(private)
type_error :: proc(what: string, message: string, v: Value) {
    log.panicf("shader '%s': %s %s, got %v", b.name, what, message, v.type)
}

@(private)
expect_type :: proc(what: string, v: Value, type: Type) {
    if v.id <= 0 || int(v.id) >= len(b.nodes) {
        log.panicf("shader '%s': %s got an invalid value (did you mix values from different shaders?)", b.name, what)
    }
    if v.type != type {
        log.panicf("shader '%s': %s expects %v, got %v", b.name, what, type, v.type)
    }
}

@(private)
check_value :: proc(what: string, v: Value) {
    if v.id <= 0 || int(v.id) >= len(b.nodes) {
        log.panicf("shader '%s': %s got an invalid value (did you mix values from different shaders?)", b.name, what)
    }
}

@(private)
add_node :: proc(node: Node, args: ..Value) -> Value {
    n := node
    n.nargs = u8(len(args))
    for a, i in args {
        check_value("argument", a)
        n.args[i] = a.id
    }

    // Every node is a pure expression, so identical nodes can be shared.
    // This also merges repeated inputs (e.g. several world_position() calls)
    // into a single varying.
    for i := len(b.nodes) - 1; i > 0; i -= 1 {
        if b.nodes[i] == n {
            return Value{i32(i), n.type}
        }
    }

    append(&b.nodes, n)
    return Value{i32(len(b.nodes) - 1), n.type}
}

@(private)
type_components :: proc(t: Type) -> int {
    switch t {
    case .Float: return 1
    case .Vec2: return 2
    case .Vec3: return 3
    case .Vec4: return 4
    case .Invalid: return 0
    }
    return 0
}

@(private)
type_from_components :: proc(n: int) -> Type {
    switch n {
    case 1: return .Float
    case 2: return .Vec2
    case 3: return .Vec3
    case 4: return .Vec4
    }
    return .Invalid
}
