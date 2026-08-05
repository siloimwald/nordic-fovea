package fovea

import "base:runtime"
import "core:flags"
import "core:fmt"
import "core:image"
import ppm "core:image/netpbm"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:sync/chan"
import "core:thread"
import "core:time"

max_depth :: 50
tile_size :: 32
thread_count :: 14

bvh: BVHTree
gamma_correction := proc(ch: f32) -> u8 {
    ch := ch
    if ch > 0 {
        ch = math.sqrt(ch)
    } else {
        ch = 0
    }
    return u8(math.clamp(ch, 0, 0.9999) * 256)
}

// used to initialize xoshiro
next_splitmix :: proc(s: ^u64) -> u64 {
    s^ += 0x9e3779b97f4a7c15
    z := s^
    z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ~ (z >> 27)) * 0x94d049bb133111eb
    return z ~ (z >> 31)
}

consume_tile :: proc(task: thread.Task) {
    consumer_data := cast(^RenderTaskData)task.data
    recv_chan := consumer_data.recv
    image_buffer := consumer_data.image_buffer
    world := consumer_data.world

    // one rng per task/thread
    rng_state: rand.Xoshiro256_Random_State
    // mesh primitives access world through the context to get at the mesh vertices
    context.user_ptr = world

    for {
        next_tile, ok := chan.recv(recv_chan)
        switch t in next_tile {
        case Tile:
            // AI bits: initialize rng for every tile a-new to have some initial
            // state that's spatially correlated. Otherwise spawning all tasks and using
            // a time-based seed will yield too similar random numbers, *probably*
            seed := u64(t.start_x * 73856093) ~ u64(t.start_y * 19349663)

            sm_state := seed

            rng_state.s[0] = next_splitmix(&sm_state)
            rng_state.s[1] = next_splitmix(&sm_state)
            rng_state.s[2] = next_splitmix(&sm_state)
            rng_state.s[3] = next_splitmix(&sm_state)

            // Override the context for this specific task
            context.random_generator = rand.xoshiro256_random_generator(
                &rng_state,
            )

            for t_x := t.start_x; t_x < t.width; t_x = t_x + 1 {
                for t_y := t.start_y; t_y < t.height; t_y = t_y + 1 {
                    color := v3{}
                    for s in 0 ..< world.samples_per_pixel {
                        ray := get_ray(world.camera, f32(t_x), f32(t_y))
                        color += color_ray(world, bvh, ray)

                    }

                    color *= (1.0 / f32(world.samples_per_pixel))

                    image_buffer[(t.image_height - t_y - 1) * t.image_width + t_x].rgb =
                        [3]u8 {
                            gamma_correction(color.r),
                            gamma_correction(color.g),
                            gamma_correction(color.b),
                        }
                }
            }
        case StopTile:
            return
        }

    }
}

produce_tile :: proc(task: thread.Task) {
    producer_data := cast(^ProducerData)task.data
    image_width := producer_data.image_width
    image_height := producer_data.image_height
    send_chan := producer_data.send
    for px := 0; px < image_width; px = px + tile_size {
        for py := 0; py < image_height; py = py + tile_size {
            next_tile := Tile {
                    start_x      = px,
                    start_y      = py,
                    width        = math.min(px + tile_size, image_width),
                    height       = math.min(py + tile_size, image_height),
                    image_width  = image_width,
                    image_height = image_height,
                }

            ok := chan.send(send_chan, next_tile)
            if !ok {
                return
            }
        }
    }

    for t := 0; t < thread_count; t = t + 1 {
        chan.send(send_chan, StopTile{})
    }

}

RenderTaskData :: struct {
    recv:         chan.Chan(RenderTaskWorkItem, .Recv),
    image_buffer: []image.RGB_Pixel,
    world:        ^World,
}

ProducerData :: struct {
    send:                      chan.Chan(RenderTaskWorkItem, .Send),
    image_width, image_height: int,
}

Tile :: struct {
    start_x, start_y, width, height: int,
    // pass these along to correctly compute image buffer positions, does not hurt
    image_width, image_height:       int,
}

// sentinel value on tile channel
StopTile :: struct {}

RenderTaskWorkItem :: union {
    Tile,
    StopTile,
}

color_ray :: proc(world: ^World, tree: BVHTree, ray: Ray) -> v3 {
    ray := ray
    isec := Intersection{}
    throughput := v3{1, 1, 1}
    accumulated := v3{}

    for _ in 0 ..< max_depth {
        interval := RayInterval{0.0001, 1e16}
        if intersect_bvh(tree, ray, interval, &isec) {
            // if intersect_list(tree, ray, interval, &isec) {
            ray_out := Ray{}
            attenuation := v3{}

            emission := evaluate_emission(
                &world.materials[isec.material],
                &isec,
                world.textures[:],
            )

            accumulated += (throughput * emission)

            do_scatter := evaluate_material(
                &world.materials[isec.material],
                ray,
                &isec,
                world.textures[:],
                &ray_out,
                &attenuation,
            )

            if do_scatter {
                ray = ray_out
                throughput *= attenuation
            } else {
                return accumulated
            }

        } else {
            accumulated += throughput * world.background
            return accumulated
        }
    }
    return accumulated
}

CommandLineOptions :: struct {
    scene_file: string `args:"required" usage:"scene file"`,
    samples:    int `usage:"override sample count from scene file"`,
}

main :: proc() {

    // faster than the default, but still plenty "random" enough
    context.random_generator = rand.xoshiro256_random_generator()

    opts: CommandLineOptions
    flags.parse_or_exit(&opts, os.args)

    world, ok := read_world(opts.scene_file)

    if !ok {
        fmt.println("something failed")
        return
    }

    // odin tricks alert. Hide world as a pointer in context
    // this saves us from passing it around everywhere
    context.user_ptr = &world

    if opts.samples > 0 {
        world.samples_per_pixel = opts.samples
    }

    defer delete(world.primitives)
    defer delete(world.textures)
    defer delete(world.materials)
    defer delete_meshes(world.meshes)
    defer delete_textures(world.textures)

    // tree traversal breaks for empty scene. Not very useful anyway...
    if len(world.primitives) == 0 {
        fmt.println("scene is empty!")
        return
    }

    bvh = build_bvh_tree(world.primitives[:])
    defer delete(bvh.nodes)

    buffer := make([]image.RGB_Pixel, world.image_width * world.image_height)
    defer delete(buffer)

    sw := time.Stopwatch{}
    time.stopwatch_start(&sw)

    fmt.printf(
        "Image %dx%d, Samples %d, Depth %d\n",
        world.image_width,
        world.image_height,
        world.samples_per_pixel,
        max_depth,
    )

    // thread pool stuff

    pool: thread.Pool

    pool_allocator := context.allocator
    thread.pool_init(&pool, pool_allocator, thread_count)
    thread.pool_start(&pool)
    defer thread.pool_destroy(&pool)

    tile_channel, err := chan.create(
        chan.Chan(RenderTaskWorkItem),
        1000,
        context.allocator,
    )
    assert(err == .None)
    defer chan.destroy(tile_channel)

    send_end := chan.as_send(tile_channel)
    receive_end := chan.as_recv(tile_channel)

    producer_data := ProducerData {
        image_width  = world.image_width,
        image_height = world.image_height,
        send         = send_end,
    }

    consumer_data := RenderTaskData {
        recv         = receive_end,
        image_buffer = buffer,
        world        = &world,
    }
    thread.pool_add_task(
        &pool,
        runtime.nil_allocator(),
        produce_tile,
        &producer_data,
    )
    for t := 0; t < thread_count; t = t + 1 {
        thread.pool_add_task(
            &pool,
            context.allocator,
            consume_tile,
            &consumer_data,
        )
    }
    thread.pool_finish(&pool)
    // for x: u32 = 0; x < world.image_width; x += 1 {
    //     for y: u32 = 0; y < world.image_height; y += 1 {

    //         color := v3{}
    //         for _ in 0 ..< world.samples_per_pixel {
    //             ray := get_ray(world.camera, f32(x), f32(y))
    //             color += color_ray(bvh, ray)
    //         }
    //         color *= (1.0 / f32(world.samples_per_pixel))
    //         buffer[(world.image_height - y - 1) * world.image_width + x].rgb =
    //             [3]u8 {
    //                 gamma_correction(color.r),
    //                 gamma_correction(color.g),
    //                 gamma_correction(color.b),
    //             }

    //     }
    //     // some basic progress reporting...
    //     p_done := 100 * f32(x) / f32(world.image_width)
    //     fmt.printf("\r %.2f %%", p_done)
    // }

    fmt.println()
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
