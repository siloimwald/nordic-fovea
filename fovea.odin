package fovea

import "core:fmt"
import "core:image"
import ppm "core:image/netpbm"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:time"

image_width : int : 400
image_height : int : 225
max_depth : int : 50
samples_per_pixel : int : 100

color_ray :: proc(world: []Sphere, materials: []Material, ray: Ray) -> v3 {
    ray := ray
    isec := Intersection{ }
    throughput := v3{ 1, 1, 1 }
    accumulated := v3{ }
    for _ in 0 ..< max_depth {
        interval := RayInterval{ 0.0001, 1e16 }
        if intersect_list(world, ray, interval, &isec) {
            ray_out := Ray{ }
            attenuation := v3{ }
            do_scatter := false
            switch m in materials[isec.material] {
            case Matte:
                do_scatter = evaluate_matte(m, ray, &isec, &ray_out, &attenuation)
            case Metal:
                do_scatter = evaluate_metal(m, ray, &isec, &ray_out, &attenuation)
            case Dielectric:
                do_scatter = evaluate_dielectric(m, ray, &isec, &ray_out, &attenuation)
            }

            if do_scatter {
                ray = ray_out
                throughput *= attenuation
            } else {
                return accumulated
            }

        } else {
            sky := linalg.lerp(v3{ 1, 1, 1 }, v3{ 0.5, 0.7, 1 }, (ray.direction.y + 1.0) * 0.5)
            accumulated += throughput * sky
            return accumulated
        }
    }
    return accumulated
}

main :: proc() {

// faster than the default, but still plenty "random" enough
    context.random_generator = rand.xoshiro256_random_generator()

    look_at := linalg.matrix4_look_at(v3{ -2, 2, 1 }, v3{ 0, 0, -1 }, v3{ 0, 1, 0 })

    cam := make_camera(look_at, 20, 3.4, 10)

    buffer := make([]image.RGB_Pixel, image_width * image_height)
    defer delete(buffer)

    materials : []Material = {
        Matte{ v3{ 0.8, 0.8, 0.0 } }, // ground
        Matte{ v3{ 0.1, 0.2, 0.5 } }, // center
        Dielectric{ 1.5 }, // left
        Dielectric{ 1.0 / 1.5 }, // left/bubble
        Metal{ v3{ 0.8, 0.6, 0.2 }, 1 }, // right
    }

    scene : []Sphere = {
        Sphere{ center = v3{ 0, -100.5, -1 }, radius = 100, material = 0 },
        Sphere{ center = v3{ 0.0, 0.0, -1.2 }, radius = 0.5, material = 1 },
        Sphere{ center = v3{ -1, 0, -1 }, radius = 0.5, material = 2 },
        Sphere{ center = v3{ -1, 0, -1 }, radius = 0.4, material = 3 },
        Sphere{ center = v3{ 1, 0, -1 }, radius = 0.5, material = 4 },
    }

    sw := time.Stopwatch{ }
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
    image_width,
    image_height,
    samples_per_pixel,
    max_depth,
    )

    for x := 0; x < image_width; x += 1 {
        for y := 0; y < image_height; y += 1 {

            color := v3{ }
            for _ in 0 ..< samples_per_pixel {
                ray := get_ray(cam, f32(x), f32(y))
                color += color_ray(scene, materials, ray)
            }
            color *= (1.0 / f32(samples_per_pixel))
            buffer[(image_height - y - 1) * image_width + x].rgb = [3]u8 {
                gamma_correction(color.r),
                gamma_correction(color.g),
                gamma_correction(color.b),
            }

        }
    }

    time.stopwatch_stop(&sw)
    elapsed := time.stopwatch_duration(sw)

    samples_per_second := f64(samples_per_pixel) / time.duration_seconds(elapsed)

    fmt.println("Time to image", elapsed, "full-image samples per second", samples_per_second)

    if img, ok := image.pixels_to_image(buffer, image_width, image_height); ok {
        ppm.save_to_file("output.ppm", &img)
    } else {
        fmt.println("something went wrong with the image")
    }

}
