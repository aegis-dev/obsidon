package obsidon

Scene :: struct {
    on_create:  proc(s: ^Scene),
    on_update:  proc(s: ^Scene) -> ^Scene,
    on_draw:    proc(s: ^Scene),
    on_destroy: proc(s: ^Scene),
}
