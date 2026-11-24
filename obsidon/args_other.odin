#+build !windows
package obsidon

import "core:os"

// Process command line arguments (program name first).
command_line_args :: proc() -> []string {
    return os.args
}
