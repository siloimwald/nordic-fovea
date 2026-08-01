package fovea

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"
import stbi "vendor:stb/image"

Texture :: union {
    Checker,
    ImageTexture,
    ValueNoise,
}

ImageTexture :: struct {
    width, height: int,
    channels:      int,
    pixels:        []u8,
    _data_ptr:     ^u8,
}

// limit recursion on this one
Checker :: struct {
    even:  v3,
    odd:   v3,
    scale: f32,
}

ValueNoise :: struct {
    values: []f32,
    width:  int,
    height: int,
}

delete_textures :: proc(textures: [dynamic]Texture) {
    for &tex in textures {
        #partial switch &t in tex {
        case ValueNoise:
            delete(t.values)
        case ImageTexture:
            if t._data_ptr != nil {
                stbi.image_free(t._data_ptr)
                t._data_ptr = nil
                t.pixels = nil
            }
        }
    }
}

evaluate_texture :: proc(
    texture: ^Texture,
    intersection: ^Intersection,
) -> v3 {
    switch &t in texture {
    case ImageTexture:
        tu := int(math.saturate(intersection.tex_u) * f32(t.width - 1))
        tv := int(math.saturate(intersection.tex_v) * f32(t.height - 1))
        index := tv * t.channels * t.width + tu * t.channels
        c := t.pixels[index:index + 4]
        return v3{f32(c[0]) / 255.0, f32(c[1]) / 255.0, f32(c[2]) / 255.0}
    case ValueNoise:
        scaled_u := intersection.tex_u * f32(t.width)
        scaled_v := intersection.tex_v * f32(t.height)
        x_floor := int(math.floor(scaled_u))
        y_floor := int(math.floor(scaled_v))
        x_low := x_floor %% t.width
        y_low := y_floor %% t.height
        x_high := (x_floor + 1) %% t.width
        y_high := (y_floor + 1) %% t.height
        smooth_u := math.smoothstep(f32(x_low), f32(x_high), scaled_u)
        smooth_v := math.smoothstep(f32(y_low), f32(y_high), scaled_v)
        top_lerp := math.lerp(
            t.values[y_low * t.width + x_low],
            t.values[y_low * t.width + x_high],
            smooth_u,
        )

        bottom_lerp := math.lerp(
            t.values[y_high * t.width + x_low],
            t.values[y_high * t.width + x_high],
            smooth_u,
        )
        v := math.lerp(top_lerp, bottom_lerp, smooth_v)
        return v3{v, v, v}
    case Checker:
        scaled_u := intersection.tex_u * t.scale
        scaled_v := intersection.tex_v * t.scale
        grid := linalg.floor(v2{scaled_u, scaled_v})

        is_even := (int(grid.x) + int(grid.y)) %% 2 == 0
        if is_even {
            return t.even
        }

        return t.odd

    }
    return v3{1, 0, 1} // that should not happen...
}

load_image_texture :: proc(
    file_name: string,
) -> (
    img: ImageTexture,
    ok: bool,
) {
    f_name := strings.clone_to_cstring(file_name)
    defer delete(f_name)

    if !os.exists(file_name) {
        fmt.printfln("Error: File does not exist at path: %s", file_name)
        return {}, false
    }

    w, h, c: i32
    // 4 aligns better and having alpha available doesn't hurt
    desired_channels: i32 = 4
    raw_data_ptr := stbi.load(f_name, &w, &h, &c, desired_channels)

    if raw_data_ptr == nil {

        fmt.printfln(
            "Failed to load '%s': %s",
            file_name,
            string(stbi.failure_reason()),
        )
        return {}, false
    }

    return ImageTexture {
            width = int(w),
            height = int(h),
            channels = int(desired_channels),
            pixels = raw_data_ptr[:int(w * h * desired_channels)],
            _data_ptr = raw_data_ptr,
        },
        true
}
