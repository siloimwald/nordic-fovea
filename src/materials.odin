package fovea

import "core:math"
import "core:math/linalg"

// the color of a material is either an index into our textures
// or a plain RGB color
MaterialAlbedo :: union {
    u32,
    v3,
}

Material :: union {
    Matte,
    Metal,
    Dielectric,
}

Matte :: struct {
    albedo: MaterialAlbedo,
}

Metal :: struct {
    albedo: MaterialAlbedo,
    fuzz:   f32,
}

Dielectric :: struct {
    ior: f32,
}

evaluate_surface_color :: proc(
    surface: MaterialAlbedo,
    textures: []Texture,
    intersection: ^Intersection,
) -> v3 {
    switch s in surface {
    case v3:
        return s
    case u32:
        return evaluate_texture(&textures[s], intersection)
    case:
        return v3{0, 0, 0}
    }
}

evaluate_matte :: proc(
    m: ^Matte,
    ray_in: Ray,
    isec: ^Intersection,
    textures: []Texture,
    ray_out: ^Ray,
    attenuation: ^v3,
) -> bool {
    scatter_direction := isec.normal + random_unit_vector()

    if near_zero(scatter_direction) {
        scatter_direction = isec.normal
    }
    ray_out^ = new_ray(isec.location, scatter_direction)
    attenuation^ = evaluate_surface_color(m.albedo, textures, isec)
    return true
}

evaluate_metal :: proc(
    m: ^Metal,
    ray_in: Ray,
    isec: ^Intersection,
    textures: []Texture,
    ray_out: ^Ray,
    attenuation: ^v3,
) -> bool {
    reflected := linalg.reflect(ray_in.direction, isec.normal)
    reflected = linalg.normalize(reflected) + (random_unit_vector() * m.fuzz)
    ray_out^ = new_ray(isec.location, reflected)
    attenuation^ = evaluate_surface_color(m.albedo, textures, isec)
    return linalg.dot(ray_out.direction, isec.normal) > 0
}

evaluate_dielectric :: proc(
    m: Dielectric,
    ray_in: Ray,
    isec: ^Intersection,
    ray_out: ^Ray,
    attenuation: ^v3,
) -> bool {
    attenuation^ = v3{1, 1, 1}
    ri := 1.0 / m.ior if isec.front_face else m.ior
    unit_dir := linalg.normalize(ray_in.direction)

    cos_theta := min(1, linalg.dot(-unit_dir, isec.normal))
    sin_theta := math.sqrt(1 - cos_theta * cos_theta)
    cannot_refract := ri * sin_theta > 1

    out_dir :=
        linalg.reflect(unit_dir, isec.normal) if cannot_refract else linalg.refract(linalg.normalize(ray_in.direction), isec.normal, ri)

    ray_out^ = new_ray(isec.location, out_dir)
    return true
}

