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

import "core:fmt"
import "core:log"
import "core:strings"

@(private)
COMMON_WGSL :: string(#load("wgsl/common.wgsl"))
@(private)
SURFACE_WGSL :: string(#load("wgsl/surface.wgsl"))
@(private)
POST_WGSL :: string(#load("wgsl/post.wgsl"))

// Engine library sources, exposed so the renderer's internal passes can reuse them.
LIBRARY_COMMON  :: COMMON_WGSL
LIBRARY_SURFACE :: SURFACE_WGSL
LIBRARY_POST    :: POST_WGSL

@(private)
Variant :: enum {
    Main,
    Prepass,
    Shadow,
    Post,
}

@(private)
Gen :: struct {
    variant:    Variant,
    out:        strings.Builder,
    frag_need:  []bool,
    vert_need:  []bool,
    world_set:  []bool,
    varying:    []bool,
}

@(private)
generate :: proc(variant: Variant) -> string {
    g := Gen{variant = variant}
    n := len(b.nodes)
    g.frag_need = make([]bool, n, context.temp_allocator)
    g.vert_need = make([]bool, n, context.temp_allocator)
    g.world_set = make([]bool, n, context.temp_allocator)
    g.varying = make([]bool, n, context.temp_allocator)
    g.out = strings.builder_make()

    // ---- Fragment roots
    frag_roots: [2]i32
    switch variant {
    case .Main, .Post: frag_roots = {b.out_color, b.out_alpha_clip}
    case .Prepass:     frag_roots = {b.out_normal, b.out_alpha_clip}
    case .Shadow:      frag_roots = {0, b.out_alpha_clip}
    }
    for r in frag_roots {
        mark_frag(&g, r)
    }
    has_fragment := variant != .Shadow || b.out_alpha_clip != 0

    // ---- Vertex roots
    if b.mode == .Surface {
        mark_vert(&g, b.out_world, g.world_set)
        for i in 1..<n {
            if g.world_set[i] && b.nodes[i].op == .Final_World {
                log.panicf("shader '%s': set_world_position() depends on world_position() - use object_to_world(position()) instead", b.name)
            }
        }
        mark_vert(&g, b.out_world, g.vert_need)
        mark_vert(&g, b.out_clip, g.vert_need)
        for i in 1..<n {
            if !g.varying[i] {
                continue
            }
            node := b.nodes[i]
            if node.op == .Interpolate {
                mark_vert(&g, node.args[0], g.vert_need)
            } else {
                mark_vert(&g, i32(i), g.vert_need)
            }
        }
    }

    // ---- Header & library
    fmt.sbprintf(&g.out, "// Obsidon generated shader '%s' (%v pass)\n\n", b.name, variant)
    strings.write_string(&g.out, COMMON_WGSL)
    strings.write_string(&g.out, "\n")
    if b.mode == .Surface {
        strings.write_string(&g.out, SURFACE_WGSL)
    } else {
        strings.write_string(&g.out, POST_WGSL)
    }
    strings.write_string(&g.out, "\n")

    // ---- Material bindings
    fmt.sbprintf(&g.out, "struct Material_Params {{\n    values: array<vec4f, %d>,\n}}\n\n", MAX_PARAMS)
    strings.write_string(&g.out, "@group(1) @binding(0) var<uniform> material: Material_Params;\n")
    strings.write_string(&g.out, "@group(1) @binding(1) var material_sampler: sampler;\n")
    for t, i in b.textures {
        fmt.sbprintf(&g.out, "@group(1) @binding(%d) var tex_%d: %s; // %s\n", i + 2, i, "texture_3d<f32>" if t.volume else "texture_2d<f32>", t.name)
    }
    strings.write_string(&g.out, "\n")

    // ---- Varyings
    strings.write_string(&g.out, "struct Vs_Out {\n    @builtin(position) clip: vec4f,\n")
    location := 0
    for i in 1..<n {
        if !g.varying[i] {
            continue
        }
        node := b.nodes[i]
        interp := ""
        if node.op == .Interpolate {
            switch Interpolation(node.index) {
            case .Perspective:
            case .Linear: interp = "@interpolate(linear) "
            case .Flat: interp = "@interpolate(flat) "
            }
        }
        fmt.sbprintf(&g.out, "    @location(%d) %sv%d: %s,\n", location, interp, i, wgsl_type(node.type))
        location += 1
    }
    if b.mode == .Post {
        // Screen uv from the fullscreen triangle: right at any target size
        // (half resolution post effects).
        fmt.sbprintf(&g.out, "    @location(%d) post_uv: vec2f,\n", location)
        location += 1
    }
    strings.write_string(&g.out, "}\n\n")
    if location > 15 {
        log.panicf("shader '%s': too many values passed from the vertex to the fragment stage (%d, max 15)", b.name, location)
    }

    // ---- Vertex stage
    if b.mode == .Surface {
        strings.write_string(&g.out, "@vertex\nfn vs_main(vin: Vertex_In) -> Vs_Out {\n")
        strings.write_string(&g.out, "    obs_draw = draws[vin.instance];\n")
        for i in 1..<n {
            if g.world_set[i] {
                emit_node(&g, i32(i), Emit.Vertex)
            }
        }
        fmt.sbprintf(&g.out, "    let final_world: vec3f = n%d;\n", b.out_world)
        for i in 1..<n {
            if g.vert_need[i] && !g.world_set[i] {
                emit_node(&g, i32(i), Emit.Vertex)
            }
        }
        strings.write_string(&g.out, "    var out: Vs_Out;\n")
        fmt.sbprintf(&g.out, "    out.clip = n%d;\n", b.out_clip)
        for i in 1..<n {
            if !g.varying[i] {
                continue
            }
            node := b.nodes[i]
            source := i32(i)
            if node.op == .Interpolate {
                source = node.args[0]
            }
            fmt.sbprintf(&g.out, "    out.v%d = n%d;\n", i, source)
        }
        strings.write_string(&g.out, "    return out;\n}\n\n")
    } else {
        strings.write_string(&g.out,
`@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> Vs_Out {
    // Full screen triangle
    let uv = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
    var out: Vs_Out;
    out.clip = vec4f(uv * 2.0 - 1.0, 0.0, 1.0);
    out.post_uv = vec2f(uv.x, 1.0 - uv.y);
    return out;
}

`)
    }

    // ---- Fragment stage
    if has_fragment {
        switch variant {
        case .Main, .Post, .Prepass:
            strings.write_string(&g.out, "@fragment\nfn fs_main(fin: Vs_Out) -> @location(0) vec4f {\n")
        case .Shadow:
            strings.write_string(&g.out, "@fragment\nfn fs_main(fin: Vs_Out) {\n")
        }
        strings.write_string(&g.out, "    obs_frag_coord = fin.clip;\n")
        if b.mode == .Post {
            strings.write_string(&g.out, "    obs_post_uv = fin.post_uv;\n")
        }
        for i in 1..<n {
            if g.frag_need[i] {
                emit_node(&g, i32(i), .Fragment)
            }
        }
        if b.out_alpha_clip != 0 {
            fmt.sbprintf(&g.out, "    if (%s < %s) {{\n        discard;\n    }}\n", ref(&g, b.out_alpha_clip, .Fragment), wgsl_float(b.alpha_clip_threshold))
        }
        switch variant {
        case .Main, .Post:
            fmt.sbprintf(&g.out, "    return %s;\n", ref(&g, b.out_color, .Fragment))
        case .Prepass:
            fmt.sbprintf(&g.out, "    let view_normal = normalize((frame.view * vec4f(normalize(%s), 0.0)).xyz);\n", ref(&g, b.out_normal, .Fragment))
            strings.write_string(&g.out, "    return vec4f(view_normal, 1.0);\n")
        case .Shadow:
        }
        strings.write_string(&g.out, "}\n")
    }

    return strings.to_string(g.out)
}

@(private)
mark_frag :: proc(g: ^Gen, id: i32) {
    if id == 0 || g.frag_need[id] || g.varying[id] {
        return
    }
    node := b.nodes[id]
    if node.stage == .Vertex_Only || node.op == .Interpolate {
        g.varying[id] = true
        return
    }
    g.frag_need[id] = true
    for i in 0..<node.nargs {
        mark_frag(g, node.args[i])
    }
}

@(private)
mark_vert :: proc(g: ^Gen, id: i32, set: []bool) {
    if id == 0 || set[id] {
        return
    }
    node := b.nodes[id]
    if node.stage == .Fragment_Only {
        log.panicf("shader '%s': %s can only be used in the fragment stage, but a vertex output depends on it", b.name, node_description(node))
    }
    if node.op == .Interpolate {
        log.panicf("shader '%s': the result of affine()/flat()/per_vertex() is a pixel value and can't feed a vertex output", b.name)
    }
    set[id] = true
    for i in 0..<node.nargs {
        mark_vert(g, node.args[i], set)
    }
}

@(private)
ref :: proc(g: ^Gen, id: i32, stage: Emit) -> string {
    if stage == .Fragment && g.varying[id] {
        return fmt.tprintf("fin.v%d", id)
    }
    return fmt.tprintf("n%d", id)
}

@(private)
emit_node :: proc(g: ^Gen, id: i32, stage: Emit) {
    node := b.nodes[id]
    fmt.sbprintf(&g.out, "    let n%d: %s = %s;\n", id, wgsl_type(node.type), expression(g, node, stage))
}

@(private)
expression :: proc(g: ^Gen, node: Node, stage: Emit) -> string {
    arg :: proc(g: ^Gen, node: Node, i: int, stage: Emit) -> string {
        id := node.args[i]
        s := ref(g, id, stage)
        if node.splat && node.type != .Float && b.nodes[id].type == .Float {
            return fmt.tprintf("%s(%s)", wgsl_type(node.type), s)
        }
        return s
    }

    switch node.op {
    case .None:
        log.panic("shader codegen: empty node")
    case .Literal:
        switch node.type {
        case .Float: return wgsl_float(node.consts[0])
        case .Vec2: return fmt.tprintf("vec2f(%s, %s)", wgsl_float(node.consts[0]), wgsl_float(node.consts[1]))
        case .Vec3: return fmt.tprintf("vec3f(%s, %s, %s)", wgsl_float(node.consts[0]), wgsl_float(node.consts[1]), wgsl_float(node.consts[2]))
        case .Vec4: return fmt.tprintf("vec4f(%s, %s, %s, %s)", wgsl_float(node.consts[0]), wgsl_float(node.consts[1]), wgsl_float(node.consts[2]), wgsl_float(node.consts[3]))
        case .Invalid:
        }
    case .Construct, .Call, .Stage_Call:
        name: string
        switch node.op {
        case .Construct: name = wgsl_type(node.type)
        case .Stage_Call: name = fmt.tprintf("%s_%s", node.text, "fs" if stage == .Fragment else "vs")
        case .Call: name = node.text
        case .None, .Literal, .Binary, .Negate, .Swizzle, .Input, .Final_World, .Param, .Sample, .Interpolate:
        }
        sb := strings.builder_make(context.temp_allocator)
        strings.write_string(&sb, name)
        strings.write_string(&sb, "(")
        for i in 0..<int(node.nargs) {
            if i > 0 {
                strings.write_string(&sb, ", ")
            }
            strings.write_string(&sb, arg(g, node, i, stage))
        }
        strings.write_string(&sb, ")")
        return strings.to_string(sb)
    case .Binary:
        return fmt.tprintf("(%s %s %s)", arg(g, node, 0, stage), node.text, arg(g, node, 1, stage))
    case .Negate:
        return fmt.tprintf("(-%s)", arg(g, node, 0, stage))
    case .Swizzle:
        return fmt.tprintf("%s.%s", arg(g, node, 0, stage), node.text)
    case .Input:
        return node.text
    case .Final_World:
        return "final_world"
    case .Param:
        swz := ""
        switch node.type {
        case .Float: swz = ".x"
        case .Vec2: swz = ".xy"
        case .Vec3: swz = ".xyz"
        case .Vec4, .Invalid:
        }
        return fmt.tprintf("material.values[%d]%s", node.index, swz)
    case .Sample:
        if node.nargs > 1 {
            return fmt.tprintf("textureSampleLevel(tex_%d, material_sampler, %s, %s)", node.index, arg(g, node, 0, stage), arg(g, node, 1, stage))
        }
        if stage == .Fragment {
            return fmt.tprintf("textureSample(tex_%d, material_sampler, %s)", node.index, arg(g, node, 0, stage))
        }
        return fmt.tprintf("textureSampleLevel(tex_%d, material_sampler, %s, 0.0)", node.index, arg(g, node, 0, stage))
    case .Interpolate:
        log.panic("shader codegen: interpolated values are only read through varyings")
    }
    return ""
}

@(private)
node_description :: proc(node: Node) -> string {
    #partial switch node.op {
    case .Input, .Call, .Stage_Call: return node.text
    case .Interpolate: return "affine()/flat() result"
    case .Sample: return "sample()"
    }
    return fmt.tprintf("%v", node.op)
}

@(private)
wgsl_type :: proc(t: Type) -> string {
    switch t {
    case .Float: return "f32"
    case .Vec2: return "vec2f"
    case .Vec3: return "vec3f"
    case .Vec4: return "vec4f"
    case .Invalid:
    }
    return "<invalid>"
}

@(private)
wgsl_float :: proc(v: f32) -> string {
    s := fmt.tprintf("%.7f", v)
    return s
}
