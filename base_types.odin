package fovea

import "core:math/linalg"
import "core:math"

v4 :: linalg.Vector4f32
v3 :: linalg.Vector3f32
v2 :: linalg.Vector2f32

PosInf := math.inf_f32(1)
NegInf := math.inf_f32(-1)

RayInterval :: struct {
    t_min: f32,
    t_max: f32,
}

interval_contains :: proc(interval: RayInterval, t: f32) -> bool {
    return interval.t_min <= t && t <= interval.t_max
}

Ray :: struct {
    origin: v3,
    direction: v3,
}

ray_points_at :: proc(ray: Ray, t: f32) -> v3 {
    return ray.origin + ray.direction * t
}

Intersection :: struct {
    location: v3,
    normal: v3,
    ray_t: f32,
    material: u32,
    front_face: bool,
}

set_face_normal :: proc(isec: ^Intersection, ray_dir: v3, outward_normal: v3) {
    isec.front_face = linalg.dot(ray_dir, outward_normal) < 0
    isec.normal = outward_normal if isec.front_face else -outward_normal
}

Camera :: struct {
    width: f32,
    height: f32,
    viewport_width: f32,
    viewport_height: f32,
    cam_to_world: linalg.Matrix4f32,
    focus_distance: f32,
    lens_radius: f32,
}

near_zero :: proc(v: v3) -> bool {
    abs_v := linalg.abs(v)
    // weird odin parser or lsp things
    return(
    abs_v.x < linalg.F32_EPSILON &&
    abs_v.y < linalg.F32_EPSILON &&
    abs_v.z < linalg.F32_EPSILON \
    )
}

World :: struct {
    geometries: [dynamic]Primitive,
    materials: [dynamic]Material,
    camera: Camera,
    samples_per_pixel: u32,
    image_width: u32,
    image_height: u32,
}