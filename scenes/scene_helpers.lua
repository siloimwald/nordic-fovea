-- math helpers and scene utilities
-- include this in every scene file
-- overwrite scene top level settings as needed

Scene = {
    primitives = {},
    image_width = 400,
    image_height = 225,
    samples_per_pixel = 300,
    camera = {
        fov = 20,
        look_at = { 0, 0, -1 },
        look_from = { -2, 2, 1 },
        up = { 0, 1, 0 }
    },
    textures = {},
    materials = {}
}

function Set_Cam(look_from, look_at, up, fov, focus_distance, defocus_angle)
    Scene.camera = {
        look_at = look_at,
        look_from = look_from,
        up = up or { 0, 1, 0 },
        fov = fov or 90,
        focus_distance = focus_distance or 10,
        defocus_angle = defocus_angle or 0
    }
end

function Add_Checker(name, tex_even, tex_odd, scale)
    Scene.textures[name] = { even = tex_even, odd = tex_odd, scale = scale, type = "checker" }
    return name
end

-- albedo is either a texture name as a string or a table with three floats
function Add_Matte(name, albedo)
    Scene.materials[name] = { albedo = albedo, type = "Matte" }
    return name
end

function Add_Dielectric(name, ior)
    Scene.materials[name] = { ior = ior, type = "Dielectric" }
    return name
end

-- see add_matte
function Add_Metal(name, albedo, fuzz)
    Scene.materials[name] = {
        albedo = albedo,
        fuzz = fuzz,
        type = "Metal"
    }
    return name
end

function Add_Sphere(center, radius, material)
    table.insert(Scene.primitives, {
        center = center,
        radius = radius,
        material = material,
        type = "Sphere"
    })
end

-- math and color helpers

function Random_3f(min, max)
    min = min or 0
    max = max or 1
    local irange = max - min
    local x = min + math.random() * irange
    local y = min + math.random() * irange
    local z = min + math.random() * irange
    return { x, y, z }
end

-- distance between point v and w
function Vec_Distance(v, w)
    local v_minus_w = { v[1] - w[1], v[2] - w[2], v[3] - w[3] }
    local lq = v_minus_w[1] * v_minus_w[1] + v_minus_w[2] * v_minus_w[2] + v_minus_w[3] * v_minus_w[3]
    return math.sqrt(lq)
end

function Color_Mix(a, b)
    return { a[1] * b[1], a[2] * b[2], a[3] * b[3] }
end

function Add_Quad(axis, min, max, position, material)
     table.insert(Scene.primitives, {
        axis = axis,
        min = min,
        max = max,
        position = position,
        material = material,
        type = "Quad"
    })
end
