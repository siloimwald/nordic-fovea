-- currently needs to match the working directory odin is run from
dofile('./scenes/scene_helpers.lua')

Scene.samples_per_pixel = 10
Scene.image_width = 1024
Scene.image_height = 786

Set_Cam({ -5, 5, 5 }, { 0, 0, 0 }, { 0, 0, 1 }, 30, 10, 0)

-- three planes with different checker textures on all three principal axes

local red_checker = Add_Checker("red_checker", { 0.9, 0.9, 0.9 }, { 0.8, 0.2, 0.2 }, 20)
local matte_red = Add_Matte("matte_red", red_checker)
Add_Quad(1, {-1, -1}, {1, 1}, -1, matte_red) -- Y

local blue_checker = Add_Checker("blue_checker", { 0.9 ,0.9, 0.9 },{0.2, 0.2, 0.8}, 20)
local matte_blue = Add_Matte("matte_blue", blue_checker)
Add_Quad(0, {-1, -1}, {1,1}, 1, matte_blue)

local green_checker = Add_Checker("green_checker", { 0.9, 0.9, 0.9 }, {0.2, 0.8, 0.2}, 20)
local matte_green = Add_Matte("matte_green", green_checker)
Add_Quad(2, {-1,-1}, {1,1}, -1, matte_green)

return Scene
