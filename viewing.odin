package fovea

import "core:math"
import "core:math/linalg"

make_camera :: proc(
look_at: linalg.Matrix4f32,
image_width: u32,
image_height: u32,
vertical_fov: f32,
focus_distance: f32,
defocus_angle: f32,
) -> Camera {

    aspect_ratio := f32(image_width) / f32(image_height)
    h := math.tan(math.to_radians(vertical_fov / 2.0))

    viewport_height := 2 * h * focus_distance
    viewport_width := aspect_ratio * viewport_height

    cam_to_world := linalg.matrix4_inverse(look_at)

    lens_radius := focus_distance * math.tan(math.to_radians(defocus_angle / 2.0))

    return Camera {
        width = f32(image_width),
        height = f32(image_height),
        viewport_width = viewport_width,
        viewport_height = viewport_height,
        focus_distance = focus_distance,
        cam_to_world = cam_to_world,
        lens_radius = lens_radius,
    }
}

get_ray :: proc(c: Camera, px: f32, py: f32) -> Ray {
    offset := sample_square()
    ndc_x := (px + offset.x) / c.width
    ndc_y := (py + offset.y) / c.height

    cam_x := (linalg.saturate(ndc_x) - 0.5) * c.viewport_width
    cam_y := (linalg.saturate(ndc_y) - 0.5) * c.viewport_height

    cam_dir := v3{ cam_x, cam_y, -c.focus_distance }

    origin := v3{ 0, 0, 0 }

    if c.lens_radius > 0 {
        uv := sample_unit_disk() * c.lens_radius
        origin = v3{ uv.x, uv.y, 0 }
    }

    origin_world := (c.cam_to_world * v4{ origin.x, origin.y, origin.z, 1 }).xyz
    direction_world := (c.cam_to_world * v4{ cam_dir.x, cam_dir.y, cam_dir.z, 1 }).xyz - origin_world

    return Ray{ origin = origin_world, direction = linalg.normalize(direction_world) }
}
