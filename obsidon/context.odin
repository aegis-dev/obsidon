// Copyright 2025 Egidijus Vaišvila
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

package obsidon

import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

import "internal/audio"
import "internal/renderer"
import "internal/window"

// Engine-level state. Kept behind a pointer so it can be handed over to newly
// loaded code when hot reloading (see hotreload.odin).
@(private)
Core_State :: struct {
    initialized:       bool,
    should_quit:       bool,
    delta_time:        f64,
    total_time:        f64,
    frame_count:       u64,
    start_time:        time.Time,
    last_frame_time:   time.Time,
    current_scene:     ^Scene,
    graphics_settings: Graphics_Settings,
    standard_shaders:  map[Standard_Shader_Options]Shader,
    auto_screenshot:   string,
    auto_screenshot_frame: u64,
    user_data:         rawptr,
    hot_reload:        Hot_Reload_State,
}

@(private)
core_storage: Core_State

@(private)
core: ^Core_State = &core_storage

// Starts the game loop.
// The method takes over the scene memory management.
// If the on_update function returns a new scene, the current scene will be destroyed and freed.
run_game :: proc{run_game_with_settings, run_game_simple}

run_game_with_settings :: proc(settings: Settings, scene: ^Scene) {
    init(settings, scene)
    for frame() {
    }
    shutdown()
}

// Classic Obsidon entry point: fullscreen with a fixed render resolution.
run_game_simple :: proc(name: string, buffer_width: u32, buffer_height: u32, scene: ^Scene) {
    settings := default_settings(name)
    settings.window_mode = .Fullscreen
    settings.graphics.resolution = .Custom
    settings.graphics.custom_resolution = {buffer_width, buffer_height}
    run_game_with_settings(settings, scene)
}

// ---------------------------------------------------------------------------
// Step-wise API: init, then call frame() until it returns false, then shutdown.
// run_game does exactly this; use it directly when something else owns the
// main loop (e.g. a hot reload host).
// ---------------------------------------------------------------------------

init :: proc(settings: Settings, scene: ^Scene) {
    validate_scene(scene)

    title := strings.clone_to_cstring(settings.title if settings.title != "" else "Obsidon", context.temp_allocator)
    window_width, window_height := window.init(title, settings.window_mode, settings.window_width, settings.window_height)

    core.graphics_settings = settings.graphics
    renderer.init(window.get_window_handle(), window_width, window_height, to_renderer_config(settings.graphics))
    sync_window_layout()

    audio.init()

    // Automated captures: OBSIDON_SCREENSHOT=out.png [OBSIDON_SCREENSHOT_FRAME=60]
    // renders that many frames, saves a screenshot and quits.
    // OBSIDON_SCREENSHOT_WINDOW=1 captures the window image instead of the render buffer.
    core.auto_screenshot = os.get_env("OBSIDON_SCREENSHOT", context.allocator)
    core.auto_screenshot_frame = 60
    if frame_text := os.get_env("OBSIDON_SCREENSHOT_FRAME", context.temp_allocator); frame_text != "" {
        if n, ok := strconv.parse_u64(frame_text); ok {
            core.auto_screenshot_frame = n
        }
    }

    core.current_scene = scene
    core.delta_time = 0
    core.total_time = 0
    core.frame_count = 0
    core.should_quit = false
    core.start_time = time.now()
    core.last_frame_time = core.start_time
    core.initialized = true

    core.current_scene->on_create()
}

// Runs one frame: input, on_update, on_draw, rendering.
// Returns false when the game should stop.
frame :: proc() -> bool {
    free_all(context.temp_allocator)

    if window.should_close() || core.should_quit {
        return false
    }

    window.poll_events()
    if window.consume_resize() {
        renderer.window_resized(window.get_window_width(), window.get_window_height())
        sync_window_layout()
    }

    time_now := time.now()
    core.delta_time = time.duration_seconds(time.diff(core.last_frame_time, time_now))
    core.total_time = time.duration_seconds(time.diff(core.start_time, time_now))
    core.last_frame_time = time_now
    renderer.set_time(core.total_time, core.delta_time)

    new_scene := core.current_scene->on_update()
    if core.should_quit {
        return false
    }
    if new_scene != nil {
        validate_scene(new_scene)

        core.current_scene->on_destroy()
        free(core.current_scene)

        core.current_scene = new_scene
        core.current_scene->on_create()
        return true
    }

    core.current_scene->on_draw()
    if core.auto_screenshot != "" && core.frame_count == core.auto_screenshot_frame {
        window_image := os.get_env("OBSIDON_SCREENSHOT_WINDOW", context.temp_allocator) == "1"
        renderer.request_screenshot(core.auto_screenshot, window_image)
    }
    renderer.end_frame()
    core.frame_count += 1
    if core.auto_screenshot != "" && core.frame_count > core.auto_screenshot_frame {
        return false
    }

    // Render size may change with the window (Native resolution).
    sync_window_layout()
    return true
}

shutdown :: proc() {
    if !core.initialized {
        return
    }
    if core.current_scene != nil {
        core.current_scene->on_destroy()
        free(core.current_scene)
        core.current_scene = nil
    }
    destroy_cached_shaders()
    audio.cleanup()
    renderer.cleanup()
    window.cleanup()
    delete(core.auto_screenshot)
    core.auto_screenshot = ""
    core.initialized = false
}

quit_game :: proc() {
    core.should_quit = true
}

get_delta_time :: proc() -> f64 {
    return core.delta_time
}

// Seconds since the game started.
get_time :: proc() -> f64 {
    return core.total_time
}

get_frame_count :: proc() -> u64 {
    return core.frame_count
}

get_current_scene :: proc() -> ^Scene {
    return core.current_scene
}

// A pointer the game can use for its own global state; survives hot reloads.
set_user_data :: proc(data: rawptr) {
    core.user_data = data
}

get_user_data :: proc() -> rawptr {
    return core.user_data
}

get_window_width :: proc() -> u32 {
    return window.get_window_width()
}

get_window_height :: proc() -> u32 {
    return window.get_window_height()
}

// Size of the internal render buffer (equals the window size for .Native).
get_framebuffer_width :: proc() -> u32 {
    return renderer.get_render_width()
}

get_framebuffer_height :: proc() -> u32 {
    return renderer.get_render_height()
}

// Background colour (sRGB).
set_clear_color :: proc{set_clear_color_rgba, set_clear_color_color}

set_clear_color_rgba :: proc(r: f64, g: f64, b: f64, a: f64 = 1) {
    set_clear_color_color(Color{f32(r), f32(g), f32(b), f32(a)})
}

set_clear_color_color :: proc(color: Color) {
    renderer.set_clear_color(renderer.srgb_to_linear(color))
}

// Blend the whole screen towards a colour (alpha = amount). Handy for fades and damage flashes.
set_screen_color_override :: proc(color: Color) {
    renderer.set_screen_tint(color)
}

clear_screen_color_override :: proc() {
    renderer.set_screen_tint({})
}

// Save the next rendered frame as a PNG file. By default the render buffer is
// saved at its own resolution; `window_image` saves exactly what the window
// shows (scaled, with borders).
save_screenshot :: proc(path: string, window_image := false) {
    renderer.request_screenshot(path, window_image)
}

@(private)
validate_scene :: proc(scene: ^Scene) {
    if scene.on_create == nil {
        log.panic("scene.on_create is nil")
    }
    if scene.on_update == nil {
        log.panic("scene.on_update is nil")
    }
    if scene.on_draw == nil {
        log.panic("scene.on_draw is nil")
    }
    if scene.on_destroy == nil {
        log.panic("scene.on_destroy is nil")
    }
}

// Tell the input system where the render buffer is shown (cursor mapping).
@(private)
sync_window_layout :: proc() {
    window.set_buffer_layout(renderer.get_render_width(), renderer.get_render_height(), renderer.get_viewport())
}
