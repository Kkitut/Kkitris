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
    // Only wired in when the directories actually exist: on systems with a
    // system-wide Vulkan (libvulkan-dev etc.) there is no SDK dir and
    // linkSystemLibrary("vulkan") above is already enough. Adding a
    // non-existent -I/-L makes the compile step fail.
    const vulkan_sdk = b.option(
        []const u8,
        "vulkan-sdk",
        "Vulkan SDK root holding include/ and lib/ (defaults to $VULKAN_SDK)",
    ) orelse b.graph.environ_map.get("VULKAN_SDK") orelse "/mnt/devs/VulkanSDK/1.4.350.1/x86_64";
    {
        const inc = b.pathJoin(&.{ vulkan_sdk, "include" });
        if (dirExistsAbsolute(b.graph.io, inc)) {
            exe_mod.addIncludePath(.{ .cwd_relative = inc });
        }
        const lib = b.pathJoin(&.{ vulkan_sdk, "lib", "VulkanLoader", "lib" });
        if (dirExistsAbsolute(b.graph.io, lib)) {
            exe_mod.addLibraryPath(.{ .cwd_relative = lib });
        }
    }

    // GLFW: prefer the vendored headers + prebuilt static lib under
    // build/_deps (left over from the old CMake build) when present (boxes
    // without a system glfw package), otherwise fall back to the system
    // package (libglfw3-dev).
    const vendored_lib = "build/_deps/glfw-build/src/libglfw3.a";
    const vendored_inc = "build/_deps/glfw-src/include";
    if (fileExistsInBuildRoot(b, vendored_lib) and dirExistsInBuildRoot(b, vendored_inc)) {
        exe_mod.addIncludePath(b.path(vendored_inc));
    } else {
        exe_mod.linkSystemLibrary("glfw", .{});
    }

    const exe = b.addExecutable(.{
        .name = "Kkitris",
        .root_module = exe_mod,
    });
    if (fileExistsInBuildRoot(b, vendored_lib) and dirExistsInBuildRoot(b, vendored_inc)) {
        exe_mod.addObjectFile(b.path(vendored_lib));
    }
    b.installArtifact(exe);

    // shader
    const wgsl_tool = findWgslCompiler(b);
    const is_tint = std.mem.eql(u8, std.fs.path.basename(wgsl_tool), "tint");
    const keep_coord = if (is_tint) false else nagaSupportsKeepCoordinateSpace(b, wgsl_tool);
    compileWgsl(b, wgsl_tool, is_tint, keep_coord, "object.vert");
    compileWgsl(b, wgsl_tool, is_tint, keep_coord, "object.frag");

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

fn compileWgsl(b: *std.Build, tool: []const u8, is_tint: bool, keep_coord: bool, name: []const u8) void {
    if (is_tint) {
        const cmd = b.addSystemCommand(&.{tool});
        cmd.addFileArg(b.path(b.fmt("src/shader/{s}.wgsl", .{name})));
        cmd.addArg("-o");
        const out = cmd.addOutputFileArg(b.fmt("{s}.spv", .{name}));
        const install = b.addInstallFile(out, b.fmt("bin/shader/{s}.spv", .{name}));
        b.getInstallStep().dependOn(&install.step);
    } else if (keep_coord) {
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
    } else {
        // Old nagac (e.g. v0.19.0): `nagac [-o <output.spv>] <input.wgsl>`,
        // no --keep-coordinate-space flag.
        const cmd = b.addSystemCommand(&.{tool});
        cmd.addArg("-o");
        const out = cmd.addOutputFileArg(b.fmt("{s}.spv", .{name}));
        cmd.addFileArg(b.path(b.fmt("src/shader/{s}.wgsl", .{name})));
        const install = b.addInstallFile(out, b.fmt("bin/shader/{s}.spv", .{name}));
        b.getInstallStep().dependOn(&install.step);
    }
}

fn dirExistsAbsolute(io: std.Io, path: []const u8) bool {
    std.Io.Dir.accessAbsolute(io, path, .{}) catch return false;
    return true;
}

fn fileExistsInBuildRoot(b: *std.Build, rel: []const u8) bool {
    b.build_root.handle.access(b.graph.io, rel, .{}) catch return false;
    return true;
}

fn dirExistsInBuildRoot(b: *std.Build, rel: []const u8) bool {
    // access() succeeds for both files and dirs; good enough here because the
    // caller pairs it with a file check for the static lib.
    b.build_root.handle.access(b.graph.io, rel, .{}) catch return false;
    return true;
}

/// Returns true when the WGSL compiler understands
/// `--keep-coordinate-space` (modern `naga`), false for old `nagac`
/// (e.g. v0.19.0, `-o` style). Probes `tool --help` output so both boxes
/// keep working without manual flags.
fn nagaSupportsKeepCoordinateSpace(b: *std.Build, tool: []const u8) bool {
    const res = std.process.run(
        b.allocator,
        b.graph.io,
        .{
            .argv = &.{ tool, "--help" },
            .environ_map = &b.graph.environ_map,
        },
    ) catch return false;
    defer b.allocator.free(res.stdout);
    defer b.allocator.free(res.stderr);
    return std.mem.indexOf(u8, res.stdout, "keep-coordinate-space") != null or
        std.mem.indexOf(u8, res.stderr, "keep-coordinate-space") != null;
}
