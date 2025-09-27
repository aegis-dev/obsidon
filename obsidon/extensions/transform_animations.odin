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

package extensions

@(private)
TransformAnimationStep :: struct {
    update: proc(animation: ^TransformAnimation, transform: ^Transform, delta_time: f32) -> bool,
    reset:  proc(animation: ^TransformAnimation),
}

TransformAnimation :: struct {
    running:      bool,
    transform:    ^Transform,
    steps:        [dynamic]TransformAnimationStep,
    current_step: int,
}

transform_animation_init :: proc(transform: ^Transform) -> TransformAnimation {
    return TransformAnimation{
        running = false,
        transform = transform,
        steps = {},
        current_step = 0,
    }
}

transform_animation_start :: proc(transform_animation: ^TransformAnimation) {
    transform_animation_reset(transform_animation)
    transform_animation.running = true
}

transform_animation_stop :: proc(transform_animation: ^TransformAnimation) {
    transform_animation.running = false
}

transform_animation_resume :: proc(transform_animation: ^TransformAnimation) {
    transform_animation.running = true
}

transform_animation_restart :: proc(transform_animation: ^TransformAnimation) {
    transform_animation_reset(transform_animation)
}

transform_animation_reset :: proc(transform_animation: ^TransformAnimation) {
    transform_animation.current_step = 0
    for step in transform_animation.steps {
        step.reset(transform_animation)
    }
}

transform_animation_update :: proc(transform_animation: ^TransformAnimation, delta_time: f32) {
    if (!transform_animation.running) {
        return
    }

    if (transform_animation.current_step >= len(transform_animation.steps)) {
        transform_animation.running = false
        return
    }

    current_step := &transform_animation.steps[transform_animation.current_step]

    if (current_step.update(transform_animation, transform_animation.transform, delta_time)) {
        transform_animation.current_step += 1
    }
}

transform_animation_is_running :: proc(transform_animation: ^TransformAnimation) -> bool {
    return transform_animation.running
}

transform_animation_add_step :: proc(transform_animation: ^TransformAnimation, step: TransformAnimationStep) {
    append(&transform_animation.steps, step)
}

@(private)
DoNothingStep :: struct {
    using step:   TransformAnimationStep,
    duration:     f32,
    elapsed_time: f32,
}

transform_animation_add_do_nothing_step :: proc(transform_animation: ^TransformAnimation, duration: f32) {
    step := DoNothingStep{
        duration = duration,
        elapsed_time = 0.0,
        step = TransformAnimationStep{
            update = proc(animation: ^TransformAnimation, transform: ^Transform, delta_time: f32) -> bool {
                step := cast(^DoNothingStep)&animation.steps[animation.current_step]
                step.elapsed_time += delta_time
                return step.elapsed_time >= step.duration
            },
            reset = proc(animation: ^TransformAnimation) {
                step := cast(^DoNothingStep)&animation.steps[animation.current_step]
                step.elapsed_time = 0.0
            },
        },
    }

    transform_animation_add_step(transform_animation, step)
}

@(private)
TransformInitStep :: struct {
    using step:       TransformAnimationStep,
    target_transform: Transform,
}

transform_animation_add_init_transform_step :: proc(transform_animation: ^TransformAnimation, target_transform: Transform) {
    step := TransformInitStep{
        target_transform = target_transform,
        step = TransformAnimationStep{
            update = proc(animation: ^TransformAnimation, transform: ^Transform, delta_time: f32) -> bool {
                step := cast(^TransformInitStep)&animation.steps[animation.current_step]
                transform^ = step.target_transform
                return true
            },
            reset = proc(animation: ^TransformAnimation) {
                // Noithing to reset
            },
        },
    }

    transform_animation_add_step(transform_animation, step)
}

@(private)
TransformIntoStep :: struct {
    using step:       TransformAnimationStep,
    target_transform: Transform,
    duration:         f32,
    elapsed_time:     f32,
}

transform_animation_add_transform_into_step :: proc(transform_animation: ^TransformAnimation, target_transform: Transform, duration: f32) {
    step := TransformIntoStep{
        target_transform = target_transform,
        duration = duration,
        elapsed_time = 0.0,
        step = TransformAnimationStep{
            update = proc(animation: ^TransformAnimation, transform: ^Transform, delta_time: f32) -> bool {
                step := cast(^TransformIntoStep)&animation.steps[animation.current_step]
               
                time_left := step.duration - step.elapsed_time
                completed := delta_time / time_left

                transform.position += (step.target_transform.position - transform.position) * completed
                transform.angle += (step.target_transform.angle - transform.angle) * completed
                transform.scale += (step.target_transform.scale - transform.scale) * completed

                step.elapsed_time += delta_time
                return step.elapsed_time >= step.duration
            },
            reset = proc(animation: ^TransformAnimation) {
                step := cast(^TransformIntoStep)&animation.steps[animation.current_step]
                step.elapsed_time = 0.0
            },
        },
    }

    transform_animation_add_step(transform_animation, step)
}

@(private)
AnimationRestartStep :: struct {
    using step: TransformAnimationStep,
}

transform_animation_add_animation_restart_step :: proc(transform_animation: ^TransformAnimation) {
    step := AnimationRestartStep{
        step = TransformAnimationStep{
            update = proc(animation: ^TransformAnimation, transform: ^Transform, delta_time: f32) -> bool {
                animation.current_step = 0

                // Returning false to avoid step increment
                return false
            },
            reset = proc(animation: ^TransformAnimation) {
                // Nothing to reset
            },
        },
    }

    transform_animation_add_step(transform_animation, step)
}
