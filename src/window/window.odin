package window

import "base:runtime"
import "core:c"
import "core:log"

import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

@(private)
instance: struct {
   window: glfw.WindowHandle
}

init :: proc(name: cstring) -> (window_width: u32, window_height: u32) {
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

    glfw.MakeContextCurrent(instance.window);
    glfw.SwapInterval(1);

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
}

get_window_handle :: proc() -> glfw.WindowHandle {
    return instance.window
}

// swap_buffers :: proc(s: Window) {
//     glfw.SwapBuffers(s.window);
// }

@(private)
glfw_error_callback :: proc "c" (code: i32, description: cstring) {
    context = runtime.default_context()
    log.errorf("glfw: %i: %s", code, description)
}
