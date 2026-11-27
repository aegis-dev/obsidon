# Obsidon

Small 3D game framework in Odin on WebGPU (`vendor:wgpu`, wgpu-native linked statically) + GLFW + miniaudio.
It grew out of a 2D engine: keep the same "small API, no ceremony" style when extending it.

## Layout

- `obsidon/` — package `obsidon`, the public API (what games import)
  - `context.odin` main loop (`run_game`), `settings.odin` (`Settings`, `Graphics_Settings`; window modes
    `.Windowed`, `.Fullscreen` (exclusive) and `.Borderless` (windowed fullscreen))
  - `mesh.odin` (primitives, OBJ, `draw_mesh`, instancing), `model.odin` (glTF via cgltf), `texture.odin`
    (2D, 3D volumes `texture_create_3d`, tileable fbm noise volume `texture_noise_3d`),
    `shader.odin` (built-in shaders, `shader_rebuild`), `material.odin` (+ post effects)
  - `hotreload.odin` (engine state handoff), `args_*.odin` (`command_line_args`, works inside DLLs)
  - `lighting.odin`, `camera.odin`, `transform.odin`, `math.odin`
  - 2D overlay: `sprite.odin`, `text.odin`, `font.odin`, `shapes.odin` (rects, lines, circles),
    `animation.odin`, `particle.odin`
- `obsidon/shader/` — package `shader`, the shader graph builder → WGSL codegen. No GPU code.
  - `builder.odin` (state, outputs, params), `nodes.odin` (primitives), `library.odin` (building blocks made
    only of primitives), `codegen.odin` (per-pass WGSL)
  - `wgsl/common.wgsl`, `surface.wgsl`, `post.wgsl` — engine shader library linked into every generated shader
- `obsidon/internal/renderer/` — WebGPU renderer. `renderer.odin` (device, layouts, helpers), `resources.odin`
  (mesh/texture/shader/material/pipelines), `targets.odin` (render targets, bind groups), `frame.odin`
  (submission, shadow views, all passes), `wgsl/` (SSAO, blur, bloom, lens streaks, tonemap, blit, overlay, debug view)
- `obsidon/internal/window/` (GLFW, input), `obsidon/internal/audio/`
- `obsidon/extensions/` — optional 2D gameplay helpers (transform, transform animations, collision)
- `example/` — sample game
- `hotreload/` — host program that runs a game DLL and swaps in rebuilt versions

## Build / verify

```bash
odin check obsidon -no-entry-point     # type-check the engine
odin build examples/basic -out:bin/example.exe -debug
odin build examples/ps1_flight -out:bin/ps1_flight.exe   # --view=1..6 --screenshot=out.png (see its game.odin)
OBSIDON_SCREENSHOT=shot.png OBSIDON_SCREENSHOT_FRAME=40 ./bin/example.exe   # render, save PNG, quit
# add OBSIDON_SCREENSHOT_WINDOW=1 to capture the final window image (scaling + borders)
```

Rendering changes must be verified visually: take a screenshot this way and look at it.
`Graphics_Settings.debug_view` (`.Ambient_Occlusion`, `.Normals`, `.Depth`) shows intermediate buffers.
Shader compile errors panic with the full generated WGSL (line-numbered) in the log.

## Frame pipeline (frame.odin `end_frame`)

1. Shadow passes — one per sun cascade (ortho, bounding sphere of a frustum slice, texel-snapped) and one
   per shadowed spot light (perspective), into depth texture arrays. Standard Z, `LessEqual`. Each shadow
   view has its own frame uniform buffer and culls casters with its own frustum
2. Depth/normal prepass (only when SSAO is on) → SSAO → 4x4 blur
3. Main pass → HDR `RGBA16Float` (reverse-Z depth, `GreaterEqual`, clear 0). Opaque sorted by shader/material, transparent back to front
4. Post effects `Before_Tonemap` (HDR ping-pong) → bloom (threshold, downsample pyramid, additive upsample)
   → anamorphic lens streaks (`Graphics_Settings.lens_streaks`, off by default: half-res bright pass that keeps
   only the centre row of large sources and drops very large ones, width-only downsample chain, additive upsample
   tinted per level so tails shift to the tint, added onto the HDR image)
   → tonemap (+ bloom, or debug view) → LDR `RGBA8Unorm`.
   Half resolution post effects (`post_effect_add(..., half_resolution = true)`, HDR only) render into a
   half size target and are composited as `scene * color.a + color.rgb` (volumetrics)
5. Post effects `After_Tonemap` (LDR ping-pong) → 2D overlay → blit to the swapchain into the rectangle from
   `get_viewport()` (`Scaling_Mode`: `.Integer` whole-number scale + centred borders, `.Fit`, `.Stretch`).
   The window package gets the same rectangle (`sync_window_layout`) to map the cursor.
   `upscale_filter = .FSR1`: AMD FSR 1 - EASU pass (`fsr_easu.wgsl`) from the LDR buffer to a target of the
   viewport's size, RCAS sharpening (+ noise detection) in the blit; only when the buffer is enlarged on both
   axes, else bilinear. `film_grain` is added in the blit at window resolution (under the overlay). Viewport
   targets live in `update_output_targets` (targets.odin), checked every frame (resize, scaling mode).
   `.Fit` fills the window when the buffer's aspect is within a pixel of it.
   `Graphics_Settings.native_overlay`: when the viewport rectangle differs from the render buffer size, the
   overlay renders into its own target of the viewport's size (cleared transparent, premultiplied, gamma
   space) and the blit composites it over the upscaled image - sharp UI over a scaled 3D render. Overlay
   coordinates stay render-buffer pixels (`world_to_screen`, mouse); `get_overlay_scale()` gives window pixels
   per overlay pixel (rasterize fonts at that size). Screenshots then save the window image (the buffer has no UI)

## Invariants — read before changing things

- **GPU structs must match WGSL byte for byte**: `Frame_Uniforms` ↔ `Frame` (common.wgsl), `Draw_Data`,
  `Light_Data`, `Overlay_Draw_Data`, `Vertex` ↔ `Vertex_In`. `types.odin` has `#assert` sizes — update both sides together.
- **Camera-relative rendering**: world space on the GPU has the camera at the origin. Public world math is
  `f64`; model matrices are made camera-relative in f64 at `end_frame`, then cast to f32. Lights too.
- **Reverse-Z** for the camera (near = 1, far/infinity = 0); `far = 0` means infinite. The shadow map uses standard Z.
- **Colours**: public `Color` is sRGB; the engine converts to linear (`srgb_to_linear`). Lighting is linear HDR.
  The LDR targets hold gamma-encoded values; the overlay blends in gamma space.
- **Immediate mode**: draws, point/spot lights and overlay sprites are resubmitted every frame and the renderer
  keeps raw pointers to meshes/materials/textures until `end_frame` — never pass pointers to temporaries.
- Pipelines are created lazily per (shader, pass kind), so graphics settings can change at runtime
  (`apply_config` recreates targets and bind groups, only when a setting they depend on changed).
- Bind groups: surface shaders use group 0 = frame layout (frame, draws, lights, sun shadow array,
  comparison sampler, AO, spot shadow array), group 1 = material (params uniform, sampler, textures from
  binding 2). Post / internal fullscreen passes share the fullscreen layout (frame, colour, depth, linear +
  nearest samplers, bloom). A texture can't be sampled in a pass that renders into it: shadow passes bind
  dummy depth arrays, bloom passes bind black for the bloom slot.
- Draw order: commands sort by `Render_Queue` (Background in submission order, Geometry by shader/material,
  Transparent back to front).
- Vertex format has tangents (`Vertex.tangent`, glTF/MikkTSpace sign convention, uv origin top-left);
  `mesh_create` computes them when all are zero.
- **Hot reload**: all engine state lives behind pointers (`core`, renderer `state`, window/audio
  `instance`) so a newly loaded DLL can adopt it (`hot_reload_set_state`). Keep new engine state inside
  those structs, never in other package globals. Old DLLs stay loaded, so registered callbacks stay valid.
  GLFW callbacks are re-installed (`window.install_callbacks`).

## Shader builder rules (`obsidon/shader`)

- Shaders can be rebuilt in place (`shader_rebuild`); materials remap values/textures by name hash.
- Up to `MAX_PARAMS` (32) material parameters per shader (one `vec4` each in the material uniform).
- `fwidth` (screen-space derivative) is fragment only: use it to anti-alias procedural patterns.
- Textures: `texture` (2D, sampled with vec2) and `texture_3d` (volume, sampled with vec3; unset = white).
  `sample_level` picks an explicit mip - use it in raymarches, where implicit mips blur far samples.
  Post shaders get `screen_uv` from the fullscreen triangle (correct at any target size).
  Procedural `fbm` is expensive per pixel; prefer sampling a baked `texture_noise_3d` volume.
- Post shaders can reconstruct the per-pixel world view direction with `view_ray(uv)` (fog, sky effects)
  and the distance with `scene_depth(uv)` (1e30 for the sky).

- The builder is a global immediate-mode graph: `sh.begin()` … primitives … `sh.end()` → `Shader_Desc`
  with WGSL for the main, shadow and prepass variants (post shaders: one variant).
- Nodes are pure and deduplicated (CSE in `add_node`), so repeated `world_position()` calls share a varying.
- **Stage semantics**: every node runs per pixel by default. `Stage.Vertex_Only` sources (vertex attributes,
  per-draw data, `Final_World`) become varyings when the fragment stage needs them. Nodes feeding
  `set_world_position` / `set_clip_position` are emitted in the vertex shader. `Interpolate` nodes
  (`per_vertex`, `affine`, `flat`) are the only way to compute something per vertex and pass it on.
  `Fragment_Only` nodes (`frag_coord`, `dither`, `ambient_occlusion`) can't feed vertex outputs.
- Calls with separate vertex/fragment implementations use `Stage_Call` (`obs_lighting_vs` / `_fs`);
  `sample` becomes `textureSampleLevel` in the vertex stage.
- Primitives take `Arg` (`union{Value, f32}`), so numbers can be passed directly. Floats are splatted for
  component-wise WGSL calls (`splat` flag).
- New engine features usable from shaders: add a WGSL function to the library (`obs_` prefix) and a typed
  primitive in `nodes.odin`. Keep shadow/prepass correctness in mind (they reuse the vertex graph).

## Style

- Apache-2.0 header on engine files. 4-space indentation. `snake_case` procedures, `Ada_Case` types.
- Public procedures are `noun_verb` (`mesh_create`, `material_set_color`); every create/load has a destroy.
- Public angles are degrees; world math f64; GPU data f32.
- Don't add dependencies on `internal/*` from game code or from `obsidon/shader`.
