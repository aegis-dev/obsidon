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

import "core:hash"
import "core:log"
import "core:math"
import "core:strings"

import "vendor:wgpu"

import sh "../../shader"

// ---------------------------------------------------------------------------
// Mesh
// ---------------------------------------------------------------------------

Mesh :: struct {
    vertex_buffer: wgpu.Buffer,
    index_buffer:  wgpu.Buffer,
    vertex_count:  u32,
    index_count:   u32,
    // Bounding sphere in object space
    bounds_center: Vec3,
    bounds_radius: f32,
}

mesh_create :: proc(vertices: []Vertex, indices: []u32) -> Mesh {
    if len(vertices) == 0 {
        log.panic("mesh_create: mesh has no vertices")
    }
    mesh := Mesh{vertex_count = u32(len(vertices)), index_count = u32(len(indices))}

    vertices := vertices
    has_tangents := false
    for v in vertices {
        if v.tangent != {} {
            has_tangents = true
            break
        }
    }
    if !has_tangents {
        vertices = slice_clone_temp(vertices)
        compute_tangents(vertices, indices)
    }

    vb_size := u64(size_of(Vertex) * len(vertices))
    mesh.vertex_buffer = make_buffer(vb_size, {.Vertex, .CopyDst})
    wgpu.QueueWriteBuffer(state.queue, mesh.vertex_buffer, 0, raw_data(vertices), uint(vb_size))

    if len(indices) > 0 {
        ib_size := u64(size_of(u32) * len(indices))
        mesh.index_buffer = make_buffer(ib_size, {.Index, .CopyDst})
        wgpu.QueueWriteBuffer(state.queue, mesh.index_buffer, 0, raw_data(indices), uint(ib_size))
    }

    lo := vertices[0].position
    hi := lo
    for v in vertices {
        lo = {min(lo.x, v.position.x), min(lo.y, v.position.y), min(lo.z, v.position.z)}
        hi = {max(hi.x, v.position.x), max(hi.y, v.position.y), max(hi.z, v.position.z)}
    }
    mesh.bounds_center = (lo + hi) * 0.5
    for v in vertices {
        d := v.position - mesh.bounds_center
        mesh.bounds_radius = max(mesh.bounds_radius, math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z))
    }
    return mesh
}

@(private)
slice_clone_temp :: proc(v: []Vertex) -> []Vertex {
    out := make([]Vertex, len(v), context.temp_allocator)
    copy(out, v)
    return out
}

// Per-vertex tangents from uv derivatives, accumulated over the triangles
// sharing a vertex (glTF / MikkTSpace sign convention, uv origin top-left).
compute_tangents :: proc(vertices: []Vertex, indices: []u32) {
    count := len(indices) if len(indices) > 0 else len(vertices)
    tan := make([]Vec3, len(vertices), context.temp_allocator)
    bit := make([]Vec3, len(vertices), context.temp_allocator)
    index :: proc(indices: []u32, i: int) -> int {
        return int(indices[i]) if len(indices) > 0 else i
    }
    for t := 0; t + 2 < count; t += 3 {
        i0, i1, i2 := index(indices, t), index(indices, t + 1), index(indices, t + 2)
        v0, v1, v2 := vertices[i0], vertices[i1], vertices[i2]
        e1 := v1.position - v0.position
        e2 := v2.position - v0.position
        du1, dv1 := v1.uv.x - v0.uv.x, v1.uv.y - v0.uv.y
        du2, dv2 := v2.uv.x - v0.uv.x, v2.uv.y - v0.uv.y
        det := du1 * dv2 - du2 * dv1
        if abs(det) < 1e-12 {
            continue
        }
        r := 1.0 / det
        t_dir := (e1 * dv2 - e2 * dv1) * r // dP/du
        b_dir := (e2 * du1 - e1 * du2) * r // dP/dv
        for i in ([3]int{i0, i1, i2}) {
            tan[i] += t_dir
            bit[i] += b_dir
        }
    }
    for &v, i in vertices {
        n := v.normal
        t := tan[i] - n * (n.x * tan[i].x + n.y * tan[i].y + n.z * tan[i].z)
        l := math.sqrt(t.x * t.x + t.y * t.y + t.z * t.z)
        if l < 1e-8 {
            // No usable uvs: any direction perpendicular to the normal.
            helper := Vec3{0, 1, 0} if abs(n.y) < 0.99 else Vec3{1, 0, 0}
            t = Vec3{helper.y * n.z - helper.z * n.y, helper.z * n.x - helper.x * n.z, helper.x * n.y - helper.y * n.x}
            l = max(math.sqrt(t.x * t.x + t.y * t.y + t.z * t.z), 1e-8)
        }
        t /= l
        // Bitangent points "up" in the image, which is -v with a top-left uv origin.
        c := Vec3{n.y * t.z - n.z * t.y, n.z * t.x - n.x * t.z, n.x * t.y - n.y * t.x}
        up := -bit[i]
        w: f32 = -1 if c.x * up.x + c.y * up.y + c.z * up.z < 0 else 1
        v.tangent = {t.x, t.y, t.z, w}
    }
}

mesh_destroy :: proc(mesh: ^Mesh) {
    if mesh.vertex_buffer != nil {
        wgpu.BufferDestroy(mesh.vertex_buffer)
        wgpu.BufferRelease(mesh.vertex_buffer)
    }
    if mesh.index_buffer != nil {
        wgpu.BufferDestroy(mesh.index_buffer)
        wgpu.BufferRelease(mesh.index_buffer)
    }
    mesh^ = {}
}

// ---------------------------------------------------------------------------
// Texture
// ---------------------------------------------------------------------------

Texture :: struct {
    texture:    wgpu.Texture,
    view:       wgpu.TextureView,
    width:      u32,
    height:     u32,
    depth:      u32, // > 1 for 3D textures
    // Lazily created bind group used by the 2D overlay.
    overlay_bg: wgpu.BindGroup,
}

// Create a texture from tightly packed RGBA8 pixels (top row first).
// `srgb` should be true for colour data and false for data like normal maps.
texture_create :: proc(pixels: []u8, width: u32, height: u32, srgb := true, mipmaps := true) -> Texture {
    if len(pixels) < int(width * height * 4) {
        log.panic("texture_create: not enough pixel data")
    }
    mip_count: u32 = 1
    if mipmaps {
        size := max(width, height)
        for size > 1 {
            size /= 2
            mip_count += 1
        }
    }

    texture := wgpu.DeviceCreateTexture(state.device, &wgpu.TextureDescriptor{
        size          = {width = width, height = height, depthOrArrayLayers = 1},
        format        = .RGBA8UnormSrgb if srgb else .RGBA8Unorm,
        usage         = {.TextureBinding, .CopyDst},
        dimension     = ._2D,
        mipLevelCount = mip_count,
        sampleCount   = 1,
    })

    level_pixels := pixels[:width * height * 4]
    w, h := width, height
    scratch: [dynamic]u8
    defer delete(scratch)
    for level in 0..<mip_count {
        wgpu.QueueWriteTexture(
            state.queue,
            &wgpu.TexelCopyTextureInfo{texture = texture, mipLevel = level, aspect = .All},
            raw_data(level_pixels),
            uint(len(level_pixels)),
            &wgpu.TexelCopyBufferLayout{bytesPerRow = w * 4, rowsPerImage = h},
            &wgpu.Extent3D{width = w, height = h, depthOrArrayLayers = 1},
        )
        if level + 1 < mip_count {
            nw, nh := max(w / 2, 1), max(h / 2, 1)
            next := make([]u8, nw * nh * 4, context.temp_allocator)
            downsample(level_pixels, w, h, next, nw, nh, srgb)
            level_pixels = next
            w, h = nw, nh
        }
    }

    view := wgpu.TextureCreateView(texture, nil)
    return Texture{texture = texture, view = view, width = width, height = height}
}

// Create a 3D texture from tightly packed RGBA8 texels (x fastest, then y,
// then z). Linear data (noise, lookup tables), optional box filtered mips.
texture_create_3d :: proc(texels: []u8, width, height, depth: u32, mipmaps := true) -> Texture {
    if len(texels) < int(width * height * depth * 4) {
        log.panic("texture_create_3d: not enough texel data")
    }
    mip_count: u32 = 1
    if mipmaps {
        size := max(width, height, depth)
        for size > 1 {
            size /= 2
            mip_count += 1
        }
    }
    texture := wgpu.DeviceCreateTexture(state.device, &wgpu.TextureDescriptor{
        size          = {width = width, height = height, depthOrArrayLayers = depth},
        format        = .RGBA8Unorm,
        usage         = {.TextureBinding, .CopyDst},
        dimension     = ._3D,
        mipLevelCount = mip_count,
        sampleCount   = 1,
    })
    level := texels[:width * height * depth * 4]
    w, h, d := width, height, depth
    for mip in 0..<mip_count {
        wgpu.QueueWriteTexture(
            state.queue,
            &wgpu.TexelCopyTextureInfo{texture = texture, mipLevel = mip, aspect = .All},
            raw_data(level),
            uint(len(level)),
            &wgpu.TexelCopyBufferLayout{bytesPerRow = w * 4, rowsPerImage = h},
            &wgpu.Extent3D{width = w, height = h, depthOrArrayLayers = d},
        )
        if mip + 1 < mip_count {
            nw, nh, nd := max(w / 2, 1), max(h / 2, 1), max(d / 2, 1)
            next := make([]u8, nw * nh * nd * 4, context.temp_allocator)
            for z in 0..<nd {
                for y in 0..<nh {
                    for x in 0..<nw {
                        for c in 0..<u32(4) {
                            sum: u32 = 0
                            for k in 0..<u32(8) {
                                sx := min(x * 2 + (k & 1), w - 1)
                                sy := min(y * 2 + ((k >> 1) & 1), h - 1)
                                sz := min(z * 2 + ((k >> 2) & 1), d - 1)
                                sum += u32(level[((sz * h + sy) * w + sx) * 4 + c])
                            }
                            next[((z * nh + y) * nw + x) * 4 + c] = u8((sum + 4) / 8)
                        }
                    }
                }
            }
            level = next
            w, h, d = nw, nh, nd
        }
    }
    view := wgpu.TextureCreateView(texture, &wgpu.TextureViewDescriptor{
        format = .RGBA8Unorm, dimension = ._3D, baseMipLevel = 0, mipLevelCount = mip_count,
        baseArrayLayer = 0, arrayLayerCount = 1, aspect = .All,
    })
    return Texture{texture = texture, view = view, width = width, height = height, depth = depth}
}

texture_create_solid :: proc(color: [4]u8, srgb: bool) -> Texture {
    pixels := color
    return texture_create(pixels[:], 1, 1, srgb, false)
}

texture_destroy :: proc(texture: ^Texture) {
    release_bind_group(&texture.overlay_bg)
    if texture.view != nil {
        wgpu.TextureViewRelease(texture.view)
    }
    if texture.texture != nil {
        wgpu.TextureDestroy(texture.texture)
        wgpu.TextureRelease(texture.texture)
    }
    texture^ = {}
}

// Box filter that averages in linear space for sRGB textures.
@(private)
downsample :: proc(src: []u8, sw, sh_: u32, dst: []u8, dw, dh: u32, srgb: bool) {
    @(static) to_linear: [256]f32
    @(static) table_ready: bool
    if !table_ready {
        for i in 0..<256 {
            v := f32(i) / 255.0
            to_linear[i] = v / 12.92 if v <= 0.04045 else math.pow((v + 0.055) / 1.055, 2.4)
        }
        table_ready = true
    }
    to_srgb :: proc(v: f32) -> u8 {
        c := v * 12.92 if v <= 0.0031308 else 1.055 * math.pow(v, 1.0 / 2.4) - 0.055
        return u8(clamp(c * 255.0 + 0.5, 0, 255))
    }

    for y in 0..<dh {
        for x in 0..<dw {
            sum: [4]f32
            for oy in u32(0)..<2 {
                for ox in u32(0)..<2 {
                    sx := min(x * 2 + ox, sw - 1)
                    sy := min(y * 2 + oy, sh_ - 1)
                    i := (sy * sw + sx) * 4
                    for c in 0..<3 {
                        sum[c] += to_linear[src[i + u32(c)]] if srgb else f32(src[i + u32(c)]) / 255.0
                    }
                    sum[3] += f32(src[i + 3]) / 255.0
                }
            }
            o := (y * dw + x) * 4
            for c in 0..<3 {
                v := sum[c] * 0.25
                dst[o + u32(c)] = to_srgb(v) if srgb else u8(clamp(v * 255.0 + 0.5, 0, 255))
            }
            dst[o + 3] = u8(clamp(sum[3] * 0.25 * 255.0 + 0.5, 0, 255))
        }
    }
}

// ---------------------------------------------------------------------------
// Shader
// ---------------------------------------------------------------------------

Pipeline_Kind :: enum {
    Main,
    Prepass,
    Shadow,
    Post_HDR,
    Post_LDR,
}

Shader :: struct {
    name:            string,
    mode:            sh.Mode,
    state:           sh.Pipeline_State,
    params:          []sh.Param_Info,
    textures:        []sh.Texture_Info,
    shadow_has_fragment: bool,

    main_module:     wgpu.ShaderModule,
    prepass_module:  wgpu.ShaderModule,
    shadow_module:   wgpu.ShaderModule,
    material_layout: wgpu.BindGroupLayout,
    pipeline_layout: wgpu.PipelineLayout,
    pipelines:       [Pipeline_Kind]wgpu.RenderPipeline,
    // Bumped by shader_rebuild; materials notice and remap their values.
    generation:      u32,
}

// Takes ownership of the description's memory.
shader_create :: proc(desc: sh.Shader_Desc) -> ^Shader {
    s := new(Shader)
    shader_init(s, desc)
    return s
}

// Replace a shader's program in place (hot reload, runtime variants).
// Materials using it keep working: their values and textures are matched to
// the new parameters by name the next time they are drawn.
shader_rebuild :: proc(s: ^Shader, desc: sh.Shader_Desc) {
    generation := s.generation
    shader_release(s)
    shader_init(s, desc)
    s.generation = generation + 1
}

@(private)
shader_init :: proc(s: ^Shader, desc: sh.Shader_Desc) {
    s^ = {}
    s.name = desc.name
    s.mode = desc.mode
    s.state = desc.state
    s.params = desc.params
    s.textures = desc.textures
    s.shadow_has_fragment = desc.shadow_has_fragment

    s.main_module = create_module(desc.main_source, desc.name)
    if desc.mode == .Surface {
        s.prepass_module = create_module(desc.prepass_source, strings.concatenate({desc.name, " (prepass)"}, context.temp_allocator))
        s.shadow_module = create_module(desc.shadow_source, strings.concatenate({desc.name, " (shadow)"}, context.temp_allocator))
    }
    delete(desc.main_source)
    delete(desc.prepass_source)
    delete(desc.shadow_source)

    entries := make([dynamic]wgpu.BindGroupLayoutEntry, context.temp_allocator)
    append(&entries, entry_uniform(0))
    append(&entries, entry_sampler(1, .Filtering))
    for t, i in s.textures {
        append(&entries, entry_texture(u32(i + 2), .Float, dimension = ._3D if t.volume else ._2D))
    }
    s.material_layout = make_layout(entries[:])

    group0 := state.frame_layout if desc.mode == .Surface else state.fullscreen_layout
    s.pipeline_layout = make_pipeline_layout({group0, s.material_layout})
}

shader_destroy :: proc(s: ^Shader) {
    if s == nil {
        return
    }
    shader_release(s)
    free(s)
}

@(private)
shader_release :: proc(s: ^Shader) {
    for p in s.pipelines {
        if p != nil {
            wgpu.RenderPipelineRelease(p)
        }
    }
    if s.main_module != nil { wgpu.ShaderModuleRelease(s.main_module) }
    if s.prepass_module != nil { wgpu.ShaderModuleRelease(s.prepass_module) }
    if s.shadow_module != nil { wgpu.ShaderModuleRelease(s.shadow_module) }
    wgpu.PipelineLayoutRelease(s.pipeline_layout)
    wgpu.BindGroupLayoutRelease(s.material_layout)
    for p in s.params {
        delete(p.name)
    }
    for t in s.textures {
        delete(t.name)
    }
    delete(s.params)
    delete(s.textures)
    delete(s.name)
}

@(private)
get_pipeline :: proc(s: ^Shader, kind: Pipeline_Kind) -> wgpu.RenderPipeline {
    if s.pipelines[kind] != nil {
        return s.pipelines[kind]
    }

    vertex_attributes := [5]wgpu.VertexAttribute{
        {format = .Float32x3, offset = u64(offset_of(Vertex, position)), shaderLocation = 0},
        {format = .Float32x3, offset = u64(offset_of(Vertex, normal)), shaderLocation = 1},
        {format = .Float32x2, offset = u64(offset_of(Vertex, uv)), shaderLocation = 2},
        {format = .Float32x4, offset = u64(offset_of(Vertex, color)), shaderLocation = 3},
        {format = .Float32x4, offset = u64(offset_of(Vertex, tangent)), shaderLocation = 4},
    }
    vertex_layout := wgpu.VertexBufferLayout{
        arrayStride    = size_of(Vertex),
        stepMode       = .Vertex,
        attributeCount = len(vertex_attributes),
        attributes     = &vertex_attributes[0],
    }

    cull: wgpu.CullMode
    switch s.state.cull {
    case .Back: cull = .Back
    case .Front: cull = .Front
    case .None: cull = .None
    }

    blend: ^wgpu.BlendState
    alpha_blend := wgpu.BlendState{
        color = {srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha, operation = .Add},
        alpha = {srcFactor = .One, dstFactor = .OneMinusSrcAlpha, operation = .Add},
    }
    additive_blend := wgpu.BlendState{
        color = {srcFactor = .SrcAlpha, dstFactor = .One, operation = .Add},
        alpha = {srcFactor = .One, dstFactor = .One, operation = .Add},
    }
    switch s.state.blend {
    case .Opaque:
    case .Alpha: blend = &alpha_blend
    case .Additive: blend = &additive_blend
    }

    desc := wgpu.RenderPipelineDescriptor{
        label       = s.name,
        layout      = s.pipeline_layout,
        primitive   = {topology = .TriangleList, frontFace = .CCW, cullMode = cull},
        multisample = {count = 1, mask = 0xFFFFFFFF},
    }
    depth_state: wgpu.DepthStencilState
    target: wgpu.ColorTargetState
    fragment: wgpu.FragmentState

    switch kind {
    case .Main, .Prepass:
        module := s.main_module if kind == .Main else s.prepass_module
        desc.vertex = {module = module, entryPoint = "vs_main", bufferCount = 1, buffers = &vertex_layout}
        depth_state = {
            format            = DEPTH_FORMAT,
            depthWriteEnabled = .True if s.state.depth_write || kind == .Prepass else .False,
            depthCompare      = .GreaterEqual if s.state.depth_test else .Always,
        }
        desc.depthStencil = &depth_state
        if kind == .Main {
            target = {format = HDR_FORMAT, blend = blend, writeMask = wgpu.ColorWriteMaskFlags_All}
        } else {
            target = {format = NORMAL_FORMAT, writeMask = wgpu.ColorWriteMaskFlags_All}
        }
        fragment = {module = module, entryPoint = "fs_main", targetCount = 1, targets = &target}
        desc.fragment = &fragment
    case .Shadow:
        desc.vertex = {module = s.shadow_module, entryPoint = "vs_main", bufferCount = 1, buffers = &vertex_layout}
        depth_state = {
            format              = DEPTH_FORMAT,
            depthWriteEnabled   = .True,
            depthCompare        = .LessEqual,
            depthBiasSlopeScale = 1.5,
        }
        desc.depthStencil = &depth_state
        if s.shadow_has_fragment {
            fragment = {module = s.shadow_module, entryPoint = "fs_main", targetCount = 0}
            desc.fragment = &fragment
        }
    case .Post_HDR, .Post_LDR:
        desc.vertex = {module = s.main_module, entryPoint = "vs_main"}
        target = {format = HDR_FORMAT if kind == .Post_HDR else LDR_FORMAT, writeMask = wgpu.ColorWriteMaskFlags_All}
        fragment = {module = s.main_module, entryPoint = "fs_main", targetCount = 1, targets = &target}
        desc.fragment = &fragment
        desc.primitive.cullMode = .None
    }

    push_error_scope()
    pipeline := wgpu.DeviceCreateRenderPipeline(state.device, &desc)
    if err := pop_error_scope(); err != "" {
        log.panicf("Failed to create %v pipeline for shader '%s': %s", kind, s.name, err)
    }
    s.pipelines[kind] = pipeline
    return pipeline
}

// ---------------------------------------------------------------------------
// Material
// ---------------------------------------------------------------------------

Material :: struct {
    shader:         ^Shader,
    values:         [sh.MAX_PARAMS]Vec4,
    textures:       [sh.MAX_TEXTURES]^Texture,
    uniform_buffer: wgpu.Buffer,
    bind_group:     wgpu.BindGroup,
    values_dirty:   bool,
    bind_dirty:     bool,
    generation:     u32,
    // For remapping after shader_rebuild.
    shader_generation: u32,
    param_hashes:      [sh.MAX_PARAMS]u64,
    texture_hashes:    [sh.MAX_TEXTURES]u64,
}

material_create :: proc(shader: ^Shader) -> Material {
    if shader == nil {
        log.panic("material_create: shader is nil")
    }
    m := Material{shader = shader, values_dirty = true, bind_dirty = true, shader_generation = shader.generation}
    for p, i in shader.params {
        m.values[i] = param_default(p)
        m.param_hashes[i] = name_hash(p.name)
    }
    for t, i in shader.textures {
        m.texture_hashes[i] = name_hash(t.name)
    }
    m.uniform_buffer = make_buffer(size_of(Vec4) * sh.MAX_PARAMS, {.Uniform, .CopyDst})
    return m
}

material_destroy :: proc(m: ^Material) {
    release_bind_group(&m.bind_group)
    if m.uniform_buffer != nil {
        wgpu.BufferDestroy(m.uniform_buffer)
        wgpu.BufferRelease(m.uniform_buffer)
    }
    m^ = {}
}

material_find_param :: proc(m: ^Material, name: string) -> (index: int, info: sh.Param_Info, ok: bool) {
    for p, i in m.shader.params {
        if p.name == name {
            return i, p, true
        }
    }
    return -1, {}, false
}

material_find_texture :: proc(m: ^Material, name: string) -> (index: int, ok: bool) {
    for t, i in m.shader.textures {
        if t.name == name {
            return i, true
        }
    }
    return -1, false
}

material_set_value :: proc(m: ^Material, index: int, value: Vec4) {
    m.values[index] = value
    m.values_dirty = true
}

material_set_texture :: proc(m: ^Material, index: int, texture: ^Texture) {
    m.textures[index] = texture
    m.bind_dirty = true
}

@(private)
material_prepare :: proc(m: ^Material) {
    if m.shader_generation != m.shader.generation {
        material_remap(m)
    }
    if m.values_dirty {
        wgpu.QueueWriteBuffer(state.queue, m.uniform_buffer, 0, &m.values, size_of(m.values))
        m.values_dirty = false
    }
    if m.bind_dirty || m.bind_group == nil || m.generation != state.material_generation {
        release_bind_group(&m.bind_group)
        entries := make([dynamic]wgpu.BindGroupEntry, context.temp_allocator)
        append(&entries, bind_buffer(0, m.uniform_buffer, size_of(Vec4) * sh.MAX_PARAMS))
        append(&entries, bind_sampler(1, state.sampler_material))
        for info, i in m.shader.textures {
            view := m.textures[i].view if m.textures[i] != nil else default_texture_view(info.default_value, info.volume)
            append(&entries, bind_texture(u32(i + 2), view))
        }
        m.bind_group = make_bind_group(m.shader.material_layout, entries[:])
        m.bind_dirty = false
        m.generation = state.material_generation
    }
}

// The shader was rebuilt: keep values / textures whose names still exist.
@(private)
material_remap :: proc(m: ^Material) {
    old_values := m.values
    old_textures := m.textures
    old_param_hashes := m.param_hashes
    old_texture_hashes := m.texture_hashes
    m.values = {}
    m.textures = {}
    m.param_hashes = {}
    m.texture_hashes = {}
    for p, i in m.shader.params {
        h := name_hash(p.name)
        m.param_hashes[i] = h
        m.values[i] = param_default(p)
        for oh, j in old_param_hashes {
            if oh == h && oh != 0 {
                m.values[i] = old_values[j]
                break
            }
        }
    }
    for t, i in m.shader.textures {
        h := name_hash(t.name)
        m.texture_hashes[i] = h
        for oh, j in old_texture_hashes {
            if oh == h && oh != 0 {
                m.textures[i] = old_textures[j]
                break
            }
        }
    }
    m.shader_generation = m.shader.generation
    m.values_dirty = true
    m.bind_dirty = true
}

@(private)
param_default :: proc(p: sh.Param_Info) -> Vec4 {
    return srgb_to_linear(p.default_value) if p.is_color else p.default_value
}

@(private)
name_hash :: proc(name: string) -> u64 {
    return hash.fnv64a(transmute([]u8)name)
}

@(private)
default_texture_view :: proc(d: sh.Default_Texture, volume := false) -> wgpu.TextureView {
    if volume {
        return state.white_volume.view
    }
    switch d {
    case .White: return state.white_texture.view
    case .Black: return state.black_texture.view
    case .Flat_Normal: return state.flat_normal_texture.view
    }
    return state.white_texture.view
}

srgb_to_linear :: proc(c: Vec4) -> Vec4 {
    convert :: proc(v: f32) -> f32 {
        if v <= 0.04045 {
            return v / 12.92
        }
        return math.pow((v + 0.055) / 1.055, 2.4)
    }
    return {convert(c.r), convert(c.g), convert(c.b), c.a}
}

// ---------------------------------------------------------------------------
// Post effects
// ---------------------------------------------------------------------------

Post_Stage :: enum {
    // Before tonemapping: linear HDR colour (bloom, exposure tricks, ...)
    Before_Tonemap,
    // After tonemapping: display colour 0..1 (dithering, CRT, colour grading, ...)
    After_Tonemap,
}

Post_Effect :: struct {
    material: ^Material,
    stage:    Post_Stage,
    enabled:  bool,
    half_resolution: bool,
}

post_effect_add :: proc(material: ^Material, stage: Post_Stage, half_resolution := false) {
    if material.shader.mode != .Post {
        log.panic("post_effect_add: the material's shader is not a post-processing shader (use shader.begin(.Post))")
    }
    if half_resolution && stage != .Before_Tonemap {
        log.panic("post_effect_add: half resolution effects are only supported before tonemapping")
    }
    append(&state.post_effects, Post_Effect{material, stage, true, half_resolution})
}

post_effect_remove :: proc(material: ^Material) {
    for e, i in state.post_effects {
        if e.material == material {
            ordered_remove(&state.post_effects, i)
            return
        }
    }
}

post_effect_set_enabled :: proc(material: ^Material, enabled: bool) {
    for &e in state.post_effects {
        if e.material == material {
            e.enabled = enabled
        }
    }
}
