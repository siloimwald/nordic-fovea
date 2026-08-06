package fovea

import "core:flags"
import "core:fmt"
import "core:image"
import ppm "core:image/netpbm"
import "core:os"
import "core:time"

max_depth :: 50
tile_size :: 32
thread_count :: 14

CommandLineOptions :: struct {
    scene_file:      string `args:"required" usage:"scene file"`,
    samples:         int `usage:"override sample count from scene file"`,
    single_threaded: bool `usage:"use a single thread"`,
    output:          string `usage:"output file name (ppm)"`,
}

main :: proc() {

    opts := CommandLineOptions {
        output = "output.ppm",
    }

    flags.parse_or_exit(&opts, os.args)

    world, ok := read_world(opts.scene_file)

    if !ok {
        fmt.println("parsing scene file failed")
        return
    }

    // whatever we just parsed, make sure we free it
    defer delete(world.primitives)
    defer delete(world.textures)
    defer delete(world.materials)
    defer delete_meshes(world.meshes)
    defer delete_textures(world.textures)

    if opts.samples > 0 {
        world.samples_per_pixel = opts.samples
    }

    // tree traversal breaks for empty scene. Not very useful anyway...
    if len(world.primitives) == 0 {
        fmt.println("scene is empty!")
        return
    }

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

    render_world(&world, buffer, opts.single_threaded)

    fmt.println()
    time.stopwatch_stop(&sw)
    elapsed := time.stopwatch_duration(sw)

    // some napkin math performance figure
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
        ppm.save_to_file(opts.output, &img)
    } else {
        fmt.println("something went wrong trying to save the image")
    }

}
