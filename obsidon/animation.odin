package obsidon

AnimationFrame :: struct {
    sprite:   ^Sprite,
    duration: f64,
}

Animation :: struct {
    frames:          [dynamic]AnimationFrame,
    frame_index:     int,
    frame_time_left: f64,
    playing:         bool,
    looping:         bool,
}

animation_create :: proc() -> Animation {
    return Animation{
        frames = make([dynamic]AnimationFrame),
    }
}

animation_add_frame :: proc(animation: ^Animation, sprite: ^Sprite, duration: f64) {
    if sprite == nil || duration <= 0.0 {
        return
    }

    append(&animation.frames, AnimationFrame{sprite = sprite, duration = duration})
    if len(animation.frames) == 1 {
        animation.frame_index = 0
        animation.frame_time_left = duration
    }
}

animation_add_frames :: proc(animation: ^Animation, sprites: []^Sprite, duration: f64) {
    for sprite in sprites {
        animation_add_frame(animation, sprite, duration)
    }
}

animation_play :: proc(animation: ^Animation, looping: bool) {
    if len(animation.frames) == 0 {
        animation.playing = false
        return
    }

    animation.frame_index = 0
    animation.frame_time_left = animation.frames[0].duration
    animation.playing = true
    animation.looping = looping
}

animation_update :: proc(animation: ^Animation) -> bool {
    if !animation.playing || len(animation.frames) == 0 {
        return false
    }

    animation.frame_time_left -= get_delta_time()
    for animation.playing && animation.frame_time_left <= 0.0 {
        animation.frame_index += 1
        if animation.frame_index >= len(animation.frames) {
            if !animation.looping {
                animation.frame_index = len(animation.frames) - 1
                animation.frame_time_left = 0.0
                animation.playing = false
                break
            }
            animation.frame_index = 0
        }
        animation.frame_time_left += animation.frames[animation.frame_index].duration
    }

    return animation.playing
}

animation_draw :: proc(animation: ^Animation, position: Vec2, origin: Vec2, angle: f64, flip: bool, scale: f32) {
    if !animation.playing || len(animation.frames) == 0 {
        return
    }

    frame := &animation.frames[animation.frame_index]
    if frame.sprite != nil {
        sprite_draw(frame.sprite, position, origin, angle, flip, scale)
    }
}

animation_cleanup :: proc(animation: ^Animation) {
    delete(animation.frames)
    animation.frames = nil
    animation.frame_index = 0
    animation.frame_time_left = 0.0
    animation.playing = false
    animation.looping = false
}

animation_destroy :: proc(animation: ^Animation) {
    animation_cleanup(animation)
}