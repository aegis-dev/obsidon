#+build windows
package obsidon

import "core:os"
import win "core:sys/windows"

// Process command line arguments (program name first). Unlike os.args this also
// works inside a game DLL loaded by the hot reload host.
command_line_args :: proc() -> []string {
    if len(os.args) > 0 {
        return os.args
    }
    count: i32
    argv := win.CommandLineToArgvW(win.GetCommandLineW(), &count)
    if argv == nil {
        return nil
    }
    defer win.LocalFree(argv)
    args := make([]string, count)
    for i in 0..<int(count) {
        arg, _ := win.wstring_to_utf8(argv[i], -1, context.allocator)
        args[i] = arg
    }
    return args
}
