const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // No GL headers on this box and the engine is Vulkan-only:
    // keep glfw3.h from pulling in <GL/gl.h>.
    exe_mod.addCMacro("GLFW_INCLUDE_NONE", "1");
    exe_mod.linkSystemLibrary("vulkan", .{});

    // Vulkan SDK root: -Dvulkan-sdk=... > $VULKAN_SDK > default install path.
    // (the SDK's setup-env.sh exports $VULKAN_SDK pointing at the x86_64 dir.)
    const vulkan_sdk = b.option(
        []const u8,
        "vulkan-sdk",
        "Vulkan SDK root holding include/ and lib/ (defaults to $VULKAN_SDK)",
    ) orelse b.graph.environ_map.get("VULKAN_SDK") orelse "/mnt/devs/VulkanSDK/1.4.350.1/x86_64";
    exe_mod.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ vulkan_sdk, "include" }) });
    exe_mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ vulkan_sdk, "lib", "VulkanLoader", "lib" }) });

    // GLFW has no system package here: use the vendored headers + prebuilt
    // static lib under build/_deps (left over from the old CMake build).
    exe_mod.addIncludePath(b.path("build/_deps/glfw-src/include"));

    const exe = b.addExecutable(.{
        .name = "Kkitris",
        .root_module = exe_mod,
    });
    exe_mod.addObjectFile(b.path("build/_deps/glfw-build/src/libglfw3.a"));
    b.installArtifact(exe);

    // shader
    const wgsl_tool = findWgslCompiler(b);
    const is_tint = std.mem.eql(u8, std.fs.path.basename(wgsl_tool), "tint");
    compileWgsl(b, wgsl_tool, is_tint, "object.vert");
    compileWgsl(b, wgsl_tool, is_tint, "object.frag");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const helper_mod = b.createModule(.{
        .root_source_file = b.path("src/helper.zig"),
        .target = target,
        .optimize = optimize,
    });
    const helper_tests = b.addTest(.{ .root_module = helper_mod });
    const run_helper_tests = b.addRunArtifact(helper_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_helper_tests.step);

    // Full suite: core (cell/piece/field/srs/bag/config/game),
    // render (camera/scene), net proto, ui stub, helper.
    const suite_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const suite_tests = b.addTest(.{ .root_module = suite_mod });
    const run_suite_tests = b.addRunArtifact(suite_tests);
    test_step.dependOn(&run_suite_tests.step);
}

fn findWgslCompiler(b: *std.Build) []const u8 {
    if (b.option([]const u8, "wgsl-compiler", "WGSL to SPIR-V compiler binary (nagac or tint)")) |opt| {
        return opt;
    }
    if (b.graph.environ_map.get("WGSL_COMPILER")) |env| {
        return env;
    }
    if (readLocalConfig(b)) |cfg| {
        if (cfg.wgsl_compiler) |tool| return tool;
    }
    if (b.findProgram(&.{ "nagac", "naga" }, &.{}) catch null) |tool| {
        return tool;
    }
    if (b.findProgram(&.{"tint"}, &.{}) catch null) |tool| {
        return tool;
    }
    @panic("you must set the WGSL compiler path: copy local.json.example to local.json and set \"wgsl_compiler\", or set $WGSL_COMPILER, or pass -Dwgsl-compiler=/path/to/nagac (or tint)");
}

const LocalConfig = struct {
    wgsl_compiler: ?[]const u8 = null,
};

fn readLocalConfig(b: *std.Build) ?LocalConfig {
    const bytes = b.build_root.handle.readFileAlloc(
        b.graph.io,
        "local.json",
        b.allocator,
        .limited(64 * 1024),
    ) catch return null;
    return std.json.parseFromSliceLeaky(
        LocalConfig,
        b.allocator,
        bytes,
        .{ .ignore_unknown_fields = true },
    ) catch return null;
}

fn compileWgsl(b: *std.Build, tool: []const u8, is_tint: bool, name: []const u8) void {
    if (is_tint) {
        const cmd = b.addSystemCommand(&.{tool});
        cmd.addFileArg(b.path(b.fmt("src/shader/{s}.wgsl", .{name})));
        cmd.addArg("-o");
        const out = cmd.addOutputFileArg(b.fmt("{s}.spv", .{name}));
        const install = b.addInstallFile(out, b.fmt("bin/shader/{s}.spv", .{name}));
        b.getInstallStep().dependOn(&install.step);
    } else {
        // Modern naga CLI takes positional args: `naga [flags] <input.wgsl> <output.spv>`.
        // `--keep-coordinate-space` is required: otherwise naga's SPIR-V
        // backend negates gl_Position.y, which would double-flip our
        // Vulkan-oriented matrices (Y-flipped perspective, Y-down ortho)
        // and render everything upside down.
        const cmd = b.addSystemCommand(&.{tool});
        cmd.addArg("--keep-coordinate-space");
        cmd.addFileArg(b.path(b.fmt("src/shader/{s}.wgsl", .{name})));
        const out = cmd.addOutputFileArg(b.fmt("{s}.spv", .{name}));
        const install = b.addInstallFile(out, b.fmt("bin/shader/{s}.spv", .{name}));
        b.getInstallStep().dependOn(&install.step);
    }
}
