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

package window

import "base:runtime"
import "core:c"
import "core:log"

import "vendor:glfw"

KEY_COUNT :: i32(Key.KEY_LAST) + 1
BUTTON_COUNT :: i32(Button.MOUSE_BUTTON_LAST) + 1

Window_Mode :: enum {
    // Borderless window covering the primary monitor.
    Fullscreen,
    // Regular resizable window.
    Windowed,
}

Window_State :: struct {
    ctx:           runtime.Context,
    window_width:  u32,
    window_height: u32,
    window:        glfw.WindowHandle,
    resized:       bool,

    prev_keys:    [KEY_COUNT]State,
    cur_keys:     [KEY_COUNT]State,
    prev_buttons: [BUTTON_COUNT]State,
    cur_buttons:  [BUTTON_COUNT]State,

    cursor_locked:  bool,
    has_last_mouse: bool,
    last_mouse:     [2]f64,
    mouse_delta:    Vec2, // window pixels this frame, y up
    mouse_position: Vec2, // virtual cursor, render buffer pixels, centred, y up
    scroll:         Vec2,
    buffer_width:   u32,
    buffer_height:  u32,
    viewport:       [4]f32, // where the buffer is shown in the window: x, y, w, h
}

@(private)
instance_storage: Window_State

// Package state lives behind a pointer so a hot reloaded build can adopt it.
@(private)
instance: ^Window_State = &instance_storage

get_state_ptr :: proc() -> rawptr { return instance }
set_state_ptr :: proc(p: rawptr) { instance = (^Window_State)(p) }
get_state_size :: proc() -> int { return size_of(Window_State) }

init :: proc(name: cstring, mode: Window_Mode, width: u32, height: u32) -> (window_width: u32, window_height: u32) {
    instance.ctx = context
    glfw.SetErrorCallback(glfw_error_callback)

    if !glfw.Init() {
        log.panic("glfw: could not be initialized")
    }

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
    glfw.WindowHint(glfw.FOCUSED, glfw.TRUE)
    glfw.WindowHint(glfw.AUTO_ICONIFY, glfw.FALSE)

    switch mode {
    case .Fullscreen:
        monitor := glfw.GetPrimaryMonitor()
        if monitor == nil {
            log.panic("glfw: no primary monitor")
        }
        video := glfw.GetVideoMode(monitor)
        glfw.WindowHint(glfw.DECORATED, glfw.FALSE)
        instance.window = glfw.CreateWindow(video.width, video.height, name, monitor, nil)
        if instance.window != nil {
            mx, my := glfw.GetMonitorPos(monitor)
            glfw.SetWindowPos(instance.window, mx, my)
        }
    case .Windowed:
        glfw.WindowHint(glfw.DECORATED, glfw.TRUE)
        instance.window = glfw.CreateWindow(c.int(max(width, 64)), c.int(max(height, 64)), name, nil, nil)
    }
    if instance.window == nil {
        log.panic("glfw: failed to create a window")
    }

    fw, fh := glfw.GetFramebufferSize(instance.window)
    instance.window_width = u32(fw)
    instance.window_height = u32(fh)

    install_callbacks()
    if glfw.RawMouseMotionSupported() {
        glfw.SetInputMode(instance.window, glfw.RAW_MOUSE_MOTION, 1)
    }
    set_cursor_locked(true)

    return instance.window_width, instance.window_height
}

// Size of the render buffer and the window rectangle it is shown in,
// used to map the cursor into buffer coordinates.
set_buffer_layout :: proc(width: u32, height: u32, viewport: [4]f32) {
    instance.buffer_width = width
    instance.buffer_height = height
    instance.viewport = viewport
}

// (Re-)register GLFW callbacks. Called again after a hot reload so GLFW calls
// into the newly loaded code.
install_callbacks :: proc() {
    glfw.SetErrorCallback(glfw_error_callback)
    glfw.SetFramebufferSizeCallback(instance.window, on_framebuffer_size)
    glfw.SetScrollCallback(instance.window, on_scroll)
}

cleanup :: proc() {
    glfw.DestroyWindow(instance.window)
    glfw.Terminate()
}

should_close :: proc() -> bool {
    return bool(glfw.WindowShouldClose(instance.window))
}

poll_events :: proc() {
    instance.scroll = {}
    glfw.PollEvents()
    refresh_keyboard()
    refresh_mouse_buttons()
    refresh_mouse()
}

get_window_handle :: proc() -> glfw.WindowHandle {
    return instance.window
}

get_window_width :: proc() -> u32 {
    return instance.window_width
}

get_window_height :: proc() -> u32 {
    return instance.window_height
}

// Returns true once after the window size changed.
consume_resize :: proc() -> bool {
    r := instance.resized
    instance.resized = false
    return r
}

// Locked: the cursor is hidden and captured (mouse look). Unlocked: normal OS cursor.
set_cursor_locked :: proc(locked: bool) {
    instance.cursor_locked = locked
    glfw.SetInputMode(instance.window, glfw.CURSOR, glfw.CURSOR_DISABLED if locked else glfw.CURSOR_NORMAL)
    instance.has_last_mouse = false
}

is_cursor_locked :: proc() -> bool {
    return instance.cursor_locked
}

@(private)
on_framebuffer_size :: proc "c" (window: glfw.WindowHandle, width: c.int, height: c.int) {
    instance.window_width = u32(max(width, 0))
    instance.window_height = u32(max(height, 0))
    instance.resized = true
}

@(private)
on_scroll :: proc "c" (window: glfw.WindowHandle, x: f64, y: f64) {
    instance.scroll += Vec2{f32(x), f32(y)}
}

@(private)
glfw_error_callback :: proc "c" (code: i32, description: cstring) {
    context = runtime.default_context()
    log.errorf("glfw: %i: %s", code, description)
}
