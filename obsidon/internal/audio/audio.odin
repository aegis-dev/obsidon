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

package audio

import "core:log"

import "vendor:miniaudio"

Audio_State :: struct {
    engine: miniaudio.engine,
}

@(private)
instance_storage: Audio_State

// Package state lives behind a pointer so a hot reloaded build can adopt it.
@(private)
instance: ^Audio_State = &instance_storage

get_state_ptr :: proc() -> rawptr { return instance }
set_state_ptr :: proc(p: rawptr) { instance = (^Audio_State)(p) }
get_state_size :: proc() -> int { return size_of(Audio_State) }

init :: proc() {
    result := miniaudio.engine_init(nil, &instance.engine)
    if result != .SUCCESS {
        log.panic("Failed to initialize audio engine")
    }
}

cleanup :: proc() {
    miniaudio.engine_uninit(&instance.engine)
}