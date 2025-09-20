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
    glfw.SetCursorPosCallback(instance.window, refresh_mouse_position)

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
}

get_window_handle :: proc() -> glfw.WindowHandle {
    return instance.window
}

is_key_down :: proc(key: Key) -> bool {
    return instance.cur_keys[key] == .Down
}

is_key_pressed :: proc(key: Key) -> bool {
    return instance.cur_keys[key] == .Down && instance.prev_keys[key] == .Up
}

is_button_down :: proc(button: Button) -> bool {
    return instance.cur_buttons[button] == .Down
}

is_button_pressed :: proc(button: Button) -> bool {
    return instance.cur_buttons[button] == .Down && instance.prev_buttons[button] == .Up
}

get_mouse_position :: proc() -> Vec2 {
    return instance.mouse_position
}

@(private)
refresh_keyboard :: proc() {
    for k in 0..<len(instance.cur_keys) {
        state := glfw.GetKey(instance.window, c.int(k))
        instance.prev_keys[k] = instance.cur_keys[k]
        if state == glfw.PRESS || state == glfw.REPEAT {
            instance.cur_keys[k] = State.Down
        } else {
            instance.cur_keys[k] = State.Up
        }
    }
}

@(private)
refresh_mouse_buttons :: proc() {
    for b in 0..<len(instance.cur_buttons) {
        state := glfw.GetMouseButton(instance.window, c.int(b))
        instance.prev_buttons[b] = instance.cur_buttons[b]
        if state == glfw.PRESS {
            instance.cur_buttons[b] = State.Down
        } else {
            instance.cur_buttons[b] = State.Up
        }
    }
}

@(private)
refresh_mouse_position :: proc "c" (w: glfw.WindowHandle, x: f64, y: f64) {
    mx := f32(x) - f32(instance.window_width) / 2.0
    my := f32(y) - f32(instance.window_height) / 2.0
    delta := Vec2{mx, my} - instance.last_mouse_position

    instance.last_mouse_position = Vec2{f32(mx), f32(my)}

    normalized := delta * instance.mouse_sensitivity
    
    instance.mouse_position -= normalized
}

@(private)
glfw_error_callback :: proc "c" (code: i32, description: cstring) {
    context = runtime.default_context()
    log.errorf("glfw: %i: %s", code, description)
}
