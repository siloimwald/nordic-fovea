package fovea

import "core:math"
import "core:math/linalg"

Material :: union {
    Matte,
    Metal,
    Dielectric,
}

Matte :: struct {
    albedo: v3,
}

Metal :: struct {
    albedo: v3,
    fuzz: f32,
}

Dielectric :: struct {
    ior: f32,
}

evaluate_matte :: proc(
m: Matte,
ray_in: Ray,
isec: ^Intersection,
ray_out: ^Ray,
attenuation: ^v3,
) -> bool {
    scatter_direction := isec.normal + random_unit_vector()

    if near_zero(scatter_direction) {
        scatter_direction = isec.normal
    }
    ray_out^ = Ray {
        origin    = isec.location,
        direction = scatter_direction,
    }
    attenuation^ = m.albedo
    return true
}

evaluate_metal :: proc(
m: Metal,
ray_in: Ray,
isec: ^Intersection,
ray_out: ^Ray,
attenuation: ^v3,
) -> bool {
    reflected := linalg.reflect(ray_in.direction, isec.normal)
    reflected = linalg.normalize(reflected) + (random_unit_vector() * m.fuzz)
    ray_out^ = Ray {
        origin    = isec.location,
        direction = reflected,
    }
    attenuation^ = m.albedo
    return linalg.dot(ray_out.direction, isec.normal) > 0
}


evaluate_dielectric :: proc(
m: Dielectric,
ray_in: Ray,
isec: ^Intersection,
ray_out: ^Ray,
attenuation: ^v3,
) -> bool {
    attenuation^ = v3{ 1, 1, 1 }
    ri := 1.0 / m.ior if isec.front_face else m.ior
    unit_dir := linalg.normalize(ray_in.direction)

    cos_theta := min(1, linalg.dot(-unit_dir, isec.normal))
    sin_theta := math.sqrt(1 - cos_theta * cos_theta)
    cannot_refract := ri * sin_theta > 1

    out_dir :=
    linalg.reflect(unit_dir, isec.normal) if cannot_refract \
            else linalg.refract(linalg.normalize(ray_in.direction), isec.normal, ri)

    ray_out^ = Ray {
        origin    = isec.location,
        direction = out_dir,
    }
    return true
}
