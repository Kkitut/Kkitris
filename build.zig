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
    exe_mod.linkSystemLibrary("glfw", .{});
    exe_mod.linkSystemLibrary("vulkan", .{});

    const exe = b.addExecutable(.{
        .name = "Kkitris",
        .root_module = exe_mod,
    });
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
    if (b.findProgram(&.{"nagac"}, &.{}) catch null) |tool| {
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
        const cmd = b.addSystemCommand(&.{tool});
        cmd.addArg("-o");
        const out = cmd.addOutputFileArg(b.fmt("{s}.spv", .{name}));
        cmd.addFileArg(b.path(b.fmt("src/shader/{s}.wgsl", .{name})));
        const install = b.addInstallFile(out, b.fmt("bin/shader/{s}.spv", .{name}));
        b.getInstallStep().dependOn(&install.step);
    }
}
