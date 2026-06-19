package obsidon

import "core:math"
import "core:math/rand"

@(private)
Particle :: struct {
    position:  Vec2,
    velocity:  Vec2,
    rotation:  f64,
    lifetime:  f64,
    initial_lifetime: f64,
}

ParticleStateOptions :: struct {
    end_scale:   f32,
    start_color: Vec4,
    end_color:   Vec4,
}

ParticleState :: struct {
    sprite:            ^Sprite,
    origin:            Vec2,
    scale:             f32,
    end_scale:         f32,
    start_color:       Vec4,
    end_color:         Vec4,
    emission_interval: f64,
    particle_lifetime: f64,
    particle_speed:    f64,
    particle_drag:     f64,
    emission_timer:    f64,
    particles:         [dynamic]Particle,
}

particle_state_init :: proc(sprite: ^Sprite, particle_scale: f32, emission_interval: f64, particle_lifetime: f64, particle_speed: f64, particle_drag: f64) -> ParticleState {
    return particle_state_init_with_options(sprite, particle_scale, emission_interval, particle_lifetime, particle_speed, particle_drag, ParticleStateOptions{
        end_scale = particle_scale,
        start_color = {1, 1, 1, 1},
        end_color = {1, 1, 1, 1},
    })
}

particle_state_init_with_options :: proc(sprite: ^Sprite, particle_scale: f32, emission_interval: f64, particle_lifetime: f64, particle_speed: f64, particle_drag: f64, options: ParticleStateOptions) -> ParticleState {
    return ParticleState{
        sprite = sprite,
        origin = {
            f64(sprite.width) * 0.5,
            f64(sprite.height) * 0.5,
        },
        scale = particle_scale,
        end_scale = options.end_scale,
        start_color = options.start_color,
        end_color = options.end_color,
        emission_interval = math.max(emission_interval, 0.0),
        particle_lifetime = math.max(particle_lifetime, 0.0),
        particle_speed = particle_speed,
        particle_drag = math.max(particle_drag, 0.0),
        emission_timer = math.max(emission_interval, 0.0),
        particles = make([dynamic]Particle),
    }
}

particle_emit :: proc(state: ^ParticleState, position: Vec2, rotation: f64, emission_angle: f64) -> bool {
    if state.sprite == nil || state.particle_lifetime <= 0.0 {
        return false
    }

    if state.emission_interval > 0.0 && state.emission_timer < state.emission_interval {
        return false
    }

    angle_offset := (rand.float64() - 0.5) * emission_angle
    particle_rotation := rotation + angle_offset
    particle_velocity := vec2_direction(particle_rotation) * state.particle_speed

    append(&state.particles, Particle{
        position = position,
        velocity = particle_velocity,
        rotation = particle_rotation,
        lifetime = state.particle_lifetime,
        initial_lifetime = state.particle_lifetime,
    })

    state.emission_timer = 0.0
    return true
}

particle_update :: proc(state: ^ParticleState) {
    delta_time := get_delta_time()
    state.emission_timer += delta_time

    alive_count := 0
    for i in 0..<len(state.particles) {
        particle := &state.particles[i]
        particle.lifetime -= delta_time
        if particle.lifetime <= 0.0 {
            continue
        }

        particle.position += particle.velocity * delta_time

        if state.particle_drag > 0.0 {
            speed := vec2_length(particle.velocity)
            if speed > 0.0 {
                next_speed := math.max(0.0, speed - state.particle_drag * delta_time)
                if next_speed == 0.0 {
                    particle.velocity = VEC2_ZERO
                } else {
                    particle.velocity *= next_speed / speed
                }
            }
        }

        if alive_count != i {
            state.particles[alive_count] = state.particles[i]
        }
        alive_count += 1
    }

    resize(&state.particles, alive_count)
}

particle_draw :: proc(state: ^ParticleState) {
    if state.sprite == nil {
        return
    }

    for &particle in state.particles {
        life_t := particle_life_t(&particle)
        scale := lerp_f32(state.scale, state.end_scale, life_t)
        color := lerp_vec4(state.start_color, state.end_color, life_t)
        sprite_draw_colored(state.sprite, particle.position, state.origin, particle.rotation, false, scale, color)
    }
}

particle_draw_ui :: proc(state: ^ParticleState) {
    if state.sprite == nil {
        return
    }

    for &particle in state.particles {
        life_t := particle_life_t(&particle)
        scale := lerp_f32(state.scale, state.end_scale, life_t)
        color := lerp_vec4(state.start_color, state.end_color, life_t)
        sprite_draw_ui_colored(state.sprite, particle.position, state.origin, particle.rotation, false, scale, color)
    }
}

particle_destroy :: proc(state: ^ParticleState) {
    delete(state.particles)
    state.particles = nil
    state.emission_timer = 0.0
}

@(private)
particle_life_t :: proc(particle: ^Particle) -> f64 {
    if particle.initial_lifetime <= 0.0 {
        return 1.0
    }

    return math.clamp(1.0 - particle.lifetime / particle.initial_lifetime, 0.0, 1.0)
}

@(private)
lerp_f32 :: proc(a: f32, b: f32, t: f64) -> f32 {
    return f32(f64(a) + (f64(b) - f64(a)) * t)
}

@(private)
lerp_vec4 :: proc(a: Vec4, b: Vec4, t: f64) -> Vec4 {
    return {
        lerp_f32(a[0], b[0], t),
        lerp_f32(a[1], b[1], t),
        lerp_f32(a[2], b[2], t),
        lerp_f32(a[3], b[3], t),
    }
}