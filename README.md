# Obsidon

A lightweight 2D game engine written in [Odin](https://odin-lang.org/) with WebGPU rendering backend.

## Features

- **Modern Rendering**: WebGPU-based renderer with sprite batching
- **Pixel Perfect Graphics**: Support for custom resolution rendering buffers (e.g., 128x128, 320x240) that scale to any window size
- **Scene System**: Flexible scene management with lifecycle callbacks
- **Input Handling**: Keyboard and mouse input support
- **Audio System**: Sound loading and playback capabilities
- **Text Rendering**: Font loading and text drawing with custom colors
- **Mathematics**: Built-in 2D vector math utilities
- **Camera System**: 2D camera with position tracking
- **Cross-Platform**: Works on Windows, macOS, and Linux

## Core Modules

- **Sprite**: 2D sprite loading, drawing, and management
- **Audio**: Sound loading and playback system
- **Input**: Keyboard and mouse input handling
- **Text/Font**: Font loading and text rendering
- **Camera**: 2D camera system
- **Scene**: Scene lifecycle management
- **Vec**: 2D vector mathematics utilities

## Extensions

Obsidon includes optional extension modules in `obsidon/extensions/` that provide additional functionality:

- **Transform**: Object transformation system for position, rotation, and scale management
- **Transform Animations**: Animation system for smooth interpolation between transform states

Extensions are designed to be lightweight and modular - use only what you need for your project.

## Philosophy

Obsidon follows a **"less is more"** philosophy:

- **Constraints breed creativity** - By providing focused, well-defined tools rather than endless options
- **Simplicity over completeness** - We prioritize ease of use and clarity over covering every possible use case
- **Intentional limitations** - Not trying to be a one-size-fits-all engine; instead focusing on 2D games and pixel art
- **Minimal but powerful** - Providing the essential building blocks that let you create without getting in your way

If you need features beyond Obsidon's scope, you're encouraged to extend it yourself or use a different tool. This keeps the core clean and focused.

## Prerequisites

- **Odin SDK**: Install the [Odin programming language](https://odin-lang.org/) and add to PATH
- **Python 3.x**: For build scripts and tooling
- **Visual Studio Code** (recommended): 
  - C/C++ Extension Pack (for debugging support)
  - Odin Language Extension

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/aegis-dev/obsidon.git
cd obsidon
```

### 2. Build and Run the Example
```bash
# Build the example
python build.py --source-dir example --output-dir bin

# Run the example (Windows)
./bin/example.exe

# Run the example (Linux/macOS)
./bin/example
```

### 3. Create Your Own Project

Create a basic main file:

```odin
package main

import "base:runtime"
import "core:log"
import obsidon "path/to/obsidon"

// Type aliases for convenience
Vec2 :: obsidon.Vec2
Scene :: obsidon.Scene
Sprite :: obsidon.Sprite

GameScene :: struct {
    using scene: Scene,
    player_sprite: Sprite,
    player_pos: Vec2,
}

scene_create :: proc(s: ^Scene) {
    scene := cast(^GameScene)s
    
    // Set background color
    obsidon.set_clear_color(0.2, 0.3, 0.4, 1.0)
    
    // Load sprites (embed asset at compile time)
    player_png: []u8 = #load("assets/player.png")
    scene.player_sprite = obsidon.sprite_load(player_png)
    scene.player_pos = Vec2{0, 0}
}

scene_update :: proc(s: ^Scene) -> ^Scene {
    scene := cast(^GameScene)s
    dt := obsidon.get_delta_time()
    
    // Handle input
    if obsidon.is_key_down(.KEY_W) do scene.player_pos.y += 100 * dt
    if obsidon.is_key_down(.KEY_S) do scene.player_pos.y -= 100 * dt
    if obsidon.is_key_down(.KEY_A) do scene.player_pos.x -= 100 * dt
    if obsidon.is_key_down(.KEY_D) do scene.player_pos.x += 100 * dt
    
    if obsidon.is_key_pressed(.KEY_ESCAPE) do obsidon.quit_game()
    
    return nil
}

scene_draw :: proc(s: ^Scene) {
    scene := cast(^GameScene)s
    
    // Draw player sprite
    origin := Vec2{f32(scene.player_sprite.width)/2, f32(scene.player_sprite.height)/2}
    obsidon.sprite_draw(&scene.player_sprite, scene.player_pos, origin, 0.0, false, 1.0)
}

scene_destroy :: proc(s: ^Scene) {
    scene := cast(^GameScene)s
    obsidon.sprite_destroy(&scene.player_sprite)
}

create_game_scene :: proc() -> ^Scene {
    scene := new(GameScene)
    scene.on_create = scene_create
    scene.on_update = scene_update  
    scene.on_draw = scene_draw
    scene.on_destroy = scene_destroy
    return scene
}

main :: proc() {
    context = runtime.default_context()
    context.logger = log.create_console_logger()
    
    scene := create_game_scene()
    obsidon.run_game("My Game", 800, 600, scene)
}
```

## API Overview

### Core Functions
```odin
// Game lifecycle
// width/height define the internal rendering resolution (e.g., 128x128 for retro games)
// The engine automatically scales to the actual window size for pixel perfect graphics
run_game(title: string, width: int, height: int, initial_scene: ^Scene)
quit_game()
get_delta_time() -> f32

// Scene management  
set_scene(scene: ^Scene)

// Rendering
set_clear_color(r, g, b, a: f32)
```

### Pixel Perfect Rendering

Obsidon supports pixel perfect graphics by allowing you to specify any internal resolution that gets automatically scaled to the window size:

```odin
// Retro 8-bit style (128x128 internal, scales to window)
obsidon.run_game("Retro Game", 128, 128, scene)

// Classic arcade resolution (320x240 internal, scales to window)  
obsidon.run_game("Arcade Game", 320, 240, scene)

// Game Boy style (160x144 internal, scales to window)
obsidon.run_game("Handheld Game", 160, 144, scene)

// Modern pixel art (480x270 internal, scales to window)
obsidon.run_game("Pixel Art Game", 480, 270, scene)
```

The engine maintains crisp pixel scaling regardless of the actual window size, making it perfect for retro-style games and pixel art.

### Sprite System
```odin
// Loading and management
sprite_load(data: []u8) -> Sprite
sprite_destroy(sprite: ^Sprite)

// Drawing
sprite_draw(sprite: ^Sprite, position: Vec2, origin: Vec2, 
           rotation: f32, flip_x: bool, scale: f32)
```

### Input System
```odin
// Keyboard
is_key_down(key: Key) -> bool
is_key_pressed(key: Key) -> bool
is_key_released(key: Key) -> bool

// Mouse
get_mouse_position() -> Vec2
is_mouse_button_down(button: Button) -> bool
```

### Audio System
```odin
sound_load_from_file(path: string) -> Sound
sound_play(sound: ^Sound)
sound_play_immediate(path: string)
```

### Text Rendering
```odin
font_load(data: []u8, size: f32) -> Font
font_destroy(font: ^Font)
text_draw(font: ^Font, text: string, position: Vec2, scale: f32, color: Vec4)
```

## Building

**Note**: The included `build.py` script is **completely optional** and provided purely for convenience. You can use any build pipeline that suits your needs - Make, CMake, shell scripts, or even direct `odin build` commands.

### Using the Convenience Script

#### Development Build
```bash
python build.py --debug --source-dir your_project --output-dir bin
```

#### Release Build  
```bash
python build.py --source-dir your_project --output-dir bin
```

#### Build Options
- `--debug`: Include debug information
- `--source-dir`: Directory containing your Odin source files
- `--output-dir`: Directory for built executable

### Manual Building

You can also build directly with Odin:

```bash
# Debug build
odin build your_project -out:bin/your_game.exe -debug

# Release build  
odin build your_project -out:bin/your_game.exe -opt:3

# With custom flags
odin build your_project -out:bin/your_game.exe -opt:3 -no-bounds-check
```

## Project Structure

```
your_project/
├── main.odin           # Entry point
├── assets/            # Game assets (images, sounds, fonts)
├── obsidon/           # Obsidon engine (as submodule or copy)
└── bin/               # Built executables
```

## Examples

Check the `example/` directory for a complete working example that demonstrates:
- Sprite loading and rendering
- Input handling (WASD movement, spacebar interaction)
- Text rendering with custom fonts
- Sound playback
- Scene management

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.

## Requirements

- **Odin**: Latest stable version
- **WebGPU**: Provided through Odin's vendor libraries
- **Platform**: Windows 10+, macOS 10.15+, or Linux with Vulkan/OpenGL support
