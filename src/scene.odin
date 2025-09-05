package obsidon

Scene :: struct {
    on_create:  proc(s: ^Scene),
    on_update:  proc(s: ^Scene, delta_time: f32) -> ^Scene,
    on_draw:    proc(s: ^Scene, delta_time: f32),
    on_destroy: proc(s: ^Scene),
}
