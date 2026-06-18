package fovea

import "core:fmt"
import "core:image"
import ppm "core:image/netpbm"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:time"

max_depth :: 50

color_ray :: proc(
    tree: BVHTree,
    materials: [dynamic]Material,
    ray: Ray,
) -> v3 {
    ray := ray
    isec := Intersection{}
    throughput := v3{1, 1, 1}
    accumulated := v3{}
    for _ in 0 ..< max_depth {
        interval := RayInterval{0.0001, 1e16}
        if intersect_bvh(tree, ray, interval, &isec) {
            ray_out := Ray{}
            attenuation := v3{}
            do_scatter := false
            switch m in materials[isec.material] {
            case Matte:
                do_scatter = evaluate_matte(
                    m,
                    ray,
                    &isec,
                    &ray_out,
                    &attenuation,
                )
            case Metal:
                do_scatter = evaluate_metal(
                    m,
                    ray,
                    &isec,
                    &ray_out,
                    &attenuation,
                )
            case Dielectric:
                do_scatter = evaluate_dielectric(
                    m,
                    ray,
                    &isec,
                    &ray_out,
                    &attenuation,
                )
            }

            if do_scatter {
                ray = ray_out
                throughput *= attenuation
            } else {
                return accumulated
            }

        } else {
            sky := linalg.lerp(
                v3{1, 1, 1},
                v3{0.5, 0.7, 1},
                (ray.direction.y + 1.0) * 0.5,
            )
            accumulated += throughput * sky
            return accumulated
        }
    }
    return accumulated
}

main :: proc() {

    // faster than the default, but still plenty "random" enough
    context.random_generator = rand.xoshiro256_random_generator()

    world, ok := read_world("./scenes/book_one_final.lua")

    if !ok {
        fmt.println("something failed")
        return
    }

    bvh := build_bvh_tree(world.geometries)
    defer delete_tree(bvh)

    buffer := make([]image.RGB_Pixel, world.image_width * world.image_height)
    defer delete(buffer)

    sw := time.Stopwatch{}
    time.stopwatch_start(&sw)

    gamma_correction := proc(ch: f32) -> u8 {
        ch := ch
        if ch > 0 {
            ch = math.sqrt(ch)
        } else {
            ch = 0
        }
        return u8(math.clamp(ch, 0, 0.9999) * 256)
    }

    fmt.printf(
        "Image %dx%d, Samples %d, Depth %d\n",
        world.image_width,
        world.image_height,
        world.samples_per_pixel,
        max_depth,
    )

    for x: u32 = 0; x < world.image_width; x += 1 {
        for y: u32 = 0; y < world.image_height; y += 1 {

            color := v3{}
            for _ in 0 ..< world.samples_per_pixel {
                ray := get_ray(world.camera, f32(x), f32(y))
                color += color_ray(bvh, world.materials, ray)
            }
            color *= (1.0 / f32(world.samples_per_pixel))
            buffer[(world.image_height - y - 1) * world.image_width + x].rgb =
                [3]u8 {
                    gamma_correction(color.r),
                    gamma_correction(color.g),
                    gamma_correction(color.b),
                }

        }
    }

    // deleting the tree takes care of deleting scene primitives
    delete(world.materials)

    time.stopwatch_stop(&sw)
    elapsed := time.stopwatch_duration(sw)

    samples_per_second :=
        f64(world.samples_per_pixel) / time.duration_seconds(elapsed)

    fmt.println(
        "Time to image",
        elapsed,
        "full-image samples per second",
        samples_per_second,
    )

    if img, ok := image.pixels_to_image(
        buffer,
        int(world.image_width),
        int(world.image_height),
    ); ok {
        ppm.save_to_file("output.ppm", &img)
    } else {
        fmt.println("something went wrong with the image")
    }

}
