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

## Notes

- GPUs are tried in score order; if one fails to initialize (e.g. an NVIDIA
  dGPU that cannot present to a Wayland compositor running on the iGPU),
  the next one is tried automatically.
- `KKITRIS_PLATFORM=x11|wayland` forces the GLFW backend
  (default: GLFW auto-detect). On hybrid-GPU Wayland setups, `x11` allows
  using the NVIDIA dGPU via XWayland:

```sh
KKITRIS_PLATFORM=x11 zig build run
```
