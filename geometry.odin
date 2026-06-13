package fovea

import "core:math"
import "core:math/linalg"

intersect_sphere :: proc(s: Sphere, ray: Ray, interval: RayInterval, isec: ^Intersection) -> bool {
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
        set_face_normal(isec, ray.direction, (isec.location - s.center) / s.radius)
        isec.ray_t = root
        isec.material = s.material

        return true
    }
}

intersect_list :: proc(
world: []Sphere,
ray: Ray,
interval: RayInterval,
isec: ^Intersection,
) -> bool {
    any_hit := false
    current_interval := interval
    for k := 0; k < len(world); k += 1 {
        if intersect_sphere(world[k], ray, current_interval, isec) {
            any_hit = true
            current_interval.t_max = isec.ray_t
        }
    }
    return any_hit
}
