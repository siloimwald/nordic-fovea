package fovea

import "core:fmt"
import linalg "core:math/linalg"
import "core:strings"
import lua "vendor:lua/5.4"

// Sadly, evaluating lua and converting it to a scene is somewhat more
// complex in odin than in rust since we cannot simply deserialize the whole thing 'magically'
// manually poking around at the stack it is, Gemini helped with this :)

read_world :: proc(file_name: string) -> (World, bool) {

    L := lua.L_newstate()
    lua.L_openlibs(L)
    defer lua.close(L) // free the lua side memory

    f_name := strings.clone_to_cstring(file_name)
    defer delete(f_name)

    // run script file, check for lua side errors
    if lua.L_dofile(L, f_name) != 0 {
        fmt.println("Lua error: ", lua.tostring(L, -1))
        return World{}, false
    }

    // check that return value is a table
    if !lua.istable(L, -1) {
        fmt.println("unexpected scene script return value")
        return World{}, false
    }

    // read textures first, as materials might reference those by name
    lua.getfield(L, -1, "textures")
    textures_names_to_index, textures := read_textures(L)
    lua.pop(L, 1)

    // read materials first, so we can assign the material index to each
    // parsed sphere right away
    lua.getfield(L, -1, "materials")
    material_names_to_index, materials := read_materials(
        L,
        textures_names_to_index,
    )
    lua.pop(L, 1)

    lua.getfield(L, -1, "primitives")
    prims, meshes := read_primitives(L, material_names_to_index)
    lua.pop(L, 1) // pop spheres

    // image dimensions and sample count sit at up level
    h := u32(read_num_from_field(L, "image_height"))
    w := u32(read_num_from_field(L, "image_width"))
    spp := u32(read_num_from_field(L, "sampels_per_pixel"))

    lua.getfield(L, -1, "camera")
    cam := read_camera(L, w, h)
    lua.pop(L, 1)

    lua.pop(L, 1) // pop root table

    // check that we've emptied the stack correctly
    stack_size := lua.gettop(L)

    if stack_size != 0 {
        fmt.println("we missed something...")
    } else {
        fmt.println("lua stack empty, all good")
    }

    fmt.println(
        "we got",
        len(prims),
        "prims and",
        len(materials),
        "materials",
        len(textures),
        "textures",
        len(meshes),
        "meshes",
    )

    // don't need those any more
    delete(textures_names_to_index)
    delete(material_names_to_index)

    return World {
            primitives = prims,
            textures = textures,
            materials = materials,
            meshes = meshes,
            image_height = h,
            image_width = w,
            camera = cam,
            samples_per_pixel = spp,
        },
        true
}

@(private = "file")
read_camera :: proc(L: ^lua.State, w: u32, h: u32) -> Camera {
    if lua.istable(L, -1) {
        look_from := read_v3_from_field(L, "look_from")
        look_at := read_v3_from_field(L, "look_at")
        up_dir := read_v3_from_field(L, "up")

        fov := f32(read_num_from_field(L, "fov"))
        focus := f32(read_num_from_field(L, "focus_distance"))
        defocus := f32(read_num_from_field(L, "defocus_angle"))

        view := linalg.matrix4_look_at(look_from, look_at, up_dir)
        return make_camera(view, w, h, fov, focus, defocus)
    } else {
        fmt.println("camera table missing")
        return Camera{}
    }
}

// see also read_materials
@(private = "file")
read_textures :: proc(L: ^lua.State) -> (map[string]u32, [dynamic]Texture) {
    if lua.istable(L, -1) {
        textures: [dynamic]Texture
        names_to_index := make(map[string]u32)

        lua.pushnil(L)

        for lua.next(L, 2) != 0 {
            if lua.type(L, -2) == lua.TSTRING {
                texture_name := string(lua.tostring(L, -2))

                if lua.istable(L, -1) {
                    texture_type := read_str_from_field(L, "type")
                    t: Texture = nil

                    if texture_type == "checker" {
                        even_color := read_v3_from_field(L, "even")
                        odd_color := read_v3_from_field(L, "odd")
                        scale := f32(read_num_from_field(L, "scale"))
                        t = Checker {
                            even  = even_color,
                            odd   = odd_color,
                            scale = scale,
                        }
                    } else {
                        fmt.println("invalid texture type", texture_type)
                    }

                    if t != nil {
                        if texture_name in names_to_index {
                            fmt.println("duplicate texture", texture_name)
                        }
                        names_to_index[texture_name] = u32(len(textures))
                        append(&textures, t)
                    }
                }
            }
            lua.pop(L, 1)
        }
        return names_to_index, textures
    } else {
        fmt.println("state not a table in read_textures")
    }
    return nil, nil
}

// read a color/albedo for a material. If it is a string, treat it as a texture reference
// otherwise assume it is a lua table with three floats for a plain color
@(private = "file")
read_albedo :: proc(
    L: ^lua.State,
    texture_indices: map[string]u32,
) -> MaterialAlbedo {
    lua.getfield(L, -1, "albedo")
    if lua.isstring(L, -1) {
        tex_name := string(lua.tostring(L, -1))
        lua.pop(L, 1)
        // some sanity check
        if !(tex_name in texture_indices) {
            fmt.println("no such texture", tex_name)
        }
        return texture_indices[tex_name]
    }
    // plain color is assumed
    a := read_float_3(L, 3)
    lua.pop(L, 1)
    return v3{a[0], a[1], a[2]}
}

// returns a mapping of material names to indices in the slice of materials
@(private = "file")
read_materials :: proc(
    L: ^lua.State,
    texture_indices: map[string]u32,
) -> (
    map[string]u32,
    [dynamic]Material,
) {

    if lua.istable(L, -1) {

        materials: [dynamic]Material
        names_to_index := make(map[string]u32)

        lua.pushnil(L) // start iteration

        for lua.next(L, -2) != 0 {
            // pushed nil plus actual table puts us at -2
            // stack is [..., Table, Key, Value]
            if lua.type(L, -2) == lua.TSTRING {

                material_name := string(lua.tostring(L, -2))

                if lua.istable(L, -1) {
                    material_type := read_str_from_field(L, "type")

                    m: Material = nil

                    if material_type == "Matte" {
                        albedo := read_albedo(L, texture_indices)
                        m = Matte {
                            albedo = albedo,
                        }
                    } else if material_type == "Metal" {
                        albedo := read_albedo(L, texture_indices)
                        fuzz := f32(read_num_from_field(L, "fuzz"))
                        m = Metal {
                            albedo = albedo,
                            fuzz   = fuzz,
                        }
                    } else if material_type == "Dielectric" {
                        ior := f32(read_num_from_field(L, "ior"))
                        m = Dielectric {
                            ior = ior,
                        }
                    } else {
                        fmt.println("unknown material type", material_type)
                    }

                    if m != nil {

                        if material_name in names_to_index {
                            fmt.println("duplicate material", material_name)
                        }

                        names_to_index[material_name] = u32(len(materials))
                        append(&materials, m)
                    }

                } else {
                    fmt.println("invalid material")
                }
            }

            lua.pop(L, 1) // pop value, keep key for .next call
        }

        return names_to_index, materials
    } else {
        fmt.println("state not a table in read_material")
    }

    return nil, nil
}

@(private = "file")
read_primitives :: proc(
    L: ^lua.State,
    material_name_to_index: map[string]u32,
) -> (
    [dynamic]Primitive,
    [dynamic]Mesh,
) {
    if lua.istable(L, -1) {

        num_prims := lua.L_len(L, -1)

        prims := make([dynamic]Primitive, 0, num_prims)
        meshes := make([dynamic]Mesh, 0)

        // one-based lua arrays
        for index := 1; index <= int(num_prims); index += 1 {
            // push current prim table onto stack
            lua.rawgeti(L, -1, lua.Integer(index))

            prim_type := read_str_from_field(L, "type")
            // this one is shared by all of them, can do material check ahead of time
            material := read_str_from_field(L, "material")

            material_index, ok := material_name_to_index[material]

            if !ok {
                fmt.println("no such material", material)
                // bail? or just keep going?
            }

            if prim_type == "Sphere" {

                radius := f32(read_num_from_field(L, "radius"))
                center := read_v3_from_field(L, "center")

                append(
                    &prims,
                    Sphere {
                        center = center,
                        radius = radius,
                        material = material_index,
                    },
                )
            } else if prim_type == "Quad" {

                min := read_v2_from_field(L, "min")
                max := read_v2_from_field(L, "max")
                position := f32(read_num_from_field(L, "position"))
                axis := Axis(read_num_from_field(L, "axis"))
                // build mesh and extract triangles
                quad_mesh := make_quad(axis, position, min, max)
                quad_mesh.material = material_index
                append(&meshes, quad_mesh)
                // fmt.println(meshes[0])
                triangles := get_triangles_for_mesh(
                    u32(len(meshes) - 1),
                    len(quad_mesh.faces),
                )
                // we should delete triangles, no?
                append(&prims, ..triangles)
                delete(triangles)
            } else {
                fmt.println("unknown primitive type", prim_type)
            }

            lua.pop(L, 1) // pop current primitive
        }

        return prims, meshes
    } else {
        fmt.println("state not a table in read_primitives")
    }

    return nil, nil
}

// dirty reuse for v2, simply always return a [3]f32, just leave last index
// unfilled for v2
@(private = "file")
read_float_3 :: proc(L: ^lua.State, last_index: int) -> [3]f32 {
    r: [3]f32 = {0, 0, 0}
    for index := 0; index < last_index; index += 1 {
        // one based lua array
        lua.rawgeti(L, -1, lua.Integer(index + 1))
        r[index] = f32(lua.tonumber(L, -1))
        // pop from stack
        lua.pop(L, 1)
    }
    return r
}

@(private = "file")
read_num_from_field :: proc(L: ^lua.State, field_name: cstring) -> lua.Number {
    lua.getfield(L, -1, field_name)
    n := lua.tonumber(L, -1)
    lua.pop(L, 1)
    return n
}

@(private = "file")
read_v3_from_field :: proc(L: ^lua.State, field_name: cstring) -> v3 {
    lua.getfield(L, -1, field_name)
    v := read_float_3(L, 3)
    lua.pop(L, 1)
    return v
}

@(private = "file")
read_v2_from_field :: proc(L: ^lua.State, field_name: cstring) -> v2 {
    lua.getfield(L, -1, field_name)
    v := read_float_3(L, 2)
    lua.pop(L, 1)
    return v.xy
}

@(private = "file")
read_str_from_field :: proc(L: ^lua.State, field_name: cstring) -> string {
    lua.getfield(L, -1, field_name)
    r := string(lua.tostring(L, -1))
    lua.pop(L, 1)
    return r
}

