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

// Code hot reloading.
//
// The game is built as a DLL (with the engine inside) and loaded by a small
// host program (obsidon/hotreload). When the DLL is rebuilt, the host loads the
// new version and hands it the running engine state with these procedures:
//
//     old DLL: state := obsidon.hot_reload_get_state()
//     new DLL: obsidon.hot_reload_set_state(state)  // engine continues where it was
//
// Everything the engine owns (window, GPU resources, audio, current scene)
// survives. Game code must keep its own state in the scene struct or behind
// obsidon.set_user_data, re-assign the scene callbacks (they point at the old
// code), and can rebuild shaders in Scene.on_reload. wgpu and GLFW must be
// linked as shared libraries (-define:WGPU_SHARED=true -define:GLFW_SHARED=true)
// so they are not duplicated per DLL; the host never unloads old DLLs, so
// callbacks registered by them stay valid.

import "core:log"

import "internal/audio"
import "internal/renderer"
import "internal/window"

Hot_Reload_State :: struct {
    core:     rawptr,
    renderer: rawptr,
    window:   rawptr,
    audio:    rawptr,
    // Sizes of the engine structs: if any changed, the new code can't take
    // over and the host has to restart the game.
    layout:   [4]int,
}

// Called on the running (old) code: the engine state to hand over.
hot_reload_get_state :: proc() -> ^Hot_Reload_State {
    core.hot_reload = Hot_Reload_State{
        core     = core,
        renderer = renderer.get_state_ptr(),
        window   = window.get_state_ptr(),
        audio    = audio.get_state_ptr(),
        layout   = hot_reload_layout(),
    }
    return &core.hot_reload
}

// Engine struct sizes of this build. Compare with Hot_Reload_State.layout.
hot_reload_layout :: proc() -> [4]int {
    return {size_of(Core_State), renderer.get_state_size(), window.get_state_size(), audio.get_state_size()}
}

// Called on the newly loaded code: adopt the running engine state.
// Returns false (and changes nothing) when the engine layout changed.
hot_reload_set_state :: proc(s: ^Hot_Reload_State) -> bool {
    if s == nil || s.layout != hot_reload_layout() {
        log.warn("hot reload: the engine data layout changed, a restart is required")
        return false
    }
    core = (^Core_State)(s.core)
    renderer.set_state_ptr(s.renderer)
    window.set_state_ptr(s.window)
    audio.set_state_ptr(s.audio)
    // GLFW callbacks point at the old code: register this build's versions.
    window.install_callbacks()
    return true
}

// Called on the new code once the game re-assigned its scene callbacks:
// runs Scene.on_reload so the scene can rebuild shaders etc.
hot_reload_finished :: proc() {
    if core.current_scene != nil && core.current_scene.on_reload != nil {
        core.current_scene->on_reload()
    }
    log.info("hot reload: done")
}
