# Obsidon Copilot Instructions

Use these instructions when working on code that imports the `obsidon` package or extends the Obsidon engine.

## Public API surface

Prefer the public API in `obsidon/obsidon/*.odin`. Do not reach into `obsidon/internal/*` from game code unless the user explicitly asks to change engine internals.

Core types commonly re-exported by games:

- `obsidon.Scene`
- `obsidon.Sprite`
- `obsidon.Font`
- `obsidon.Sound`
- `obsidon.Vec2`, `obsidon.Vec3`, `obsidon.Vec4`
- `obsidon.Key`, `obsidon.Button`, `obsidon.State`

## Scene model

Obsidon games are scene-driven.

- `obsidon.run_game(name, buffer_width, buffer_height, scene)` owns the main loop.
- A scene must provide all four callbacks on `obsidon.Scene`:
  - `on_create`
  - `on_update`
  - `on_draw`
  - `on_destroy`
- `on_update` returns `^Scene`.
- Return `nil` to stay on the current scene.
- Return a newly allocated scene to transition. Obsidon destroys and frees the previous scene automatically.
- Allocate scene state in your own scene struct that `using`s `obsidon.Scene`, then cast from `^Scene` inside callbacks.

Typical pattern:

```odin
GameScene :: struct {
    using scene: obsidon.Scene,
    player: Player,
}

scene_update :: proc(s: ^obsidon.Scene) -> ^obsidon.Scene {
    scene := cast(^GameScene)s
    _ = scene
    return nil
}
```

## Coordinate system

Obsidon uses a centered 2D coordinate system for both world and UI drawing.

- The visible center of the framebuffer is `(0, 0)`.
- Positive `x` goes right.
- Positive `y` goes up.
- Negative `y` goes down.
- Camera position is in world coordinates.
- World draw calls are transformed by the camera.
- UI draw calls are not transformed by the camera, but still use the same centered origin.

Practical consequences:

- To place something in the top-right of the screen, compute from half the framebuffer size:
  - `x = f64(obsidon.get_framebuffer_width()) * 0.5 - padding`
  - `y = f64(obsidon.get_framebuffer_height()) * 0.5 - padding`
- To move text down one line in UI space, subtract from `y`.
- `obsidon.get_mouse_position()` returns mouse coordinates in screen/UI space.
- `obsidon.get_mouse_absolute_position()` returns mouse coordinates in world space by adding camera position.

## Rendering

Prefer Obsidon helpers instead of custom renderer code.

Sprite loading and lifetime:

- Load textures from embedded PNG bytes with `obsidon.sprite_load(#load(...))`.
- Release sprite resources with `obsidon.sprite_destroy(&sprite)`.

World-space sprite drawing:

- `obsidon.sprite_draw(&sprite, position, origin, angle, flip, scale)`
- `obsidon.sprite_draw_colored(&sprite, position, origin, angle, flip, scale, color)`

UI-space sprite drawing:

- `obsidon.sprite_draw_ui(&sprite, position, origin, angle, flip, scale)`
- `obsidon.sprite_draw_ui_colored(&sprite, position, origin, angle, flip, scale, color)`

Conventions:

- Use world draw calls for game objects that should move with the camera.
- Use UI draw calls for HUD, reticles fixed to screen space, menus, and overlays.
- For centered rotation and placement, set `origin` to half sprite width and height.
- Angles are in degrees.

Screen effects:

- Set background color with `obsidon.set_clear_color(r, g, b, a)`.
- Use `obsidon.set_screen_color_override(color)` and `obsidon.clear_screen_color_override()` for full-screen tint/flash effects.

## Text

Font loading and lifetime:

- Load fonts from embedded TTF bytes with `obsidon.font_load(ttf_bytes, font_size)`.
- Release font resources with `obsidon.font_destroy(&font)`.

Drawing text:

- `obsidon.text_draw(&font, text, position, scale, color, line_spacing = 0.2, ui = false)`
- Set `ui = true` for HUD/menu text.
- Use `obsidon.text_width(&font, text, scale)` for centering or right-alignment.

Text layout notes:

- Multi-line text is supported by `text_draw`.
- `text_width` ignores line breaks and is best for single-line alignment or simple labels.

## Input

Use the input helpers from `obsidon/input.odin`.

- `obsidon.is_key_down(key)` for continuous movement/input.
- `obsidon.is_key_pressed(key)` for edge-triggered actions.
- `obsidon.is_button_down(button)` and `obsidon.is_button_pressed(button)` for mouse input.
- `obsidon.get_key_state(key)` and `obsidon.get_button_state(button)` when explicit state is needed.

Examples:

- Movement: `obsidon.is_key_down(.KEY_W)`
- Toggle or confirm: `obsidon.is_key_pressed(.KEY_SPACE)`
- Mouse world targeting: `obsidon.get_mouse_absolute_position()`

## Camera

Use the public camera helpers.

- `obsidon.set_camera_position(position)`
- `obsidon.get_camera_position()`
- `obsidon.set_camera_angle(angle)`
- `obsidon.get_camera_angle()`
- `obsidon.set_camera_zoom(zoom)`
- `obsidon.get_camera_zoom()`

Conventions:

- Keep gameplay entity positions in world space.
- Move the camera instead of offsetting every draw call manually.
- Use world mouse position for aim/look-at logic and screen mouse position for UI interactions.

## Timing and frame loop

- Use `obsidon.get_delta_time()` for frame-rate independent simulation.
- Scale velocity, acceleration, interpolation, and timers by delta time as needed.
- Call `obsidon.quit_game()` to exit the main loop.

## Audio

Current public audio API:

- `obsidon.sound_load_from_file(path)`
- `obsidon.sound_copy(&sound)`
- `obsidon.sound_play(&sound)`
- `obsidon.sound_stop(&sound)`
- `obsidon.sound_set_volume(&sound, volume)`
- `obsidon.sound_destroy(&sound)`
- `obsidon.sound_play_immediate(path)`

Audio guidance:

- Treat `sound_play_immediate` as a temporary workaround API, not the default first choice for new features.
- Prefer loading and owning `Sound` values when the normal flow works for the use case.

## Math helpers

Prefer Obsidon vector helpers before adding duplicate math utilities.

- `obsidon.vec2_distance(a, b)`
- `obsidon.vec2_direction(angle)`
- `obsidon.vec2_lerp(a, b, amount)`
- `obsidon.vec2_lerp_clamped(a, b, amount)`
- `obsidon.vec2_rotate(v, angle)`
- `obsidon.vec2_angle(v)`
- `obsidon.vec2_normalize(v)`
- `obsidon.vec2_length(v)`
- Constants: `obsidon.VEC2_ZERO`, `obsidon.VEC3_ZERO`, `obsidon.VEC4_ZERO`

## Resource lifetime rules

When you load engine-owned GPU or audio resources, also plan their destruction.

- `sprite_load` pairs with `sprite_destroy`
- `font_load` pairs with `font_destroy`
- `sound_load_from_file` pairs with `sound_destroy`

Prefer loading long-lived assets in scene or bootstrap creation code, not per-frame draw/update paths.

## Guidance for Copilot suggestions

Focused engine reference files live in `obsidon/.github/instructions/`:

- `scene-flow.instructions.md`
- `rendering-ui.instructions.md`
- `input-camera.instructions.md`
- `assets-lifecycle.instructions.md`

When proposing code for an Obsidon game:

- Import and call `obsidon` public functions instead of inventing renderer/input abstractions.
- Follow the existing scene callback pattern.
- Keep render code in `on_draw`, simulation in `on_update`, and cleanup in `on_destroy`.
- Use centered framebuffer coordinates for UI placement.
- Use world coordinates for entities and camera-aware drawing.
- Avoid adding direct dependencies on `obsidon/internal/*` from game code.