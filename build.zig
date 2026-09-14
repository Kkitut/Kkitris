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

    // Shaders are compiled with glslc to zig-out/bin/shader/*.spv,
    // next to the executable, mirroring the layout engine.zig expects.
    const glslc = b.findProgram(&.{"glslc"}, &.{}) catch "glslc";
    compileShader(b, glslc, "object.vert");
    compileShader(b, glslc, "object.frag");

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

fn compileShader(b: *std.Build, glslc: []const u8, name: []const u8) void {
    const cmd = b.addSystemCommand(&.{glslc});
    cmd.addFileArg(b.path(b.fmt("src/shader/{s}", .{name})));
    cmd.addArg("-o");
    const out = cmd.addOutputFileArg(b.fmt("{s}.spv", .{name}));
    const install = b.addInstallFile(out, b.fmt("bin/shader/{s}.spv", .{name}));
    b.getInstallStep().dependOn(&install.step);
}
