const std = @import("std");
const bc = @import("c.zig");
const c = bc.c;
const logger = @import("logger.zig");
const Engine = @import("engine.zig").Engine;
const game_mod = @import("core/game.zig");
const Game = game_mod.Game;
const Buttons = game_mod.Buttons;
const Action = game_mod.Action;
const config_mod = @import("core/config.zig");
const RulesConfig = config_mod.RulesConfig;
const board_view = @import("render/board_view.zig");
const MenuSize = board_view.MenuSize;
const inst_mod = @import("render/instance.zig");
const camera = @import("render/camera.zig");
const freecam_mod = @import("render/freecam.zig");

const app_name = "Kkitris";

const Screen = enum { menu, settings, play };

const AppState = struct {
    screen: Screen = .menu,
    menu_selected: usize = 0,
    settings_selected: usize = 0,
    cfg: RulesConfig = .{},
    game: Game = undefined,
    has_game: bool = false,
    held: Buttons = .{},
    freecam: freecam_mod.Freecam = .{},
    engine: ?*Engine = null,
    last_vp: [16]f32 = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },
    time: f32 = 0,
    seed_counter: u64 = 0,
    allocator: std.mem.Allocator = undefined,
    io: std.Io = undefined,
};

fn glfwErrorDescription() []const u8 {
    var desc: [*c]const u8 = null;
    _ = c.glfwGetError(&desc);
    if (desc) |d| return std.mem.span(d);
    return "(no description)";
}

fn platformOverride() ?c_int {
    const raw = std.c.getenv("KKITRIS_PLATFORM") orelse return null;
    const value = std.mem.span(raw);
    if (std.ascii.eqlIgnoreCase(value, "x11")) return c.GLFW_PLATFORM_X11;
    if (std.ascii.eqlIgnoreCase(value, "wayland")) return c.GLFW_PLATFORM_WAYLAND;
    return null;
}

fn getState(window: ?*c.GLFWwindow) ?*AppState {
    const ptr = c.glfwGetWindowUserPointer(window) orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn nextSeed(st: *AppState) u64 {
    st.seed_counter +%= 1;
    const time_ms: u64 = @intFromFloat(@max(st.time, 0) * 1000.0);
    return 0x9e3779b97f4a7c15 *% st.seed_counter ^ (time_ms *% 0xbf58476d1ce4e5b9);
}

fn startPlay(st: *AppState) void {
    if (st.has_game) {
        st.game.deinit();
        st.has_game = false;
    }
    const dims = MenuSize.tall.dims();
    const seed = nextSeed(st);
    var cfg = st.cfg;
    cfg.w = dims.w;
    cfg.h = dims.h;
    cfg.visible_h = dims.visible;
    cfg.seed = seed;
    cfg.preview_count = 5;
    cfg.endless = true;
    st.game = Game.init(st.allocator, cfg) catch return;
    st.has_game = true;
    st.held = .{};
    st.screen = .play;
}

fn aspectOf(window: ?*c.GLFWwindow) f32 {
    var fbw: c_int = 0;
    var fbh: c_int = 0;
    c.glfwGetFramebufferSize(window, &fbw, &fbh);
    const fw: f32 = @floatFromInt(@max(fbw, 1));
    const fh: f32 = @floatFromInt(@max(fbh, 1));
    return fw / fh;
}

fn defaultViewFor(game: *const Game, aspect: f32) camera.FitView {
    const visible = @min(game.cfg.visible_h, game.field.h);
    return camera.defaultView(
        game.field.w,
        visible,
        board_view.PANEL_MARGIN,
        aspect,
        0.0,
        camera.DEFAULT_FOV_Y_DEG,
    );
}

fn syncFreecamToDefault(window: ?*c.GLFWwindow, st: *AppState) void {
    if (!st.has_game) return;
    const v = defaultViewFor(&st.game, aspectOf(window));
    st.freecam.resetToDefault(v.eye, v.center);
}

fn rawMouseAllowed() bool {
    const raw = std.c.getenv("KKITRIS_RAW_MOUSE") orelse return true;
    const v = std.mem.span(raw);
    return !(std.ascii.eqlIgnoreCase(v, "0") or
        std.ascii.eqlIgnoreCase(v, "off") or
        std.ascii.eqlIgnoreCase(v, "no"));
}

fn enterFreecam(window: ?*c.GLFWwindow, st: *AppState) void {
    syncFreecamToDefault(window, st);
    st.freecam.active = true;
    st.held = .{};
    var raw = false;
    if (window) |w| {
        c.glfwSetInputMode(w, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
        if (rawMouseAllowed() and c.glfwRawMouseMotionSupported() != 0) {
            c.glfwSetInputMode(w, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
            raw = true;
        }
    }
    logger.info("Freecam on (raw mouse: {s})", .{if (raw) "on" else "off"});
}

fn exitFreecam(window: ?*c.GLFWwindow, st: *AppState) void {
    st.freecam.active = false;
    st.freecam.keys = .{};
    st.held = .{};
    if (window) |w| {
        c.glfwSetInputMode(w, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_FALSE);
        c.glfwSetInputMode(w, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
    }
}

fn stopToMenu(window: ?*c.GLFWwindow, st: *AppState) void {
    if (st.freecam.active) exitFreecam(window, st);
    if (st.has_game) {
        st.game.deinit();
        st.has_game = false;
    }
    st.held = .{};
    st.screen = .menu;
}

fn cursorCallback(
    window: ?*c.GLFWwindow,
    xpos: f64,
    ypos: f64,
) callconv(.c) void {
    const st = getState(window) orelse return;
    if (st.screen != .play or !st.freecam.active) return;
    st.freecam.applyMouse(xpos, ypos);
}

fn adjustSetting(st: *AppState, dir: i32) void {
    const d: f32 = @floatFromInt(dir);
    switch (st.settings_selected) {
        0 => st.cfg.das_sec = @min(@max(st.cfg.das_sec + d * 0.005, 0), 0.5),
        1 => st.cfg.arr_sec = @min(@max(st.cfg.arr_sec + d * 0.001, 0), 0.2),
        2 => st.cfg.dcd_sec = @min(@max(st.cfg.dcd_sec + d * 0.001, 0), 0.1),
        3 => st.cfg.sdf = @min(@max(st.cfg.sdf + d * 1.0, 1.0), 41.0),
        else => return,
    }
    config_mod.save(st.io, st.allocator, config_mod.SETTINGS_PATH, st.cfg) catch {
        logger.fail("Settings save failed", .{});
    };
}

fn keyCallback(
    window: ?*c.GLFWwindow,
    key: c_int,
    scancode: c_int,
    action: c_int,
    mods: c_int,
) callconv(.c) void {
    _ = scancode;
    _ = mods;
    const st = getState(window) orelse return;
    const pressed = action == c.GLFW_PRESS;
    const released = action == c.GLFW_RELEASE;

    if (key == c.GLFW_KEY_F12 and pressed) {
        if (st.engine) |e| {
            e.dump_requested = true;
            if (st.screen == .play and st.has_game) {
                const w: f32 = @floatFromInt(st.game.field.w);
                const v: f32 = @floatFromInt(@min(st.game.cfg.visible_h, st.game.field.h));
                if (camera.projectNdc(st.last_vp, .{ w * 0.5, v * 0.5, 0 })) |ndc| {
                    logger.info(
                        "Dump armed: active=({d},{d}) ndc=({d:.3},{d:.3},{d:.3})",
                        .{ st.game.active.x, st.game.active.y, ndc[0], ndc[1], ndc[2] },
                    );
                } else {
                    logger.info("Dump armed: board center CLIPPED (matrix bug?)", .{});
                }
                if (st.freecam.active) {
                    logger.info(
                        "Freecam: pos=({d:.2},{d:.2},{d:.2}) yaw={d:.3} pitch={d:.3}",
                        .{
                            st.freecam.pos[0],
                            st.freecam.pos[1],
                            st.freecam.pos[2],
                            st.freecam.yaw,
                            st.freecam.pitch,
                        },
                    );
                }
            } else {
                logger.info("Dump armed (menu)", .{});
            }
        }
        return;
    }

    switch (st.screen) {
        .menu => {
            if (!pressed) return;
            switch (key) {
                c.GLFW_KEY_ESCAPE => if (window) |w| c.glfwSetWindowShouldClose(w, 1),
                c.GLFW_KEY_UP => st.menu_selected = if (st.menu_selected == 0) 2 else st.menu_selected - 1,
                c.GLFW_KEY_DOWN => st.menu_selected = if (st.menu_selected >= 2) 0 else st.menu_selected + 1,
                c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER, c.GLFW_KEY_SPACE => {
                    if (st.menu_selected == 2) {
                        if (window) |w| c.glfwSetWindowShouldClose(w, 1);
                    } else if (st.menu_selected == 1) {
                        st.settings_selected = 0;
                        st.screen = .settings;
                    } else {
                        startPlay(st);
                    }
                },
                else => {},
            }
        },
        .settings => {
            if (!pressed) return;
            switch (key) {
                c.GLFW_KEY_ESCAPE => st.screen = .menu,
                c.GLFW_KEY_UP => st.settings_selected = if (st.settings_selected == 0) 4 else st.settings_selected - 1,
                c.GLFW_KEY_DOWN => st.settings_selected = if (st.settings_selected >= 4) 0 else st.settings_selected + 1,
                c.GLFW_KEY_LEFT => adjustSetting(st, -1),
                c.GLFW_KEY_RIGHT => adjustSetting(st, 1),
                c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER, c.GLFW_KEY_SPACE => {
                    if (st.settings_selected == 4) st.screen = .menu;
                },
                else => {},
            }
        },
        .play => {
            if (!st.has_game) return;
            if (key == c.GLFW_KEY_F6 and pressed) {
                if (st.freecam.active) {
                    exitFreecam(window, st);
                } else {
                    enterFreecam(window, st);
                }
                return;
            }
            if (st.freecam.active) {
                if (key == c.GLFW_KEY_F7 and pressed) {
                    syncFreecamToDefault(window, st);
                    return;
                }
                switch (key) {
                    c.GLFW_KEY_W => {
                        if (pressed) st.freecam.keys.w = true;
                        if (released) st.freecam.keys.w = false;
                    },
                    c.GLFW_KEY_A => {
                        if (pressed) st.freecam.keys.a = true;
                        if (released) st.freecam.keys.a = false;
                    },
                    c.GLFW_KEY_S => {
                        if (pressed) st.freecam.keys.s = true;
                        if (released) st.freecam.keys.s = false;
                    },
                    c.GLFW_KEY_D => {
                        if (pressed) st.freecam.keys.d = true;
                        if (released) st.freecam.keys.d = false;
                    },
                    c.GLFW_KEY_Q => {
                        if (pressed) st.freecam.keys.q = true;
                        if (released) st.freecam.keys.q = false;
                    },
                    c.GLFW_KEY_E => {
                        if (pressed) st.freecam.keys.e = true;
                        if (released) st.freecam.keys.e = false;
                    },
                    c.GLFW_KEY_UP => {
                        if (pressed) st.freecam.keys.arr_up = true;
                        if (released) st.freecam.keys.arr_up = false;
                    },
                    c.GLFW_KEY_DOWN => {
                        if (pressed) st.freecam.keys.arr_down = true;
                        if (released) st.freecam.keys.arr_down = false;
                    },
                    c.GLFW_KEY_LEFT => {
                        if (pressed) st.freecam.keys.arr_left = true;
                        if (released) st.freecam.keys.arr_left = false;
                    },
                    c.GLFW_KEY_RIGHT => {
                        if (pressed) st.freecam.keys.arr_right = true;
                        if (released) st.freecam.keys.arr_right = false;
                    },
                    else => {},
                }
                return;
            }
            switch (key) {
                c.GLFW_KEY_ESCAPE => {
                    if (pressed) stopToMenu(window, st);
                },
                c.GLFW_KEY_LEFT => {
                    if (pressed) st.held.left = true;
                    if (released) st.held.left = false;
                },
                c.GLFW_KEY_RIGHT => {
                    if (pressed) st.held.right = true;
                    if (released) st.held.right = false;
                },
                c.GLFW_KEY_DOWN => {
                    if (pressed) st.held.soft = true;
                    if (released) st.held.soft = false;
                },
                c.GLFW_KEY_R => {
                    if (pressed) st.game.restart(nextSeed(st));
                },
                else => {
                    if (!pressed) return;
                    const a: ?Action = switch (key) {
                        c.GLFW_KEY_UP, c.GLFW_KEY_X => .rotate_cw,
                        c.GLFW_KEY_Z => .rotate_ccw,
                        c.GLFW_KEY_A => .rotate_180,
                        c.GLFW_KEY_SPACE => .hard_drop,
                        c.GLFW_KEY_C,
                        c.GLFW_KEY_LEFT_SHIFT,
                        c.GLFW_KEY_RIGHT_SHIFT,
                        => .hold,
                        else => null,
                    };
                    if (a) |act| st.game.doAction(act);
                },
            }
        },
    }
}

pub fn run(io: std.Io, allocator: std.mem.Allocator) !void {
    logger.info("Starting...", .{});

    if (platformOverride()) |p| {
        c.glfwInitHint(c.GLFW_PLATFORM, p);
        logger.info("GLFW platform override: {d}", .{p});
    }

    if (c.glfwInit() == 0) {
        logger.fail("Failed to initialize GLFW: {s}", .{glfwErrorDescription()});
        return error.GlfwInitFailed;
    }
    defer c.glfwTerminate();

    if (c.glfwVulkanSupported() == 0) {
        logger.fail("GLFW reports Vulkan is not supported", .{});
        return error.VulkanNotSupported;
    }

    logger.info("GLFW platform: {d}", .{c.glfwGetPlatform()});

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

    const window = c.glfwCreateWindow(1600, 900, app_name, null, null) orelse {
        logger.fail("Failed to create GLFW window: {s}", .{glfwErrorDescription()});
        return error.WindowCreationFailed;
    };
    defer c.glfwDestroyWindow(window);

    c.glfwSetWindowSizeLimits(window, 320, 180, c.GLFW_DONT_CARE, c.GLFW_DONT_CARE);

    var state = AppState{ .allocator = allocator, .io = io };
    if (config_mod.load(io, allocator, config_mod.SETTINGS_PATH) catch |err| blk: {
        logger.fail("Settings load failed, using defaults: {s}", .{@errorName(err)});
        break :blk null;
    }) |cfg| {
        state.cfg = cfg;
    }
    c.glfwSetWindowUserPointer(window, &state);
    _ = c.glfwSetKeyCallback(window, keyCallback);
    _ = c.glfwSetCursorPosCallback(window, cursorCallback);

    var engine: Engine = undefined;
    try engine.init(io, allocator, window);
    defer engine.deinit();
    state.engine = &engine;

    defer if (state.has_game) {
        state.game.deinit();
        state.has_game = false;
    };

    logger.info("Ready", .{});

    var quads: [inst_mod.MAX_INSTANCES]inst_mod.InstanceData = undefined;
    var last_frame_time = c.glfwGetTime();
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();

        const frame_time = c.glfwGetTime();
        const dt: f32 = @floatCast(@min(frame_time - last_frame_time, 0.25));
        last_frame_time = frame_time;
        state.time += dt;

        var fbw: c_int = 0;
        var fbh: c_int = 0;
        c.glfwGetFramebufferSize(window, &fbw, &fbh);
        const fw: f32 = @floatFromInt(@max(fbw, 1));
        const fh: f32 = @floatFromInt(@max(fbh, 1));

        const n = switch (state.screen) {
            .menu => blk: {
                engine.setOrtho(fw, fh);
                break :blk board_view.renderMenu(&quads, fw, fh, state.menu_selected, state.time);
            },
            .settings => blk: {
                engine.setOrtho(fw, fh);
                break :blk board_view.renderSettings(&quads, fw, fh, state.cfg, state.settings_selected);
            },
            .play => blk: {
                if (!state.has_game) {
                    stopToMenu(window, &state);
                    engine.setOrtho(fw, fh);
                    break :blk board_view.renderMenu(&quads, fw, fh, state.menu_selected, state.time);
                }
                const held: Buttons = if (state.freecam.active) .{} else state.held;
                state.game.tick(dt, held);
                const def = defaultViewFor(&state.game, fw / fh);
                if (state.freecam.active) {
                    state.freecam.update(dt);
                    state.last_vp = state.freecam.viewProj(def.proj);
                    engine.setViewProj(state.last_vp);
                } else {
                    state.last_vp = def.view_proj;
                    engine.setViewProj(def.view_proj);
                }
                break :blk board_view.renderPlay(&quads, &state.game, state.time);
            },
        };
        engine.setInstances(quads[0..n]);

        engine.update(dt);
        engine.render();
    }

    logger.info("Bye", .{});
}
