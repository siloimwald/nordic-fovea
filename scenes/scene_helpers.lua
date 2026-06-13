-- math helpers and scene utilities
-- include this in every scene file
-- overwrite scene top level settings as needed

Scene = {
    spheres = {},
    image_width = 400,
    image_height = 225,
    samples_per_pixel = 300,
    camera = {
        fov = 20,
        look_at = { 0, 0, -1 },
        look_from = { -2, 2, 1 },
        up = { 0, 1, 0 }
    },
    materials = {}
}

function set_cam(look_from, look_at, up, fov, focus_distance, defocus_angle)
    Scene.camera = {
        look_at = look_at,
        look_from = look_from,
        up = up or { 0, 1, 0 },
        fov = fov or 90,
        focus_distance = focus_distance or 10,
        defocus_angle = defocus_angle or 0
    }
end

function add_matte(name, r, g, b)
    Scene.materials[name] = { albedo = { r, g, b }, type = "Matte" }
    return name
end

function add_dielectric(name, ior)
    Scene.materials[name] = { ior = ior, type = "Dielectric" }
    return name
end

function add_metal(name, r, g, b, fuzz)
    Scene.materials[name] = {
        albedo = { r, g, b },
        fuzz = fuzz,
        type = "Metal"
    }
    return name
end

function add_sphere(x, y, z, radius, material)
    table.insert(Scene.spheres, {
        center = { x, y, z },
        radius = radius,
        material = material
    })
end

-- math and color helpers

function random_3(min, max)
    min = min or 0
    max = max or 1
    irange = max - min
    x = min + math.random() * irange
    y = min + math.random() * irange
    z = min + math.random() * irange
    return { x = x, y = y, z = z }
end

-- distance between point v and w
function distance(v, w)
    v_minus_w = { v.x - w.x, v.y - w.y, v.z - w.z }
    lq = v_minus_w[1] * v_minus_w[1] + v_minus_w[2] * v_minus_w[2] + v_minus_w[3] * v_minus_w[3]
    return math.sqrt(lq)
end

function color_mix(a, b)
    return { x = a.x * b.x, y = a.y * b.y, z = a.z * b.z }
end
