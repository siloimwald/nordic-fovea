package fovea

import "core:math"
import "core:math/linalg"

// this should make it easier to switch to a primitive union later, rather
// than replacing sphere all over the place
Primitive :: union {
    Sphere,
}

Sphere :: struct {
    center:   v3,
    radius:   f32,
    material: u32,
}

get_primitive_bounds :: proc(prim: Primitive) -> BoundingBox {
    switch p in prim {
    case Sphere:
        return BoundingBox {
            min = p.center - v3{p.radius, p.radius, p.radius},
            max = p.center + v3{p.radius, p.radius, p.radius},
        }
    // might as well panic
    case:
        return get_empty_bounds()
    }
}

intersect_primitive :: proc(
    prim: Primitive,
    ray: Ray,
    interval: RayInterval,
    isec: ^Intersection,
) -> bool {
    switch p in prim {
    case Sphere:
        return intersect_sphere(p, ray, interval, isec)
    case:
        return false
    }
}

@(private = "file")
intersect_sphere :: proc(
    s: Sphere,
    ray: Ray,
    interval: RayInterval,
    isec: ^Intersection,
) -> bool {
    oc := s.center - ray.origin
    a := linalg.length2(ray.direction)
    h := linalg.dot(ray.direction, oc)
    c := linalg.length2(oc) - s.radius * s.radius
    disc := h * h - a * c

    if disc < 0 {
        return false
    } else {
        d := math.sqrt(disc)
        root := (h - d) / a

        if !interval_contains(interval, root) {
            root = (h + d) / a
            if !interval_contains(interval, root) {
                return false
            }
        }

        isec.location = ray_points_at(ray, root)
        outward_normal := (isec.location - s.center) / s.radius
        // texture coordinates
        theta := math.acos(-outward_normal.y)
        phi := math.atan2(-outward_normal.z, outward_normal.x) + math.PI
        isec.tex_u = phi / (2.0 * math.PI)
        isec.tex_v = theta / math.PI
        set_face_normal(isec, ray.direction, outward_normal)
        isec.ray_t = root
        isec.material = s.material

        return true
    }
}

