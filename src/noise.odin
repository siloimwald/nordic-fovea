package fovea

import "core:slice"

value_noise :: proc(width: int, height: int) -> ValueNoise {
    // generate a simple width by height sized lattice/grid
    grid_points := make([]f32, width * height)

    for k := 0; k < width * height; k = k + 1 {
        grid_points[k] = random_float()
    }

    return ValueNoise{width = width, height = height, values = grid_points}
}

// first the book perlin noise variant
new_perlin :: proc(points: int) {
}
