-- currently needs to match the working directory odin is run from
dofile('./scenes/scene_helpers.lua')

Scene.samples_per_pixel = 1500
Scene.image_width = 512
Scene.image_height = 384
Scene.background = { 0.3, 0.5, 0.7 }

Set_Cam({ 13, 2, 3 }, { 0, 0, 0 }, { 0, 1, 0 }, 20, 10, 0)

-- three planes with different checker textures on all three principal axes

local noise = Add_PerlinNoise_Tex("perlinNoise", 4)

local color_band = {
    { 0.05, 0.12, 0.08 },
    { 0.12, 0.28, 0.18 },
    { 0.35, 0.50, 0.40 },
    { 0.65, 0.75, 0.70 },
    { 0.92, 0.95, 0.90 },
}

local noiseWithColorBand = Add_PerlinNoise_Tex("perlinColored", 4, color_band)
local noiseTex = Add_Matte("noiseTex", noise)
local noiseTex2 = Add_Matte("noiseTexColored", noiseWithColorBand)
Add_Quad(1, { -1000, -1000 }, { 1000, 1000 }, 0, noiseTex)
Add_Sphere({ 0, 2, 0 }, 2, noiseTex2)

return Scene
