# Kkitris

Zig + Vulkan + GLFW Tetris clone.

## Prerequisites

- Zig 0.16.0
- zls 0.16.0 (optional, for editor support)
- `glslc` (shader compiler, e.g. `shaderc` package)
- Vulkan SDK / drivers (`libvulkan-dev`)
- GLFW (`libglfw3-dev`)

```sh
sudo apt install libglfw3-dev libvulkan-dev shaderc
```

## Build & Run

```sh
zig build        # builds zig-out/bin/Kkitris + shaders
zig build run    # build and run
zig build test   # unit tests
```

Shaders in `src/shader/` are compiled with `glslc` into
`zig-out/bin/shader/*.spv` next to the executable, where the engine loads
them at runtime. Logs go to `<exe-dir>/logs/latest.log`.
