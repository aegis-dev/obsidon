---
description: "Use when working on Obsidon asset-loading or resource-lifetime guidance; covers sprite, font, and sound ownership, load/destroy pairings, and scene-aligned cleanup strategy."
---

# Obsidon Assets And Resource Lifetime Reference

Engine-owned resource pairs:

- `obsidon.sprite_load` -> `obsidon.sprite_destroy`
- `obsidon.font_load` -> `obsidon.font_destroy`
- `obsidon.sound_load_from_file` -> `obsidon.sound_destroy`

Guidelines:

- Load long-lived resources during scene setup or bootstrap flow
- Destroy resources in the owning lifecycle
- Do not load sprites, fonts, or sounds every frame
- Keep ownership explicit when resources are shared across scenes

Recommended ownership model:

- Scene-local asset: load it in that scene's `on_create`, release it in `on_destroy`
- Shared bootstrap asset: load it once in startup flow and document where cleanup occurs
- Transition-only asset: keep ownership with the transition/loading scene

Scene-aligned approach:

- `on_create`: acquire scene-owned resources
- `on_destroy`: release scene-owned resources

When documenting or generating Obsidon gameplay code, always include the matching destroy path for newly loaded resources.

Common pairings:

- `obsidon.sprite_load(#load(...))` -> `obsidon.sprite_destroy(&sprite)`
- `obsidon.font_load(ttf_bytes, size)` -> `obsidon.font_destroy(&font)`
- `obsidon.sound_load_from_file(path)` -> `obsidon.sound_destroy(&sound)`