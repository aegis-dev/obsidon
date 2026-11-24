package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"

import obsidon "../../obsidon"

// Lumpy low-poly asteroid: a displaced sphere with flat-shaded faces.
make_asteroid_mesh :: proc(seed: u64) -> Mesh {
    rng := rand.create(seed)
    context.random_generator = rand.default_random_generator(&rng)

    SEGMENTS :: 10
    RINGS :: 7
    // Random bumps: a handful of directions that push the surface in or out.
    Bump :: struct { dir: [3]f32, amount: f32, size: f32 }
    bumps: [9]Bump
    for &b in bumps {
        b.dir = linalg.normalize([3]f32{rand.float32_range(-1, 1), rand.float32_range(-1, 1), rand.float32_range(-1, 1)})
        b.amount = rand.float32_range(-0.25, 0.2)
        b.size = rand.float32_range(0.3, 0.8)
    }

    grid: [RINGS + 1][SEGMENTS][3]f32
    for ring in 0..=RINGS {
        phi := f32(ring) / RINGS * math.PI
        for seg in 0..<SEGMENTS {
            theta := f32(seg) / SEGMENTS * 2 * math.PI
            d := [3]f32{math.sin(phi) * math.cos(theta), math.cos(phi), -math.sin(phi) * math.sin(theta)}
            r: f32 = 0.5
            for b in bumps {
                closeness := max(linalg.dot(d, b.dir) - (1 - b.size), 0) / b.size
                r += b.amount * closeness * 0.5
            }
            r *= rand.float32_range(0.93, 1.05)
            grid[ring][seg] = d * r
        }
    }
    // Poles must be single points.
    for seg in 1..<SEGMENTS {
        grid[0][seg] = grid[0][0]
        grid[RINGS][seg] = grid[RINGS][0]
    }

    vertices := make([dynamic]obsidon.Vertex, context.temp_allocator)
    tri :: proc(vertices: ^[dynamic]obsidon.Vertex, a, b, c: [3]f32) {
        n := linalg.cross(b - a, c - a)
        if linalg.length(n) < 1e-8 {
            return // degenerate (pole)
        }
        n = linalg.normalize(n)
        shade := rand.float32_range(0.85, 1.0)
        col := [4]f32{shade, shade * 0.97, shade * 0.93, 1}
        // Planar uv projection along the dominant axis.
        uv :: proc(p: [3]f32, n: [3]f32) -> [2]f32 {
            an := linalg.abs(n)
            if an.x > an.y && an.x > an.z { return p.zy * 1.5 }
            if an.y > an.z { return p.xz * 1.5 }
            return p.xy * 1.5
        }
        append(vertices, obsidon.Vertex{a, n, uv(a, n), col, {}}, obsidon.Vertex{b, n, uv(b, n), col, {}}, obsidon.Vertex{c, n, uv(c, n), col, {}})
    }
    for ring in 0..<RINGS {
        for seg in 0..<SEGMENTS {
            next := (seg + 1) % SEGMENTS
            a := grid[ring][seg]
            b := grid[ring + 1][seg]
            c := grid[ring][next]
            d := grid[ring + 1][next]
            tri(&vertices, a, b, c)
            tri(&vertices, c, b, d)
        }
    }
    return obsidon.mesh_create(vertices[:])
}

// Normal map of metal panels: grooves between plates and a rivet in each corner.
make_panel_normal_map :: proc(size: u32 = 128, panels: u32 = 4) -> Texture {
    heights := make([]f32, size * size, context.temp_allocator)
    cell := f32(size) / f32(panels)
    for y in 0..<size {
        for x in 0..<size {
            fx := math.mod(f32(x) + 0.5, cell)
            fy := math.mod(f32(y) + 0.5, cell)
            edge := min(min(fx, cell - fx), min(fy, cell - fy))
            h := math.smoothstep(f32(0.5), f32(2.5), edge) // grooves
            for corner in ([4][2]f32{{5, 5}, {cell - 5, 5}, {5, cell - 5}, {cell - 5, cell - 5}}) {
                d := math.sqrt((fx - corner.x) * (fx - corner.x) + (fy - corner.y) * (fy - corner.y))
                h += max(0, 1 - d / 2.2) * 0.6 // rivets
            }
            heights[y * size + x] = h
        }
    }
    return obsidon.texture_normal_map_from_heights(heights, size, size, 1.5)
}

// Small noisy grey-brown texture for rocks.
make_rock_texture :: proc() -> Texture {
    SIZE :: 64
    rng := rand.create(42)
    context.random_generator = rand.default_random_generator(&rng)
    pixels := make([]u8, SIZE * SIZE * 4, context.temp_allocator)
    for y in 0..<SIZE {
        for x in 0..<SIZE {
            // Blocky value noise: cheap, and it suits the PS1 look.
            coarse := f32(((x / 8) * 7 + (y / 8) * 13) % 5) / 5
            v := 0.35 + coarse * 0.15 + rand.float32_range(0, 0.18)
            i := (y * SIZE + x) * 4
            pixels[i + 0] = u8(clamp(v * 1.05, 0, 1) * 255)
            pixels[i + 1] = u8(clamp(v * 0.95, 0, 1) * 255)
            pixels[i + 2] = u8(clamp(v * 0.85, 0, 1) * 255)
            pixels[i + 3] = 255
        }
    }
    return obsidon.texture_create(pixels, SIZE, SIZE)
}
