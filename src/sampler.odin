package fovea

import "core:math"
import "core:math/rand"

// generates a random point within ([-0.5,0.5), [-0.5,0.5))
sample_square :: proc() -> v2 {
    return v2{rand.float32() - 0.5, rand.float32() - 0.5}
}

// generate a random unit vector
random_unit_vector :: proc() -> v3 {
    r1 := rand.float32()
    r2 := rand.float32()
    r := math.sqrt((2 * (r2 * (1.0 - r2))))
    phi := 2.0 * math.TAU * r1
    return v3{r * math.cos(phi), r * math.sin(phi), 1.0 - 2.0 * r2}
}

// random point on unit disk
sample_unit_disk :: proc() -> v2 {
    r := math.sqrt(rand.float32())
    theta := math.PI * rand.float32() * 2.0
    return v2{r * math.cos(theta), r * math.sin(theta)}
}

random_float :: proc() -> f32 {
    return rand.float32()
}

// used to initialize xoshiro
next_splitmix :: proc(s: ^u64) -> u64 {
    s^ += 0x9e3779b97f4a7c15
    z := s^
    z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ~ (z >> 27)) * 0x94d049bb133111eb
    return z ~ (z >> 31)
}
