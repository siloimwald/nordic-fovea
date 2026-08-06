#+private file
package fovea

import "base:runtime"
import "core:fmt"
import "core:image"
import "core:math"
import "core:math/rand"
import "core:sync/chan"
import "core:thread"

bvh_tree: BVHTree

// center piece goes on top
color_ray :: proc(ray: Ray) -> v3 {
    ray := ray
    isec := Intersection{}
    throughput := v3{1, 1, 1}
    accumulated := v3{}

    // extract world from context user data
    world := cast(^World)context.user_ptr

    for _ in 0 ..< max_depth {
        interval := RayInterval{0.0001, 1e16}
        if intersect_bvh(bvh_tree, ray, interval, &isec) {
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

// render the scene into the given image buffer
@(private) // explictly expose this one
render_world :: proc(
    world: ^World,
    image_buffer: []image.RGB_Pixel,
    single_thread: bool,
) {

    // odin tricks alert. Hide world as a pointer in context
    // this saves us from passing it around everywhere
    context.user_ptr = world

    bvh_tree = build_bvh_tree(world.primitives[:])
    defer delete(bvh_tree.nodes)

    if single_thread {
        fmt.println("using a single thread...")
        render_single_threaded(world, image_buffer)
    } else {
        render_multi_threaded(world, image_buffer)
    }
}

// data passed to a single render task/thread
RenderTaskData :: struct {
    // channel producing image tiles/sections to render
    recv:         chan.Chan(RenderTaskWorkItem, .Recv),
    // target image buffer
    image_buffer: []image.RGB_Pixel,
    // all the jazz, materials, textures
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

// sentinel value on tile channel, receiving this tells consumer tasks to stop
StopTile :: struct {}

RenderTaskWorkItem :: union {
    Tile,
    StopTile,
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

// main rendering loop/threading goes here
consume_tile :: proc(task: thread.Task) {
    consumer_data := cast(^RenderTaskData)task.data
    recv_chan := consumer_data.recv
    image_buffer := consumer_data.image_buffer
    world := consumer_data.world

    // one rng per task/thread
    rng_state: rand.Xoshiro256_Random_State
    // mesh primitives such as quads access world through the context to get at the mesh vertices
    context.user_ptr = world

    for {
        next_tile, ok := chan.recv(recv_chan)

        if !ok {
            return
        }

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
                    for _ in 0 ..< world.samples_per_pixel {
                        ray := get_ray(world.camera, f32(t_x), f32(t_y))
                        color += color_ray(ray)

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

render_multi_threaded :: proc(world: ^World, image_buffer: []image.RGB_Pixel) {
    // setup the whole thread/task pool
    pool: thread.Pool

    pool_allocator := context.allocator
    thread.pool_init(&pool, pool_allocator, thread_count)
    thread.pool_start(&pool)
    defer thread.pool_destroy(&pool)

    tile_channel, err := chan.create(
            chan.Chan(RenderTaskWorkItem),
            1000, // could do some napkin math to figure out the upper bounds on the tiles
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
            image_buffer = image_buffer,
            world        = world,
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
            runtime.nil_allocator(),
            consume_tile,
            &consumer_data,
        )
    }

    // wait for all tasks to finish
    thread.pool_finish(&pool)
}

render_single_threaded :: proc(
    world: ^World,
    image_buffer: []image.RGB_Pixel,
) {

    // faster than the default, good enough for rendering
    context.random_generator = rand.xoshiro256_random_generator()

    for x := 0; x < world.image_width; x += 1 {
        for y := 0; y < world.image_height; y += 1 {

            color := v3{}
            for _ in 0 ..< world.samples_per_pixel {
                ray := get_ray(world.camera, f32(x), f32(y))
                color += color_ray(ray)
            }
            color *= (1.0 / f32(world.samples_per_pixel))
            image_buffer[(world.image_height - y - 1) * world.image_width + x].rgb =
                [3]u8 {
                    gamma_correction(color.r),
                    gamma_correction(color.g),
                    gamma_correction(color.b),
                }

        }
        // some basic progress reporting...
        p_done := 100 * f32(x) / f32(world.image_width)
        fmt.printf("\r %.2f %%", p_done)
    }
}

gamma_correction := proc(ch: f32) -> u8 {
    ch := ch
    if ch > 0 {
        ch = math.sqrt(ch)
    } else {
        ch = 0
    }
    return u8(math.clamp(ch, 0, 0.9999) * 256)
}
