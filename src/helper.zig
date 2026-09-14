const std = @import("std");

pub fn printlnf(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub fn makePath(buffer: []u8, base_path: []const u8, name: []const u8) ?[]u8 {
    return std.fmt.bufPrint(buffer, "{s}/{s}", .{ base_path, name }) catch null;
}

pub fn getExecutableDirectory(io: std.Io, buffer: []u8) ?[]u8 {
    const len = std.process.executableDirPath(io, buffer) catch return null;
    return buffer[0..len];
}

test "makePath joins base and name" {
    var buf: [64]u8 = undefined;
    const p = makePath(&buf, "/a/b", "c/d");
    try std.testing.expectEqualStrings("/a/b/c/d", p.?);
}

test "makePath returns null when buffer too small" {
    var buf: [4]u8 = undefined;
    try std.testing.expect(makePath(&buf, "/a/b", "c") == null);
}
