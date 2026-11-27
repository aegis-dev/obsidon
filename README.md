# Obsidon

A lightweight 3D game framework written in [Odin](https://odin-lang.org/) with a WebGPU rendering backend.

Obsidon keeps the "small API, no ceremony" spirit of its 2D roots: a scene with four callbacks,
`xxx_load` / `xxx_draw` / `xxx_destroy` procedures, and rendering features you switch on with a
settings struct. Shaders are written in Odin with a small set of primitives instead of a shading
language, and every shader automatically works with shadows, SSAO and the rest of the pipeline.

## Features

- **Modern rendering**: WebGPU (Vulkan / DX12 / Metal) forward renderer with an HDR pipeline
- **Shader builder**: describe shaders in Odin code (`obsidon/shader`), WGSL is generated for you
- **Lighting**: hemisphere ambient light, a directional sun, up to 256 point / spot lights per frame, distance fog
- **Shadows**: cascaded sun shadow maps (1-4 cascades) and spot light shadows, selectable resolution
  (512 - 4096) and filtering (hard, PCF 3x3, PCF 5x5)
- **SSAO**: screen space ambient occlusion with a depth / normal pre-pass, three quality levels
- **Bloom & post-processing**: HDR bloom, tonemapping (ACES, Reinhard), custom post effects built with the shader builder
- **Materials**: normal maps (tangents generated automatically), emission maps, uv tiling
- **Models**: glTF 2.0 (.glb / .gltf) with textures and materials, OBJ, primitives, custom vertex data
- **Instancing**: thousands of copies of a mesh in one draw call
- **Hot reload**: edit game code and shaders while the game runs
- **Any render resolution**: render at the window size or at a fixed size (presets or any custom
  `width x height`) shown with integer scaling + black borders, fit or stretched; a built-in PS1 shader
  (vertex snapping, affine textures, Gouraud lighting, dithering)
- **Upscaling**: AMD FidelityFX Super Resolution 1 (FSR 1: edge adaptive upsampling + sharpening) for a
  scaled down render, a UI drawn at native window resolution over it (`native_overlay`), film grain after
  upscaling
- **Big worlds**: 64-bit world coordinates with camera-relative rendering, infinite reverse-Z far plane
- **2D overlay**: sprites, animations, particles, text and solid shapes (`draw_rect`, `draw_line`,
  `draw_circle`, ...) drawn over the 3D scene (HUD, menus)
- **Scene system, input, audio**: unchanged simple APIs

## Quick start

```bash
git submodule add https://github.com/aegis-dev/obsidon.git
```

```odin
package main

import obsidon "obsidon/obsidon"

GameScene :: struct {
    using scene: obsidon.Scene,
    shader:   obsidon.Shader,
    material: obsidon.Material,
    cube:     obsidon.Mesh,
    floor:    obsidon.Mesh,
}

scene_create :: proc(s: ^obsidon.Scene) {
    scene := cast(^GameScene)s
    obsidon.set_sun({-0.5, -1, -0.3}, obsidon.WHITE, 2)
    obsidon.set_ambient_light(obsidon.rgb(0.5, 0.6, 0.8), obsidon.rgb(0.2, 0.2, 0.2))

    scene.shader = obsidon.shader_standard()
    scene.material = obsidon.material_create(scene.shader)
    obsidon.material_set_color(&scene.material, "color", obsidon.color_hex(0xE07A5F))

    scene.cube = obsidon.mesh_cube()
    scene.floor = obsidon.mesh_plane({20, 20})

    obsidon.set_camera_position({4, 3, 6})
    obsidon.camera_look_at({0, 0.5, 0})
}

scene_update :: proc(s: ^obsidon.Scene) -> ^obsidon.Scene {
    if obsidon.is_key_pressed(.KEY_ESCAPE) do obsidon.quit_game()
    return nil
}

scene_draw :: proc(s: ^obsidon.Scene) {
    scene := cast(^GameScene)s
    spin := obsidon.quat_angle_axis(obsidon.get_time() * 45, obsidon.VEC3_UP)
    obsidon.draw_mesh(&scene.floor, &scene.material, {}, tint = obsidon.GRAY)
    obsidon.draw_mesh(&scene.cube, &scene.material, {position = {0, 0.5, 0}, rotation = spin})
}

scene_destroy :: proc(s: ^obsidon.Scene) {
    scene := cast(^GameScene)s
    obsidon.mesh_destroy(&scene.cube)
    obsidon.mesh_destroy(&scene.floor)
    obsidon.material_destroy(&scene.material)
    obsidon.shader_destroy(scene.shader)
}

main :: proc() {
    scene := new(GameScene)
    scene.on_create = scene_create
    scene.on_update = scene_update
    scene.on_draw = scene_draw
    scene.on_destroy = scene_destroy

    settings := obsidon.default_settings("My Game")
    settings.graphics.shadows = true
    settings.graphics.shadow_resolution = .R2048
    settings.graphics.ssao = true
    obsidon.run_game(settings, scene)
}
```

See `examples/basic/` for a fuller sample (custom shader, PS1 shader, lights, sprites and text).

## Graphics settings

Everything is configured with `obsidon.Graphics_Settings` (start from `default_graphics_settings()`),
either at start-up through `Settings.graphics` or at runtime with `set_graphics_settings`:

| Setting | Values |
| --- | --- |
| `resolution` | `.Native`, `.R320x240`, `.R427x240`, `.R640x360`, `.R640x480`, `.R854x480`, `.R1280x720`, `.R1920x1080`, `.Custom` |
| `custom_resolution` | `{width, height}` for `.Custom`, e.g. `{320, 240}` |
| `scaling` | `.Integer` (whole-number scale, centred, black borders), `.Fit`, `.Stretch` |
| `upscale_filter` | `.Nearest` (crisp pixels), `.Linear` (smooth), `.FSR1` (AMD FSR 1, when the buffer is enlarged) |
| `fsr_sharpness` | FSR 1 sharpening in stops, `0` = sharpest (default `0.25`) |
| `native_overlay` | `bool`: draw the 2D overlay at window resolution (sharp UI over a scaled render); `get_overlay_scale()` |
| `film_grain` | `f32` grain amount added after upscaling (`0` = off) |
| `vsync` | `bool` |
| `texture_filter` | `.Nearest` (retro), `.Linear` (+ mipmaps) |
| `shadows` | `bool` |
| `shadow_resolution` | `.R512`, `.R1024`, `.R2048`, `.R4096` |
| `shadow_distance` | world units covered by the shadow maps |
| `shadow_cascades` | `1` - `4` |
| `shadow_filter` | `.Hard`, `.PCF_3x3`, `.PCF_5x5` |
| `spot_shadows`, `spot_shadow_resolution` | `bool`, `Shadow_Resolution` (up to 4 shadowed spots per frame) |
| `ssao` | `bool` |
| `ssao_quality` | `.Low` (8), `.Medium` (16), `.High` (32 samples) |
| `ssao_radius`, `ssao_intensity`, `ssao_direct_amount` | `f32` |
| `bloom`, `bloom_intensity`, `bloom_threshold` | `bool`, `f32`, `f32` |
| `tonemapper` | `.None`, `.Reinhard`, `.ACES` |
| `exposure` | `f32` |
| `debug_view` | `.None`, `.Ambient_Occlusion`, `.Normals`, `.Depth`, `.Shadow_Cascades` |

## Shaders

Shaders are graphs built from Odin calls. There is no operator overloading in Odin, so arithmetic is
`sh.add`, `sh.mul`, ... and every primitive accepts either a graph value or a plain number.

```odin
import sh "obsidon/obsidon/shader"

make_toon_shader :: proc() -> obsidon.Shader {
    sh.begin(name = "toon")
    albedo := sh.mul(sh.sample(sh.texture("albedo"), sh.uv()), sh.param_color("color"))
    light  := sh.lighting(sh.world_position(), sh.world_normal())
    bands  := sh.div(sh.floor(sh.mul(light, 3)), 3)          // 3 light bands
    sh.set_color(sh.vec4(sh.mul(sh.rgb(albedo), bands), 1))
    return obsidon.shader_create(sh.end())
}
```

How it works:

- **Per pixel by default.** Vertex inputs (`uv()`, `normal()`, `world_position()`, ...) are interpolated
  automatically when the pixel stage needs them.
- **Vertex outputs.** `set_world_position` (displacement, wind, waves) and `set_clip_position` (e.g.
  `snap_to_grid` for PS1 wobble) run in the vertex shader.
- **Interpolation control.** `per_vertex(v)` computes a value per vertex (Gouraud lighting is
  `lighting_per_vertex`), `affine(v)` disables perspective correction (PS1 texture warping), `flat(v)`
  disables interpolation.
- **Engine integration.** `lighting()` includes ambient + SSAO, the sun + shadows and all point / spot
  lights. `fog()`, `specular()`, `shadow()`, `ambient_occlusion()`, `noise()`, `fbm()`, `dither()`, ... are
  available as primitives. From one description the engine generates the colour pass, the shadow pass
  and the SSAO pre-pass, so custom shaders always cast shadows correctly (including displaced vertices
  and alpha clipping).
- **Materials.** `param_float/vec*/color` and `texture` declare material inputs, set them with
  `material_set_*`.
- **Post effects.** `sh.begin(.Post)` builds a full screen effect (`scene_color(uv)`, `scene_depth(uv)`,
  `screen_uv()`); add it with `post_effect_add`, before or after tonemapping.
- **Escape hatch.** `custom_call` calls any WGSL / engine function.

- **Draw order.** `set_queue(.Background)` for skies and backdrops, `.Transparent` is set by `set_blend`.
- **Building blocks.** A building block is just an Odin procedure returning `sh.Value`. The library ships
  `fresnel`, `rim_light`, `triplanar`, `toon_ramp`, `normal_map`, `noise`, `fbm`, `uv_scroll`, `uv_rotate`,
  `checker`, `remap`, `pulse`, `desaturate`, and for post effects `vignette`, `scanlines`,
  `chromatic_aberration`, `bloom` (see `obsidon/shader/library.odin`).
- **Rebuilding.** `shader_rebuild(shader, sh.end())` swaps a shader's code in place; materials keep their
  values and textures (matched by parameter name).

Built-in shaders: `shader_standard`, `shader_unlit`, `shader_psx`, `shader_post_dither`, `shader_post_vignette`.

## Models and instancing

```odin
helmet, ok := obsidon.model_load_gltf(#load("helmet.glb"))   // or model_load_gltf_file(path)
obsidon.model_draw(&helmet, {position = {0, 1, 0}})
obsidon.model_destroy(&helmet)

// One draw call for many copies:
obsidon.draw_mesh_instanced(&rock, &rock_material, rock_transforms[:])
```

glTF materials map onto the standard shader (base colour, normal and emissive maps, alpha modes, double
sided); pass a shader to `model_load_gltf` to use your own.

## Hot reload

Build the game as a DLL with the engine inside and run it through the host in `hotreload/`. Rebuilding
the DLL swaps the new code into the running game: window, GPU resources and the scene stay alive.

The game DLL exports six procedures (see `hotreload/main.odin`); they are mostly one-liners:

```odin
@(export) game_init :: proc() { obsidon.init(settings, create_scene()) }
@(export) game_frame :: proc() -> bool { return obsidon.frame() }
@(export) game_shutdown :: proc() { obsidon.shutdown() }
@(export) game_memory :: proc() -> rawptr { return obsidon.hot_reload_get_state() }
@(export) game_memory_size :: proc() -> int { /* combine obsidon.hot_reload_layout() with size_of(your structs) */ }
@(export) game_hot_reloaded :: proc(memory: rawptr) -> bool {
    if !obsidon.hot_reload_set_state((^obsidon.Hot_Reload_State)(memory)) do return false
    bind_scene_callbacks(obsidon.get_current_scene()) // they point at the old code
    obsidon.hot_reload_finished()                     // runs Scene.on_reload (rebuild shaders there)
    return true
}
```

Build the DLL with `-build-mode:dll -define:WGPU_SHARED=true -define:GLFW_SHARED=true` and put
`wgpu_native.dll` and `glfw3.dll` next to the host. Keep game state in the scene struct or behind
`obsidon.set_user_data` (package globals reset on reload). When the data layout changes the host restarts
the game automatically. Space Sim Neo's `build.py --hot` is a complete example.

## Coordinates

- Right-handed, Y up, cameras and objects look along -Z.
- World math is `f64` (`Vec3`, `Quat`, `Mat4`); rendering is camera-relative so precision is kept far from
  the origin. Colours (`Color`) are sRGB `f32`.
- Angles in the public API are degrees.
- The 2D overlay uses render buffer pixels with (0, 0) in the centre of the screen and +Y up.

## Automated screenshots

Set `OBSIDON_SCREENSHOT=out.png` (and optionally `OBSIDON_SCREENSHOT_FRAME=60`) to render that many frames,
save a PNG and exit. `OBSIDON_SCREENSHOT_WINDOW=1` captures the window image (after scaling, borders
included) instead of the render buffer. `save_screenshot(path, window_image)` does the same from code.

## Building

```bash
odin build examples/basic -out:bin/example.exe
odin build examples/ps1_flight -out:bin/ps1_flight.exe
```

Requires a recent Odin (tested with dev-2026-11). wgpu-native is linked statically from `vendor:wgpu`.

## Philosophy

Obsidon follows a **"less is more"** philosophy:

- **Constraints breed creativity** - focused, well-defined tools rather than endless options
- **Simplicity over completeness** - ease of use and clarity over covering every possible use case
- **Minimal but powerful** - the essential building blocks that let you create without getting in your way

## License

Apache 2.0, see [LICENSE](LICENSE).

### Third-party code

- **AMD FidelityFX Super Resolution 1.0** (EASU and RCAS, ported to WGSL in
  `obsidon/internal/renderer/wgsl/fsr_easu.wgsl` and `blit.wgsl`) - Copyright (c) 2021 Advanced Micro
  Devices, Inc., MIT license. FidelityFX and FSR are trademarks of Advanced Micro Devices, Inc.
  See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
