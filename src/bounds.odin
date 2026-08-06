package fovea

import "core:math/linalg"

// a bounding box is defined by the two positions that are min/max in each dimension
BoundingBox :: struct {
    min: v3,
    max: v3,
}

ray_intersect_box :: proc(
    b: BoundingBox,
    ray: Ray,
    interval: RayInterval,
) -> bool {

    interval := interval

    for a := 0; a < 3; a += 1 {
        t0 := (b.min[a] - ray.origin[a]) * ray.inv_dir[a]
        t1 := (b.max[a] - ray.origin[a]) * ray.inv_dir[a]

        if ray.inv_dir[a] < 0 {
            t0, t1 = t1, t0
        }

        if t0 > interval.t_min {
            interval.t_min = t0
        }

        if t1 < interval.t_max {
            interval.t_max = t1
        }

        if interval.t_max <= interval.t_min {
            return false
        }
    }
    return true
}

// creates the empty box, spanning min=[inf,..] to max[-inf]
// i.e. union on this and any other 'normal' box should yield the normal box
get_empty_bounds :: proc() -> BoundingBox {
    return BoundingBox {
        min = v3{PosInf, PosInf, PosInf},
        max = v3{NegInf, NegInf, NegInf},
    }
}

// compute the union of two bounding box, such that the result tightly contains both argument boxes
bounds_union :: proc(a: BoundingBox, b: BoundingBox) -> BoundingBox {
    return BoundingBox {
        min = linalg.min(a.min, b.min),
        max = linalg.max(a.max, b.max),
    }
}

// compute the size of the bounding box in all three dimensions
get_bounds_extent :: proc(bounds: BoundingBox) -> v3 {
    return bounds.max - bounds.min
}

// compute the geometric center of the box
get_bounds_centroid :: proc(bounds: BoundingBox) -> v3 {
    return bounds.min * 0.5 + bounds.max * 0.5
}

// gets the bounding box volume
get_bounds_volume :: proc(bounds: BoundingBox) -> f32 {
    ext := get_bounds_extent(bounds)
    return ext.x * ext.y * ext.z
}

// area of box
get_bounds_area :: proc(bounds: BoundingBox) -> f32 {
    ext := get_bounds_extent(bounds)
    return 2.0 * (ext.x * ext.y + ext.y * ext.z + ext.z * ext.x)
}
