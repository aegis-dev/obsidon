package example

import "core:log"

import obsidon "../../obsidon"

// Aliases for convenience
Vec2      :: obsidon.Vec2
Vec3      :: obsidon.Vec3
Color     :: obsidon.Color
Scene     :: obsidon.Scene
Mesh      :: obsidon.Mesh
Material  :: obsidon.Material
Shader    :: obsidon.Shader
Texture   :: obsidon.Texture
Sprite    :: obsidon.Sprite
Font      :: obsidon.Font
Transform :: obsidon.Transform
Key       :: obsidon.Key

main :: proc() {
    context.logger = log.create_console_logger()

    settings := obsidon.default_settings("Obsidon example")
    settings.graphics.resolution = .R640x360   // chunky pixels, scaled to the window
    settings.graphics.shadows = true
    settings.graphics.shadow_resolution = .R2048
    settings.graphics.ssao = true

    obsidon.run_game(settings, create_game_scene())
}
