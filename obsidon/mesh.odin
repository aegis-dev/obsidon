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

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:strconv"
import "core:strings"

import "internal/renderer"

// GPU mesh. Create with mesh_create / mesh_load_obj / mesh_cube / ...
// and free with mesh_destroy.
Mesh :: renderer.Mesh

// position, normal, uv, color - all f32 (GPU data).
Vertex :: renderer.Vertex

// Triangle list, counter-clockwise front faces. `indices` may be empty.
mesh_create :: proc(vertices: []Vertex, indices: []u32 = nil) -> Mesh {
    return renderer.mesh_create(vertices, indices)
}

mesh_destroy :: proc(mesh: ^Mesh) {
    renderer.mesh_destroy(mesh)
}

// Queue a mesh for rendering this frame (call from on_draw).
// `tint` multiplies the colour in shaders that use shader.tint() (all built-in ones do).
draw_mesh :: proc(mesh: ^Mesh, material: ^Material, transform: Transform, tint := WHITE) {
    renderer.draw_mesh(mesh, material, transform_matrix(transform), renderer.srgb_to_linear(tint))
}

draw_mesh_matrix :: proc(mesh: ^Mesh, material: ^Material, model: Mat4, tint := WHITE) {
    renderer.draw_mesh(mesh, material, model, renderer.srgb_to_linear(tint))
}

// Draw many copies of a mesh in a single draw call (asteroid fields, debris,
// trees, crowds...). Much faster than calling draw_mesh in a loop.
draw_mesh_instanced :: proc(mesh: ^Mesh, material: ^Material, transforms: []Transform, tint := WHITE) {
    models := make([]Mat4, len(transforms), context.temp_allocator)
    for t, i in transforms {
        models[i] = transform_matrix(t)
    }
    tints := [1]renderer.Vec4{renderer.srgb_to_linear(tint)}
    renderer.draw_mesh_instanced(mesh, material, models, tints[:])
}

// Instanced draw with one tint per instance (len(tints) == len(transforms)).
draw_mesh_instanced_tinted :: proc(mesh: ^Mesh, material: ^Material, transforms: []Transform, tints: []Color) {
    models := make([]Mat4, len(transforms), context.temp_allocator)
    for t, i in transforms {
        models[i] = transform_matrix(t)
    }
    linear := make([]renderer.Vec4, len(tints), context.temp_allocator)
    for c, i in tints {
        linear[i] = renderer.srgb_to_linear(c)
    }
    renderer.draw_mesh_instanced(mesh, material, models, linear)
}

// Instanced draw from model matrices.
draw_mesh_instanced_matrices :: proc(mesh: ^Mesh, material: ^Material, models: []Mat4, tint := WHITE) {
    tints := [1]renderer.Vec4{renderer.srgb_to_linear(tint)}
    renderer.draw_mesh_instanced(mesh, material, models, tints[:])
}

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

// Axis aligned box centred on the origin.
mesh_cube :: proc(size := Vec3{1, 1, 1}, color := WHITE) -> Mesh {
    h := [3]f32{f32(size.x) * 0.5, f32(size.y) * 0.5, f32(size.z) * 0.5}
    c := renderer.Vec4(color)
    Face :: struct { n, u, v: [3]f32 }
    faces := [6]Face{
        {{1, 0, 0}, {0, 0, -1}, {0, 1, 0}},
        {{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}},
        {{0, 1, 0}, {1, 0, 0}, {0, 0, -1}},
        {{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
        {{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},
        {{0, 0, -1}, {-1, 0, 0}, {0, 1, 0}},
    }
    vertices := make([dynamic]Vertex, 0, 24, context.temp_allocator)
    indices := make([dynamic]u32, 0, 36, context.temp_allocator)
    for f in faces {
        base := u32(len(vertices))
        corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
        for corner in corners {
            p := (f.n + f.u * corner.x + f.v * corner.y) * h
            append(&vertices, Vertex{p, f.n, {corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5}, c, {}})
        }
        append(&indices, base, base + 1, base + 2, base, base + 2, base + 3)
    }
    return mesh_create(vertices[:], indices[:])
}

// UV sphere centred on the origin.
mesh_sphere :: proc(radius: f64 = 0.5, segments: int = 24, rings: int = 16, color := WHITE) -> Mesh {
    segments := max(segments, 3)
    rings := max(rings, 2)
    c := renderer.Vec4(color)
    vertices := make([dynamic]Vertex, context.temp_allocator)
    indices := make([dynamic]u32, context.temp_allocator)
    for ring in 0..=rings {
        v := f32(ring) / f32(rings)
        phi := v * math.PI
        for seg in 0..=segments {
            u := f32(seg) / f32(segments)
            theta := u * 2 * math.PI
            n := [3]f32{math.sin(phi) * math.cos(theta), math.cos(phi), -math.sin(phi) * math.sin(theta)}
            append(&vertices, Vertex{n * f32(radius), n, {u, v}, c, {}})
        }
    }
    stride := u32(segments + 1)
    for ring in 0..<u32(rings) {
        for seg in 0..<u32(segments) {
            a := ring * stride + seg
            b := a + stride
            append(&indices, a, b, a + 1, a + 1, b, b + 1)
        }
    }
    return mesh_create(vertices[:], indices[:])
}

// Flat plane on the XZ axes facing +Y, centred on the origin.
// `uv_scale` repeats the texture over the plane.
mesh_plane :: proc(size := Vec2{10, 10}, subdivisions: int = 1, uv_scale: f32 = 1, color := WHITE) -> Mesh {
    n := max(subdivisions, 1)
    c := renderer.Vec4(color)
    vertices := make([dynamic]Vertex, context.temp_allocator)
    indices := make([dynamic]u32, context.temp_allocator)
    for z in 0..=n {
        for x in 0..=n {
            u := f32(x) / f32(n)
            v := f32(z) / f32(n)
            p := [3]f32{(u - 0.5) * f32(size.x), 0, (v - 0.5) * f32(size.y)}
            append(&vertices, Vertex{p, {0, 1, 0}, {u * uv_scale, v * uv_scale}, c, {}})
        }
    }
    stride := u32(n + 1)
    for z in 0..<u32(n) {
        for x in 0..<u32(n) {
            a := z * stride + x
            b := a + stride
            append(&indices, a, b, a + 1, a + 1, b, b + 1)
        }
    }
    return mesh_create(vertices[:], indices[:])
}

// Cylinder along the Y axis, centred on the origin.
mesh_cylinder :: proc(radius: f64 = 0.5, height: f64 = 1, segments: int = 24, color := WHITE) -> Mesh {
    segments := max(segments, 3)
    c := renderer.Vec4(color)
    r := f32(radius)
    hh := f32(height) * 0.5
    vertices := make([dynamic]Vertex, context.temp_allocator)
    indices := make([dynamic]u32, context.temp_allocator)
    // Side
    for seg in 0..=segments {
        u := f32(seg) / f32(segments)
        theta := u * 2 * math.PI
        n := [3]f32{math.cos(theta), 0, -math.sin(theta)}
        append(&vertices, Vertex{{n.x * r, -hh, n.z * r}, n, {u, 1}, c, {}})
        append(&vertices, Vertex{{n.x * r, hh, n.z * r}, n, {u, 0}, c, {}})
    }
    for seg in 0..<u32(segments) {
        a := seg * 2
        append(&indices, a, a + 2, a + 1, a + 1, a + 2, a + 3)
    }
    // Caps
    for cap in 0..<2 {
        y := hh if cap == 0 else -hh
        ny: f32 = 1 if cap == 0 else -1
        center := u32(len(vertices))
        append(&vertices, Vertex{{0, y, 0}, {0, ny, 0}, {0.5, 0.5}, c, {}})
        for seg in 0..=segments {
            theta := f32(seg) / f32(segments) * 2 * math.PI
            x, z := math.cos(theta), -math.sin(theta)
            append(&vertices, Vertex{{x * r, y, z * r}, {0, ny, 0}, {x * 0.5 + 0.5, z * 0.5 + 0.5}, c, {}})
        }
        for seg in 0..<u32(segments) {
            if cap == 0 {
                append(&indices, center, center + 1 + seg, center + 2 + seg)
            } else {
                append(&indices, center, center + 2 + seg, center + 1 + seg)
            }
        }
    }
    return mesh_create(vertices[:], indices[:])
}

// ---------------------------------------------------------------------------
// OBJ loading
// ---------------------------------------------------------------------------

// Load a Wavefront OBJ (positions, uvs, normals, optional vertex colours
// written as `v x y z r g b`). Polygons are triangulated; missing normals are
// generated (flat). Materials (.mtl) are ignored - use Obsidon materials.
mesh_load_obj :: proc(obj_data: []u8, color := WHITE) -> Mesh {
    text := string(obj_data)
    positions := make([dynamic][3]f32, context.temp_allocator)
    colors := make([dynamic][4]f32, context.temp_allocator)
    uvs := make([dynamic][2]f32, context.temp_allocator)
    normals := make([dynamic][3]f32, context.temp_allocator)
    vertices := make([dynamic]Vertex, context.temp_allocator)
    indices := make([dynamic]u32, context.temp_allocator)
    lookup := make(map[[3]int]u32, allocator = context.temp_allocator)
    base_color := renderer.Vec4(color)
    missing_normals := false

    parse_f32 :: proc(s: string) -> f32 {
        v, _ := strconv.parse_f32(s)
        return v
    }

    resolve :: proc(index_text: string, count: int) -> int {
        if index_text == "" {
            return -1
        }
        i, ok := strconv.parse_int(index_text)
        if !ok {
            return -1
        }
        if i < 0 {
            return count + i
        }
        return i - 1
    }

    line_iter := text
    for line in strings.split_lines_iterator(&line_iter) {
        l := strings.trim_space(line)
        if len(l) == 0 || l[0] == '#' {
            continue
        }
        fields := strings.fields(l, context.temp_allocator)
        switch fields[0] {
        case "v":
            if len(fields) < 4 {
                continue
            }
            append(&positions, [3]f32{parse_f32(fields[1]), parse_f32(fields[2]), parse_f32(fields[3])})
            if len(fields) >= 7 {
                append(&colors, [4]f32{parse_f32(fields[4]), parse_f32(fields[5]), parse_f32(fields[6]), 1})
            } else {
                append(&colors, [4]f32{1, 1, 1, 1})
            }
        case "vt":
            if len(fields) < 3 {
                continue
            }
            // OBJ uv origin is bottom-left, textures are top-left.
            append(&uvs, [2]f32{parse_f32(fields[1]), 1 - parse_f32(fields[2])})
        case "vn":
            if len(fields) < 4 {
                continue
            }
            append(&normals, [3]f32{parse_f32(fields[1]), parse_f32(fields[2]), parse_f32(fields[3])})
        case "f":
            corners := make([dynamic]u32, context.temp_allocator)
            for corner in fields[1:] {
                parts := strings.split(corner, "/", context.temp_allocator)
                vi := resolve(parts[0], len(positions))
                ti := resolve(parts[1], len(uvs)) if len(parts) > 1 else -1
                ni := resolve(parts[2], len(normals)) if len(parts) > 2 else -1
                if vi < 0 || vi >= len(positions) {
                    continue
                }
                if ni < 0 {
                    missing_normals = true
                }
                key := [3]int{vi, ti, ni}
                index, found := lookup[key]
                if !found {
                    v := Vertex{
                        position = positions[vi],
                        color    = colors[vi] * base_color,
                    }
                    if ti >= 0 && ti < len(uvs) { v.uv = uvs[ti] }
                    if ni >= 0 && ni < len(normals) { v.normal = normals[ni] }
                    index = u32(len(vertices))
                    append(&vertices, v)
                    lookup[key] = index
                }
                append(&corners, index)
            }
            for i in 2..<len(corners) {
                append(&indices, corners[0], corners[i - 1], corners[i])
            }
        }
    }

    if len(vertices) == 0 {
        log.error("mesh_load_obj: no geometry found")
        return mesh_cube()
    }

    if missing_normals {
        // Flat normals: un-share vertices per triangle.
        flat := make([dynamic]Vertex, 0, len(indices), context.temp_allocator)
        for t := 0; t + 2 < len(indices); t += 3 {
            a, b, c := vertices[indices[t]], vertices[indices[t + 1]], vertices[indices[t + 2]]
            n := linalg.normalize(linalg.cross(b.position - a.position, c.position - a.position))
            a.normal, b.normal, c.normal = n, n, n
            append(&flat, a, b, c)
        }
        return mesh_create(flat[:])
    }
    return mesh_create(vertices[:], indices[:])
}
