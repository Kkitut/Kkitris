const std = @import("std");
const bc = @import("c.zig");
const c = bc.c;
const logger = @import("logger.zig");
const Engine = @import("engine.zig").Engine;

const app_name = "Kkitris";

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

fn keyCallback(
    window: ?*c.GLFWwindow,
    key: c_int,
    scancode: c_int,
    action: c_int,
    mods: c_int,
) callconv(.c) void {
    _ = scancode;
    _ = mods;
    if (key == c.GLFW_KEY_ESCAPE and action == c.GLFW_PRESS) {
        if (window) |w| c.glfwSetWindowShouldClose(w, 1);
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

    _ = c.glfwSetKeyCallback(window, keyCallback);

    var engine: Engine = undefined;
    try engine.init(io, allocator, window);
    defer engine.deinit();

    logger.info("Ready", .{});

    var last_frame_time = c.glfwGetTime();
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();

        const frame_time = c.glfwGetTime();
        const dt: f32 = @floatCast(frame_time - last_frame_time);
        last_frame_time = frame_time;

        engine.update(dt);
        engine.render();
    }

    logger.info("Bye", .{});
}
