-- currently needs to match the working directory odin is run from
dofile('./scenes/scene_helpers.lua')

Scene.samples_per_pixel = 200
Scene.image_width = 512
Scene.image_height = 384

Set_Cam({ 0, 0, 5 }, { 0, 0, 0 }, { 0, 1, 0 }, 25, 10, 0)

-- three planes with different checker textures on all three principal axes

local valueNoise = Add_ValueNoise_Tex("value_noise", 256, 256)
local noiseTex = Add_Matte("noiseTex", valueNoise)
Add_Quad(2, {-1, -1}, {1, 1}, 0, noiseTex)

return Scene
