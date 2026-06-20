package fovea

import "core:math/linalg"

Texture :: union {
    Checker,
}

// limit recursion on this one
Checker :: struct {
    even:  v3,
    odd:   v3,
    scale: f32,
}

evaluate_texture :: proc(
    texture: ^Texture,
    intersection: ^Intersection,
) -> v3 {
    switch t in texture {
    case Checker:
        scaled_u := intersection.tex_u * t.scale
        scaled_v := intersection.tex_v * t.scale
        grid := linalg.floor(v2{scaled_u, scaled_v})

        is_even := (int(grid.x) + int(grid.y)) %% 2 == 0
        if is_even {
            return t.even
        }

        return t.odd

    }
    return v3{1, 0, 1} // that should not happen...
}

