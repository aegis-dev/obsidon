package main

import sh "../../obsidon/shader"

// Custom shaders, written with the Obsidon shader builder.
// Each describe_* returns the shader description: flight_create builds them
// with obsidon.shader_create, and after a hot reload flight_reload swaps the
// new code in with obsidon.shader_rebuild.
// No WGSL here: every shader is a small graph of primitives, and the engine
// generates the colour, shadow and SSAO pre-pass variants from it.

// Gas giant: procedural bands in object space + a sun-facing atmosphere rim.
describe_gas_giant :: proc() -> sh.Shader_Desc {
    sh.begin(name = "gas_giant")

    // Object-space normal gives a pattern that sticks to the planet as it rotates.
    n := sh.normalize(sh.normal())
    swirl := sh.mul(sh.sin(sh.add(sh.mul(sh.x(n), 9), sh.mul(sh.z(n), 7))), 0.12)
    band_pos := sh.add(sh.y(n), swirl)
    bands := sh.add(sh.mul(sh.sin(sh.mul(band_pos, 17)), 0.5), 0.5)
    fine := sh.add(sh.mul(sh.sin(sh.mul(band_pos, 53)), 0.1), 0.9)

    albedo := sh.mix(
        sh.rgb(sh.param_color("color_a", {0.85, 0.62, 0.42, 1})),
        sh.rgb(sh.param_color("color_b", {0.45, 0.28, 0.22, 1})),
        bands,
    )
    albedo = sh.mul(albedo, fine)

    pos := sh.world_position()
    normal := sh.normalize(sh.world_normal())
    color := sh.mul(albedo, sh.lighting(pos, normal))

    // Atmosphere: fresnel rim, only on the lit side.
    rim := sh.fresnel(normal, pos, 4)
    sun_side := sh.saturate(sh.add(sh.dot(normal, sh.sun_direction()), 0.25))
    atmosphere := sh.mul(sh.rgb(sh.param_color("atmosphere", {0.55, 0.75, 1.0, 1})), sh.mul(rim, sh.mul(sun_side, 3)))

    sh.set_color(sh.add(color, atmosphere))
    return sh.end()
}

// Star field drawn on the inside of a big sphere that follows the camera.
describe_sky :: proc() -> sh.Shader_Desc {
    sh.begin(name = "sky")
    sh.set_queue(.Background)    // behind everything, whatever the distance
    sh.set_cull(.Front)          // we are inside the sphere
    sh.set_depth_write(false)    // everything else draws in front
    sh.set_cast_shadows(false)

    dir := sh.normalize(sh.position())

    // Stars: hash a grid on the sphere, keep the rare bright cells.
    cell := sh.floor(sh.mul(dir, 260))
    seed := sh.vec2(sh.add(sh.x(cell), sh.mul(sh.z(cell), 1.731)), sh.sub(sh.y(cell), sh.mul(sh.z(cell), 3.117)))
    h := sh.hash(seed)
    star := sh.step(0.9965, h)
    twinkle := sh.add(0.75, sh.mul(sh.sin(sh.add(sh.mul(sh.time(), 3), sh.mul(h, 500))), 0.25))
    tint := sh.mix(sh.vec3(0.7, 0.8, 1.0), sh.vec3(1.0, 0.85, 0.7), sh.hash(sh.add(seed, 17)))
    stars := sh.mul(tint, sh.mul(star, sh.mul(twinkle, 3)))

    // Faint nebula: a few low frequency waves.
    wave := sh.mul(sh.sin(sh.add(sh.mul(sh.x(dir), 3.1), sh.mul(sh.y(dir), 2.3))), sh.sin(sh.add(sh.mul(sh.z(dir), 2.7), 1.3)))
    nebula := sh.mul(sh.param_color("nebula", {0.25, 0.12, 0.35, 1}), sh.mul(sh.saturate(wave), 0.35))
    base := sh.rgb(sh.param_color("space", {0.01, 0.012, 0.025, 1}))

    sh.set_color(sh.add(sh.add(base, sh.rgb(nebula)), stars))
    return sh.end()
}

// Additive, pulsing glow for engines and beacons (HDR > 1 values).
describe_glow :: proc() -> sh.Shader_Desc {
    sh.begin(name = "glow")
    sh.set_blend(.Additive)
    sh.set_cast_shadows(false)
    sh.set_cull(.None)

    pulse := sh.add(0.85, sh.mul(sh.sin(sh.mul(sh.time(), sh.param_float("pulse_speed", 25))), 0.15))
    view := sh.view_direction(sh.world_position())
    facing := sh.saturate(sh.dot(sh.normalize(sh.world_normal()), view))
    glow := sh.mul(sh.rgb(sh.param_color("color", {1.0, 0.55, 0.2, 1})), sh.mul(pulse, sh.mul(facing, sh.param_float("strength", 4))))
    sh.set_color(sh.vec4(sh.mul(glow, sh.rgb(sh.tint())), 1))
    return sh.end()
}

// Earth-like planet, fully procedural: fractal noise continents, oceans,
// biomes by altitude, polar ice, ocean glint, city lights on the night side
// and an atmosphere rim. Change the "seed" param for a different world.
describe_terran_planet :: proc() -> sh.Shader_Desc {
    sh.begin(name = "terran_planet")

    // Direction from the planet centre (object space) is the texture coordinate.
    dir := sh.normalize(sh.normal())
    p := sh.add(sh.mul(dir, sh.param_float("scale", 2.4)), sh.param_vec3("seed", {3.1, 7.7, 1.3}))

    // Domain warping gives natural looking coastlines.
    warp := sh.fbm(sh.add(p, 11.3), 3)
    height := sh.fbm(sh.add(p, sh.mul(warp, 0.9)), 6)
    sea_level := sh.param_float("sea_level", 0.49)
    land := sh.smoothstep(sea_level, sh.add(sea_level, 0.004), height)
    elevation := sh.saturate(sh.div(sh.sub(height, sea_level), 0.2))

    // Ocean: deeper water is darker.
    shallow := sh.smoothstep(sh.sub(sea_level, 0.08), sea_level, height)
    ocean := sh.mix(sh.vec3(0.01, 0.04, 0.14), sh.vec3(0.03, 0.22, 0.35), shallow)

    // Land biomes by elevation.
    ground := sh.mix(sh.vec3(0.76, 0.70, 0.50), sh.vec3(0.20, 0.42, 0.12), sh.smoothstep(0.0, 0.06, elevation))
    ground = sh.mix(ground, sh.vec3(0.08, 0.25, 0.08), sh.smoothstep(0.12, 0.3, elevation))
    ground = sh.mix(ground, sh.vec3(0.36, 0.30, 0.25), sh.smoothstep(0.38, 0.55, elevation))
    ground = sh.mix(ground, sh.vec3(0.95, 0.95, 0.97), sh.smoothstep(0.7, 0.8, elevation))

    // Polar ice caps with a ragged edge.
    edge := sh.mul(sh.sub(sh.fbm(sh.mul(p, 3), 3), 0.5), 0.25)
    ice := sh.smoothstep(0.78, 0.82, sh.add(sh.abs(sh.y(dir)), edge))

    albedo := sh.mix(ocean, ground, land)
    albedo = sh.mix(albedo, sh.vec3(0.92, 0.95, 1.0), ice)

    pos := sh.world_position()
    normal := sh.normalize(sh.world_normal())
    color := sh.mul(albedo, sh.lighting(pos, normal))

    // Sun glint on open water only.
    water := sh.mul(sh.one_minus(land), sh.one_minus(ice))
    color = sh.add(color, sh.mul(sh.specular(pos, normal, 80), sh.mul(water, 0.8)))

    // City lights where it's night.
    night := sh.saturate(sh.mul(sh.dot(normal, sh.sun_direction()), -5))
    cities := sh.step(0.7, sh.noise(sh.mul(p, 45)))
    cities = sh.mul(cities, sh.mul(sh.mul(land, sh.one_minus(ice)), sh.smoothstep(0.02, 0.1, elevation)))
    cities = sh.mul(cities, sh.one_minus(sh.smoothstep(0.3, 0.45, elevation)))
    color = sh.add(color, sh.mul(sh.vec3(1.0, 0.65, 0.3), sh.mul(cities, sh.mul(night, 1.5))))

    // Atmosphere rim on the day side.
    rim := sh.fresnel(normal, pos, 3)
    day := sh.saturate(sh.add(sh.dot(normal, sh.sun_direction()), 0.3))
    color = sh.add(color, sh.mul(sh.vec3(0.35, 0.6, 1.0), sh.mul(rim, sh.mul(day, 2.5))))

    sh.set_color(color)
    return sh.end()
}

// Drifting cloud layer for the terran planet (a slightly bigger sphere).
describe_cloud :: proc() -> sh.Shader_Desc {
    sh.begin(name = "clouds")
    sh.set_blend(.Alpha)
    sh.set_cast_shadows(false)

    dir := sh.normalize(sh.normal())
    drift := sh.mul(sh.time(), sh.param_float("speed", 0.006))
    p := sh.add(sh.mul(dir, 3.2), sh.vec3(drift, sh.mul(drift, 0.3), sh.mul(drift, -0.7)))
    swirl := sh.fbm(sh.add(p, 4.7), 3)
    density := sh.fbm(sh.add(p, sh.mul(swirl, 1.4)), 5)
    coverage := sh.param_float("coverage", 0.57)
    alpha := sh.smoothstep(coverage, sh.add(coverage, 0.18), density)

    pos := sh.world_position()
    normal := sh.normalize(sh.world_normal())
    color := sh.lighting(pos, normal)

    sh.set_color(sh.vec4(color, sh.mul(alpha, 0.9)))
    return sh.end()
}
