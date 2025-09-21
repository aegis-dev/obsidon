package audio

import "core:log"

import "vendor:miniaudio"

@(private)
instance: struct {
    engine: miniaudio.engine,
}

init :: proc() {
    result := miniaudio.engine_init(nil, &instance.engine)
    if result != .SUCCESS {
        log.panic("Failed to initialize audio engine")
    }
}

cleanup :: proc() {
    miniaudio.engine_uninit(&instance.engine)
}