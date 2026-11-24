package main

import "core:log"
import "core:strconv"
import "core:strings"

import obsidon "../../obsidon"

// Short aliases, the same convention as the Obsidon examples.
Vec2      :: obsidon.Vec2
Vec3      :: obsidon.Vec3
Quat      :: obsidon.Quat
Color     :: obsidon.Color
Scene     :: obsidon.Scene
Mesh      :: obsidon.Mesh
Material  :: obsidon.Material
Shader    :: obsidon.Shader
Texture   :: obsidon.Texture
Transform :: obsidon.Transform
Font      :: obsidon.Font
Key       :: obsidon.Key

// Command line options for automated captures:
//   --screenshot=out.png  save a screenshot after --frames frames and quit
//   --frames=N            (default 90)
//   --view=N              fixed camera preset instead of the flight camera
//   --native              render at window resolution
//   --res=WxH             render at a custom resolution, e.g. --res=320x240
//   --window-shot         screenshot the window image (scaled, with borders)
//   --fit / --stretch     scaling mode (default: integer scaling with borders)
//   --no-ssao / --no-shadows / --no-post
//   --debug-ao / --debug-normals / --debug-depth
Options :: struct {
    screenshot: string,
    frames:     int,
    view:       int,
    native:     bool,
    no_ssao:    bool,
    no_shadows: bool,
    no_post:    bool,
    no_bloom:   bool,
    no_sun:     bool,
    resolution: [2]u32,
    scaling:    obsidon.Scaling_Mode,
    window_shot: bool,
    debug:      obsidon.Debug_View,
    // Change graphics settings at runtime every few frames (engine test).
    settings_test: bool,
}

options: ^Options

parse_options :: proc() -> ^Options {
    options := new(Options)
    options.frames = 90
    args := obsidon.command_line_args()
    for arg in args[min(1, len(args)):] {
        switch {
        case strings.has_prefix(arg, "--screenshot="): options.screenshot = arg[len("--screenshot="):]
        case strings.has_prefix(arg, "--frames="): options.frames, _ = strconv.parse_int(arg[len("--frames="):])
        case strings.has_prefix(arg, "--view="): options.view, _ = strconv.parse_int(arg[len("--view="):])
        case arg == "--native": options.native = true
        case strings.has_prefix(arg, "--res="):
            parts := strings.split(arg[len("--res="):], "x", context.temp_allocator)
            if len(parts) == 2 {
                w, _ := strconv.parse_uint(parts[0])
                h, _ := strconv.parse_uint(parts[1])
                options.resolution = {u32(w), u32(h)}
            }
        case arg == "--fit": options.scaling = .Fit
        case arg == "--window-shot": options.window_shot = true
        case arg == "--stretch": options.scaling = .Stretch
        case arg == "--no-ssao": options.no_ssao = true
        case arg == "--no-shadows": options.no_shadows = true
        case arg == "--no-post": options.no_post = true
        case arg == "--no-bloom": options.no_bloom = true
        case arg == "--no-sun": options.no_sun = true
        case arg == "--debug-ao": options.debug = .Ambient_Occlusion
        case arg == "--debug-normals": options.debug = .Normals
        case arg == "--debug-depth": options.debug = .Depth
        case arg == "--debug-cascades": options.debug = .Shadow_Cascades
        case arg == "--settings-test": options.settings_test = true
        }
    }
    return options
}

make_settings :: proc() -> obsidon.Settings {
    settings := obsidon.default_settings("Space Sim Neo")
    settings.window_mode = .Windowed
    settings.window_width = 1280
    settings.window_height = 720

    // Rendering features are plain settings.
    settings.graphics.resolution = .Native if options.native else .R640x360
    if options.resolution.x > 0 && options.resolution.y > 0 {
        settings.graphics.resolution = .Custom
        settings.graphics.custom_resolution = options.resolution
    }
    settings.graphics.scaling = options.scaling
    settings.graphics.texture_filter = .Nearest
    settings.graphics.shadows = !options.no_shadows
    settings.graphics.shadow_resolution = .R2048
    settings.graphics.shadow_distance = 150
    settings.graphics.shadow_cascades = 3
    settings.graphics.shadow_filter = .PCF_3x3
    settings.graphics.ssao = !options.no_ssao
    settings.graphics.ssao_quality = .Medium
    settings.graphics.ssao_radius = 1.5
    settings.graphics.ssao_intensity = 2.0
    settings.graphics.ssao_direct_amount = 0.6
    settings.graphics.tonemapper = .ACES
    settings.graphics.debug_view = options.debug
    settings.graphics.bloom = !options.no_bloom

    return settings
}

// PS1-style flight demo: a station deck, an asteroid belt, procedural planets
// and a flyable ship, rendered at a low resolution with dithering.
//
//     odin build examples/ps1_flight -out:bin/ps1_flight.exe
main :: proc() {
    context.logger = log.create_console_logger(.Info)
    options = parse_options()
    obsidon.set_user_data(options)
    obsidon.run_game(make_settings(), create_flight_scene())
}
