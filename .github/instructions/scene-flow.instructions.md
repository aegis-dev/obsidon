---
description: "Use when working on Obsidon scene lifecycle guidance or scene-based gameplay architecture; covers Scene callbacks, transitions, update/draw separation, and resource ownership."
---

# Obsidon Scene Flow Reference

Obsidon is scene-driven.

- `obsidon.run_game(name, buffer_width, buffer_height, scene)` owns the main loop
- Every `obsidon.Scene` must define `on_create`, `on_update`, `on_draw`, and `on_destroy`
- `on_update` returns `^Scene`
- Returning `nil` keeps the current scene
- Returning a new scene transitions and causes the previous scene to be destroyed and freed by the engine

Recommended scene structure:

- Create a concrete scene struct that `using`s `obsidon.Scene`
- Store scene-owned state and long-lived resources on that struct
- Cast from `^Scene` to the concrete scene type inside callbacks

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

Recommended split:

- `on_create`: load resources and initialize state
- `on_update`: input, simulation, timers, transitions
- `on_draw`: rendering only
- `on_destroy`: release owned resources

Simulation rules:

- Use `obsidon.get_delta_time()` for frame-rate independent simulation
- Keep movement, acceleration, timers, and interpolation in `on_update`
- Avoid rendering side effects in `on_update`

Ownership rules:

- Load scene-owned assets in `on_create`
- Release scene-owned assets in `on_destroy`
- Do not allocate new sprites, fonts, or sounds every frame