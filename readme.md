### odin for fun (and profit)

- learn and try out [Odin](https://odin-lang.org/)
- mostly a port of the [C# variant](https://github.com/siloimwald/fovea)
- still largely based on [Ray Tracing in One Weekend](https://raytracing.github.io/)
- use Lua for scene description instead of hard coding things or messing with JSON nonsense
- (not so soon) live preview with camera controls through some suitable library (SDL or whatever fits)
- attempt to make it fast
- side quest, do the same in Rust, compare which one _feels_ better

running things:

- needs recent odin installed/on the path (duh)
- uses stb from odin/vendor, need to compile that
- attempting to start without stb around will give a helpful message (just run `make` in the proper directory)
- uses [Task](https://taskfile.dev/) as a "Makefile" replacement
- run something like `task run-rel -- -scene-file=./scenes/noise.lua`

random in-progress render passing through

![texture stuff](https://github.com/siloimwald/nordic-fovea/blob/main/results/textures.png)

perlin noise, with the option to interpolate across a color band

![texture stuff](https://github.com/siloimwald/nordic-fovea/blob/main/results/noise.png)
