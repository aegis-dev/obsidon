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
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

KEY_COUNT :: i32(Key.KEY_LAST) + 1
BUTTON_COUNT :: i32(Button.MOUSE_BUTTON_LAST) + 1

@(private)
instance: struct {
    window_width: u32,
    window_height: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,

    window: glfw.WindowHandle,

    prev_keys: [KEY_COUNT]State,
    cur_keys:  [KEY_COUNT]State,
    prev_buttons: [BUTTON_COUNT]State,
    cur_buttons:  [BUTTON_COUNT]State,

    mouse_position: Vec2,
    last_mouse_position: Vec2,
    mouse_sensitivity: Vec2,
}

init :: proc(name: cstring, framebuffer_width: u32, framebuffer_height: u32) -> (window_width: u32, window_height: u32) {
    glfw.SetErrorCallback(glfw_error_callback)

    if !glfw.Init() {
        log.panic("glfw: could not be initialized")
    }

    monitor := glfw.GetPrimaryMonitor()
    if monitor == nil {
        log.panic("glfw: No primary monitor")
    }

    mode := glfw.GetVideoMode(monitor);
    width  := mode.width;
    height := mode.height;

    mx, my := glfw.GetMonitorPos(monitor);

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.DECORATED, glfw.FALSE)
    glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
    glfw.WindowHint(glfw.FOCUSED, glfw.TRUE)
    glfw.WindowHint(glfw.AUTO_ICONIFY, glfw.FALSE)
    
    instance.window = glfw.CreateWindow(c.int(width), c.int(height), "name", nil, nil)
    if instance.window == nil {
        log.panic("glfw: failed to create a window")
    }

    glfw.SetWindowPos(instance.window, mx, my);
    glfw.SetInputMode(instance.window, glfw.CURSOR, glfw.CURSOR_HIDDEN)

    instance.window_width = u32(width)
    instance.window_height = u32(height)
    instance.framebuffer_width = framebuffer_width
    instance.framebuffer_height = framebuffer_height

    instance.mouse_sensitivity = Vec2{f32(framebuffer_width) / f32(width), f32(framebuffer_height) / f32(height)}

    return u32(width), u32(height)
}

cleanup :: proc() {
    glfw.DestroyWindow(instance.window)
    glfw.Terminate()
}

should_close :: proc() -> bool {
    return bool(glfw.WindowShouldClose(instance.window))
}

poll_events :: proc() {
    glfw.PollEvents()
    refresh_keyboard()
    refresh_mouse_buttons()
    refresh_mouse_position()
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

@(private)
glfw_error_callback :: proc "c" (code: i32, description: cstring) {
    context = runtime.default_context()
    log.errorf("glfw: %i: %s", code, description)
}
