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

import "internal/renderer"
import sh "shader"

// A shader plus values for its parameters and textures.
// Many materials can share one shader.
Material :: renderer.Material

material_create :: proc(shader: Shader) -> Material {
    return renderer.material_create(shader)
}

material_destroy :: proc(material: ^Material) {
    renderer.material_destroy(material)
}

// Set a colour parameter (declared with shader.param_color). sRGB.
material_set_color :: proc(material: ^Material, name: string, color: Color) {
    index, info, ok := find_param(material, name, "material_set_color")
    if !ok {
        return
    }
    value := renderer.Vec4(color)
    if info.is_color {
        value = renderer.srgb_to_linear(value)
    }
    renderer.material_set_value(material, index, value)
}

material_set_float :: proc(material: ^Material, name: string, value: f32) {
    index, _, ok := find_param(material, name, "material_set_float")
    if ok {
        renderer.material_set_value(material, index, {value, 0, 0, 0})
    }
}

material_set_vec2 :: proc(material: ^Material, name: string, value: [2]f32) {
    index, _, ok := find_param(material, name, "material_set_vec2")
    if ok {
        renderer.material_set_value(material, index, {value.x, value.y, 0, 0})
    }
}

material_set_vec3 :: proc(material: ^Material, name: string, value: [3]f32) {
    index, _, ok := find_param(material, name, "material_set_vec3")
    if ok {
        renderer.material_set_value(material, index, {value.x, value.y, value.z, 0})
    }
}

material_set_vec4 :: proc(material: ^Material, name: string, value: [4]f32) {
    index, _, ok := find_param(material, name, "material_set_vec4")
    if ok {
        renderer.material_set_value(material, index, value)
    }
}

// Assign a texture to a slot declared with shader.texture(name).
// The texture must stay alive while the material uses it. nil restores the default.
material_set_texture :: proc(material: ^Material, name: string, texture: ^Texture) {
    index, ok := renderer.material_find_texture(material, name)
    if !ok {
        log.errorf("material_set_texture: shader '%s' has no texture named '%s'", material.shader.name, name)
        return
    }
    renderer.material_set_texture(material, index, texture)
}

@(private)
find_param :: proc(material: ^Material, name: string, what: string) -> (int, sh.Param_Info, bool) {
    if material == nil || material.shader == nil {
        log.errorf("%s: material was not created", what)
        return -1, {}, false
    }
    index, info, ok := renderer.material_find_param(material, name)
    if !ok {
        log.errorf("%s: shader '%s' has no parameter named '%s'", what, material.shader.name, name)
    }
    return index, info, ok
}

// ---------------------------------------------------------------------------
// Post-processing
// ---------------------------------------------------------------------------

Post_Stage :: renderer.Post_Stage

// Run a post-processing material (shader built with shader.begin(.Post))
// over the whole screen every frame. Effects run in the order they were added.
// The material must stay alive while the effect is active.
post_effect_add :: proc(material: ^Material, stage := Post_Stage.After_Tonemap) {
    renderer.post_effect_add(material, stage)
}

post_effect_remove :: proc(material: ^Material) {
    renderer.post_effect_remove(material)
}

post_effect_set_enabled :: proc(material: ^Material, enabled: bool) {
    renderer.post_effect_set_enabled(material, enabled)
}
