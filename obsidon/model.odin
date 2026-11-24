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

package obsidon

import "core:c"
import "core:encoding/base64"
import "core:log"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "vendor:cgltf"
import stbi "vendor:stb/image"

import "internal/renderer"

// A loaded 3D model: meshes, materials and textures, with the node hierarchy
// baked into one local matrix per part.
Model :: struct {
    parts:     [dynamic]Model_Part,
    meshes:    [dynamic]Mesh,
    materials: [dynamic]Material,
    textures:  [dynamic]Texture,
    // Axis aligned bounds of the whole model in model space.
    bounds_min: Vec3,
    bounds_max: Vec3,
}

Model_Part :: struct {
    mesh:     int, // index into Model.meshes
    material: int, // index into Model.materials
    local:    Mat4,
}

// Load a glTF 2.0 model from memory: a .glb, or a .gltf whose buffers and
// images are embedded (data URIs). Use model_load_gltf_file for models with
// external files.
//
// glTF PBR materials are mapped onto the standard shader (base colour, normal
// and emissive maps, roughness approximated as specular sharpness). Pass
// `shader` to use your own shader for every material instead: its "albedo",
// "normal", "emission_map" textures and "color" / "emission" params are filled
// when present.
model_load_gltf :: proc(data: []u8, shader: Shader = nil) -> (model: Model, ok: bool) {
    options := cgltf.options{}
    gltf, res := cgltf.parse(options, raw_data(data), uint(len(data)))
    if res != .success {
        log.errorf("model_load_gltf: failed to parse (%v)", res)
        return {}, false
    }
    defer cgltf.free(gltf)
    if res = cgltf.load_buffers(options, gltf, ""); res != .success {
        log.errorf("model_load_gltf: failed to load buffers (%v) - use model_load_gltf_file for external files", res)
        return {}, false
    }
    return build_model(gltf, "", shader)
}

model_load_gltf_file :: proc(path: string, shader: Shader = nil) -> (model: Model, ok: bool) {
    options := cgltf.options{}
    cpath := strings.clone_to_cstring(path, context.temp_allocator)
    gltf, res := cgltf.parse_file(options, cpath)
    if res != .success {
        log.errorf("model_load_gltf_file: failed to parse %s (%v)", path, res)
        return {}, false
    }
    defer cgltf.free(gltf)
    if res = cgltf.load_buffers(options, gltf, cpath); res != .success {
        log.errorf("model_load_gltf_file: failed to load buffers of %s (%v)", path, res)
        return {}, false
    }
    return build_model(gltf, filepath.dir(path), shader)
}

model_draw :: proc(model: ^Model, transform: Transform, tint := WHITE) {
    model_draw_matrix(model, transform_matrix(transform), tint)
}

model_draw_matrix :: proc(model: ^Model, world: Mat4, tint := WHITE) {
    linear_tint := renderer.srgb_to_linear(tint)
    for &part in model.parts {
        renderer.draw_mesh(&model.meshes[part.mesh], &model.materials[part.material], world * part.local, linear_tint)
    }
}

// Draw the model with one material for every part (e.g. a hologram effect).
model_draw_with_material :: proc(model: ^Model, material: ^Material, transform: Transform, tint := WHITE) {
    world := transform_matrix(transform)
    linear_tint := renderer.srgb_to_linear(tint)
    for &part in model.parts {
        renderer.draw_mesh(&model.meshes[part.mesh], material, world * part.local, linear_tint)
    }
}

model_destroy :: proc(model: ^Model) {
    for &m in model.meshes {
        mesh_destroy(&m)
    }
    for &m in model.materials {
        material_destroy(&m)
    }
    for &t in model.textures {
        texture_destroy(&t)
    }
    delete(model.parts)
    delete(model.meshes)
    delete(model.materials)
    delete(model.textures)
    model^ = {}
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

@(private = "file")
Builder :: struct {
    gltf:      ^cgltf.data,
    dir:       string,
    shader:    Shader,
    model:     ^Model,
    meshes:    map[^cgltf.primitive]int,
    materials: map[^cgltf.material]int,
    textures:  map[[2]int]int, // (image index, srgb) -> texture index
    // Textures are referenced by pointer from materials, so they must not move:
    // they're collected first and appended to the model before materials bind them.
    pending:   [dynamic]Texture,
}

@(private = "file")
build_model :: proc(gltf: ^cgltf.data, dir: string, shader: Shader) -> (model: Model, ok: bool) {
    b := Builder{gltf = gltf, dir = dir, shader = shader, model = &model}
    b.meshes = make(map[^cgltf.primitive]int, allocator = context.temp_allocator)
    b.materials = make(map[^cgltf.material]int, allocator = context.temp_allocator)
    b.textures = make(map[[2]int]int, allocator = context.temp_allocator)

    // Textures first (materials keep pointers into model.textures).
    for &gm in gltf.materials {
        pbr := gm.pbr_metallic_roughness
        texture_index(&b, pbr.base_color_texture.texture, true)
        texture_index(&b, gm.normal_texture.texture, false)
        texture_index(&b, gm.emissive_texture.texture, true)
    }
    reserve(&model.textures, len(b.pending))
    for t in b.pending {
        append(&model.textures, t)
    }
    delete(b.pending)

    model.bounds_min = {math.F64_MAX, math.F64_MAX, math.F64_MAX}
    model.bounds_max = -model.bounds_min

    visit :: proc(b: ^Builder, node: ^cgltf.node) {
        if node.mesh != nil {
            m: [16]f32
            cgltf.node_transform_world(node, &m[0])
            local32 := transmute(matrix[4, 4]f32)m
            local: Mat4
            for col in 0..<4 {
                for row in 0..<4 {
                    local[row, col] = f64(local32[row, col])
                }
            }
            for &prim in node.mesh.primitives {
                mesh, ok := primitive_mesh(b, &prim, local)
                if !ok {
                    continue
                }
                append(&b.model.parts, Model_Part{mesh = mesh, material = material_index(b, prim.material), local = local})
            }
        }
        for child in node.children {
            visit(b, child)
        }
    }
    if gltf.scene != nil {
        for n in gltf.scene.nodes {
            visit(&b, n)
        }
    } else {
        for &n in gltf.nodes {
            if n.parent == nil {
                visit(&b, &n)
            }
        }
    }

    if len(model.parts) == 0 {
        log.error("model_load_gltf: the file contains no triangle meshes")
        model_destroy(&model)
        return {}, false
    }
    return model, true
}

@(private = "file")
primitive_mesh :: proc(b: ^Builder, prim: ^cgltf.primitive, local: Mat4) -> (int, bool) {
    if index, found := b.meshes[prim]; found {
        update_bounds(b, index, local)
        return index, true
    }
    if prim.type != .triangles {
        log.warnf("model_load_gltf: skipping a %v primitive (only triangles are supported)", prim.type)
        return -1, false
    }

    positions, normals, uvs, colors, tangents: ^cgltf.accessor
    for attr in prim.attributes {
        switch attr.type {
        case .position: positions = attr.data
        case .normal: normals = attr.data
        case .tangent: tangents = attr.data
        case .texcoord: if attr.index == 0 { uvs = attr.data }
        case .color: if attr.index == 0 { colors = attr.data }
        case .invalid, .joints, .weights, .custom:
        }
    }
    if positions == nil {
        return -1, false
    }

    count := int(positions.count)
    vertices := make([]Vertex, count, context.temp_allocator)
    for i in 0..<count {
        v := &vertices[i]
        v.color = {1, 1, 1, 1}
        _ = cgltf.accessor_read_float(positions, uint(i), &v.position[0], 3)
        if normals != nil { _ = cgltf.accessor_read_float(normals, uint(i), &v.normal[0], 3) }
        if uvs != nil { _ = cgltf.accessor_read_float(uvs, uint(i), &v.uv[0], 2) }
        if tangents != nil { _ = cgltf.accessor_read_float(tangents, uint(i), &v.tangent[0], 4) }
        if colors != nil {
            n: uint = 4 if colors.type == .vec4 else 3
            _ = cgltf.accessor_read_float(colors, uint(i), &v.color[0], n)
        }
    }

    indices: []u32
    if prim.indices != nil {
        indices = make([]u32, prim.indices.count, context.temp_allocator)
        for i in 0..<int(prim.indices.count) {
            indices[i] = u32(cgltf.accessor_read_index(prim.indices, uint(i)))
        }
    }

    if normals == nil {
        // Flat normals: one vertex per triangle corner.
        flat := make([dynamic]Vertex, context.temp_allocator)
        n := len(indices) if len(indices) > 0 else count
        for t := 0; t + 2 < n; t += 3 {
            idx := [3]int{t, t + 1, t + 2}
            if len(indices) > 0 {
                idx = {int(indices[t]), int(indices[t + 1]), int(indices[t + 2])}
            }
            a, bb, cc := vertices[idx[0]], vertices[idx[1]], vertices[idx[2]]
            e1 := bb.position - a.position
            e2 := cc.position - a.position
            nn := [3]f32{e1.y * e2.z - e1.z * e2.y, e1.z * e2.x - e1.x * e2.z, e1.x * e2.y - e1.y * e2.x}
            l := math.sqrt(nn.x * nn.x + nn.y * nn.y + nn.z * nn.z)
            if l > 0 { nn /= l }
            a.normal, bb.normal, cc.normal = nn, nn, nn
            append(&flat, a, bb, cc)
        }
        vertices = flat[:]
        indices = nil
    }

    append(&b.model.meshes, mesh_create(vertices, indices))
    index := len(b.model.meshes) - 1
    b.meshes[prim] = index

    update_bounds(b, index, local)
    return index, true
}

@(private = "file")
update_bounds :: proc(b: ^Builder, mesh_index: int, local: Mat4) {
    mesh := b.model.meshes[mesh_index]
    c := mesh.bounds_center
    center := local * [4]f64{f64(c.x), f64(c.y), f64(c.z), 1}
    scale := max(vec3_length(local[0].xyz), vec3_length(local[1].xyz), vec3_length(local[2].xyz))
    r := f64(mesh.bounds_radius) * scale
    for i in 0..<3 {
        b.model.bounds_min[i] = min(b.model.bounds_min[i], center[i] - r)
        b.model.bounds_max[i] = max(b.model.bounds_max[i], center[i] + r)
    }
}

@(private = "file")
texture_index :: proc(b: ^Builder, tex: ^cgltf.texture, srgb: bool) -> int {
    if tex == nil || tex.image_ == nil {
        return -1
    }
    image_index := int((uintptr(tex.image_) - uintptr(&b.gltf.images[0])) / size_of(cgltf.image))
    key := [2]int{image_index, 1 if srgb else 0}
    if index, found := b.textures[key]; found {
        return index
    }

    bytes: []u8
    img := tex.image_
    if img.buffer_view != nil {
        data := cgltf.buffer_view_data(img.buffer_view)
        bytes = data[:img.buffer_view.size]
    } else if img.uri != nil {
        uri := string(img.uri)
        if strings.has_prefix(uri, "data:") {
            comma := strings.index_byte(uri, ',')
            if comma >= 0 {
                decoded, err := base64.decode(uri[comma + 1:], allocator = context.temp_allocator)
                if err == nil {
                    bytes = decoded
                }
            }
        } else if b.dir != "" {
            path, _ := filepath.join({b.dir, uri}, context.temp_allocator)
            data, err := os.read_entire_file(path, context.temp_allocator)
            if err == nil {
                bytes = data
            }
        }
    }
    if len(bytes) == 0 {
        log.warnf("model_load_gltf: could not read image %d", image_index)
        return -1
    }

    w, h, channels: c.int
    pixels := stbi.load_from_memory(raw_data(bytes), c.int(len(bytes)), &w, &h, &channels, 4)
    if pixels == nil {
        log.warnf("model_load_gltf: could not decode image %d", image_index)
        return -1
    }
    defer stbi.image_free(pixels)

    append(&b.pending, renderer.texture_create(pixels[:w * h * 4], u32(w), u32(h), srgb))
    index := len(b.pending) - 1
    b.textures[key] = index
    return index
}

@(private = "file")
material_index :: proc(b: ^Builder, gm: ^cgltf.material) -> int {
    if index, found := b.materials[gm]; found {
        return index
    }

    options := Standard_Shader_Options{}
    if gm != nil {
        options.alpha_clip = gm.alpha_mode == .mask
        options.transparent = gm.alpha_mode == .blend
        options.double_sided = bool(gm.double_sided)
    }
    shader := b.shader if b.shader != nil else cached_standard_shader(options)
    material := material_create(shader)

    if gm != nil {
        pbr := gm.pbr_metallic_roughness
        color := [4]f32{1, 1, 1, 1}
        roughness: f32 = 1
        if gm.has_pbr_metallic_roughness {
            color = pbr.base_color_factor
            roughness = pbr.roughness_factor
        }
        // glTF factors are linear already: set them raw.
        try_set_vec4(&material, "color", color)
        r := clamp(roughness, 0.02, 1)
        try_set_float(&material, "shininess", clamp(2 / (r * r * r * r) - 2, 4, 512))
        try_set_float(&material, "specular", 0.05 + 0.9 * (1 - r) * (1 - r))

        emissive := gm.emissive_factor
        strength: f32 = 1
        if gm.has_emissive_strength {
            strength = gm.emissive_strength.emissive_strength
        }
        try_set_vec4(&material, "emission", {emissive.x, emissive.y, emissive.z, 1})
        try_set_float(&material, "emission_strength", strength)

        try_set_texture(b, &material, "albedo", texture_index(b, pbr.base_color_texture.texture, true))
        try_set_texture(b, &material, "normal", texture_index(b, gm.normal_texture.texture, false))
        if gm.normal_texture.texture != nil {
            try_set_float(&material, "normal_strength", gm.normal_texture.scale if gm.normal_texture.scale != 0 else 1)
        }
        try_set_texture(b, &material, "emission_map", texture_index(b, gm.emissive_texture.texture, true))
    }

    append(&b.model.materials, material)
    index := len(b.model.materials) - 1
    b.materials[gm] = index
    return index
}

@(private = "file")
try_set_vec4 :: proc(m: ^Material, name: string, v: [4]f32) {
    if index, _, ok := renderer.material_find_param(m, name); ok {
        renderer.material_set_value(m, index, v)
    }
}

@(private = "file")
try_set_float :: proc(m: ^Material, name: string, v: f32) {
    if index, _, ok := renderer.material_find_param(m, name); ok {
        renderer.material_set_value(m, index, {v, 0, 0, 0})
    }
}

@(private = "file")
try_set_texture :: proc(b: ^Builder, m: ^Material, name: string, texture: int) {
    if texture < 0 {
        return
    }
    if index, ok := renderer.material_find_texture(m, name); ok {
        renderer.material_set_texture(m, index, &b.model.textures[texture])
    }
}
