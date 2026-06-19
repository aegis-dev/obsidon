---
description: "Use when working on Obsidon input or camera guidance; covers key/button helpers, UI-vs-world mouse coordinates, camera helpers, and vector math helpers used by gameplay code."
---

# Obsidon Input And Camera Reference

Input helpers:

- `obsidon.is_key_down(key)` for continuous actions
- `obsidon.is_key_pressed(key)` for edge-triggered actions
- `obsidon.is_button_down(button)` for continuous mouse button input
- `obsidon.is_button_pressed(button)` for edge-triggered mouse button input
- `obsidon.get_key_state(key)` when explicit key state is needed
- `obsidon.get_button_state(button)` when explicit mouse button state is needed

Mouse:

- `obsidon.get_mouse_position()` is screen/UI space
- `obsidon.get_mouse_absolute_position()` is world space

Use screen/UI mouse coordinates for menus and HUD interactions. Use world mouse coordinates for aiming, targeting, and other camera-relative gameplay interactions.

Camera helpers:

- `obsidon.set_camera_position(position)`
- `obsidon.get_camera_position()`
- `obsidon.set_camera_angle(angle)`
- `obsidon.get_camera_angle()`
- `obsidon.set_camera_zoom(zoom)`
- `obsidon.get_camera_zoom()`

Camera conventions:

- Keep gameplay entity positions in world space
- Move the camera instead of manually offsetting every draw call
- Use camera helpers rather than introducing a parallel camera abstraction

Gameplay math helpers:

- `obsidon.vec2_length`
- `obsidon.vec2_distance`
- `obsidon.vec2_direction`
- `obsidon.vec2_lerp`
- `obsidon.vec2_lerp_clamped`
- `obsidon.vec2_normalize`
- `obsidon.vec2_rotate`
- `obsidon.vec2_angle`

Timing rule:

- Scale movement, acceleration, and interpolation by `obsidon.get_delta_time()`