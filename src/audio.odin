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

import "audio"

Sound :: audio.Sound

sound_load_from_file :: proc(file_path: string) -> Sound {
    return audio.sound_load_from_file(file_path)
}

sound_copy :: proc(original: ^Sound) -> Sound {
    return audio.sound_copy(original)
}

sound_play :: proc(sound: ^Sound) {
    audio.sound_play(sound)
}

sound_stop :: proc(sound: ^Sound) {
    audio.sound_stop(sound)
}

// Set volume (0.0 to 1.0)
sound_set_volume :: proc(sound: ^Sound, volume: f32) {
    audio.sound_set_volume(sound, volume)
}

sound_destroy :: proc(sound: ^Sound) {
    audio.sound_destroy(sound)
}

// Temporary workaround to play a sound while the bug is not fixed
sound_play_immediate :: proc(file_path: string) {
    audio.sound_play_immediate(file_path)
}