package example

import "base:runtime"

import "core:fmt"
import "core:log"

import obsidon "../obsidon"

// Aliases for convenience
Vec2 :: obsidon.Vec2
Vec4 :: obsidon.Vec4
Sprite :: obsidon.Sprite
Font :: obsidon.Font
Scene :: obsidon.Scene
Sound :: obsidon.Sound
Key :: obsidon.Key
Button :: obsidon.Button

main :: proc() {
    context = runtime.default_context()
    context.logger = log.create_console_logger()

    scene := create_game_scene()

    obsidon.run_game("game", 800, 600, scene)
}