package window

import "base:runtime"
import "core:c"
import "core:log"

import "vendor:glfw"

Window :: struct {
   window: glfw.WindowHandle
}

init :: proc(name: cstring) -> Window {
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
    
    win := glfw.CreateWindow(c.int(width), c.int(height), "name", nil, nil)
    if win == nil {
        log.panic("glfw: failed to create a window")
    }

    glfw.SetWindowPos(win, mx, my);

    glfw.MakeContextCurrent(win);
    glfw.SwapInterval(1);

    return Window {
        win
    }
}

cleanup :: proc(s: Window) {
    glfw.DestroyWindow(s.window)
    glfw.Terminate()
}

should_close :: proc(s: Window) -> bool {
    return bool(glfw.WindowShouldClose(s.window))
}

poll_events :: proc(s: Window) {
    glfw.PollEvents()
}

swap_buffers :: proc(s: Window) {
    glfw.SwapBuffers(s.window);
}

@(private)
glfw_error_callback :: proc "c" (code: i32, description: cstring) {
    context = runtime.default_context()
    log.errorf("glfw: %i: %s", code, description)
}
