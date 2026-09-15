# Kkitris

puzzle game, you know how it is. (DEFINITELY NOT T*tris)

## need

- zig 0.16.0
- nagac or tint (shaders)
- libvulkan-dev, libglfw3-dev

```sh
cp local.json.example local.json
```

## run

```sh
zig build run
zig build test
```

shaders in `src/shader/` get compiled to `zig-out/bin/shader/*.spv`.
no compiler set up? build will yell at you. logs in `<exe-dir>/logs/latest.log`.

## notes

- gpus are tried best-first. ****ing nvidia on wayland usually pretends to work
  and then doesnt, so it just moves on. if wayland is being wayland:
- `KKITRIS_PLATFORM=x11|wayland` forces the glfw backend (default: whatever
  glfw feels like). on hybrid-gpu wayland, `x11` lets you use the nvidia gpu
  via xwayland:

```sh
KKITRIS_PLATFORM=x11 zig build run
```
