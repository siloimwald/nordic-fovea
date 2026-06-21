package fovea

import "core:flags"
import "core:fmt"
import "core:image"
import ppm "core:image/netpbm"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:time"

max_depth :: 50

color_ray :: proc(tree: BVHTree, ray: Ray) -> v3 {
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
            // look up material in our world which hides in the context
            world := cast(^World)context.user_ptr
            switch &m in world.materials[isec.material] {
            case Matte:
                do_scatter = evaluate_matte(
                    &m,
                    ray,
                    &isec,
                    world.textures[:],
                    &ray_out,
                    &attenuation,
                )
            case Metal:
                do_scatter = evaluate_metal(
                    &m,
                    ray,
                    &isec,
                    world.textures[:],
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

CommandLineOptions :: struct {
    scene_file: string `args:"required" usage:"scene file"`,
    samples:    u32 `usage:"override sample count from scene file"`,
}

main :: proc() {

    // faster than the default, but still plenty "random" enough
    context.random_generator = rand.xoshiro256_random_generator()

    opts: CommandLineOptions
    flags.parse_or_exit(&opts, os.args)

    world, ok := read_world(opts.scene_file)

    // odin tricks alert. Hide world as a pointer in context
    // this saves us from passing it around everywhere
    context.user_ptr = &world

    if opts.samples > 0 {
        world.samples_per_pixel = opts.samples
    }

    if !ok {
        fmt.println("something failed")
        return
    }

    defer delete(world.primitives)
    defer delete(world.textures)
    defer delete(world.materials)
    defer delete_meshes(world.meshes)

    // tree traversal breaks for empty scene. Not very useful anyway...
    if len(world.primitives) == 0 {
        fmt.println("scene is empty!")
        return
    }

    bvh := build_bvh_tree(world.primitives[:])
    defer delete(bvh.nodes)

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
                color += color_ray(bvh, ray)
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

    if img, img_ok := image.pixels_to_image(
        buffer,
        int(world.image_width),
        int(world.image_height),
    ); img_ok {
        ppm.save_to_file("output.ppm", &img)
    } else {
        fmt.println("something went wrong with the image")
    }

}

