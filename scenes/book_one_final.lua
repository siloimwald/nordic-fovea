-- currently needs to match the working directory odin is run from
dofile('./scenes/scene_helpers.lua')

Scene.samples_per_pixel = 10
Scene.image_width = 1024
Scene.image_height = 786

Set_Cam({ 13, 2, 3 }, { 0, 0, 0 }, { 0, 1, 0 }, 20, 10, 0.6)

local off_limits = { 4, 0.2, 0 }

-- cannot deal (yet) with one-off/throw away materials, need unique
-- names, count up each time we use something for the random spheres
local mat_counter = 0
-- random spheres
for a = -11, 10, 1 do
    for b = -11, 10, 1 do
        local material = math.random()

        local sphere_center = {
            a + 0.9 * math.random(),
            0.2,
            b + 0.9 * math.random()
        }

        if Vec_Distance(sphere_center, off_limits) > 0.9 then
            local mat_name = string.format("material_%d", mat_counter)
            mat_counter = mat_counter + 1
            if material < 0.8 then
                local matte_color = Color_Mix(Random_3f(), Random_3f())
                Add_Matte(mat_name, matte_color)
            elseif material < 0.95 then
                local metal_color = Random_3f(0.5, 1)
                Add_Metal(mat_name, metal_color, math.random() * 0.5)
            else
                Add_Dielectric(mat_name, 1.5)
            end

            Add_Sphere(sphere_center, 0.2, mat_name)
        end
    end
end

local ground = Add_Matte("ground", {0.5, 0.5, 0.5})
Add_Sphere({0, -1000, -1}, 1000, ground)

-- the three non-random spheres
local glass = Add_Dielectric("glass", 1.5)
Add_Sphere({0, 1, 0}, 1, glass)

local checker_tex = Add_Checker("checker_ground", { 0.2, 0.3, 0.1 }, { 0.9, 0.9, 0.9 }, 800)
local matte = Add_Matte("matte", checker_tex)
Add_Sphere({-4, 1, 0}, 1, matte)

local metal = Add_Metal("metal", {0.7, 0.6, 0.5}, 0)
Add_Sphere({4, 1, 0}, 1, metal)

return Scene
