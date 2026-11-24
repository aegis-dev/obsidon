// Copyright 2026 Egidijus Vaišvila
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

// Hot reload host.
//
// Loads a game built as a DLL and swaps in new builds while it runs. The game
// DLL exports (see obsidon/hotreload.odin and the game template in README.md):
//
//     game_init         :: proc()
//     game_frame        :: proc() -> bool          // false = quit
//     game_shutdown     :: proc()
//     game_memory       :: proc() -> rawptr        // state to hand to the next build
//     game_memory_size  :: proc() -> int           // layout fingerprint of that state
//     game_hot_reloaded :: proc(memory: rawptr) -> bool
//
// Usage: host.exe [--game=path/to/game.dll] [game arguments...]
// The host doesn't import the engine; build it once and keep it running while
// rebuilding the DLL.
package hotreload_host

import "core:dynlib"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

Game_API :: struct {
    init:         proc(),
    frame:        proc() -> bool,
    shutdown:     proc(),
    memory:       proc() -> rawptr,
    memory_size:  proc() -> int,
    hot_reloaded: proc(memory: rawptr) -> bool,

    lib:          dynlib.Library,
    write_time:   time.Time,
    version:      int,
}

main :: proc() {
    context.logger = log.create_console_logger(.Info)

    exe_dir := filepath.dir(os.args[0])
    game_path, _ := filepath.join({exe_dir, "game" + DLL_EXT})
    for arg in os.args[1:] {
        if strings.has_prefix(arg, "--game=") {
            game_path = arg[len("--game="):]
        }
    }
    remove_old_copies(game_path)

    api, ok := load_game(game_path, 0)
    if !ok {
        log.panicf("hot reload: could not load %s", game_path)
    }
    api.init()

    changed_at: time.Time
    pending := false
    for api.frame() {
        // A new build is picked up once the file stopped changing for a moment
        // (the linker may still be writing it).
        write_time, err := os.last_write_time_by_name(game_path)
        if err != nil || time.diff(api.write_time, write_time) <= 0 {
            pending = false
            continue
        }
        if !pending {
            pending = true
            changed_at = time.now()
            continue
        }
        if time.duration_milliseconds(time.since(changed_at)) < 300 {
            continue
        }
        pending = false

        new_api, loaded := load_game(game_path, api.version + 1)
        if !loaded {
            api.write_time = write_time // don't retry a broken build every frame
            continue
        }
        if new_api.memory_size() == api.memory_size() && new_api.hot_reloaded(api.memory()) {
            log.infof("hot reload: now running build %d", new_api.version)
        } else {
            log.info("hot reload: game data layout changed, restarting the game")
            api.shutdown()
            new_api.init()
        }
        // The old build stays loaded: callbacks registered by it (GPU, audio)
        // remain valid.
        api = new_api
    }
    api.shutdown()
}

when ODIN_OS == .Windows {
    DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
    DLL_EXT :: ".dylib"
} else {
    DLL_EXT :: ".so"
}

load_game :: proc(path: string, version: int) -> (api: Game_API, ok: bool) {
    write_time, err := os.last_write_time_by_name(path)
    if err != nil {
        log.errorf("hot reload: %s not found", path)
        return {}, false
    }
    // Load a copy so the original can be overwritten by the next build.
    copy_path := copy_name(path, version)
    if os.copy_file(copy_path, path) != nil {
        log.warnf("hot reload: could not copy %s (still being written?)", path)
        return {}, false
    }
    count, loaded := dynlib.initialize_symbols(&api, copy_path, "game_", "lib")
    if !loaded || count < 6 {
        log.errorf("hot reload: %s is missing exports (%s)", copy_path, dynlib.last_error())
        return {}, false
    }
    api.write_time = write_time
    api.version = version
    return api, true
}

copy_name :: proc(path: string, version: int) -> string {
    base := strings.trim_suffix(path, DLL_EXT)
    buf: [16]u8
    return strings.concatenate({base, "_hot_", itoa(buf[:], version), DLL_EXT}, context.allocator)
}

remove_old_copies :: proc(path: string) {
    for i in 0..<1000 {
        name := copy_name(path, i)
        if !os.exists(name) {
            break
        }
        os.remove(name)
    }
}

itoa :: proc(buf: []u8, value: int) -> string {
    v := value
    i := len(buf)
    for {
        i -= 1
        buf[i] = u8('0' + v % 10)
        v /= 10
        if v == 0 {
            break
        }
    }
    return string(buf[i:])
}
