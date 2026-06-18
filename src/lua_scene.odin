package fovea

import "core:fmt"
import linalg "core:math/linalg"
import lua "vendor:lua/5.4"

// Sadly, evaluating lua and converting it to a scene is somewhat more
// complex in odin than in rust since we cannot simply deserialize the whole thing 'magically'
// manually poking around at the stack it is, Gemini helped with this :)

read_world :: proc(file_name: cstring) -> (World, bool) {

    L := lua.L_newstate()
    lua.L_openlibs(L)
    defer lua.close(L) // free the lua side memory

    // run script file, check for lua side errors
    if lua.L_dofile(L, file_name) != 0 {
        fmt.println("Lua error: ", lua.tostring(L, -1))
        return World{}, false
    }

    // check that return value is a table
    if !lua.istable(L, -1) {
        fmt.println("unexpected scene script return value")
        return World{}, false
    }

    // read materials first, so we can assign the material index to each
    // parsed sphere right away
    lua.getfield(L, -1, "materials")
    material_names_to_index, materials := read_materials(L)
    lua.pop(L, 1)

    lua.getfield(L, -1, "spheres")
    geom := read_geometry(L, material_names_to_index)
    lua.pop(L, 1) // pop spheres

    lua.pop(L, 1) // pop root table

    // check that we've emptied the stack correctly
    stack_size := lua.gettop(L)

    if stack_size != 0 {
        fmt.println("we missed something...")
    } else {
        fmt.println("lua stack empty, all good")
    }

    fmt.println("we got", len(geom), "prims and", len(materials), "materials")

    // don't need that any longer
    delete(material_names_to_index)

    view := linalg.matrix4_look_at(v3{13, 2, 3}, v3{0, 0, 0}, v3{0, 1, 0})

    return World {
            geometries = geom,
            materials = materials,
            image_height = 225,
            image_width = 400,
            camera = make_camera(view, 400, 225, 20, 10.0, 0.6),
            samples_per_pixel = 500,
        },
        true
}

// returns a mapping of material names to indices in the slice of materials
@(private = "file")
read_materials :: proc(L: ^lua.State) -> (map[string]u32, [dynamic]Material) {

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
                    lua.getfield(L, -1, "type")
                    material_type := lua.tostring(L, -1)

                    lua.pop(L, 1) // pop material type

                    m: Material = nil

                    if material_type == "Matte" {
                        lua.getfield(L, -1, "albedo")
                        albedo := read_float_3(L)
                        lua.pop(L, 1)
                        m = Matte {
                            albedo = albedo,
                        }
                    } else if material_type == "Metal" {
                        lua.getfield(L, -1, "albedo")
                        albedo := read_float_3(L)
                        lua.pop(L, 1)
                        lua.getfield(L, -1, "fuzz")
                        fuzz := f32(lua.tonumber(L, -1))
                        lua.pop(L, 1)
                        m = Metal {
                            albedo = albedo,
                            fuzz   = fuzz,
                        }
                    } else if material_type == "Dielectric" {
                        lua.getfield(L, -1, "ior")
                        ior := f32(lua.tonumber(L, -1))
                        lua.pop(L, 1)
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
read_geometry :: proc(
    L: ^lua.State,
    material_name_to_index: map[string]u32,
) -> [dynamic]Primitive {
    if lua.istable(L, -1) {

        num_spheres := lua.L_len(L, -1)

        //        fmt.println("we seem to have", num_spheres, "spheres")

        spheres := make([dynamic]Primitive, 0, num_spheres)

        // one-based lua arrays
        for index := 1; index <= int(num_spheres); index += 1 {
            // push current sphere table onto stack
            lua.rawgeti(L, -1, lua.Integer(index))

            lua.getfield(L, -1, "radius")
            radius := f32(lua.tonumber(L, -1))
            lua.pop(L, 1)

            lua.getfield(L, -1, "material")
            material := string(lua.tostring(L, -1))
            lua.pop(L, 1)

            lua.getfield(L, -1, "center")
            center := read_float_3(L)
            lua.pop(L, 1)

            lua.pop(L, 1) // pop current sphere

            material_index, ok := material_name_to_index[material]
            if ok {
                append(
                    &spheres,
                    Sphere {
                        center = center,
                        radius = radius,
                        material = material_index,
                    },
                )
            } else {
                fmt.println("no such material", material)
            }

        }

        return spheres
    } else {
        fmt.println("state not a table in read_geomtry")
    }

    return nil
}

@(private = "file")
read_float_3 :: proc(L: ^lua.State) -> v3 {
    r := v3{}
    for index := 0; index < 3; index += 1 {
        // one based lua array
        lua.rawgeti(L, -1, lua.Integer(index + 1))
        r[index] = f32(lua.tonumber(L, -1))
        // pop from stack
        lua.pop(L, 1)
    }
    return r
}

