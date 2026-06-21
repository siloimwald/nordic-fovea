-- currently needs to match the working directory odin is run from
dofile('./scenes/scene_helpers.lua')

Scene.samples_per_pixel = 10
Scene.image_width = 1024
Scene.image_height = 786

Set_Cam({ 13, 2, 3 }, { 0, 0, 0 }, { 0, 1, 0 }, 20, 10, 0.6)

-- a plane made from two triangles with a checker-texture
-- three spheres, with image texture and noise

local ground = Add_Matte("ground", {0.5, 0.5, 0.5})
Add_Quad(1, {-20, -20}, {20, 20}, 0, ground)

-- -- the three non-random spheres
-- local glass = Add_Dielectric("glass", 1.5)
-- Add_Sphere({0, 1, 0}, 1, glass)

-- local checker_tex = Add_Checker("checker_ground", { 0.2, 0.3, 0.1 }, { 0.9, 0.9, 0.9 }, 800)
-- local matte = Add_Matte("matte", checker_tex)
-- Add_Sphere({-4, 1, 0}, 1, matte)

-- local metal = Add_Metal("metal", {0.7, 0.6, 0.5}, 0)
-- Add_Sphere({4, 1, 0}, 1, metal)

return Scene
