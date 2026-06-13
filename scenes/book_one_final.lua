-- currently needs to match the working directory cargo is run from
-- need to find some other clever way or provide it in rust directly
dofile('./scenes/scene_helpers.lua')

Scene.samples_per_pixel = 10

set_cam({ 13, 2, 3 }, { 0, 0, 0 }, { 0, 1, 0 }, 20, 10, 0.6)

off_limits = { x = 4, y = 0.2, z = 0 }

-- cannot deal (yet) with one-off/throw away materials, need unique
-- names, count up each time we use something for the random spheres
mat_counter = 0
-- random spheres
for a = -11, 10, 1 do
    for b = -11, 10, 1 do
        material = math.random()

        sphere_center = {
            x = a + 0.9 * math.random(),
            y = 0.2,
            z = b + 0.9 * math.random()
        }

        if distance(sphere_center, off_limits) > 0.9 then
            m = {}
            mat_name = string.format("material_%d", mat_counter)
            mat_counter = mat_counter + 1
            if material < 0.8 then
                matte_color = color_mix(random_3(), random_3())
                add_matte(mat_name, matte_color.x, matte_color.y, matte_color.z)
            elseif material < 0.95 then
                metal_color = random_3(0.5, 1)
                add_metal(mat_name, metal_color.x, metal_color.y, metal_color.z, math.random() * 0.5)
            else
                add_dielectric(mat_name, 1.5)
            end

            add_sphere(sphere_center.x, sphere_center.y, sphere_center.z, 0.2, mat_name)
        end
    end
end

ground = add_matte("ground", 0.5, 0.5, 0.5)

add_sphere(0, -1000, -1, 1000, ground)

-- the three non-random spheres
glass = add_dielectric("glass", 1.5)
add_sphere(0, 1, 0, 1, glass)

matte = add_matte("matte", 0.4, 0.2, 0.1)
add_sphere(-4, 1, 0, 1, matte)

metal = add_metal("metal", 0.7, 0.6, 0.5, 0)
add_sphere(4, 1, 0, 1, metal)

return Scene
