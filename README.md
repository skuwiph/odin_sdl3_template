# odin_sdl3_template

A playground for starting exploring SDL3 development in Odin.

From [nadako/hello-sdlgpu3-odin](https://github.com/nadako/hello-sdlgpu3-odin/tree/master)

## Notes

* object models live in `/content/meshes/` and were all sourced originally from [Kenney](kenney.nl), so no point in duplicating.
* mesh textures should live in `/content/textures/`, sourced from Kenney.NL's downloads as well.
* expects [shadercross](https://github.com/libsdl-org/SDL_shadercross) to be present on the path in order to build and compile the shaders.
* compiled shaders are created in `/content/shaders/out` as part of the build stage
