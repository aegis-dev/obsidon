---
description: "Use when working on Obsidon rendering guidance; covers world-space vs UI-space drawing, centered coordinates, text rendering, framebuffer-relative HUD layout, and sprite/font lifetime."
---

# Obsidon Rendering And UI Reference

Coordinate system:

- `(0, 0)` is the framebuffer center
- Positive `x` goes right
- Positive `y` goes up
- Negative `y` goes down
- World and UI drawing both use centered coordinates
- UI drawing ignores camera transforms

World rendering:

- `obsidon.sprite_draw(&sprite, position, origin, angle, flip, scale)`
- `obsidon.sprite_draw_colored(&sprite, position, origin, angle, flip, scale, color)`
- World draw calls are camera-transformed

Use world draw calls for entities, projectiles, cursors in world space, and anything else that should move with the camera.

UI rendering:

- `obsidon.sprite_draw_ui(&sprite, position, origin, angle, flip, scale)`
- `obsidon.sprite_draw_ui_colored(&sprite, position, origin, angle, flip, scale, color)`
- `obsidon.text_draw(..., ui=true)`
- UI space is centered and camera-independent

Use UI draw calls for HUD, menus, overlays, and screen-fixed reticles.

Text:

- `obsidon.font_load(ttf_bytes, font_size)`
- `obsidon.font_destroy(&font)`
- `obsidon.text_draw(&font, text, position, scale, color, line_spacing = 0.2, ui = false)`
- `obsidon.text_width(&font, text, scale)`

Text notes:

- Multi-line text is supported by `text_draw`
- `text_width` is mainly useful for single-line alignment and simple labels

Placement guidance:

- Compute HUD edges from half framebuffer width and height
- Use sprite half extents as origin for centered placement and rotation
- To place HUD text in the top-right, compute from half extents instead of using top-left coordinates

Resource pairings:

- `obsidon.sprite_load(#load(...))` -> `obsidon.sprite_destroy(&sprite)`
- `obsidon.font_load(...)` -> `obsidon.font_destroy(&font)`

Rendering conventions:

- Angles are in degrees
- Use `obsidon.set_clear_color(r, g, b, a)` for background color
- Use `obsidon.set_screen_color_override(color)` and `obsidon.clear_screen_color_override()` for full-screen tint effects