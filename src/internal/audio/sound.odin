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
import "core:c"

import "vendor:miniaudio"

Sound :: struct {
    sound: miniaudio.sound,
}

sound_load_from_file :: proc(file_path: string) -> Sound {
    sound := Sound{}

    result := miniaudio.sound_init_from_file(
        &instance.engine, 
        cstring(raw_data(file_path)), 
        { .STREAM, }, 
        nil, 
        nil, 
        &sound.sound
    )
    
    if result != .SUCCESS {
        log.panic("Failed to load sound: %s", file_path)
    }

    return sound
}

sound_copy :: proc(original: ^Sound) -> Sound {
    sound := Sound{}

    result := miniaudio.sound_init_copy(&instance.engine, &original.sound, { .DECODE }, nil, &sound.sound)
    if result != .SUCCESS {
        log.panic("Failed to copy sound")
    }

    return sound
}

sound_play :: proc(sound: ^Sound) {
    miniaudio.sound_start(&sound.sound)
}

sound_stop :: proc(sound: ^Sound) {
    miniaudio.sound_stop(&sound.sound)
}

sound_set_looping :: proc(sound: ^Sound, looping: bool) {
    miniaudio.sound_set_looping(&sound.sound, b32(looping))
}

// Set volume (0.0 to 1.0)
sound_set_volume :: proc(sound: ^Sound, volume: f32) {
    miniaudio.sound_set_volume(&sound.sound, volume)
}

// Set volume (0.0 to 1.0)
audio_engine_set_volume :: proc(volume: f32) {
    miniaudio.engine_set_volume(&instance.engine, volume)
}

sound_destroy :: proc(sound: ^Sound) {
    miniaudio.sound_uninit(&sound.sound)
}

sound_play_immediate :: proc(file_path: string) {
    miniaudio.engine_play_sound(
        &instance.engine, 
        cstring(raw_data(file_path)), 
        nil
    )

}