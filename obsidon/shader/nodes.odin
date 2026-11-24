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

package shader

import "core:log"
import "core:strings"
import m "core:math"

// Most primitives accept either a graph value or a plain number:
//     sh.mul(color, 2.0)   sh.vec4(rgb, 1)   sh.add(0.5, sh.sin(sh.time()))
Arg :: union {
    Value,
    f32,
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

float :: proc(x: f32) -> Value {
    ensure_active("float")
    return add_node(Node{op = .Literal, type = .Float, stage = .Any, consts = {x, 0, 0, 0}})
}

// Build a vector from any mix of values and numbers whose components add up:
//     sh.vec3(1, 0, 0)   sh.vec4(rgb, 1)   sh.vec2(sh.x(p), sh.z(p))
vec2 :: proc(args: ..Arg) -> Value { return construct("vec2", 2, args) }
vec3 :: proc(args: ..Arg) -> Value { return construct("vec3", 3, args) }
vec4 :: proc(args: ..Arg) -> Value { return construct("vec4", 4, args) }

// Colour constant (sRGB, converted to linear like every engine colour).
color :: proc(c: [4]f32) -> Value {
    ensure_active("color")
    lin := srgb_to_linear(c)
    return add_node(Node{op = .Literal, type = .Vec4, stage = .Any, consts = lin})
}

// ---------------------------------------------------------------------------
// Vertex inputs (surface shaders)
// ---------------------------------------------------------------------------

// Object-space vertex position.
position :: proc() -> Value { return input("position", "vin.position", .Vec3, .Vertex_Only) }
// Object-space vertex normal.
normal :: proc() -> Value { return input("normal", "vin.normal", .Vec3, .Vertex_Only) }
// Texture coordinates.
uv :: proc() -> Value { return input("uv", "vin.uv", .Vec2, .Vertex_Only) }
// Per-vertex colour (white when the mesh has none).
vertex_color :: proc() -> Value { return input("vertex_color", "vin.color", .Vec4, .Vertex_Only) }
// Object-space tangent (xyz) and bitangent sign (w), for normal mapping.
tangent :: proc() -> Value { return input("tangent", "vin.tangent", .Vec4, .Vertex_Only) }
// Per-draw tint passed to `obsidon.draw_mesh` (linear space).
tint :: proc() -> Value { return input("tint", "obs_draw.tint", .Vec4, .Vertex_Only) }

// Final world-space position of the vertex/fragment (after set_world_position).
// World space in Obsidon is camera-relative: the camera always sits at the
// origin, which keeps precision perfect even millions of units away.
// Add camera_position() for absolute coordinates.
world_position :: proc() -> Value {
    ensure_active("world_position")
    ensure_surface("world_position")
    return add_node(Node{op = .Final_World, type = .Vec3, stage = .Vertex_Only})
}

// World-space normal (normalized in the vertex stage; re-normalize after
// interpolation if you need exact unit length - the lighting primitives do).
world_normal :: proc() -> Value {
    return object_to_world_dir(normal())
}

// World-space tangent (xyz) + bitangent sign (w).
world_tangent :: proc() -> Value {
    ensure_surface("world_tangent")
    t := tangent()
    dir := call_staged_min("obs_object_to_world_vector", .Vec3, .Vertex_Only, xyz(t))
    return vec4(dir, w(t))
}

// World-space normal with a tangent space normal map applied.
// Load normal maps with srgb = false; declare the slot with
// texture("normal", .Flat_Normal) so unset materials stay flat.
normal_map :: proc(tex: Texture_Ref, uv: Value, strength: Arg = 1) -> Value {
    ensure_surface("normal_map")
    expect_type("normal_map", uv, .Vec2)
    s := to_value(strength)
    expect_type("normal_map strength", s, .Float)
    m := xyz(sample(tex, uv))
    return call("obs_perturb_normal", .Vec3, world_normal(), world_tangent(), m, s)
}

// Default clip-space position of the vertex: world_to_clip(world_position()).
clip_position :: proc() -> Value {
    return world_to_clip(world_position())
}

object_to_world :: proc(p: Value) -> Value {
    ensure_surface("object_to_world")
    expect_type("object_to_world", p, .Vec3)
    return call_staged_min("obs_object_to_world", .Vec3, .Vertex_Only, p)
}

object_to_world_dir :: proc(d: Value) -> Value {
    ensure_surface("object_to_world_dir")
    expect_type("object_to_world_dir", d, .Vec3)
    return call_staged_min("obs_object_to_world_dir", .Vec3, .Vertex_Only, d)
}

world_to_clip :: proc(p: Value) -> Value {
    expect_type("world_to_clip", p, .Vec3)
    return call("obs_world_to_clip", .Vec4, p)
}

world_to_view :: proc(p: Value) -> Value {
    expect_type("world_to_view", p, .Vec3)
    return call("obs_world_to_view", .Vec3, p)
}

// Normalized direction from the surface towards the camera.
view_direction :: proc(world_pos: Value) -> Value {
    expect_type("view_direction", world_pos, .Vec3)
    return call("obs_view_direction", .Vec3, world_pos)
}

// Distance from the camera.
view_distance :: proc(world_pos: Value) -> Value {
    expect_type("view_distance", world_pos, .Vec3)
    return call("length", .Float, world_pos)
}

// ---------------------------------------------------------------------------
// Global inputs
// ---------------------------------------------------------------------------

// Seconds since the game started.
time :: proc() -> Value { return input("time", "frame.time.x", .Float, .Any) }
delta_time :: proc() -> Value { return input("delta_time", "frame.time.y", .Float, .Any) }
// Render resolution in pixels.
resolution :: proc() -> Value { return input("resolution", "frame.resolution.xy", .Vec2, .Any) }
// Absolute camera position (f32 precision).
camera_position :: proc() -> Value { return input("camera_position", "frame.camera_position.xyz", .Vec3, .Any) }
// Direction towards the sun (normalized).
sun_direction :: proc() -> Value { return input("sun_direction", "frame.sun_direction.xyz", .Vec3, .Any) }
// Sun colour multiplied by its intensity.
sun_color :: proc() -> Value { return input("sun_color", "frame.sun_color.rgb", .Vec3, .Any) }
fog_color :: proc() -> Value { return input("fog_color", "frame.fog_color.rgb", .Vec3, .Any) }

// Pixel coordinate of the fragment (fragment only).
frag_coord :: proc() -> Value { return input("frag_coord", "obs_frag_coord.xy", .Vec2, .Fragment_Only) }
// 0..1 screen coordinate of the fragment, (0,0) is the top-left (fragment only).
screen_uv :: proc() -> Value { return input("screen_uv", "(obs_frag_coord.xy * frame.resolution.zw)", .Vec2, .Fragment_Only) }

// ---------------------------------------------------------------------------
// Interpolation control
// ---------------------------------------------------------------------------

// Interpolate a vertex value without perspective correction.
// Applied to UVs this gives the warping PS1 textures are known for.
affine :: proc(v: Value) -> Value { return interpolate("affine", v, .Linear) }

// Compute a value per vertex and interpolate it across the triangle
// (cheaper, and the look of per-vertex lighting / fog on old hardware).
per_vertex :: proc(v: Value) -> Value { return interpolate("per_vertex", v, .Perspective) }

// Don't interpolate at all: every fragment of a triangle gets the value of
// its first vertex (flat shading, low-poly look).
flat :: proc(v: Value) -> Value { return interpolate("flat", v, .Flat) }

// ---------------------------------------------------------------------------
// Lighting & effects
// ---------------------------------------------------------------------------

// Total diffuse light reaching a surface, computed per pixel: ambient
// (hemisphere sky/ground, with SSAO when enabled) + sun (with shadows) +
// point/spot lights. Multiply your albedo with it.
lighting :: proc(world_pos: Value, world_normal: Value) -> Value {
    expect_type("lighting", world_pos, .Vec3)
    expect_type("lighting", world_normal, .Vec3)
    ensure_surface("lighting")
    return stage_call("obs_lighting", .Vec3, world_pos, world_normal)
}

// Same as `lighting` but evaluated per vertex and interpolated (Gouraud
// shading, the classic PS1 look). SSAO is not applied to per-vertex light.
lighting_per_vertex :: proc(world_pos: Value, world_normal: Value) -> Value {
    expect_type("lighting_per_vertex", world_pos, .Vec3)
    expect_type("lighting_per_vertex", world_normal, .Vec3)
    ensure_surface("lighting_per_vertex")
    return per_vertex(stage_call("obs_lighting", .Vec3, world_pos, world_normal))
}

// Direct light only (sun + point/spot lights), no ambient.
direct_lighting :: proc(world_pos: Value, world_normal: Value) -> Value {
    expect_type("direct_lighting", world_pos, .Vec3)
    expect_type("direct_lighting", world_normal, .Vec3)
    ensure_surface("direct_lighting")
    return call("obs_direct_diffuse", .Vec3, world_pos, world_normal)
}

// Blinn-Phong specular highlights from the sun and point/spot lights,
// computed per pixel. Higher shininess = smaller, sharper highlights.
specular :: proc(world_pos: Value, world_normal: Value, shininess: Arg) -> Value {
    expect_type("specular", world_pos, .Vec3)
    expect_type("specular", world_normal, .Vec3)
    ensure_surface("specular")
    s := to_value(shininess)
    expect_type("specular shininess", s, .Float)
    return call("obs_specular", .Vec3, world_pos, world_normal, s)
}

// Hemisphere ambient light for a normal (sky colour above, ground below).
ambient :: proc(world_normal: Value) -> Value {
    expect_type("ambient", world_normal, .Vec3)
    ensure_surface("ambient")
    return call("obs_ambient", .Vec3, world_normal)
}

// Sun shadow factor: 0 = fully shadowed, 1 = lit.
shadow :: proc(world_pos: Value, world_normal: Value) -> Value {
    expect_type("shadow", world_pos, .Vec3)
    expect_type("shadow", world_normal, .Vec3)
    ensure_surface("shadow")
    return call("obs_shadow", .Float, world_pos, world_normal)
}

// Screen-space ambient occlusion factor (1 when SSAO is disabled). Fragment only.
ambient_occlusion :: proc() -> Value {
    ensure_surface("ambient_occlusion")
    return add_node(Node{op = .Call, type = .Float, stage = .Fragment_Only, text = "obs_ao"})
}

// Blend a colour towards the fog colour based on distance (see obsidon.set_fog).
fog :: proc(color: Value, world_pos: Value) -> Value {
    expect_type("fog", world_pos, .Vec3)
    if color.type != .Vec3 {
        type_error("fog", "expects a vec3 colour", color)
    }
    return call("obs_fog", .Vec3, color, world_pos)
}

// Snap a clip-space position to a pixel grid (PS1 vertex jitter / wobble).
// `grid` is the virtual resolution, e.g. sh.vec2(320, 240) or sh.resolution().
snap_to_grid :: proc(clip: Value, grid: Arg) -> Value {
    expect_type("snap_to_grid", clip, .Vec4)
    g := to_value(grid)
    if g.type == .Float {
        g = vec2(g, g)
    }
    expect_type("snap_to_grid grid", g, .Vec2)
    return call("obs_snap_to_grid", .Vec4, clip, g)
}

// Reduce colour depth with an ordered (Bayer) dither pattern. `levels` is
// the number of shades per channel, e.g. 32 for PS1-like 15-bit colour.
dither :: proc(color: Value, levels: Arg) -> Value {
    if color.type != .Vec3 {
        type_error("dither", "expects a vec3 colour", color)
    }
    l := to_value(levels)
    expect_type("dither levels", l, .Float)
    return add_node(Node{op = .Call, type = .Vec3, stage = .Fragment_Only, text = "obs_dither"}, color, l)
}

// Reduce colour depth without dithering.
quantize :: proc(color: Value, levels: Arg) -> Value {
    if color.type != .Vec3 {
        type_error("quantize", "expects a vec3 colour", color)
    }
    l := to_value(levels)
    expect_type("quantize levels", l, .Float)
    return call_splat("obs_quantize", .Vec3, color, l)
}

// Perceived brightness of a colour.
luminance :: proc(color: Value) -> Value {
    if color.type != .Vec3 {
        type_error("luminance", "expects a vec3 colour", color)
    }
    return call("obs_luminance", .Float, color)
}

// Pseudo random value in 0..1 from a 2D seed.
hash :: proc(seed: Value) -> Value {
    expect_type("hash", seed, .Vec2)
    return call("obs_hash", .Float, seed)
}

// Smooth 3D value noise in 0..1 (procedural textures, planets, clouds...).
noise :: proc(p: Value) -> Value {
    expect_type("noise", p, .Vec3)
    return call("obs_noise3", .Float, p)
}

// Fractal noise: `octaves` layers of noise, each twice as detailed. 0..1.
fbm :: proc(p: Value, octaves: Arg = 5) -> Value {
    expect_type("fbm", p, .Vec3)
    o := to_value(octaves)
    expect_type("fbm octaves", o, .Float)
    return call("obs_fbm3", .Float, p, o)
}

// ---------------------------------------------------------------------------
// Post-processing inputs
// ---------------------------------------------------------------------------

// Colour of the rendered scene (or the previous effect) at `uv`.
scene_color :: proc(uv: Value) -> Value {
    ensure_post("scene_color")
    expect_type("scene_color", uv, .Vec2)
    return call("obs_scene_color", .Vec4, uv)
}

// Distance from the camera to the scene at `uv` (huge for the sky).
scene_depth :: proc(uv: Value) -> Value {
    ensure_post("scene_depth")
    expect_type("scene_depth", uv, .Vec2)
    return call("obs_scene_linear_depth", .Float, uv)
}

// Size of one render target pixel in uv units.
texel_size :: proc() -> Value { return input("texel_size", "frame.resolution.zw", .Vec2, .Any) }

// ---------------------------------------------------------------------------
// Math
// ---------------------------------------------------------------------------

add :: proc(a: Arg, c: Arg) -> Value { return binary("add", "+", a, c) }
sub :: proc(a: Arg, c: Arg) -> Value { return binary("sub", "-", a, c) }
mul :: proc(a: Arg, c: Arg) -> Value { return binary("mul", "*", a, c) }
div :: proc(a: Arg, c: Arg) -> Value { return binary("div", "/", a, c) }

negate :: proc(a: Value) -> Value {
    check_value("negate", a)
    return add_node(Node{op = .Negate, type = a.type}, a)
}

one_minus :: proc(a: Value) -> Value { return sub(1.0, a) }

dot :: proc(a: Value, c: Value) -> Value {
    same_vector("dot", a, c)
    return call("dot", .Float, a, c)
}

cross :: proc(a: Value, c: Value) -> Value {
    expect_type("cross", a, .Vec3)
    expect_type("cross", c, .Vec3)
    return call("cross", .Vec3, a, c)
}

normalize :: proc(a: Value) -> Value {
    vector("normalize", a)
    return call("normalize", a.type, a)
}

length :: proc(a: Value) -> Value {
    check_value("length", a)
    return call("length", .Float, a)
}

distance :: proc(a: Value, c: Value) -> Value {
    if a.type != c.type {
        log.panicf("shader '%s': distance expects matching types, got %v and %v", b.name, a.type, c.type)
    }
    return call("distance", .Float, a, c)
}

reflect :: proc(incident: Value, normal: Value) -> Value {
    same_vector("reflect", incident, normal)
    return call("reflect", incident.type, incident, normal)
}

abs   :: proc(a: Value) -> Value { return unary("abs", a) }
floor :: proc(a: Value) -> Value { return unary("floor", a) }
ceil  :: proc(a: Value) -> Value { return unary("ceil", a) }
round :: proc(a: Value) -> Value { return unary("round", a) }
fract :: proc(a: Value) -> Value { return unary("fract", a) }
sqrt  :: proc(a: Value) -> Value { return unary("sqrt", a) }
exp   :: proc(a: Value) -> Value { return unary("exp", a) }
log2  :: proc(a: Value) -> Value { return unary("log2", a) }
sin   :: proc(a: Value) -> Value { return unary("sin", a) }
cos   :: proc(a: Value) -> Value { return unary("cos", a) }
tan   :: proc(a: Value) -> Value { return unary("tan", a) }
sign  :: proc(a: Value) -> Value { return unary("sign", a) }
saturate :: proc(a: Value) -> Value { return unary("saturate", a) }

min :: proc(a: Arg, c: Arg) -> Value { return componentwise("min", a, c) }
max :: proc(a: Arg, c: Arg) -> Value { return componentwise("max", a, c) }
pow :: proc(a: Arg, c: Arg) -> Value { return componentwise("pow", a, c) }
mod :: proc(a: Arg, c: Arg) -> Value { return binary("mod", "%", a, c) }
step :: proc(edge: Arg, x: Arg) -> Value { return componentwise("step", edge, x) }

clamp :: proc(x: Arg, lo: Arg, hi: Arg) -> Value { return componentwise("clamp", x, lo, hi) }
smoothstep :: proc(lo: Arg, hi: Arg, x: Arg) -> Value { return componentwise("smoothstep", lo, hi, x) }

// Linear blend between a and c by t (t can be a float or match a/c).
mix :: proc(a: Arg, c: Arg, t: Arg) -> Value { return componentwise("mix", a, c, t) }

// ---------------------------------------------------------------------------
// Swizzles
// ---------------------------------------------------------------------------

// Pick / reorder components, e.g. sh.swizzle(v, "zyx").
swizzle :: proc(v: Value, pattern: string) -> Value {
    check_value("swizzle", v)
    n := len(pattern)
    if n < 1 || n > 4 {
        log.panicf("shader '%s': invalid swizzle '%s'", b.name, pattern)
    }
    count := type_components(v.type)
    for c in pattern {
        idx := -1
        switch c {
        case 'x', 'r': idx = 0
        case 'y', 'g': idx = 1
        case 'z', 'b': idx = 2
        case 'w', 'a': idx = 3
        }
        if idx < 0 || idx >= count {
            log.panicf("shader '%s': swizzle '%s' is invalid for %v", b.name, pattern, v.type)
        }
    }
    if v.type == .Float {
        // Scalars can't be swizzled in WGSL; splat instead.
        switch n {
        case 1: return v
        case 2: return vec2(v, v)
        case 3: return vec3(v, v, v)
        case 4: return vec4(v, v, v, v)
        }
    }
    return add_node(Node{op = .Swizzle, type = type_from_components(n), text = strings.clone(pattern)}, v)
}

x :: proc(v: Value) -> Value { return swizzle(v, "x") }
y :: proc(v: Value) -> Value { return swizzle(v, "y") }
z :: proc(v: Value) -> Value { return swizzle(v, "z") }
w :: proc(v: Value) -> Value { return swizzle(v, "w") }
xy :: proc(v: Value) -> Value { return swizzle(v, "xy") }
xyz :: proc(v: Value) -> Value { return swizzle(v, "xyz") }
rgb :: proc(v: Value) -> Value { return swizzle(v, "xyz") }
a :: proc(v: Value) -> Value { return swizzle(v, "w") }

// ---------------------------------------------------------------------------
// Escape hatch
// ---------------------------------------------------------------------------

// Call any WGSL built-in or engine function by name. The result type must be
// given explicitly. Prefer the typed primitives above when possible.
custom_call :: proc(function: string, result: Type, args: ..Value) -> Value {
    ensure_active("custom_call")
    return add_node(Node{op = .Call, type = result, text = strings.clone(function)}, ..args)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

@(private)
to_value :: proc(a: Arg) -> Value {
    switch v in a {
    case Value: return v
    case f32: return float(v)
    }
    log.panic("shader: empty argument")
}

@(private)
input :: proc(what: string, expr: string, type: Type, stage: Stage) -> Value {
    ensure_active(what)
    if stage == .Vertex_Only && b.mode == .Post {
        log.panicf("shader.%s: vertex inputs are not available in post-processing shaders", what)
    }
    return add_node(Node{op = .Input, type = type, stage = stage, text = expr})
}

@(private)
interpolate :: proc(what: string, v: Value, mode: Interpolation) -> Value {
    ensure_active(what)
    ensure_surface(what)
    check_value(what, v)
    return add_node(Node{op = .Interpolate, type = v.type, index = i32(mode)}, v)
}

@(private)
call :: proc(function: string, result: Type, args: ..Value) -> Value {
    ensure_active(function)
    return add_node(Node{op = .Call, type = result, text = function}, ..args)
}

// A call that needs per-draw data and therefore must run in the vertex stage
// (its result is interpolated when used in the pixel stage).
@(private)
call_staged_min :: proc(function: string, result: Type, stage: Stage, args: ..Value) -> Value {
    ensure_active(function)
    return add_node(Node{op = .Call, type = result, stage = stage, text = function}, ..args)
}

// A call with separate vertex (`_vs`) and fragment (`_fs`) implementations.
@(private)
stage_call :: proc(function: string, result: Type, args: ..Value) -> Value {
    ensure_active(function)
    return add_node(Node{op = .Stage_Call, type = result, text = function}, ..args)
}

// A call where float arguments are splatted to the result vector type.
@(private)
call_splat :: proc(function: string, result: Type, args: ..Value) -> Value {
    ensure_active(function)
    return add_node(Node{op = .Call, type = result, text = function, splat = true}, ..args)
}

@(private)
unary :: proc(function: string, a: Value) -> Value {
    ensure_active(function)
    check_value(function, a)
    return call(function, a.type, a)
}

@(private)
vector :: proc(what: string, a: Value) {
    check_value(what, a)
    if a.type == .Float {
        log.panicf("shader '%s': %s expects a vector, got float", b.name, what)
    }
}

@(private)
same_vector :: proc(what: string, a: Value, c: Value) {
    vector(what, a)
    vector(what, c)
    if a.type != c.type {
        log.panicf("shader '%s': %s expects matching vectors, got %v and %v", b.name, what, a.type, c.type)
    }
}

@(private)
binary :: proc(what: string, op: string, a_arg: Arg, c_arg: Arg) -> Value {
    ensure_active(what)
    a := to_value(a_arg)
    c := to_value(c_arg)
    result := combine_types(what, {a.type, c.type})
    return add_node(Node{op = .Binary, type = result, text = op}, a, c)
}

@(private)
componentwise :: proc(what: string, args: ..Arg) -> Value {
    ensure_active(what)
    values: [4]Value
    types: [4]Type
    for arg, i in args {
        values[i] = to_value(arg)
        types[i] = values[i].type
    }
    result := combine_types(what, types[:len(args)])
    return add_node(Node{op = .Call, type = result, text = what, splat = true}, ..values[:len(args)])
}

// All non-float types must match; floats are broadcast.
@(private)
combine_types :: proc(what: string, types: []Type) -> Type {
    result := Type.Float
    for t in types {
        if t == .Invalid {
            log.panicf("shader '%s': %s got an invalid value", b.name, what)
        }
        if t == .Float {
            continue
        }
        if result == .Float {
            result = t
        } else if result != t {
            log.panicf("shader '%s': %s can't combine %v and %v", b.name, what, result, t)
        }
    }
    return result
}

@(private)
construct :: proc(what: string, n: int, args: []Arg) -> Value {
    ensure_active(what)
    values: [4]Value
    if len(args) > 4 || len(args) == 0 {
        log.panicf("shader '%s': %s takes 1 to 4 arguments", b.name, what)
    }

    all_const := true
    consts: [4]f32
    count := 0
    for arg, i in args {
        switch v in arg {
        case f32:
            if count < 4 { consts[count] = v }
            count += 1
        case Value:
            all_const = false
            count += type_components(v.type)
        }
    }

    if len(args) == 1 && count == 1 {
        // Splat: vec3(x) == vec3(x, x, x)
        count = n
        if all_const {
            consts = {consts[0], consts[0], consts[0], consts[0]}
        }
    }

    if count != n {
        log.panicf("shader '%s': %s needs %d components, got %d", b.name, what, n, count)
    }

    if all_const {
        return add_node(Node{op = .Literal, type = type_from_components(n), stage = .Any, consts = consts})
    }
    for arg, i in args {
        values[i] = to_value(arg)
    }
    return add_node(Node{op = .Construct, type = type_from_components(n)}, ..values[:len(args)])
}

@(private)
srgb_to_linear :: proc(c: [4]f32) -> [4]f32 {
    convert :: proc(v: f32) -> f32 {
        if v <= 0.04045 {
            return v / 12.92
        }
        return m.pow((v + 0.055) / 1.055, 2.4)
    }
    return {convert(c.r), convert(c.g), convert(c.b), c.a}
}
