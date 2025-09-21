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