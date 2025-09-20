package obsidon

import "renderer"

set_camera_position :: proc(position: Vec2) {
    renderer.set_camera_position(position)
}

set_camera_angle :: proc(angle: f32) {
    renderer.set_camera_angle(angle)
}

set_camera_zoom :: proc(zoom: f32) {
    renderer.set_camera_zoom(zoom)
}

get_camera_position :: proc() -> Vec2 {
    return renderer.get_camera_position()
}

get_camera_angle :: proc() -> f32 {
    return renderer.get_camera_angle()
}

get_camera_zoom :: proc() -> f32 {
    return renderer.get_camera_zoom()
}
