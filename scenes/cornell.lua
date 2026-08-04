dofile('./scenes/scene_helpers.lua')

Scene.samples_per_pixel = 500
Scene.image_width = 512
Scene.image_height = 512

Set_Cam({ 278, 278, -800 }, { 278, 278, 0 }, { 0, 1, 0 }, 40, 10, 0)

local red = Add_Matte("red", { 0.65, 0.05, 0.05 })
local white = Add_Matte("white", { 0.73, 0.73, 0.73 })
local green = Add_Matte("green", { 0.12, 0.45, 0.15 })
local light = Add_Emissive("light", { 15, 15, 15 })

-- Add_Sphere({ 278, 278, 0 }, 278, red)

Add_Quad(0, { 0, 0 }, { 555, 555 }, 0, green)
Add_Quad(0, { 0, 0 }, { 555, 555 }, 555, red)
Add_Quad(2, {0, 0}, {555, 555}, 555, white)
Add_Quad(1, {0, 0}, {555, 555}, 555, white)
Add_Quad(1, {0, 0}, {555, 555}, 0, white)
Add_Quad(1, { 213, 228 }, { 343, 342 }, 554, light)

return Scene
