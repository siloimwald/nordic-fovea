package fovea

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:slice"

PerlinNoise :: struct {
    rand_vecs: []v3,
    perm_x:    []int,
    perm_y:    []int,
    perm_z:    []int,
}

// first the book perlin noise variant
new_perlin :: proc() -> PerlinNoise {
    rand_vecs := make([]v3, 256)

    base_perm := make([]int, 256)

    for k := 0; k < 256; k = k + 1 {
        rand_vecs[k] = random_unit_vector()
        base_perm[k] = k
    }

    rand.shuffle(base_perm)
    perm_y := slice.clone(base_perm)
    rand.shuffle(base_perm)
    perm_z := slice.clone(base_perm)
    rand.shuffle(base_perm)

    return PerlinNoise {
        rand_vecs = rand_vecs,
        perm_x = base_perm,
        perm_y = perm_y,
        perm_z = perm_z,
    }
}

delete_perlin :: proc(t: ^PerlinNoise) {
    delete(t.rand_vecs)
    delete(t.perm_x)
    delete(t.perm_y)
    delete(t.perm_z)
}

@(private = "file")
get_gradient_vector :: #force_inline proc(
    nt: ^PerlinNoise,
    i: int,
    j: int,
    k: int,
) -> v3 {
    return(
        nt.rand_vecs[nt.perm_x[i & 255] ~ nt.perm_y[j & 255] ~ nt.perm_z[k & 255]] \
    )
}

evaluate_perlin :: proc(t: ^PerlinNoise, loc: v3) -> f32 {
    floored := linalg.floor(loc)
    uvw := loc - floored

    // pretty much the same as in the book, but unrolled
    // with some AI help, but makes the book algorithm much clearer
    i := int(floored.x)
    j := int(floored.y)
    k := int(floored.z)

    su := linalg.smoothstep(f32(0.0), 1.0, uvw.x)
    sv := linalg.smoothstep(f32(0.0), 1.0, uvw.y)
    sw := linalg.smoothstep(f32(0.0), 1.0, uvw.z)

    g000 := get_gradient_vector(t, i, j, k)
    g100 := get_gradient_vector(t, i + 1, j, k)
    g010 := get_gradient_vector(t, i, j + 1, k)
    g110 := get_gradient_vector(t, i + 1, j + 1, k)
    g001 := get_gradient_vector(t, i, j, k + 1)
    g101 := get_gradient_vector(t, i + 1, j, k + 1)
    g011 := get_gradient_vector(t, i, j + 1, k + 1)
    g111 := get_gradient_vector(t, i + 1, j + 1, k + 1)

    // distances to corners
    d000 := v3{uvw.x, uvw.y, uvw.z}
    d100 := v3{uvw.x - 1, uvw.y, uvw.z}
    d010 := v3{uvw.x, uvw.y - 1, uvw.z}
    d110 := v3{uvw.x - 1, uvw.y - 1, uvw.z}
    d001 := v3{uvw.x, uvw.y, uvw.z - 1}
    d101 := v3{uvw.x - 1, uvw.y, uvw.z - 1}
    d011 := v3{uvw.x, uvw.y - 1, uvw.z - 1}
    d111 := v3{uvw.x - 1, uvw.y - 1, uvw.z - 1}

    v000 := linalg.dot(g000, d000)
    v100 := linalg.dot(g100, d100)
    v010 := linalg.dot(g010, d010)
    v110 := linalg.dot(g110, d110)
    v001 := linalg.dot(g001, d001)
    v101 := linalg.dot(g101, d101)
    v011 := linalg.dot(g011, d011)
    v111 := linalg.dot(g111, d111)

    x00 := math.lerp(v000, v100, su)

    x10 := math.lerp(v010, v110, su)

    x01 := math.lerp(v001, v101, su)
    x11 := math.lerp(v011, v111, su)

    y0 := math.lerp(x00, x10, sv)
    y1 := math.lerp(x01, x11, sv)

    return math.lerp(y0, y1, sw)
}

turbulence :: proc(location: v3, n: ^PerlinNoise, depth: int) -> f32 {
    // add noise to itself for some turbulence
    accum: f32 = 0.0
    temp_p := location
    weight: f32 = 1.0

    for i := 0; i < depth; i = i + 1 {
        accum = accum + weight * evaluate_perlin(n, temp_p)
        weight = weight * 0.5
        temp_p = temp_p * 2.0
    }
    return math.abs(accum)
}
